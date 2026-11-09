import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'jo_pos.db');
    _db = await openDatabase(path, version: 1, onCreate: (d, v) async {
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
    });
    await _defaults();
    return _db!;
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
    final s = q.trim();
    final rows = s.isEmpty
        ? await d.query('products', orderBy: 'name COLLATE NOCASE', limit: limit)
        : await d.query('products',
            where: 'name LIKE ? OR barcode LIKE ?',
            whereArgs: ['%$s%', '%$s%'],
            orderBy: 'name COLLATE NOCASE',
            limit: limit);
    return rows.map(Product.fromMap).toList();
  }

  static Future<Product?> byBarcode(String code) async {
    final d = await db;
    final r = await d.query('products', where: 'barcode=?', whereArgs: [code.trim()], limit: 1);
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  static Future<int> productCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
  }

  /// Returns the new id, or null when the barcode already exists.
  static Future<int?> insertProduct(Product x) async {
    final d = await db;
    try {
      return await d.insert('products',
          {'barcode': x.barcode.trim(), 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now())});
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) return null;
      rethrow;
    }
  }

  /// False when the new barcode collides with another product.
  static Future<bool> updateProduct(Product x) async {
    final d = await db;
    try {
      await d.update('products',
          {'barcode': x.barcode.trim(), 'name': x.name.trim(), 'price': x.price, 'updated_at': fmtDt(DateTime.now())},
          where: 'id=?', whereArgs: [x.id]);
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
      await t.delete('products', where: 'id=?', whereArgs: [id]);
    });
  }

  /// Insert-or-update by barcode (used by file import and desktop pull). Alternatives are kept.
  static Future<int> bulkUpsert(List<Product> items) async {
    final d = await db;
    var n = 0;
    await d.transaction((t) async {
      final b = t.batch();
      final now = fmtDt(DateTime.now());
      for (final x in items) {
        final code = x.barcode.trim();
        final name = x.name.trim();
        if (code.isEmpty || name.isEmpty) continue;
        b.insert('products', {'barcode': code, 'name': name, 'price': x.price, 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        b.update('products', {'name': name, 'price': x.price, 'updated_at': now},
            where: 'barcode=?', whereArgs: [code]);
        n++;
      }
      await b.commit(noResult: true);
    });
    return n;
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
