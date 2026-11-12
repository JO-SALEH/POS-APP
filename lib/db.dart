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

String hashPassword(String pw) => sha256.convert(utf8.encode('jo-pos|$pw')).toString();

class Product {
  int? id;
  String barcode;
  String name;
  double price;
  Product({this.id, required this.barcode, required this.name, required this.price});

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: m['id'] as int?,
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
      );
}

/// One product read from a file / database, with its extra barcodes.
class ImportItem {
  final Product product;
  final List<String> altCodes;
  ImportItem(this.product, [this.altCodes = const []]);
}

/// What an import really did (shown to the user, and checked by re-reading the database).
class ImportReport {
  int rows = 0; // records read from the file
  int added = 0, updated = 0, unchanged = 0;
  int skippedNoCode = 0, skippedNoName = 0, skippedOther = 0, duplicatesInFile = 0;
  int altAdded = 0, altExisting = 0, altConflicts = 0, altPrimaryWins = 0;
  int sciWarnings = 0; // barcodes that Excel had turned into 1.23E+12
  int mismatches = 0; // verification failures (must be 0)
  int productsAfter = 0, codesAfter = 0;
  final List<String> notes = [];

  int get imported => added + updated + unchanged;
  int get skipped => skippedNoCode + skippedNoName + skippedOther;
  bool get verified => mismatches == 0;
  bool get hasIssues => skipped > 0 || duplicatesInFile > 0 || altConflicts > 0 || sciWarnings > 0 || mismatches > 0;

  void note(String s) {
    if (notes.length < 30) notes.add(s);
  }
}

class CartLine {
  Product product;
  int qty;
  CartLine(this.product, [this.qty = 1]);
  double get subtotal => product.price * qty;
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
  SaleHeader(this.id, this.receiptNo, this.createdAt, this.subtotal, this.discount, this.net, this.payment, this.synced);

  factory SaleHeader.fromMap(Map<String, Object?> m) => SaleHeader(
        m['id'] as int,
        m['receipt_no'] as String,
        m['created_at'] as String,
        (m['subtotal'] as num).toDouble(),
        (m['discount'] as num).toDouble(),
        (m['net_total'] as num).toDouble(),
        m['payment'] as String,
        (m['synced'] as int) == 1,
      );
}

class Db {
  static Database? _db;

  static const schemaVersion = 2;

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
          updated_at TEXT)''');
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
          synced INTEGER NOT NULL DEFAULT 0)''');
      await d.execute('''CREATE TABLE sale_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          barcode TEXT NOT NULL,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          qty INTEGER NOT NULL,
          subtotal REAL NOT NULL)''');
      await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
      await d.execute('CREATE INDEX idx_sale_items_sale ON sale_items(sale_id)');
      await d.execute('CREATE INDEX idx_sales_synced ON sales(synced)');
      await _createCodes(d);
    }, onUpgrade: (d, from, to) async {
      if (from < 2) {
        await _createCodes(d);
        await _normalizeStored(d);
      }
    });
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
  static Future<List<Product>> searchProducts(String q, {int limit = 60}) async {
    final d = await db;
    final s = Codes.latinDigits(q.trim());
    final rows = s.isEmpty
        ? await d.query('products', orderBy: 'name COLLATE NOCASE', limit: limit)
        : await d.query('products',
            where: 'name LIKE ? OR barcode LIKE ? OR id IN (SELECT product_id FROM product_codes WHERE code LIKE ?)',
            whereArgs: ['%$s%', '%$s%', '%${s.toUpperCase()}%'],
            orderBy: 'name COLLATE NOCASE',
            limit: limit);
    return rows.map(Product.fromMap).toList();
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
          {'barcode': code, 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now())});
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
            {'barcode': code, 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now())},
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
  static Future<int> bulkUpsert(List<Product> items) async =>
      (await importBatch(items.map((e) => ImportItem(e)).toList())).imported;

  /// Insert-or-update by (normalised) barcode, plus extra barcodes, in ONE transaction, then re-reads
  /// the database and compares it with the file. Nothing is half-imported: on an error everything rolls back.
  ///  * the same barcode twice in the file: the last row wins (counted in the report);
  ///  * an extra code that is another product's primary / extra code is NOT taken (counted as a conflict);
  ///  * when a code becomes a product's primary barcode it stops being an extra code of another product.
  static Future<ImportReport> importBatch(List<ImportItem> items, {ImportReport? into}) async {
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
      byCode[code] = ImportItem(Product(barcode: code, name: name, price: it.product.price), alts);
    }

    final expectedAlts = <String, String>{}; // extra code -> its primary
    await d.transaction((t) async {
      // 2) products
      final existing = <String, Map<String, Object?>>{};
      final norms = <String, int>{};
      for (final r in await t.query('products', columns: ['id', 'barcode', 'name', 'price'])) {
        final n = Codes.norm(r['barcode'] as String?);
        existing[n] = r;
        norms[n] = (norms[n] ?? 0) + 1;
      }
      final now = fmtDt(DateTime.now());
      final b = t.batch();
      for (final e in byCode.entries) {
        final ex = existing[e.key];
        final x = e.value.product;
        if (ex == null) {
          b.insert('products', {'barcode': e.key, 'name': x.name, 'price': x.price, 'updated_at': now},
              conflictAlgorithm: ConflictAlgorithm.ignore);
          rep.added++;
        } else {
          final same = ex['name'] == x.name && ((ex['price'] as num).toDouble() - x.price).abs() < 0.0005;
          final fixCode = ex['barcode'] != e.key && norms[e.key] == 1;
          if (same && !fixCode) {
            rep.unchanged++;
          } else {
            b.update(
                'products',
                {
                  if (fixCode) 'barcode': e.key,
                  'name': x.name,
                  'price': x.price,
                  'updated_at': now,
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
      if (r == null || r['name'] != e.value.product.name ||
          ((r['price'] as num).toDouble() - e.value.product.price).abs() >= 0.0005) {
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
  static Future<String> createSale(List<CartLine> lines, double discount, String payment, String cashier) async {
    final d = await db;
    final devId = await getSetting('device_id', 'DEV');
    final now = DateTime.now();
    final prefix = 'MB-$devId-${two(now.year % 100)}${two(now.month)}${two(now.day)}-';
    final subtotal = lines.fold<double>(0, (a, l) => a + l.subtotal);
    final disc = discount.clamp(0, subtotal).toDouble();
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
        'net_total': subtotal - disc,
        'payment': payment,
        'cashier': cashier,
        'synced': 0,
      });
      for (final l in lines) {
        await t.insert('sale_items', {
          'sale_id': id,
          'barcode': l.product.barcode,
          'name': l.product.name,
          'price': l.product.price,
          'qty': l.qty,
          'subtotal': l.subtotal,
        });
      }
    });
    return receipt;
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
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM sales WHERE synced=0')) ?? 0;
  }

  static Future<({int count, double total})> todayStats() async {
    final d = await db;
    final n = DateTime.now();
    final day = '${n.year}-${two(n.month)}-${two(n.day)}%';
    final r = await d.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(net_total),0) s FROM sales WHERE created_at LIKE ?', [day]);
    return (count: (r.first['c'] as int), total: (r.first['s'] as num).toDouble());
  }

  /// JSON payload understood by the desktop receiver (jo_mobile_sync.py).
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
