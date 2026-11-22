import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'codes.dart';

String two(int n) => n.toString().padLeft(2, '0');
String fmtDt(DateTime d) =>
    '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
String fmtMoney(num v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

String todayStr() {
  final n = DateTime.now();
  return '${n.year}-${two(n.month)}-${two(n.day)}';
}

String hashPassword(String pw) => sha256.convert(utf8.encode('jo-pos|$pw')).toString();

class Product {
  int? id;
  String barcode;
  String name;
  double price;
  String nameAr;
  int unitsPerPack; // tablets (units) in one pack
  int stripSize; // units in one strip (0 = not sold by strip)
  int? stock; // stock in units, null = unknown (not synced from the PC yet)
  String expiry; // earliest batch expiry (yyyy-MM-dd) from the PC, '' = unknown
  int minStock; // reorder level in PACKS (from the PC), 0 = none
  int? sellable; // units that are NOT expired (from the PC), null = unknown
  bool hasMeta; // true when nameAr / pack size / stock came from the PC or a database and must be saved
  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.price,
    this.nameAr = '',
    this.unitsPerPack = 1,
    this.stripSize = 0,
    this.stock,
    this.expiry = '',
    this.minStock = 0,
    this.sellable,
    this.hasMeta = false,
  });

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        nameAr: (m['name_ar'] as String?) ?? '',
        unitsPerPack: ((m['units_per_pack'] as num?)?.toInt() ?? 1).clamp(1, 100000),
        stripSize: (m['strip_size'] as num?)?.toInt() ?? 0,
        stock: (m['stock'] as num?)?.toInt(),
        expiry: (m['expiry'] as String?) ?? '',
        minStock: (m['min_stock'] as num?)?.toInt() ?? 0,
        sellable: (m['sellable'] as num?)?.toInt(),
      );

  /// Units that can really be sold now: the PC's non-expired stock when known, else the plain stock.
  int? get available => sellable ?? stock;

  /// Everything on the shelf is past its date (the PC refuses to sell it).
  bool get expired => expiry.isNotEmpty && expiry.compareTo(todayStr()) < 0 && (sellable ?? 0) <= 0 && (stock ?? 0) > 0;

  /// Days until the earliest expiry (negative = already expired), null when unknown.
  int? get daysToExpiry {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(expiry);
    if (m == null) return null;
    final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    final n = DateTime.now();
    return d.difference(DateTime(n.year, n.month, n.day)).inDays;
  }

  /// Ways this product can be sold, like the desktop: pack always; strip when a strip size is set; single unit when a pack has several.
  List<String> get unitOptions {
    final o = ['pack'];
    if (stripSize > 0 && stripSize < unitsPerPack) o.add('strip');
    if (unitsPerPack > 1) o.add('unit');
    return o;
  }

  /// Units (tablets) taken from stock by ONE sold [unit].
  int multOf(String unit) => unit == 'pack' ? unitsPerPack : (unit == 'strip' ? (stripSize > 0 ? stripSize : unitsPerPack) : 1);

  /// Same formula as the main JØ PHARMA program: price * mult / units_per_pack, 2 decimals.
  double priceFor(String unit) => unit == 'pack' ? double.parse(price.toStringAsFixed(2)) : double.parse((price * multOf(unit) / unitsPerPack).toStringAsFixed(2));
}

/// One product read from a file / database, with its extra barcodes.
class ImportItem {
  final Product product;
  final List<String> altCodes;
  ImportItem(this.product, [this.altCodes = const []]);
}

/// Products found in a file, before they are written to the database.
class ParseResult {
  final List<ImportItem> items = [];
  int rows = 0, noCode = 0, noName = 0, other = 0, sci = 0;
  int merged = 0; // same barcode on several rows: merged into one product
  int badNumbers = 0; // a price that is not a number (imported with price 0)
  int noPrice = 0; // products imported with price 0
  int namedByCode = 0; // no name in the file: the barcode is used as the name
}

/// How products that already exist are treated by an import.
enum ImportMode { all, priceOnly, newOnly }

/// What an import really did (shown to the user, and checked by re-reading the database).
class ImportReport {
  int rows = 0; // records read from the file
  int added = 0, updated = 0, unchanged = 0;
  int skippedNoCode = 0, skippedNoName = 0, skippedOther = 0, duplicatesInFile = 0;
  int altAdded = 0, altExisting = 0, altConflicts = 0, altPrimaryWins = 0;
  int sciWarnings = 0; // barcodes that Excel had turned into 1.23E+12
  int badNumbers = 0, noPrice = 0, namedByCode = 0;
  int mismatches = 0; // verification failures (must be 0)
  int productsAfter = 0, codesAfter = 0;
  final List<String> notes = [];

  int get imported => added + updated + unchanged;
  int get skipped => skippedNoCode + skippedNoName + skippedOther;
  bool get verified => mismatches == 0;
  bool get hasIssues =>
      skipped > 0 || duplicatesInFile > 0 || altConflicts > 0 || sciWarnings > 0 || mismatches > 0 || badNumbers > 0;

  void note(String s) {
    if (notes.length < 30) notes.add(s);
  }
}

class CartLine {
  Product product;
  int qty;
  String unit; // pack | strip | unit
  CartLine(this.product, [this.qty = 1, this.unit = 'pack']);
  double get price => product.priceFor(unit);
  double get subtotal => double.parse((price * qty).toStringAsFixed(2));
  int get baseUnits => qty * product.multOf(unit);
  CartLine copy() => CartLine(product, qty, unit);
}

class SaleHeader {
  final int id;
  final String receiptNo;
  final String createdAt;
  final double subtotal;
  final double discount;
  final double net;
  final String payment;
  final bool synced;
  final String note;
  final String customer;
  final double tax;
  final double received;
  final String cashier;
  SaleHeader(this.id, this.receiptNo, this.createdAt, this.subtotal, this.discount, this.net, this.payment, this.synced,
      [this.note = '', this.customer = '', this.tax = 0, this.received = 0, this.cashier = '']);

  factory SaleHeader.fromMap(Map<String, Object?> m) => SaleHeader(
        m['id'] as int,
        m['receipt_no'] as String,
        m['created_at'] as String,
        (m['subtotal'] as num).toDouble(),
        (m['discount'] as num).toDouble(),
        (m['net_total'] as num).toDouble(),
        m['payment'] as String,
        (m['synced'] as int) == 1,
        (m['sync_note'] as String?) ?? '',
        (m['customer'] as String?) ?? '',
        (m['tax'] as num?)?.toDouble() ?? 0,
        (m['received'] as num?)?.toDouble() ?? 0,
        (m['cashier'] as String?) ?? '',
      );
}

/// Numbers of a day / shift for the dashboard.
class DayReport {
  int count = 0;
  double sales = 0;
  double discounts = 0;
  int returnsCount = 0;
  double returns = 0;
  final Map<String, double> byPayment = {};
  final Map<String, double> returnsByPayment = {};
  final List<({String name, int qty, double total})> top = [];
  double get net => sales - returns;
}

enum ProductSort { name, newest, priceAsc, priceDesc }

class Db {
  static Database? _db;

  static const schemaVersion = 5;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await openAt(p.join(await getDatabasesPath(), 'jo_pos.db'));
    await _defaults();
    return _db!;
  }

  @visibleForTesting
  static Future<void> useForTest(Database d) async {
    _db = d;
    await _defaults();
  }

  @visibleForTesting
  static Future<void> reset() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
  }

  static Future<Database> openAt(String path) {
    return openDatabase(path, version: schemaVersion, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          price REAL NOT NULL DEFAULT 0,
          updated_at TEXT,
          name_ar TEXT,
          units_per_pack INTEGER NOT NULL DEFAULT 1,
          strip_size INTEGER NOT NULL DEFAULT 0,
          stock INTEGER,
          expiry TEXT,
          min_stock INTEGER NOT NULL DEFAULT 0,
          sellable INTEGER)''');
      await d.execute('''CREATE TABLE alternatives(
          product_id INTEGER NOT NULL,
          alt_id INTEGER NOT NULL,
          PRIMARY KEY(product_id, alt_id))''');
      await d.execute('''CREATE TABLE sales(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          receipt_no TEXT UNIQUE NOT NULL,
          created_at TEXT NOT NULL,
          subtotal REAL NOT NULL,
          discount REAL NOT NULL DEFAULT 0,
          net_total REAL NOT NULL,
          payment TEXT NOT NULL DEFAULT 'Cash',
          cashier TEXT,
          synced INTEGER NOT NULL DEFAULT 0,
          sync_note TEXT,
          customer TEXT,
          tax REAL NOT NULL DEFAULT 0,
          received REAL NOT NULL DEFAULT 0)''');
      await d.execute('''CREATE TABLE sale_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          qty INTEGER NOT NULL,
          subtotal REAL NOT NULL,
          unit TEXT NOT NULL DEFAULT 'pack',
          base_units INTEGER NOT NULL DEFAULT 0)''');
      await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
      await d.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');
      await d.execute('CREATE INDEX idx_sales_synced ON sales(synced)');
      await _createCodes(d);
      await _createV4(d);
      await _createV5(d);
    }, onUpgrade: (d, from, to) async {
      if (from < 2) {
        await _createCodes(d);
        await _normalizeStored(d);
      }
      if (from < 3) {
        await d.execute('ALTER TABLE sales ADD COLUMN sync_note TEXT');
      }
      if (from < 4) {
        for (final a in const [
          'ALTER TABLE products ADD COLUMN name_ar TEXT',
          'ALTER TABLE products ADD COLUMN units_per_pack INTEGER NOT NULL DEFAULT 1',
          'ALTER TABLE products ADD COLUMN strip_size INTEGER NOT NULL DEFAULT 0',
          'ALTER TABLE products ADD COLUMN stock INTEGER',
          'ALTER TABLE sales ADD COLUMN customer TEXT',
          'ALTER TABLE sales ADD COLUMN tax REAL NOT NULL DEFAULT 0',
          'ALTER TABLE sales ADD COLUMN received REAL NOT NULL DEFAULT 0',
          "ALTER TABLE sale_items ADD COLUMN unit TEXT NOT NULL DEFAULT 'pack'",
          'ALTER TABLE sale_items ADD COLUMN base_units INTEGER NOT NULL DEFAULT 0',
        ]) {
          await d.execute(a);
        }
        await _createV4(d);
      }
      if (from < 5) {
        for (final a in const [
          'ALTER TABLE products ADD COLUMN expiry TEXT',
          'ALTER TABLE products ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 0',
          'ALTER TABLE products ADD COLUMN sellable INTEGER',
        ]) {
          await d.execute(a);
        }
        await _createV5(d);
        if (from >= 4) {
          await d.execute('ALTER TABLE returns ADD COLUMN sync_state INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE returns ADD COLUMN sync_note TEXT');
        }
      }
    });
  }

  /// Customers synced from the PC (name + credit balance), and the sync state of returns.
  static Future<void> _createV5(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS customers(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        balance REAL NOT NULL DEFAULT 0)''');
  }

  /// Held invoices, returns and cashier shifts.
  static Future<void> _createV4(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS held(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        created_at TEXT NOT NULL,
        cart_json TEXT NOT NULL)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS returns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_no TEXT UNIQUE NOT NULL,
        sale_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        total REAL NOT NULL,
        payment TEXT NOT NULL,
        cashier TEXT,
        sync_state INTEGER NOT NULL DEFAULT 0,
        sync_note TEXT)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS return_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        sale_item_id INTEGER NOT NULL,
        barcode TEXT NOT NULL,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        qty INTEGER NOT NULL,
        price REAL NOT NULL,
        subtotal REAL NOT NULL,
        base_units INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening REAL NOT NULL DEFAULT 0,
        expected REAL,
        counted REAL,
        cashier TEXT)''');
  }

  /// Extra barcodes of a product (desktop item_codes, extra Excel columns). The primary barcode stays in products.
  static Future<void> _createCodes(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS product_codes(
        code TEXT PRIMARY KEY NOT NULL,
        product_id INTEGER NOT NULL)''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_product_codes_pid ON product_codes(product_id)');
  }

  /// One-time clean-up of barcodes saved by the first version (Arabic digits, spaces, hidden characters).
  static Future<void> _normalizeStored(Database d) async {
    final rows = await d.query('products', columns: ['id', 'barcode']);
    final count = <String, int>{};
    for (final r in rows) {
      final n = Codes.norm(r['barcode'] as String?);
      count[n] = (count[n] ?? 0) + 1;
    }
    for (final r in rows) {
      final old = (r['barcode'] as String?) ?? '';
      final n = Codes.norm(old);
      if (n != old && !Codes.isJunk(n) && count[n] == 1) {
        await d.update('products', {'barcode': n}, where: 'id=?', whereArgs: [r['id']]);
      }
    }
  }

  static Future<String> dbPath() async => p.join(await getDatabasesPath(), 'jo_pos.db');

  // ---------------------------------------------------------------- settings
  static Future<void> _defaults() async {
    final rnd = Random.secure();
    final devId = List.generate(4, (_) => rnd.nextInt(16).toRadixString(16)).join().toUpperCase();
    final defs = {
      'device_id': devId,
      'device_name': 'Phone-$devId',
      'username': 'admin',
      'pw_hash': hashPassword('1234'),
      'lang': 'ar',
      'server_url': '',
      'pair_key': '',
      'remember': '0',
    };
    for (final e in defs.entries) {
      await _db!.insert('settings', {'k': e.key, 'v': e.value}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<String> getSetting(String k, [String def = '']) async {
    final d = await db;
    final r = await d.query('settings', where: 'k=?', whereArgs: [k], limit: 1);
    return r.isEmpty ? def : ((r.first['v'] as String?) ?? def);
  }

  static Future<void> setSetting(String k, String v) async {
    final d = await db;
    await d.insert('settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------- products
  static (String where, List<Object?> args) _filter(String q, bool noPrice) {
    final s = Codes.latinDigits(q.trim());
    final w = <String>[];
    final a = <Object?>[];
    if (s.isNotEmpty) {
      w.add('(name LIKE ? OR name_ar LIKE ? OR barcode LIKE ? OR id IN (SELECT product_id FROM product_codes WHERE code LIKE ?))');
      a.addAll(['%$s%', '%$s%', '%$s%', '%${s.toUpperCase()}%']);
    }
    if (noPrice) w.add('price<=0');
    return (w.isEmpty ? '1=1' : w.join(' AND '), a);
  }

  static String _order(ProductSort sort) => switch (sort) {
        ProductSort.name => 'name COLLATE NOCASE',
        ProductSort.newest => 'id DESC',
        ProductSort.priceAsc => 'price ASC, name COLLATE NOCASE',
        ProductSort.priceDesc => 'price DESC, name COLLATE NOCASE',
      };

  static Future<List<Product>> searchProducts(String q,
      {int limit = 60, int offset = 0, ProductSort sort = ProductSort.name, bool noPrice = false}) async {
    final d = await db;
    final f = _filter(q, noPrice);
    final rows = await d.query('products', where: f.$1, whereArgs: f.$2, orderBy: _order(sort), limit: limit, offset: offset);
    return rows.map(Product.fromMap).toList();
  }

  /// Number of products matching the search / filter (the list shows them page by page).
  static Future<int> countMatching(String q, {bool noPrice = false}) async {
    final d = await db;
    final f = _filter(q, noPrice);
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM products WHERE ${f.$1}', f.$2)) ?? 0;
  }

  /// Ids of EVERY product matching the search / filter (for "select all").
  static Future<List<int>> idsMatching(String q, {bool noPrice = false}) async {
    final d = await db;
    final f = _filter(q, noPrice);
    final r = await d.query('products', columns: ['id'], where: f.$1, whereArgs: f.$2);
    return r.map((e) => e['id'] as int).toList();
  }

  /// Deletes the products with their extra barcodes and alternative links (past sales keep their own copy of name/price).
  static Future<int> deleteProducts(Iterable<int> ids) async {
    final d = await db;
    final all = ids.toList();
    var n = 0;
    await d.transaction((t) async {
      for (var i = 0; i < all.length; i += 400) {
        final chunk = all.sublist(i, i + 400 > all.length ? all.length : i + 400);
        final q = List.filled(chunk.length, '?').join(',');
        await t.delete('alternatives', where: 'product_id IN ($q) OR alt_id IN ($q)', whereArgs: [...chunk, ...chunk]);
        await t.delete('product_codes', where: 'product_id IN ($q)', whereArgs: chunk);
        n += await t.delete('products', where: 'id IN ($q)', whereArgs: chunk);
      }
    });
    return n;
  }

  static Future<int> deleteAllProducts() async {
    final d = await db;
    var n = 0;
    await d.transaction((t) async {
      await t.delete('alternatives');
      await t.delete('product_codes');
      n = await t.delete('products');
    });
    return n;
  }

  /// Raises (+) or lowers (-) the price of the given products by [percent], rounded to 2 decimals (never below 0).
  static Future<int> adjustPrices(Iterable<int> ids, double percent) async {
    final d = await db;
    final all = ids.toList();
    final f = 1 + percent / 100;
    var n = 0;
    final now = fmtDt(DateTime.now());
    await d.transaction((t) async {
      for (var i = 0; i < all.length; i += 400) {
        final chunk = all.sublist(i, i + 400 > all.length ? all.length : i + 400);
        final q = List.filled(chunk.length, '?').join(',');
        n += await t.rawUpdate(
            'UPDATE products SET price=MAX(0, ROUND(price*?, 2)), updated_at=? WHERE id IN ($q)', [f, now, ...chunk]);
      }
    });
    return n;
  }

  /// Replaces the extra barcodes of a product. Codes that belong to ANOTHER product are refused and returned.
  static Future<List<String>> setCodes(int productId, List<String> codes) async {
    final d = await db;
    final refused = <String>[];
    await d.transaction((t) async {
      final own = await t.query('products', columns: ['barcode'], where: 'id=?', whereArgs: [productId]);
      final primary = own.isEmpty ? '' : Codes.norm(own.first['barcode'] as String?);
      await t.delete('product_codes', where: 'product_id=?', whereArgs: [productId]);
      for (final raw in codes.map(Codes.norm).toSet()) {
        if (raw == primary || Codes.isJunk(raw)) continue;
        if (await _codeTaken(t, raw, exceptProduct: productId)) {
          refused.add(raw);
          continue;
        }
        await t.insert('product_codes', {'code': raw, 'product_id': productId}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    return refused;
  }

  /// All products with their extra barcodes, for the CSV export.
  static Future<List<List<String>>> exportRows() async {
    final d = await db;
    final extra = <int, List<String>>{};
    for (final r in await d.query('product_codes', orderBy: 'code')) {
      (extra[r['product_id'] as int] ??= []).add(r['code'] as String);
    }
    final out = <List<String>>[];
    for (final r in await d.query('products', orderBy: 'name COLLATE NOCASE')) {
      out.add([
        r['barcode'] as String,
        r['name'] as String,
        fmtMoney((r['price'] as num).toDouble()),
        (extra[r['id'] as int] ?? const []).join(' | '),
      ]);
    }
    return out;
  }

  /// Finds a product from a scanned / typed code: primary barcode, then extra barcodes,
  /// then the same code without leading zeros (only when that is unambiguous).
  static Future<Product?> byBarcode(String raw) async {
    final d = await db;
    final code = Codes.norm(raw);
    if (code.isEmpty) return null;
    var r = await d.query('products', where: 'barcode=?', whereArgs: [code], limit: 1);
    if (r.isNotEmpty) return Product.fromMap(r.first);
    r = await d.rawQuery(
        'SELECT p.* FROM products p JOIN product_codes c ON c.product_id=p.id WHERE c.code=? LIMIT 1', [code]);
    if (r.isNotEmpty) return Product.fromMap(r.first);
    final trimmed = raw.trim();
    if (trimmed != code) {
      r = await d.query('products', where: 'barcode=?', whereArgs: [trimmed], limit: 1);
      if (r.isNotEmpty) return Product.fromMap(r.first);
    }
    final loose = Codes.loose(code);
    if (loose != code || RegExp(r'^\d{7,}$').hasMatch(code)) {
      r = await d.rawQuery("SELECT * FROM products WHERE LTRIM(barcode,'0')=? LIMIT 2", [loose]);
      if (r.length == 1) return Product.fromMap(r.first);
      if (r.isEmpty) {
        r = await d.rawQuery(
            "SELECT DISTINCT p.* FROM products p JOIN product_codes c ON c.product_id=p.id WHERE LTRIM(c.code,'0')=? LIMIT 2",
            [loose]);
        if (r.length == 1) return Product.fromMap(r.first);
      }
    }
    return null;
  }

  static Future<List<String>> codesOf(int productId) async {
    final d = await db;
    final r = await d.query('product_codes', where: 'product_id=?', whereArgs: [productId], orderBy: 'code');
    return r.map((e) => e['code'] as String).toList();
  }

  static Future<int> productCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
  }

  static Future<int> codeCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM product_codes')) ?? 0;
  }

  static Future<bool> _codeTaken(DatabaseExecutor d, String code, {int? exceptProduct}) async {
    final a = await d.query('products', columns: ['id'], where: 'barcode=?', whereArgs: [code]);
    if (a.any((e) => e['id'] != exceptProduct)) return true;
    final b = await d.query('product_codes', columns: ['product_id'], where: 'code=?', whereArgs: [code]);
    return b.any((e) => e['product_id'] != exceptProduct);
  }

  /// Returns the new id, or null when the barcode already exists (as a primary or an extra code).
  static Future<int?> insertProduct(Product x) async {
    final d = await db;
    final code = Codes.norm(x.barcode);
    if (Codes.isJunk(code) || await _codeTaken(d, code)) return null;
    try {
      return await d.insert('products',
          {'barcode': code, 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now()), ..._metaAlways(x)});
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return null;
      rethrow;
    }
  }

  /// False when the new barcode collides with another product.
  static Future<bool> updateProduct(Product x) async {
    final d = await db;
    final code = Codes.norm(x.barcode);
    if (Codes.isJunk(code) || await _codeTaken(d, code, exceptProduct: x.id)) return false;
    try {
      await d.transaction((t) async {
        await t.update('products',
            {'barcode': code, 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now()), ..._metaAlways(x)},
            where: 'id=?', whereArgs: [x.id]);
        await t.delete('product_codes', where: 'code=?', whereArgs: [code]); // now it is the primary
      });
      return true;
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return false;
      rethrow;
    }
  }

  static Future<void> deleteProduct(int id) async {
    final d = await db;
    await d.transaction((t) async {
      await t.delete('alternatives', where: 'product_id=? OR alt_id=?', whereArgs: [id, id]);
      await t.delete('product_codes', where: 'product_id=?', whereArgs: [id]);
      await t.delete('products', where: 'id=?', whereArgs: [id]);
    });
  }

  /// Plain products (no extra codes): used by the desktop pull and JSON import.
  static Map<String, Object?> _metaAlways(Product x) =>
      {'name_ar': x.nameAr, 'units_per_pack': x.unitsPerPack < 1 ? 1 : x.unitsPerPack, 'strip_size': x.stripSize, 'stock': x.stock, 'expiry': x.expiry, 'min_stock': x.minStock, 'sellable': x.sellable};

  static Map<String, Object?> _meta(Product x) => x.hasMeta
      ? {'name_ar': x.nameAr, 'units_per_pack': x.unitsPerPack, 'strip_size': x.stripSize, 'stock': x.stock, 'expiry': x.expiry, 'min_stock': x.minStock, 'sellable': x.sellable}
      : const {};

  static Future<int> bulkUpsert(List<Product> items) async =>
      (await importBatch(items.map((e) => ImportItem(e)).toList())).imported;

  /// Insert-or-update by (normalised) barcode, plus extra barcodes, in ONE transaction, then re-reads
  /// the database and compares it with the file. Nothing is half-imported: on an error everything rolls back.
  ///  * the same barcode twice in the file: the last row wins (counted in the report);
  ///  * an extra code that is another product's primary / extra code is NOT taken (counted as a conflict);
  ///  * when a code becomes a product's primary barcode it stops being an extra code of another product.
  static Future<ImportReport> importBatch(List<ImportItem> items,
      {ImportReport? into, ImportMode mode = ImportMode.all}) async {
    final d = await db;
    final rep = into ?? ImportReport();
    if (rep.rows == 0) rep.rows = items.length;

    // 1) normalise + merge duplicates inside the file
    final byCode = <String, ImportItem>{};
    for (final it in items) {
      final code = Codes.norm(it.product.barcode);
      final name = it.product.name.trim();
      if (Codes.isJunk(code)) {
        rep.skippedNoCode++;
        continue;
      }
      if (name.isEmpty) {
        rep.skippedNoName++;
        continue;
      }
      final prev = byCode[code];
      if (prev != null) {
        rep.duplicatesInFile++;
        rep.note('dup $code: ${prev.product.name} -> $name');
      }
      final alts = <String>{...?prev?.altCodes, ...it.altCodes}.toList();
      final xp = it.product;
      byCode[code] = ImportItem(
          Product(
              barcode: code,
              name: name,
              price: xp.price,
              nameAr: xp.nameAr,
              unitsPerPack: xp.unitsPerPack,
              stripSize: xp.stripSize,
              stock: xp.stock,
              expiry: xp.expiry,
              minStock: xp.minStock,
              sellable: xp.sellable,
              hasMeta: xp.hasMeta),
          alts);
    }

    final expectedAlts = <String, String>{}; // extra code -> its primary
    final existingBefore = <String>{};
    await d.transaction((t) async {
      // 2) products
      final existing = <String, Map<String, Object?>>{};
      final norms = <String, int>{};
      for (final r in await t.query('products', columns: ['id', 'barcode', 'name', 'price', 'name_ar', 'units_per_pack', 'strip_size', 'stock', 'expiry', 'min_stock', 'sellable'])) {
        final n = Codes.norm(r['barcode'] as String?);
        existing[n] = r;
        existingBefore.add(n);
        norms[n] = (norms[n] ?? 0) + 1;
      }
      final now = fmtDt(DateTime.now());
      final b = t.batch();
      for (final e in byCode.entries) {
        final ex = existing[e.key];
        final x = e.value.product;
        if (ex == null) {
          b.insert('products', {'barcode': e.key, 'name': x.name, 'price': x.price, 'updated_at': now, ..._meta(x)},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          rep.added++;
        } else {
          final oldPrice = (ex['price'] as num).toDouble();
          // a price of 0 in the file means "not given": it never wipes a price the product already has
          final newPrice = x.price > 0 ? x.price : oldPrice;
          // a name that is only the barcode (file had no name) never replaces a real name
          final newName = (mode == ImportMode.all && x.name != e.key) ? x.name : '${ex['name']}';
          final same = ex['name'] == newName && (oldPrice - newPrice).abs() < 0.0005;
          final fixCode = ex['barcode'] != e.key && norms[e.key] == 1;
          final metaChanged = x.hasMeta &&
              (ex['name_ar'] != x.nameAr ||
                  ex['units_per_pack'] != x.unitsPerPack ||
                  ex['strip_size'] != x.stripSize ||
                  ex['stock'] != x.stock ||
                  (ex['expiry'] ?? '') != x.expiry ||
                  ex['min_stock'] != x.minStock ||
                  ex['sellable'] != x.sellable);
          if (mode == ImportMode.newOnly) {
            rep.unchanged++;
          } else if (same && !fixCode && metaChanged) {
            b.update('products', _meta(x), where: 'id=?', whereArgs: [ex['id']]); // stock / pack size only: not a "change" for the report
            rep.unchanged++;
          } else if (same && !fixCode) {
            rep.unchanged++;
          } else {
            b.update(
                'products',
                {
                  if (fixCode) 'barcode': e.key,
                  'name': newName,
                  'price': newPrice,
                  'updated_at': now,
                  ..._meta(x),
                },
                where: 'id=?',
                whereArgs: [ex['id']]);
            if (same) {
              rep.unchanged++;
            } else {
              rep.updated++;
            }
          }
        }
      }
      await b.commit(noResult: true);

      // 3) extra barcodes
      final ids = <String, int>{};
      for (final r in await t.query('products', columns: ['id', 'barcode'])) {
        ids[Codes.norm(r['barcode'] as String?)] = r['id'] as int;
      }
      final alts = <String, int>{};
      for (final r in await t.query('product_codes')) {
        alts[r['code'] as String] = r['product_id'] as int;
      }
      final b2 = t.batch();
      for (final e in byCode.entries) {
        final pid = ids[e.key];
        if (pid == null) continue;
        final owner = alts[e.key];
        if (owner != null) {
          b2.delete('product_codes', where: 'code=?', whereArgs: [e.key]); // the primary barcode always wins
          alts.remove(e.key);
          if (owner != pid) rep.altPrimaryWins++;
        }
      }
      for (final e in byCode.entries) {
        final pid = ids[e.key];
        if (pid == null) continue;
        for (final raw in e.value.altCodes) {
          final ac = Codes.norm(raw);
          if (ac == e.key || Codes.isJunk(ac) || ac.length < 4) continue;
          final primaryOwner = ids[ac];
          if (primaryOwner != null) {
            if (primaryOwner != pid) {
              rep.altConflicts++;
              rep.note('conflict $ac (${e.key}) belongs to another product');
            }
            continue;
          }
          final cur = alts[ac];
          if (cur == null) {
            b2.insert('product_codes', {'code': ac, 'product_id': pid}, conflictAlgorithm: ConflictAlgorithm.ignore);
            alts[ac] = pid;
            rep.altAdded++;
          } else if (cur == pid) {
            rep.altExisting++;
          } else {
            rep.altConflicts++;
            rep.note('conflict $ac (${e.key}) already belongs to another product');
            continue;
          }
          expectedAlts[ac] = e.key;
        }
      }
      await b2.commit(noResult: true);
    });

    // 4) verify by reading everything back
    final stored = <String, Map<String, Object?>>{};
    for (final r in await d.query('products', columns: ['id', 'barcode', 'name', 'price'])) {
      stored[Codes.norm(r['barcode'] as String?)] = r;
    }
    final idByCode = {for (final e in stored.entries) e.key: e.value['id'] as int};
    for (final e in byCode.entries) {
      final r = stored[e.key];
      final wasThere = existingBefore.contains(e.key);
      final checkName = !wasThere || (mode == ImportMode.all && e.value.product.name != e.key);
      final checkPrice = (mode != ImportMode.newOnly || !wasThere) && e.value.product.price > 0;
      if (r == null ||
          (checkName && r['name'] != e.value.product.name) ||
          (checkPrice && ((r['price'] as num).toDouble() - e.value.product.price).abs() >= 0.0005)) {
        rep.mismatches++;
        rep.note('verify failed: ${e.key}');
      }
    }
    final codeRows = {for (final r in await d.query('product_codes')) r['code'] as String: r['product_id'] as int};
    for (final e in expectedAlts.entries) {
      if (codeRows[e.key] == null || codeRows[e.key] != idByCode[e.value]) {
        rep.mismatches++;
        rep.note('verify failed (extra code): ${e.key}');
      }
    }
    rep.productsAfter = stored.length;
    rep.codesAfter = codeRows.length;
    return rep;
  }

  // ------------------------------------------------------------ alternatives
  static Future<List<Product>> altsOf(int productId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT p.* FROM products p JOIN alternatives a ON a.alt_id=p.id WHERE a.product_id=? ORDER BY p.name COLLATE NOCASE',
        [productId]);
    return r.map(Product.fromMap).toList();
  }

  static Future<int> altCount(int productId) async {
    final d = await db;
    return Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM alternatives WHERE product_id=?', [productId])) ??
        0;
  }

  /// Replace the alternatives of [productId]; links are stored both ways.
  static Future<void> setAlts(int productId, List<int> altIds) async {
    final d = await db;
    await d.transaction((t) async {
      await t.delete('alternatives', where: 'product_id=? OR alt_id=?', whereArgs: [productId, productId]);
      for (final a in altIds.toSet()) {
        if (a == productId) continue;
        await t.insert('alternatives', {'product_id': productId, 'alt_id': a},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await t.insert('alternatives', {'product_id': a, 'alt_id': productId},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  // ------------------------------------------------------------------- sales
  static Future<String> createSale(List<CartLine> lines, double discount, String payment, String cashier,
      {String customer = '', double received = 0, double tax = 0}) async {
    final d = await db;
    final devId = await getSetting('device_id', 'DEV');
    final now = DateTime.now();
    final prefix = 'MB-$devId-${two(now.year % 100)}${two(now.month)}${two(now.day)}-';
    final subtotal = double.parse(lines.fold<double>(0, (a, l) => a + l.subtotal).toStringAsFixed(2));
    final disc = discount.clamp(0, subtotal).toDouble();
    final taxAmt = double.parse(tax.clamp(0, 1e9).toStringAsFixed(2));
    late String receipt;
    await d.transaction((t) async {
      var n = (Sqflite.firstIntValue(
                  await t.rawQuery('SELECT COUNT(*) FROM sales WHERE receipt_no LIKE ?', ['$prefix%'])) ??
              0) +
          1;
      while ((await t.query('sales', where: 'receipt_no=?', whereArgs: ['$prefix${n.toString().padLeft(4, '0')}'])).isNotEmpty) {
        n++;
      }
      receipt = '$prefix${n.toString().padLeft(4, '0')}';
      final id = await t.insert('sales', {
        'receipt_no': receipt,
        'created_at': fmtDt(now),
        'subtotal': subtotal,
        'discount': disc,
        'net_total': double.parse((subtotal - disc + taxAmt).toStringAsFixed(2)),
        'payment': payment,
        'cashier': cashier,
        'synced': 0,
        'customer': customer.trim().isEmpty ? null : customer.trim(),
        'tax': taxAmt,
        'received': received,
      });
      for (final l in lines) {
        await t.insert('sale_items', {
          'sale_id': id,
          'barcode': l.product.barcode,
          'name': l.product.name,
          'price': l.price,
          'qty': l.qty,
          'subtotal': l.subtotal,
          'unit': l.unit,
          'base_units': l.baseUnits,
        });
        // keeps the shelf count honest until the next refresh from the PC
        await t.rawUpdate('UPDATE products SET stock=MAX(0, stock-?) WHERE barcode=? AND stock IS NOT NULL',
            [l.baseUnits, l.product.barcode]);
      }
      // a CREDIT sale raises the customer's balance right away (the PC's own figure replaces it on the next catalog refresh)
      final c = customer.trim();
      if (payment == 'Credit' && c.isNotEmpty) {
        final net = double.parse((subtotal - disc + taxAmt).toStringAsFixed(2));
        await t.rawUpdate('UPDATE customers SET balance=round(balance+?,2) WHERE lower(name)=lower(?)', [(net - received).clamp(0, 1e12).toDouble(), c]);
      }
    });
    return receipt;
  }

  // ------------------------------------------------------- held invoices
  static Future<int> holdCart(List<CartLine> lines, String label) async {
    final d = await db;
    final json = jsonEncode([
      for (final l in lines) {'barcode': l.product.barcode, 'qty': l.qty, 'unit': l.unit}
    ]);
    return d.insert('held', {'label': label.trim().isEmpty ? fmtDt(DateTime.now()).substring(11, 16) : label.trim(), 'created_at': fmtDt(DateTime.now()), 'cart_json': json});
  }

  static Future<List<Map<String, Object?>>> heldList() async {
    final d = await db;
    final r = await d.query('held', orderBy: 'id DESC');
    return [
      for (final h in r)
        {
          'id': h['id'],
          'label': h['label'],
          'created_at': h['created_at'],
          'count': (jsonDecode(h['cart_json'] as String) as List).length,
        }
    ];
  }

  /// Lines of a held invoice with the CURRENT product data (a product deleted meanwhile is skipped).
  static Future<List<CartLine>> takeHeld(int id) async {
    final d = await db;
    final r = await d.query('held', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) return [];
    final out = <CartLine>[];
    for (final e in (jsonDecode(r.first['cart_json'] as String) as List)) {
      final p = await byBarcode('${e['barcode']}');
      if (p == null) continue;
      final unit = '${e['unit']}';
      out.add(CartLine(p, (e['qty'] as num).toInt(), p.unitOptions.contains(unit) ? unit : 'pack'));
    }
    await d.delete('held', where: 'id=?', whereArgs: [id]);
    return out;
  }

  static Future<void> deleteHeld(int id) async {
    final d = await db;
    await d.delete('held', where: 'id=?', whereArgs: [id]);
  }

  // ------------------------------------------------------- quick access / reports
  /// Best sellers (by sold units): the "fast items" row of the sell screen.
  static Future<List<Product>> topSold({int limit = 12}) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT p.* FROM products p JOIN (SELECT barcode, SUM(qty) q FROM sale_items GROUP BY barcode ORDER BY q DESC LIMIT ?) s ON s.barcode=p.barcode ORDER BY s.q DESC',
        [limit]);
    return r.map(Product.fromMap).toList();
  }

  /// Products whose known stock (units) is at or under [threshold], or at or under their reorder level set on the PC.
  static Future<List<Product>> lowStock({int threshold = 5, int limit = 200}) async {
    final d = await db;
    final r = await d.query('products',
        where: 'stock IS NOT NULL AND (stock<=? OR (min_stock>0 AND stock<=min_stock*units_per_pack))',
        whereArgs: [threshold],
        orderBy: 'stock, name COLLATE NOCASE',
        limit: limit);
    return r.map(Product.fromMap).toList();
  }

  /// Products with stock on the shelf whose earliest expiry is within [days] days (already expired ones first).
  static Future<List<Product>> expiringSoon({int days = 90, int limit = 200}) async {
    final d = await db;
    final n = DateTime.now().add(Duration(days: days));
    final lim = '${n.year}-${two(n.month)}-${two(n.day)}';
    final r = await d.query('products',
        where: "expiry IS NOT NULL AND expiry<>'' AND expiry<=? AND stock IS NOT NULL AND stock>0", whereArgs: [lim], orderBy: 'expiry, name COLLATE NOCASE', limit: limit);
    return r.map(Product.fromMap).toList();
  }

  // ---------------------------------------------------------- customers
  static Future<void> replaceCustomers(List<dynamic> rows) async {
    final d = await db;
    await d.transaction((t) async {
      await t.delete('customers');
      final b = t.batch();
      for (final r in rows) {
        if (r is! List || r.length < 4 || r[0] is! int) continue;
        b.insert('customers', {'id': r[0], 'name': '${r[1]}', 'phone': '${r[2]}', 'balance': (r[3] is num ? (r[3] as num).toDouble() : 0.0)}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await b.commit(noResult: true);
    });
  }

  static Future<List<({String name, String phone, double balance})>> searchCustomers(String q, {int limit = 5}) async {
    final d = await db;
    final s = q.trim();
    if (s.isEmpty) return [];
    final r = await d.query('customers', where: 'name LIKE ? OR phone LIKE ?', whereArgs: ['%$s%', '%$s%'], orderBy: 'name COLLATE NOCASE', limit: limit);
    return [for (final e in r) (name: '${e['name']}', phone: '${e['phone'] ?? ''}', balance: (e['balance'] as num).toDouble())];
  }

  /// Balance the PC reported for a customer (exact name, case-insensitive), null when unknown.
  static Future<double?> customerBalance(String name) async {
    final d = await db;
    final r = await d.query('customers', where: 'lower(name)=lower(?)', whereArgs: [name.trim()], limit: 1);
    return r.isEmpty ? null : (r.first['balance'] as num).toDouble();
  }

  // ------------------------------------------------- returns -> PC
  /// Returns waiting for the PC. Only those whose sale the PC already has (otherwise it could not find it).
  static Future<List<Map<String, Object?>>> lanReturns() async {
    final d = await db;
    final install = await installId();
    final device = await getSetting('device_name');
    final heads = await d.rawQuery(
        'SELECT r.*, s.receipt_no AS sale_receipt FROM returns r JOIN sales s ON s.id=r.sale_id WHERE r.sync_state=0 AND s.synced=1 ORDER BY r.id');
    final out = <Map<String, Object?>>[];
    for (final h in heads) {
      final items = await d.query('return_items', where: 'return_id=?', whereArgs: [h['id']], orderBy: 'id');
      if (items.isEmpty) continue;
      out.add({
        'client_return_id': '$install-${h['receipt_no']}',
        'client_sale_id': '$install-${h['sale_receipt']}',
        'cashier': h['cashier'],
        'device_name': device,
        'items': [
          for (final i in items) {'barcode': i['barcode'], 'qty': i['qty'], 'unit': i['unit']}
        ],
      });
    }
    return out;
  }

  static Future<int> unsyncedReturns() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM returns WHERE sync_state=0')) ?? 0;
  }

  /// state: 1 = the PC has it, 2 = the PC refused it (see note), 0 = try again.
  static Future<void> setReturnResult(String receiptNo, int state, {String note = ''}) async {
    final d = await db;
    await d.update('returns', {'sync_state': state, 'sync_note': note.isEmpty ? null : note}, where: 'receipt_no=?', whereArgs: [receiptNo]);
  }

  static Future<int> stockKnownCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM products WHERE stock IS NOT NULL')) ?? 0;
  }

  /// Numbers of one day (yyyy-MM-dd) or of everything since [since] (a "yyyy-MM-dd HH:mm:ss" text).
  static Future<DayReport> report({String? day, String? since}) async {
    final d = await db;
    final w = day != null ? 'created_at LIKE ?' : 'created_at >= ?';
    final a = day != null ? ['$day%'] : [since ?? '0000'];
    final r = DayReport();
    final s = await d.rawQuery('SELECT COUNT(*) c, COALESCE(SUM(net_total),0) t, COALESCE(SUM(discount),0) disc FROM sales WHERE $w', a);
    r.count = s.first['c'] as int;
    r.sales = (s.first['t'] as num).toDouble();
    r.discounts = (s.first['disc'] as num).toDouble();
    for (final e in await d.rawQuery('SELECT payment, COUNT(*) c, SUM(net_total) t FROM sales WHERE $w GROUP BY payment', a)) {
      r.byPayment['${e['payment']}'] = (e['t'] as num).toDouble();
    }
    final rr = await d.rawQuery('SELECT COUNT(*) c, COALESCE(SUM(total),0) t FROM returns WHERE $w', a);
    r.returnsCount = rr.first['c'] as int;
    r.returns = (rr.first['t'] as num).toDouble();
    for (final e in await d.rawQuery('SELECT payment, SUM(total) t FROM returns WHERE $w GROUP BY payment', a)) {
      r.returnsByPayment['${e['payment']}'] = (e['t'] as num).toDouble();
    }
    final wi = day != null ? 's.created_at LIKE ?' : 's.created_at >= ?';
    for (final e in await d.rawQuery(
        'SELECT i.name n, SUM(i.qty) q, SUM(i.subtotal) t FROM sale_items i JOIN sales s ON s.id=i.sale_id WHERE $wi GROUP BY i.barcode ORDER BY q DESC LIMIT 8',
        a)) {
      r.top.add((name: '${e['n']}', qty: (e['q'] as num).toInt(), total: (e['t'] as num).toDouble()));
    }
    return r;
  }

  // ------------------------------------------------------------ returns
  /// Items of a sale with how many of each were already returned.
  static Future<List<({int itemId, String barcode, String name, String unit, int qty, int returned, double price})>> returnable(int saleId) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT i.id, i.barcode, i.name, i.unit, i.qty, i.price, COALESCE((SELECT SUM(qty) FROM return_items x WHERE x.sale_item_id=i.id),0) ret FROM sale_items i WHERE i.sale_id=? ORDER BY i.id',
        [saleId]);
    return [
      for (final e in r)
        (
          itemId: e['id'] as int,
          barcode: '${e['barcode']}',
          name: '${e['name']}',
          unit: '${e['unit']}',
          qty: e['qty'] as int,
          returned: (e['ret'] as num).toInt(),
          price: (e['price'] as num).toDouble()
        )
    ];
  }

  /// What a returned amount really is: the lines at the price actually paid.  A sale with a discount / tax refunds the same share of
  /// them (the PC does exactly this), so the phone and the PC always agree on the refund.
  static double refundFactor(double subtotal, double net) => subtotal > 0.004 ? net / subtotal : 1.0;

  /// Returns [qtyByItem] (sale_item id -> units to take back). Stock is restored. Never more than was sold.
  /// Local record (the desktop receiver takes sales only): shown in the day report and the shift cash.
  static Future<String?> createReturn(int saleId, Map<int, int> qtyByItem, String cashier) async {
    final d = await db;
    final items = await returnable(saleId);
    final pick = <({int itemId, String barcode, String name, String unit, int qty, int returned, double price}), int>{};
    for (final it in items) {
      final q = (qtyByItem[it.itemId] ?? 0).clamp(0, it.qty - it.returned);
      if (q > 0) pick[it] = q;
    }
    if (pick.isEmpty) return null;
    final sale = (await d.query('sales', where: 'id=?', whereArgs: [saleId])).first;
    final now = DateTime.now();
    var total = 0.0;
    late String no;
    await d.transaction((t) async {
      var n = (Sqflite.firstIntValue(await t.rawQuery('SELECT COUNT(*) FROM returns')) ?? 0) + 1;
      while ((await t.query('returns', where: 'receipt_no=?', whereArgs: ['RT-${sale['receipt_no']}-$n'])).isNotEmpty) {
        n++;
      }
      no = 'RT-${sale['receipt_no']}-$n';
      for (final e in pick.entries) {
        total += e.key.price * e.value;
      }
      total = double.parse((total * refundFactor((sale['subtotal'] as num).toDouble(), (sale['net_total'] as num).toDouble())).toStringAsFixed(2));
      final rid = await t.insert('returns', {
        'receipt_no': no,
        'sale_id': saleId,
        'created_at': fmtDt(now),
        'total': total,
        'payment': sale['payment'],
        'cashier': cashier,
      });
      for (final e in pick.entries) {
        final it = e.key;
        final sub = double.parse((it.price * e.value).toStringAsFixed(2));
        final row = await t.query('sale_items', columns: ['base_units', 'qty'], where: 'id=?', whereArgs: [it.itemId]);
        final per = (row.first['qty'] as int) == 0 ? 0 : ((row.first['base_units'] as int) ~/ (row.first['qty'] as int));
        await t.insert('return_items', {
          'return_id': rid,
          'sale_item_id': it.itemId,
          'barcode': it.barcode,
          'name': it.name,
          'unit': it.unit,
          'qty': e.value,
          'price': it.price,
          'subtotal': sub,
          'base_units': per * e.value,
        });
        await t.rawUpdate('UPDATE products SET stock=stock+? WHERE barcode=? AND stock IS NOT NULL', [per * e.value, it.barcode]);
      }
      // a CREDIT sale: the refund comes off the customer's account (the PC does the same when the return reaches it; its figure replaces this one
      // on the next catalog refresh)
      final cust = '${sale['customer'] ?? ''}'.trim();
      if ('${sale['payment']}' == 'Credit' && cust.isNotEmpty) {
        await t.rawUpdate('UPDATE customers SET balance=round(balance-?,2) WHERE lower(name)=lower(?)', [total, cust]);
      }
    });
    return no;
  }

  // ------------------------------------------------------------- shifts
  static Future<Map<String, Object?>?> openShift() async {
    final d = await db;
    final r = await d.query('shifts', where: 'closed_at IS NULL', orderBy: 'id DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> startShift(double opening, String cashier) async {
    final d = await db;
    if (await openShift() != null) return;
    await d.insert('shifts', {'opened_at': fmtDt(DateTime.now()), 'opening': opening, 'cashier': cashier});
  }

  /// Cash that should be in the drawer: opening + cash sales - cash returns since the shift opened.
  static Future<double> expectedCash(Map<String, Object?> shift) async {
    final r = await report(since: '${shift['opened_at']}');
    return (shift['opening'] as num).toDouble() + (r.byPayment['Cash'] ?? 0) - (r.returnsByPayment['Cash'] ?? 0);
  }

  static Future<double> closeShift(int id, double counted) async {
    final d = await db;
    final sh = (await d.query('shifts', where: 'id=?', whereArgs: [id])).first;
    final exp = await expectedCash(sh);
    await d.update('shifts', {'closed_at': fmtDt(DateTime.now()), 'expected': exp, 'counted': counted}, where: 'id=?', whereArgs: [id]);
    return counted - exp;
  }

  static Future<List<Map<String, Object?>>> lastShifts({int limit = 6}) async {
    final d = await db;
    return d.query('shifts', where: 'closed_at IS NOT NULL', orderBy: 'id DESC', limit: limit);
  }

  static Future<List<SaleHeader>> recentSales({int limit = 300}) async {
    final d = await db;
    final r = await d.query('sales', orderBy: 'id DESC', limit: limit);
    return r.map(SaleHeader.fromMap).toList();
  }

  static Future<List<Map<String, Object?>>> itemsOf(int saleId) async {
    final d = await db;
    return d.query('sale_items', where: 'sale_id=?', whereArgs: [saleId], orderBy: 'id');
  }

  static Future<int> unsyncedCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM sales s WHERE s.synced=0 AND EXISTS (SELECT 1 FROM sale_items i WHERE i.sale_id=s.id)')) ?? 0;
  }

  static Future<({int count, double total})> todayStats() async {
    final d = await db;
    final n = DateTime.now();
    final day = '${n.year}-${two(n.month)}-${two(n.day)}%';
    final r = await d.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(net_total),0) s FROM sales WHERE created_at LIKE ?', [day]);
    return (count: (r.first['c'] as int), total: (r.first['s'] as num).toDouble());
  }

  /// JSON payload understood by the JØ PHARMA receiver.
  static Future<Map<String, Object?>> buildPayload({bool onlyUnsynced = true}) async {
    final d = await db;
    final heads = await d.query('sales', where: onlyUnsynced ? 'synced=0' : null, orderBy: 'id');
    final sales = <Map<String, Object?>>[];
    for (final h in heads) {
      final items = await d.query('sale_items', where: 'sale_id=?', whereArgs: [h['id']], orderBy: 'id');
      sales.add({
        'receipt_no': h['receipt_no'],
        'created_at': h['created_at'],
        'subtotal': h['subtotal'],
        'discount': h['discount'],
        'net': h['net_total'],
        'payment': h['payment'],
        'cashier': h['cashier'],
        'items': items
            .map((i) => {
                  'barcode': i['barcode'],
                  'name': i['name'],
                  'price': i['price'],
                  'qty': i['qty'],
                  'subtotal': i['subtotal'],
                })
            .toList(),
      });
    }
    return {
      'format': 'jo-pos-mobile/1',
      'device_id': await getSetting('device_id'),
      'device': await getSetting('device_name'),
      'exported_at': fmtDt(DateTime.now()),
      'sales': sales,
    };
  }

  /// Invoices in the exact shape the JØ PHARMA receiver takes: POST /sales {"invoices":[...]}.
  /// The same JSON is what the desktop's "import file" reads, so the offline export works too.
  static Future<List<Map<String, Object?>>> lanInvoices({bool onlyUnsynced = true}) async {
    final d = await db;
    final install = await installId();
    final device = await getSetting('device_name');
    final heads = await d.query('sales', where: onlyUnsynced ? 'synced=0' : null, orderBy: 'id');
    final out = <Map<String, Object?>>[];
    for (final h in heads) {
      final items = await d.query('sale_items', where: 'sale_id=?', whereArgs: [h['id']], orderBy: 'id');
      if (items.isEmpty) continue;
      out.add({
        'client_sale_id': '$install-${h['receipt_no']}',
        'created_at': h['created_at'],
        'cashier': h['cashier'],
        'device_name': device,
        'payment_method': h['payment'],
        'discount': h['discount'],
        if ('${h['payment']}' == 'Credit') 'received': h['received'], // the part paid at the counter: only the rest is a debt on the PC
        'customer_name': h['customer'],
        'items': [
          for (final i in items) {'barcode': i['barcode'], 'qty': i['qty'], 'unit': i['unit'] ?? 'pack'}
        ],
      });
    }
    return out;
  }

  /// Stable random id of this installation (makes every invoice id unique across phones).
  static Future<String> installId() async {
    var v = await getSetting('install_id');
    if (v.isEmpty) {
      final r = Random.secure();
      v = List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
      await setSetting('install_id', v);
    }
    return v;
  }

  /// [synced] = the desktop has the invoice (booked, duplicate or waiting for an unknown barcode to be linked).
  static Future<void> setSyncResult(String receiptNo, {required bool synced, String note = ''}) async {
    final d = await db;
    await d.update('sales', {'synced': synced ? 1 : 0, 'sync_note': note.isEmpty ? null : note},
        where: 'receipt_no=?', whereArgs: [receiptNo]);
  }

  static Future<void> markSynced(Iterable<String> receipts) async {
    final d = await db;
    await d.transaction((t) async {
      for (final r in receipts) {
        await t.update('sales', {'synced': 1}, where: 'receipt_no=?', whereArgs: [r]);
      }
    });
  }

  static Future<void> markAllSynced() async {
    final d = await db;
    await d.update('sales', {'synced': 1});
  }
}
