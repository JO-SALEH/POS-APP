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
  String role = 'manager'; // manager | cashier
  String lang = 'ar';
  final List<CartLine> cart = [];
  final List<List<CartLine>> _undo = [];

  bool get isManager => role == 'manager';

  Future<void> init() async {
    lang = await Db.getSetting('lang', 'ar');
    L.code = lang;
    user = await Db.getSetting('username', 'admin');
    role = await Db.getSetting('last_role', 'manager');
    loggedIn = (await Db.getSetting('remember', '0')) == '1';
    notifyListeners();
  }

  Future<bool> login(String u, String pw, bool remember) async {
    final su = await Db.getSetting('username', 'admin');
    final sp = await Db.getSetting('pw_hash');
    final cu = await Db.getSetting('cashier_user');
    final cp = await Db.getSetting('cashier_pw_hash');
    String? r;
    if (u.trim() == su && hashPassword(pw) == sp) {
      r = 'manager';
      user = su;
    } else if (cu.isNotEmpty && cp.isNotEmpty && u.trim() == cu && hashPassword(pw) == cp) {
      r = 'cashier';
      user = cu;
    }
    if (r == null) return false;
    role = r;
    loggedIn = true;
    await Db.setSetting('last_role', r);
    await Db.setSetting('username_active', user);
    await Db.setSetting('remember', remember ? '1' : '0');
    notifyListeners();
    return true;
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
  double get cartTotal => double.parse(cart.fold<double>(0, (a, l) => a + l.subtotal).toStringAsFixed(2));
  int get cartCount => cart.fold(0, (a, l) => a + l.qty);
  bool get canUndo => _undo.isNotEmpty;

  void _snap() {
    _undo.add([for (final l in cart) l.copy()]);
    if (_undo.length > 20) _undo.removeAt(0);
  }

  void addToCart(Product p, {String unit = 'pack'}) {
    _snap();
    final i = cart.indexWhere((l) => l.product.barcode == p.barcode && l.unit == unit);
    if (i >= 0) {
      cart[i].qty++;
    } else {
      cart.insert(0, CartLine(p, 1, unit));
    }
    notifyListeners();
  }

  void setQty(CartLine l, int q) {
    _snap();
    if (q <= 0) {
      cart.remove(l);
    } else {
      l.qty = q;
    }
    notifyListeners();
  }

  /// Sells the line by pack / strip / single unit (merges with a line that already has that unit).
  void setUnit(CartLine l, String unit) {
    if (l.unit == unit || !l.product.unitOptions.contains(unit)) return;
    _snap();
    final other = cart.indexWhere((x) => x != l && x.product.barcode == l.product.barcode && x.unit == unit);
    if (other >= 0) {
      cart[other].qty += l.qty;
      cart.remove(l);
    } else {
      l.unit = unit;
    }
    notifyListeners();
  }

  void replaceLine(CartLine l, Product np) {
    final i = cart.indexOf(l);
    if (i < 0) return;
    _snap();
    final existing = cart.indexWhere((x) => x.product.barcode == np.barcode);
    if (existing >= 0 && existing != i) {
      cart[existing].qty += l.qty;
      cart.removeAt(i);
    } else {
      cart[i] = CartLine(np, l.qty);
    }
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    cart
      ..clear()
      ..addAll(_undo.removeLast());
    notifyListeners();
  }

  void clearCart() {
    if (cart.isNotEmpty) _snap();
    cart.clear();
    notifyListeners();
  }

  /// Sale finished: the cart is emptied and the undo history dropped.
  void finishSale() {
    cart.clear();
    _undo.clear();
    notifyListeners();
  }

  Future<void> holdCurrent(String label) async {
    if (cart.isEmpty) return;
    await Db.holdCart(cart, label);
    finishSale();
  }

  /// Puts a held invoice into the cart (on top of what is already there).
  Future<int> recall(int id) async {
    final lines = await Db.takeHeld(id);
    _snap();
    for (final l in lines) {
      final i = cart.indexWhere((x) => x.product.barcode == l.product.barcode && x.unit == l.unit);
      if (i >= 0) {
        cart[i].qty += l.qty;
      } else {
        cart.add(l);
      }
    }
    notifyListeners();
    return lines.length;
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
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')], subject: 'JØ PHARMA MOBILE sales');
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
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'JØ PHARMA MOBILE sales');
  }

  static Future<void> shareText(String text) => Share.share(text, subject: 'JØ PHARMA MOBILE');

  /// Plain-text receipt of a saved sale (readable in WhatsApp, SMS, any print-service app).
  static Future<String?> receiptText(String receiptNo) async {
    final d = await Db.db;
    final h = await d.query('sales', where: 'receipt_no=?', whereArgs: [receiptNo]);
    if (h.isEmpty) return null;
    final sale = h.first;
    final items = await Db.itemsOf(sale['id'] as int);
    final store = await Db.getSetting('store_name', 'JØ PHARMA');
    String line(String a, String b) => '${a.padRight(18)}${b.padLeft(14)}';
    final b = StringBuffer()
      ..writeln(store)
      ..writeln('${sale['receipt_no']}')
      ..writeln('${sale['created_at']}');
    if (('${sale['customer'] ?? ''}').isNotEmpty) b.writeln('${tr('customer')}: ${sale['customer']}');
    b.writeln('-' * 32);
    for (final i in items) {
      final unit = '${i['unit']}' == 'pack' ? '' : ' (${tr('unit_${i['unit']}')})';
      b.writeln('${i['name']}$unit');
      b.writeln(line('  ${fmtMoney(i['price'] as num)} x ${i['qty']}', fmtMoney(i['subtotal'] as num)));
    }
    b.writeln('-' * 32);
    b.writeln(line(tr('total'), fmtMoney(sale['subtotal'] as num)));
    if ((sale['discount'] as num) > 0) b.writeln(line(tr('discount'), '-${fmtMoney(sale['discount'] as num)}'));
    if (((sale['tax'] as num?) ?? 0) > 0) b.writeln(line(tr('tax'), fmtMoney(sale['tax'] as num)));
    b.writeln(line(tr('net'), '${fmtMoney(sale['net_total'] as num)} ${tr('currency')}'));
    b.writeln(line(tr('payment'), '${sale['payment']}'));
    final rc = ((sale['received'] as num?) ?? 0).toDouble();
    if (rc > 0) {
      b.writeln(line(tr('received'), fmtMoney(rc)));
      b.writeln(line(tr('change'), fmtMoney(rc - (sale['net_total'] as num))));
    }
    return b.toString();
  }

  /// Products + extra barcodes as CSV (opens in Excel; can be imported back, also into another phone).
  static Future<void> shareProducts() async {
    final rows = await Db.exportRows();
    final b = StringBuffer('\uFEFFbarcode,name,price,extra_barcodes\n');
    for (final r in rows) {
      b.writeln(r.map(_csv).join(','));
    }
    final f = await _tmp('jo_products_${_stamp()}.csv', utf8.encode(b.toString()));
    await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: 'JØ PHARMA MOBILE products');
  }

  static Future<void> shareDb() async {
    final d = await Db.db;
    await d.execute('PRAGMA wal_checkpoint(FULL)');
    final bytes = await File(await Db.dbPath()).readAsBytes();
    final f = await _tmp('jo_pos_backup_${_stamp()}.db', bytes);
    await Share.shareXFiles([XFile(f.path)], subject: 'JØ PHARMA MOBILE backup');
  }

}
