import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'i18n.dart';
import 'lan.dart';
import 'services.dart';

/// A purchase order the PC handed to this phone (a PDF that was downloaded and kept inside the app).
class PcOrder {
  final String id;
  final String title;
  final String createdAt; // as written by the PC, e.g. 2026-11-21 14:05:11
  final int items;
  final int pages;
  final int size; // bytes
  final bool prices; // true: the PDF has prices and totals, false: names and quantities only
  final String file; // absolute path of the PDF on the phone
  bool seen;
  PcOrder({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.items,
    required this.pages,
    required this.size,
    required this.prices,
    required this.file,
    this.seen = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt,
        'items': items,
        'pages': pages,
        'size': size,
        'prices': prices,
        'file': file,
        'seen': seen,
      };

  static PcOrder? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = '${o['id'] ?? ''}';
    final file = '${o['file'] ?? ''}';
    if (id.isEmpty || file.isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
    return PcOrder(
      id: id,
      title: '${o['title'] ?? ''}',
      createdAt: '${o['created_at'] ?? ''}',
      items: n(o['items']),
      pages: n(o['pages']),
      size: n(o['size']),
      prices: o['prices'] == true,
      file: file,
      seen: o['seen'] == true,
    );
  }
}

/// Purchase orders sent from the PC ("Send to mobile" in JO PHARMA).  The phone asks the PC on every sync round (every 30 s while the app
/// is open), downloads any new PDF, keeps it, tells the PC "received" and raises a notification.
class Orders {
  static const int _keep = 50;
  static const int _maxBytes = 30 * 1024 * 1024;
  static final ValueNotifier<List<PcOrder>> list = ValueNotifier(const <PcOrder>[]);
  static final ValueNotifier<int> unseen = ValueNotifier(0);
  static void Function()? onOpen; // set by main.dart: pushes the orders screen
  static bool pendingOpen = false; // a notification was tapped while signed out: open the screen after sign-in
  static bool screenOpen = false;
  static bool _busy = false;
  static bool _loaded = false;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/po_orders');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static void _set(List<PcOrder> rows) {
    list.value = List<PcOrder>.unmodifiable(rows);
    unseen.value = rows.where((o) => !o.seen).length;
  }

  static Future<void> _save() async {
    final d = await _dir();
    final tmp = File('${d.path}/index.json.tmp');
    await tmp.writeAsString(jsonEncode([for (final o in list.value) o.toJson()]), flush: true);
    await tmp.rename('${d.path}/index.json');
  }

  /// Reads the list kept on the phone (once).
  static Future<void> load() async {
    if (_loaded) return;
    final d = await _dir();
    final f = File('${d.path}/index.json');
    final rows = <PcOrder>[];
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is List) {
          for (final x in j) {
            final o = PcOrder.fromJson(x);
            if (o != null && await File(o.file).exists()) rows.add(o);
          }
        }
      } catch (_) {}
    }
    _set(rows);
    _loaded = true;
  }

  /// Opens the orders screen (a tapped notification, or the button in Settings).  Managers only, and only when signed in.
  static void open() {
    if (!app.loggedIn || !app.isManager) {
      pendingOpen = true;
      return;
    }
    if (!screenOpen) onOpen?.call();
  }

  static Future<void> markAllSeen() async {
    if (!_loaded || list.value.every((o) => o.seen)) return;
    for (final o in list.value) {
      o.seen = true;
    }
    _set(list.value);
    try {
      await _save();
    } catch (_) {}
  }

  static Future<void> delete(PcOrder o) async {
    try {
      final f = File(o.file);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _set(list.value.where((x) => x.id != o.id).toList());
    try {
      await _save();
    } catch (_) {}
  }

  /// One quiet round: ask the PC for orders it offers, download the ones this phone does not have yet.  Network problems are
  /// thrown to the caller (Lan.tick ignores them); an older PC program without orders answers 404 and nothing happens.
  static Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final p = await Lan.load();
      if (p == null) return;
      final r = await http.get(Uri.parse('${p.base}/orders'), headers: Lan.headers(p)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final remote = j is Map ? j['orders'] : null;
      if (remote is! List || remote.isEmpty) return;
      await load();
      final have = list.value.map((o) => o.id).toSet();
      final rows = <PcOrder>[...list.value];
      final added = <PcOrder>[];
      for (final x in remote.reversed) {
        // oldest first, so the newest ends up on top
        if (x is! Map) continue;
        final id = '${x['id'] ?? ''}';
        if (!RegExp(r'^[0-9a-f]{8,32}$').hasMatch(id) || have.contains(id)) continue;
        final size = x['size'] is num ? (x['size'] as num).toInt() : 0;
        if (size > _maxBytes) continue;
        final pr = await http.get(Uri.parse('${p.base}/orders/$id.pdf'), headers: Lan.headers(p)).timeout(const Duration(seconds: 120));
        if (pr.statusCode != 200 || pr.bodyBytes.length < 8) continue;
        final dir = await _dir();
        final file = File('${dir.path}/$id.pdf');
        await file.writeAsBytes(pr.bodyBytes, flush: true);
        final o = PcOrder(
          id: id,
          title: '${x['title'] ?? ''}',
          createdAt: '${x['created_at'] ?? ''}',
          items: x['items'] is num ? (x['items'] as num).toInt() : 0,
          pages: x['pages'] is num ? (x['pages'] as num).toInt() : 0,
          size: pr.bodyBytes.length,
          prices: x['prices'] == true,
          file: file.path,
        );
        rows.insert(0, o);
        added.add(o);
        have.add(id);
        try {
          await http.post(Uri.parse('${p.base}/orders/$id/ack'), headers: Lan.headers(p)).timeout(const Duration(seconds: 5));
        } catch (_) {} // the PDF is safe on the phone; the PC window just keeps saying "waiting"
      }
      if (added.isEmpty) return;
      while (rows.length > _keep) {
        final old = rows.removeLast();
        try {
          final f = File(old.file);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      _set(rows);
      await _save();
      for (final o in added) {
        await Notifier.show(o.id.hashCode & 0x7fffffff, tr('orders_notif_title'), tr('orders_notif_body', [o.title, o.items]));
      }
    } finally {
      _busy = false;
    }
  }
}

/// The phone notification ("a new purchase order arrived").  Every call is safe: a missing permission or plugin never breaks the app.
class Notifier {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool launchedByNotification = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (_) => Orders.open(),
      );
      final d = await _plugin.getNotificationAppLaunchDetails();
      launchedByNotification = d?.didNotificationLaunchApp ?? false;
      _ready = true;
    } catch (_) {}
  }

  /// Android 13+: asks the user once to allow notifications (called right after pairing with the PC).
  static Future<void> askPermission() async {
    await init();
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> show(int id, String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'jo_orders',
            'Purchase orders',
            channelDescription: 'Purchase orders sent from the PC',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: 'orders',
      );
    } catch (_) {}
  }
}
