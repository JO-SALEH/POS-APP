import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'i18n.dart';
import 'importer.dart';

// =============================================================== app state
class AppState extends ChangeNotifier {
  bool loggedIn = false;
  String user = 'admin';
  String lang = 'ar';
  final List<CartLine> cart = [];

  Future<void> init() async {
    lang = await Db.getSetting('lang', 'ar');
    L.code = lang;
    user = await Db.getSetting('username', 'admin');
    loggedIn = (await Db.getSetting('remember', '0')) == '1';
    notifyListeners();
  }

  Future<bool> login(String u, String pw, bool remember) async {
    final su = await Db.getSetting('username', 'admin');
    final sp = await Db.getSetting('pw_hash');
    if (u.trim() == su && hashPassword(pw) == sp) {
      user = su;
      loggedIn = true;
      await Db.setSetting('remember', remember ? '1' : '0');
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    loggedIn = false;
    await Db.setSetting('remember', '0');
    notifyListeners();
  }

  Future<void> setLang(String code) async {
    lang = code;
    L.code = code;
    await Db.setSetting('lang', code);
    notifyListeners();
  }

  // ---- cart
  double get cartTotal => cart.fold(0, (a, l) => a + l.subtotal);
  int get cartCount => cart.fold(0, (a, l) => a + l.qty);

  void addToCart(Product p) {
    final i = cart.indexWhere((l) => l.product.barcode == p.barcode);
    if (i >= 0) {
      cart[i].qty++;
    } else {
      cart.insert(0, CartLine(p));
    }
    notifyListeners();
  }

  void setQty(CartLine l, int q) {
    if (q <= 0) {
      cart.remove(l);
    } else {
      l.qty = q;
    }
    notifyListeners();
  }

  void replaceLine(CartLine l, Product np) {
    final i = cart.indexOf(l);
    if (i < 0) return;
    final existing = cart.indexWhere((x) => x.product.barcode == np.barcode);
    if (existing >= 0 && existing != i) {
      cart[existing].qty += l.qty;
      cart.removeAt(i);
    } else {
      cart[i] = CartLine(np, l.qty);
    }
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }
}

final app = AppState();

// ================================================================== sync
class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

class SyncResult {
  final int sent;
  final int duplicates;
  SyncResult(this.sent, this.duplicates);
}

class SyncService {
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final noScheme = s.replaceFirst(RegExp(r'^https?://'), '');
    final hostPart = noScheme.split('/').first;
    if (!hostPart.contains(':')) {
      s = s.replaceFirst(hostPart, '$hostPart:8765');
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static Future<Map<String, String>> _headers() async => {
        'Content-Type': 'application/json; charset=utf-8',
        'X-JO-Key': await Db.getSetting('pair_key'),
      };

  static Future<String> _base() async {
    final u = normalize(await Db.getSetting('server_url'));
    if (u.isEmpty) throw SyncException(L.ar ? 'أدخل عنوان السيرفر في الإعدادات' : 'Set the server address in Settings');
    return u;
  }

  static Map<String, dynamic> _decode(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw SyncException(L.ar ? 'مفتاح الربط غير صحيح' : 'Wrong pairing key');
    }
    if (r.statusCode != 200) throw SyncException('HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SyncException {
      rethrow;
    } on SocketException {
      throw SyncException(L.ar ? 'تعذر الوصول للسيرفر (تأكد من نفس شبكة الواي فاي)' : 'Cannot reach the server (same Wi-Fi?)');
    } on http.ClientException catch (e) {
      throw SyncException(e.message);
    } on Exception catch (e) {
      throw SyncException(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Returns the desktop's name on success.
  static Future<String> ping() => _guard(() async {
        final r = await http
            .get(Uri.parse('${await _base()}/api/ping'), headers: await _headers())
            .timeout(const Duration(seconds: 6));
        final j = _decode(r);
        return (j['name'] ?? 'JO PHARMA').toString();
      });

  static Future<SyncResult> pushSales() => _guard(() async {
        final payload = await Db.buildPayload();
        final sales = payload['sales'] as List;
        if (sales.isEmpty) return SyncResult(0, 0);
        final r = await http
            .post(Uri.parse('${await _base()}/api/sales'),
                headers: await _headers(), body: utf8.encode(jsonEncode(payload)))
            .timeout(const Duration(seconds: 30));
        final j = _decode(r);
        final accepted = ((j['accepted'] ?? []) as List).map((e) => e.toString()).toList();
        final dups = ((j['duplicates'] ?? []) as List).map((e) => e.toString()).toList();
        await Db.markSynced([...accepted, ...dups]);
        return SyncResult(accepted.length, dups.length);
      });

  static Future<int> pullProducts() => _guard(() async {
        final r = await http
            .get(Uri.parse('${await _base()}/api/products'), headers: await _headers())
            .timeout(const Duration(seconds: 60));
        final j = _decode(r);
        final list = (j['products'] ?? []) as List;
        return Db.bulkUpsert(list.map(_productFromJson).whereType<Product>().toList());
      });
}

Product? _productFromJson(dynamic e) {
  if (e is! Map) return null;
  final code = (e['barcode'] ?? e['code'] ?? '').toString().trim();
  final name = (e['name'] ?? '').toString().trim();
  final price = double.tryParse((e['price'] ?? '0').toString().replaceAll(',', '.')) ?? 0;
  if (code.isEmpty || name.isEmpty) return null;
  return Product(barcode: code, name: name, price: price);
}

// ============================================================ file helpers
class Files {
  static Future<File> _tmp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  /// All sales (not only unsynced) as JSON the desktop can import with `jo_mobile_sync.py --import`.
  static Future<void> shareJson() async {
    final payload = await Db.buildPayload(onlyUnsynced: false);
    final f = await _tmp('jo_sales_${_stamp()}.json', utf8.encode(const JsonEncoder.withIndent(' ').convert(payload)));
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')], subject: 'JO POS sales');
  }

  static String _csv(Object? v) {
    final s = '${v ?? ''}';
    return (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static Future<void> shareCsv() async {
    final payload = await Db.buildPayload(onlyUnsynced: false);
    final b = StringBuffer('\uFEFFreceipt_no,date_time,payment,barcode,name,price,qty,subtotal,invoice_discount\n');
    for (final s in payload['sales'] as List) {
      for (final i in s['items'] as List) {
        b.writeln([s['receipt_no'], s['created_at'], s['payment'], i['barcode'], i['name'], i['price'], i['qty'],
                i['subtotal'], s['discount']]
            .map(_csv)
            .join(','));
      }
    }
    final f = await _tmp('jo_sales_${_stamp()}.csv', utf8.encode(b.toString()));
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'JO POS sales');
  }

  static Future<void> shareDb() async {
    final d = await Db.db;
    await d.execute('PRAGMA wal_checkpoint(FULL)');
    final bytes = await File(await Db.dbPath()).readAsBytes();
    final f = await _tmp('jo_pos_backup_${_stamp()}.db', bytes);
    await Share.shareXFiles([XFile(f.path)], subject: 'JO POS backup');
  }

  /// Returns the verified import report, or null when the user cancelled.
  /// Excel (.xlsx), JO PHARMA database (jo_pharmacy.db), JO POS backup, CSV or JSON - detected from the file itself.
  /// Throws [ImportException] (already translated) when the file cannot be used.
  static Future<ImportReport?> importProducts() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    if (res == null || res.files.isEmpty) return null;
    final path = res.files.first.path;
    if (path == null) throw ImportException(tr('import_empty'));
    return Importer.importPath(path, parseText: parseProducts);
  }

  @visibleForTesting
  static ParseResult parseProducts(String text) {
    final t = text.trimLeft();
    final out = ParseResult();
    if (t.startsWith('{') || t.startsWith('[')) {
      final j = jsonDecode(t);
      final list = j is List ? j : (j['products'] ?? []) as List;
      for (final e in list) {
        out.rows++;
        final p = _productFromJson(e);
        if (p == null) {
          out.noCode++;
          continue;
        }
        final extra = (e is Map ? (e['codes'] ?? e['alt_codes'] ?? e['barcodes']) : null);
        out.items.add(ImportItem(p, extra is List ? extra.map((x) => '$x').toList() : const []));
      }
      return out;
    }
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return out;
    final first = lines.first;
    final delim = first.contains('\t') ? '\t' : (first.contains(';') && !first.contains(',') ? ';' : ',');
    // header names (English / Arabic) pick the columns; without a header it is barcode, name, price
    return Importer.fromRows(lines.map((l) => _splitCsv(l, delim)).toList());
  }

  static List<String> _splitCsv(String line, String d) {
    final out = <String>[];
    final cur = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (q) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            q = false;
          }
        } else {
          cur.write(ch);
        }
      } else if (ch == '"') {
        q = true;
      } else if (ch == d) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }
}
