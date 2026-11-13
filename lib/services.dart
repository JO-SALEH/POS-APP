import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'db.dart';
import 'i18n.dart';

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

  /// All sales (not only unsynced) as JSON the desktop can import with the desktop's Mobile receiver > Import file.
  static Future<void> shareJson() async {
    final payload = {'invoices': await Db.lanInvoices(onlyUnsynced: false)};
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

  /// Products + extra barcodes as CSV (opens in Excel; can be imported back, also into another phone).
  static Future<void> shareProducts() async {
    final rows = await Db.exportRows();
    final b = StringBuffer('\uFEFFbarcode,name,price,extra_barcodes\n');
    for (final r in rows) {
      b.writeln(r.map(_csv).join(','));
    }
    final f = await _tmp('jo_products_${_stamp()}.csv', utf8.encode(b.toString()));
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'JO POS products');
  }

  static Future<void> shareDb() async {
    final d = await Db.db;
    await d.execute('PRAGMA wal_checkpoint(FULL)');
    final bytes = await File(await Db.dbPath()).readAsBytes();
    final f = await _tmp('jo_pos_backup_${_stamp()}.db', bytes);
    await Share.shareXFiles([XFile(f.path)], subject: 'JO POS backup');
  }

}
