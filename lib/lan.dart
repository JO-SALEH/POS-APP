import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'db.dart';
import 'i18n.dart';
import 'importer.dart';
import 'orders.dart';

/// Shown to the user as is (already translated).
class LanException implements Exception {
  final String message;
  final bool unreachable;
  LanException(this.message, {this.unreachable = false});
  @override
  String toString() => message;
}

/// Address + secret of the desktop receiver (the content of the QR shown by JO PHARMA > Mobile receiver).
class Pairing {
  final String ip;
  final int port;
  final String token;
  const Pairing(this.ip, this.port, this.token);

  String get base => ip.contains(':') ? 'http://[$ip]:$port' : 'http://$ip:$port';
  Pairing withIp(String newIp) => Pairing(newIp, port, token);

  /// QR text: {"v":1,"ip":"192.168.1.5","port":8765,"token":"..."}; null when it is not a JO PHARMA code.
  static Pairing? parseQr(String text) {
    try {
      final j = jsonDecode(text.trim());
      if (j is! Map) return null;
      return _make('${j['ip'] ?? ''}', j['port'], '${j['token'] ?? ''}');
    } catch (_) {
      return null;
    }
  }

  /// Typed by hand: "192.168.1.5" or "192.168.1.5:8765" + the code.
  static Pairing? parseManual(String addr, String token) {
    var a = addr.trim().replaceFirst(RegExp(r'^https?://'), '');
    a = a.split('/').first;
    var port = 8765;
    var host = a;
    final i = a.lastIndexOf(':');
    if (i > 0 && !a.contains('::')) {
      host = a.substring(0, i);
      port = int.tryParse(a.substring(i + 1)) ?? -1;
    }
    return _make(host, port, token.trim());
  }

  static Pairing? _make(String ip, Object? port, String token) {
    final p = port is int ? port : int.tryParse('$port');
    final addr = InternetAddress.tryParse(ip.trim());
    if (addr == null || p == null || p < 1 || p > 65535 || token.isEmpty) return null;
    return Pairing(ip.trim(), p, token);
  }
}

class LanPushResult {
  int booked = 0; // new invoices booked on the desktop
  int duplicates = 0; // the desktop already had them (sent before)
  int unmatched = 0; // booked, but some barcodes are unknown there: link them in the desktop "pending" list
  int returnsSent = 0; // returns the desktop booked
  int failed = 0; // refused: stay unsent, reason in the invoice note
  final List<String> errors = [];
  int get acknowledged => booked + duplicates + unmatched;
  int get total => acknowledged + failed;
}

class LanStatus {
  final bool paired;
  final bool online;
  final bool busy;
  final int unsynced;
  final String? name;
  final String? error;
  final DateTime? lastOk;
  const LanStatus({this.paired = false, this.online = false, this.busy = false, this.unsynced = 0, this.name, this.error, this.lastOk});
}

class Lan {
  static final ValueNotifier<LanStatus> status = ValueNotifier(const LanStatus());
  static bool _busy = false;
  static Timer? _timer;
  static DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _lastCatalog = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime? _lastOk;
  static String? _name;
  static final _obs = _Lifecycle();

  // ------------------------------------------------------------- settings
  static Future<Pairing?> load() async {
    final ip = await Db.getSetting('lan_ip');
    final port = int.tryParse(await Db.getSetting('lan_port')) ?? 8765;
    final token = await Db.getSetting('lan_token');
    if (ip.isEmpty || token.isEmpty) return null;
    return Pairing(ip, port, token);
  }

  static Future<void> _save(Pairing p, {String? name}) async {
    await Db.setSetting('lan_ip', p.ip);
    await Db.setSetting('lan_port', '${p.port}');
    await Db.setSetting('lan_token', p.token);
    if (name != null) await Db.setSetting('lan_name', name);
  }

  static Future<void> unpair() async {
    await Db.setSetting('lan_ip', '');
    await Db.setSetting('lan_token', '');
    await Db.setSetting('lan_name', '');
    await Db.setSetting('lan_rev', '');
    _name = null;
    _lastOk = null;
    await _publish(online: false);
  }

  // ----------------------------------------------------------------- http
  static LanException _httpError(http.Response r) {
    if (r.statusCode == 401) return LanException(tr('lan_bad_token'));
    if (r.statusCode == 403) return LanException(tr('lan_forbidden'));
    return LanException('HTTP ${r.statusCode}');
  }

  static Future<T> _net<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on LanException {
      rethrow;
    } on TimeoutException {
      throw LanException(tr('lan_unreachable'), unreachable: true);
    } on SocketException {
      throw LanException(tr('lan_unreachable'), unreachable: true);
    } on http.ClientException {
      throw LanException(tr('lan_unreachable'), unreachable: true);
    } on HandshakeException {
      throw LanException(tr('lan_unreachable'), unreachable: true);
    }
  }

  static Map<String, String> _hdr(Pairing p, {bool json = false}) =>
      {'X-JO-Token': p.token, 'X-JO-Client': 'mobile', if (json) 'Content-Type': 'application/json; charset=utf-8'};

  /// Headers of every request to the PC (token + "I am the phone app": the PC window then knows the phone is connected).
  static Map<String, String> headers(Pairing p) => _hdr(p);

  static Map<String, dynamic> _json(http.Response r) {
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }

  /// Name of the pharmacy on the desktop; throws when it cannot be reached or the code is wrong.
  static Future<String> ping(Pairing p, {Duration timeout = const Duration(seconds: 5)}) => _net(() async {
        final r = await http.get(Uri.parse('${p.base}/ping'), headers: _hdr(p)).timeout(timeout);
        if (r.statusCode != 200) throw _httpError(r);
        final j = _json(r);
        if (j['ok'] != true) throw LanException(tr('lan_not_jo'));
        return ('${j['name'] ?? ''}').trim().isEmpty ? 'JO PHARMA' : '${j['name']}';
      });

  // -------------------------------------------------------------- pairing
  /// Pairs with the QR text or typed values; saves only when the desktop really answers.
  static Future<String> pair(Pairing p) async {
    final name = await ping(p);
    await _save(p, name: name);
    await Db.setSetting('lan_rev', '');
    _name = name;
    _lastOk = DateTime.now();
    await _publish(online: true);
    unawaited(Notifier.askPermission()); // Android 13+: allow the "new purchase order" notification
    return name;
  }

  // ------------------------------------------------------------ push sales
  /// Sends every unsent invoice. Safe to repeat: the desktop books each invoice id once.
  static Future<LanPushResult> push({bool rediscover = true}) async {
    var p = await load();
    if (p == null) throw LanException(tr('lan_not_paired'));
    final invoices = await Db.lanInvoices();
    final res = LanPushResult();
    if (invoices.isEmpty && await Db.unsyncedReturns() == 0) return res;
    try {
      if (invoices.isNotEmpty) await _pushTo(p, invoices, res);
      await _pushReturns(p, res);
    } on LanException catch (e) {
      if (!e.unreachable || !rediscover) rethrow;
      final np = await findDesktop(p);
      if (np == null) rethrow;
      final again = await Db.lanInvoices();
      if (again.isNotEmpty) await _pushTo(np, again, res); // only what is still unsent
      await _pushReturns(np, res);
    }
    return res;
  }

  /// Returns of sales the PC already has: it restocks, books the refund and lowers the customer's credit.
  static Future<void> _pushReturns(Pairing p, LanPushResult res) async {
    final rets = await Db.lanReturns();
    if (rets.isEmpty) return;
    final install = await Db.installId();
    for (var i = 0; i < rets.length; i += 25) {
      final chunk = rets.sublist(i, i + 25 > rets.length ? rets.length : i + 25);
      final http.Response r = await _net(() => http
          .post(Uri.parse('${p.base}/returns'), headers: _hdr(p, json: true), body: utf8.encode(jsonEncode({'returns': chunk})))
          .timeout(const Duration(seconds: 30)));
      if (r.statusCode == 404) return; // an older PC program without returns: they stay on the phone
      if (r.statusCode != 200) throw _httpError(r);
      final results = _json(r)['results'];
      if (results is! List) throw LanException('bad reply');
      for (final x in results) {
        if (x is! Map) continue;
        final cid = '${x['client_return_id'] ?? ''}';
        if (!cid.startsWith('$install-')) continue;
        final receipt = cid.substring(install.length + 1);
        final st = '${x['status'] ?? ''}';
        if (st == 'done' || st == 'duplicate') {
          await Db.setReturnResult(receipt, 1);
          res.returnsSent++;
        } else if (st == 'failed' && x['retryable'] != true) {
          await Db.setReturnResult(receipt, 2, note: '${x['error'] ?? 'error'}');
          res.failed++;
          res.errors.add('$receipt: ${x['error']}');
        } // not_booked / retryable: stays pending for the next round
      }
    }
  }

  static Future<void> _pushTo(Pairing p, List<Map<String, Object?>> invoices, LanPushResult res) async {
    final install = await Db.installId();
    final chunks = <List<Map<String, Object?>>>[];
    var cur = <Map<String, Object?>>[];
    var bytes = 0;
    for (final inv in invoices) {
      final n = utf8.encode(jsonEncode(inv)).length;
      if (cur.isNotEmpty && (cur.length >= 25 || bytes + n > 180000)) {
        chunks.add(cur);
        cur = [];
        bytes = 0;
      }
      cur.add(inv);
      bytes += n;
    }
    if (cur.isNotEmpty) chunks.add(cur);

    for (final chunk in chunks) {
      final http.Response r = await _net(() => http
          .post(Uri.parse('${p.base}/sales'), headers: _hdr(p, json: true), body: utf8.encode(jsonEncode({'invoices': chunk})))
          .timeout(const Duration(seconds: 30)));
      if (r.statusCode != 200) throw _httpError(r);
      final results = _json(r)['results'];
      if (results is! List) throw LanException('bad reply');
      final answered = <String>{};
      for (final x in results) {
        if (x is! Map) continue;
        final cid = '${x['client_sale_id'] ?? ''}';
        if (!cid.startsWith('$install-')) continue;
        final receipt = cid.substring(install.length + 1);
        answered.add(cid);
        await _apply(receipt, x, res);
      }
      // an invoice the desktop did not answer stays unsent (it will be offered again next time)
      for (final inv in chunk) {
        if (!answered.contains(inv['client_sale_id'])) {
          res.failed++;
          res.errors.add('${inv['client_sale_id']}: no answer');
        }
      }
    }
    _lastOk = DateTime.now();
    await _save(p);
  }

  static Future<void> _apply(String receipt, Map x, LanPushResult res) async {
    final st = '${x['status'] ?? ''}';
    final dup = x['duplicate'] == true;
    final unmatched = (x['unmatched'] is List) ? (x['unmatched'] as List).where((u) => u is Map && u['status'] != 'dismissed').length : 0;
    if (st == 'done') {
      await Db.setSyncResult(receipt, synced: true);
      dup ? res.duplicates++ : res.booked++;
    } else if (st == 'partial' || st == 'pending') {
      await Db.setSyncResult(receipt, synced: true, note: tr(st == 'partial' ? 'lan_note_partial' : 'lan_note_pending', [unmatched]));
      res.unmatched++;
    } else {
      final err = '${x['message'] ?? x['error'] ?? 'error'}';
      await Db.setSyncResult(receipt, synced: false, note: tr('lan_note_failed', [err]));
      res.failed++;
      res.errors.add('$receipt: $err');
    }
  }

  // ------------------------------------------------------------- catalog
  /// Updates the product list from the desktop (name, price, all barcodes). Returns null when nothing changed.
  static Future<ImportReport?> pullCatalog({bool force = false}) async {
    final p = await load();
    if (p == null) throw LanException(tr('lan_not_paired'));
    final saved = await Db.getSetting('lan_rev');
    final rev = await _net(() async {
      final r = await http.get(Uri.parse('${p.base}/catalog/rev'), headers: _hdr(p)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw _httpError(r);
      return '${_json(r)['rev'] ?? ''}';
    });
    if (!force && rev.isNotEmpty && rev == saved) return null;
    final body = await _net(() async {
      final r = await http.get(Uri.parse('${p.base}/catalog'), headers: _hdr(p)).timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) throw _httpError(r);
      var b = r.bodyBytes;
      if (b.length > 2 && b[0] == 0x1f && b[1] == 0x8b) b = Uint8List.fromList(gzip.decode(b));
      final j = jsonDecode(utf8.decode(b));
      if (j is! Map<String, dynamic>) throw LanException('bad reply');
      return j;
    });
    final rep = await Importer.commit(Importer.fromCatalog(body));
    if (body['customers'] is List) await Db.replaceCustomers(body['customers'] as List);
    if (rep.verified) await Db.setSetting('lan_rev', '${body['rev'] ?? rev}');
    _lastCatalog = DateTime.now();
    return rep;
  }

  // ----------------------------------------------------------- discovery
  /// The PC got another address from the router: look for it on the phone's own Wi-Fi network (same port + same code).
  static Future<Pairing?> findDesktop(Pairing p) async {
    _lastScan = DateTime.now();
    final prefixes = <String>{};
    final own = <String>{};
    try {
      for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in ni.addresses) {
          final o = a.address.split('.');
          if (o.length != 4 || !_isPrivate(a.address)) continue;
          prefixes.add('${o[0]}.${o[1]}.${o[2]}');
          own.add(a.address);
        }
      }
    } catch (_) {}
    for (final pre in prefixes) {
      final hosts = [for (var i = 1; i <= 254; i++) '$pre.$i'].where((h) => !own.contains(h) && h != p.ip).toList();
      for (var i = 0; i < hosts.length; i += 64) {
        final batch = hosts.skip(i).take(64);
        final found = await Future.wait(batch.map((h) => _probe(p.withIp(h))));
        final hit = found.whereType<Pairing>();
        if (hit.isNotEmpty) {
          final np = hit.first;
          try {
            _name = await ping(np);
          } catch (_) {}
          await _save(np, name: _name);
          return np;
        }
      }
    }
    return null;
  }

  static bool _isPrivate(String ip) {
    final o = ip.split('.').map(int.tryParse).toList();
    if (o.length != 4 || o.contains(null)) return false;
    return o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31);
  }

  static Future<Pairing?> _probe(Pairing p) async {
    try {
      final s = await Socket.connect(p.ip, p.port, timeout: const Duration(milliseconds: 500));
      s.destroy();
    } catch (_) {
      return null;
    }
    try {
      await ping(p, timeout: const Duration(seconds: 2));
      return p;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ automatic
  static void startAuto() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(_obs);
    WidgetsBinding.instance.addObserver(_obs);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => tick());
    tick();
  }

  static void stopAuto() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(_obs);
  }

  /// Call after a sale is saved: sends it right away when the PC is reachable.
  static void afterSale() => unawaited(tick());

  static Future<void> _publish({required bool online, bool busy = false, String? error}) async {
    final p = await load();
    status.value = LanStatus(
      paired: p != null,
      online: online,
      busy: busy,
      unsynced: await Db.unsyncedCount(),
      name: _name ?? (await Db.getSetting('lan_name')),
      error: error,
      lastOk: _lastOk,
    );
  }

  /// One quiet round: send unsent invoices, refresh the product list when the desktop changed it.
  static Future<void> tick() async {
    if (_busy) return;
    final p = await load();
    if (p == null) {
      await _publish(online: false);
      return;
    }
    _busy = true;
    try {
      await _publish(online: status.value.online, busy: true);
      final n = await Db.unsyncedCount() + await Db.unsyncedReturns();
      final canScan = DateTime.now().difference(_lastScan) > const Duration(minutes: 3);
      if (n > 0) {
        await push(rediscover: canScan);
      } else {
        try {
          _name = await ping(p, timeout: const Duration(seconds: 3));
          _lastOk = DateTime.now();
        } on LanException catch (e) {
          if (!e.unreachable || !canScan) rethrow;
          final np = await findDesktop(p);
          if (np == null) rethrow;
          _lastOk = DateTime.now();
        }
      }
      if (DateTime.now().difference(_lastCatalog) > const Duration(minutes: 5)) {
        try {
          await pullCatalog();
        } catch (_) {} // the product list can wait: invoices matter more
        _lastCatalog = DateTime.now();
      }
      try {
        await Orders.poll(); // purchase orders the PC handed over (download + notification)
      } catch (_) {} // never blocks invoices
      await _publish(online: true);
    } on LanException catch (e) {
      await _publish(online: false, error: e.message);
    } catch (e) {
      await _publish(online: false, error: '$e');
    } finally {
      _busy = false;
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) unawaited(Lan.tick());
  }
}
