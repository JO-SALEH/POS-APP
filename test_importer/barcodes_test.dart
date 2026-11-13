import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jo_pos_mobile/codes.dart';
import 'package:jo_pos_mobile/db.dart';
import 'package:jo_pos_mobile/importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> freshDb() async {
  await Db.reset();
  await Db.useForTest(await Db.openAt(inMemoryDatabasePath));
}

ImportItem item(String code, String name, double price, [List<String> alts = const []]) =>
    ImportItem(Product(barcode: code, name: name, price: price), alts);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Codes', () {
    test('normalises digits, prefixes, spaces, excel artefacts', () {
      expect(Codes.norm('٦٢٢١٠٣١٠٠٠٠٢٨'), '6221031000028');
      expect(Codes.norm(']E06221031234567'), '6221031234567');
      expect(Codes.norm(" 622 103​1234567 '"), '6221031234567');
      expect(Codes.norm('6221031234567.0'), '6221031234567');
      expect(Codes.norm('1.23E+12'), '1230000000000');
      expect(Codes.norm('ab-12'), 'AB-12');
      expect(Codes.isJunk(Codes.norm('null')), true);
      expect(Codes.isJunk(''), true);
    });
    test('loose and split', () {
      expect(Codes.loose('0123456789012'), '123456789012');
      expect(Codes.loose('0012'), '0012');
      expect(Codes.splitMany('111111, 222222'), ['111111', '222222']);
      expect(Codes.splitMany('6 221 031 234 567'), ['6221031234567']);
      expect(Codes.splitMany('9999 8888'), ['9999', '8888']);
    });
  });

  group('xlsx import', () {
    test('real Excel file: columns, alt barcodes, skips, duplicates', () async {
      final bytes = File('test_importer/fixtures/items.xlsx').readAsBytesSync();
      final pr = Importer.fromRows(Importer.rowsFromXlsx(bytes));
      expect(pr.rows, 8);
      expect(pr.noCode, 1);
      expect(pr.merged, 1);
      expect(pr.namedByCode, 1);
      expect(pr.sci, 1);
      await freshDb();
      final rep = await Importer.commit(pr);
      expect(rep.added, 6);
      expect(rep.duplicatesInFile, 1);
      expect(rep.altAdded, 4);
      expect(rep.altConflicts, 1);
      expect(rep.productsAfter, 6);
      expect(rep.codesAfter, 4);
      expect(rep.verified, true);
      final dup = await Db.byBarcode('6221031000011'); // same barcode twice: merged, first row wins
      expect(dup!.name, 'Augmentin 1g');
      expect(dup.price, 45);
      expect((await Db.byBarcode('7000000000001'))!.name, '7000000000001'); // no name -> barcode
      expect((await Db.byBarcode('6221031000028'))!.name, 'أموكسيل');
      expect((await Db.byBarcode('9999'))!.name, 'بنادول 500 مجم');
      expect((await Db.byBarcode('222222'))!.name, 'Multi in cell');
    });
  });

  group('database', () {
    test('alt codes, loose match, re-import is idempotent', () async {
      await freshDb();
      final items = [item('6221031234567', 'A', 10, ['111111', '222222']), item('333333', 'B', 5)];
      final r1 = await Db.importBatch(items);
      expect(r1.added, 2);
      expect(r1.altAdded, 2);
      final r2 = await Db.importBatch(items);
      expect(r2.added, 0);
      expect(r2.unchanged, 2);
      expect(r2.altExisting, 2);
      expect(r2.productsAfter, 2);
      expect((await Db.byBarcode('٢٢٢٢٢٢'))!.name, 'A');
      expect((await Db.byBarcode(']E0333333'))!.name, 'B');
      expect((await Db.byBarcode('06221031234567'))!.name, 'A'); // leading zero
      expect(await Db.byBarcode('62210312'), isNull);
    });
    test('primary wins over another product extra code; conflicts are refused', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'A', 1, ['5555555'])]);
      final r = await Db.importBatch([item('5555555', 'B', 2), item('1000002', 'C', 3, ['1000001'])]);
      expect(r.altPrimaryWins, 1);
      expect(r.altConflicts, 1);
      expect((await Db.byBarcode('5555555'))!.name, 'B');
      expect((await Db.byBarcode('1000001'))!.name, 'A');
      expect(r.verified, true);
    });
    test('manual insert refuses a code that is an extra code', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'A', 1, ['5555555'])]);
      expect(await Db.insertProduct(Product(barcode: '5555555', name: 'X', price: 1)), isNull);
      expect(await Db.insertProduct(Product(barcode: '7777777', name: 'X', price: 1)), isNotNull);
    });
    test('upgrade from v1 keeps data and cleans old barcodes', () async {
      await Db.reset();
      final path = '${Directory.systemTemp.path}/jo_v1_${DateTime.now().microsecondsSinceEpoch}.db';
      final v1 = await openDatabase(path, version: 1, onCreate: (d, v) async {
        await d.execute('CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, barcode TEXT UNIQUE NOT NULL, name TEXT NOT NULL, price REAL NOT NULL DEFAULT 0, updated_at TEXT)');
        await d.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
        await d.execute('CREATE TABLE sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, barcode TEXT NOT NULL, name TEXT NOT NULL, price REAL NOT NULL, qty INTEGER NOT NULL, subtotal REAL NOT NULL)');
        await d.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_no TEXT UNIQUE NOT NULL, created_at TEXT NOT NULL, subtotal REAL NOT NULL, discount REAL NOT NULL DEFAULT 0, net_total REAL NOT NULL, payment TEXT NOT NULL DEFAULT \'Cash\', cashier TEXT, synced INTEGER NOT NULL DEFAULT 0)');
      });
      await v1.insert('products', {'barcode': '٦٢٢١٠٣١٠٠٠٠٢٨ ', 'name': 'Old', 'price': 3});
      await v1.close();
      final d = await Db.openAt(path);
      await Db.useForTest(d);
      expect((await Db.byBarcode('6221031000028'))!.name, 'Old');
      expect(await Db.codeCount(), 0);
      expect((await Db.recentSales()), isEmpty); // v3 column exists
      await Db.reset();
      File(path).deleteSync();
    });
  });

  group('desktop database', () {
    test('medications + item_codes', () async {
      final src = await openDatabase(inMemoryDatabasePath, version: 1, onCreate: (d, v) async {
        await d.execute('CREATE TABLE medications(id INTEGER PRIMARY KEY, barcode TEXT, name TEXT, name_ar TEXT, price REAL)');
        await d.execute('CREATE TABLE item_codes(code TEXT PRIMARY KEY, med_id INTEGER, source TEXT, created_at TEXT)');
      });
      await src.insert('medications', {'id': 1, 'barcode': '6221031234567', 'name': 'Panadol', 'name_ar': 'بنادول', 'price': 12.5});
      await src.insert('medications', {'id': 2, 'barcode': '', 'name': '', 'name_ar': 'فيتامين', 'price': 7});
      await src.insert('medications', {'id': 3, 'barcode': '', 'name': 'Nothing', 'name_ar': '', 'price': 1});
      for (final c in [['6221031234567', 1], ['111111', 1], ['222222', 1], ['999999', 2], ['888888', 2]]) {
        await src.insert('item_codes', {'code': c[0], 'med_id': c[1], 'source': 's', 'created_at': 'x'});
      }
      final pr = await Importer.readSqlite(src);
      await src.close();
      expect(pr.rows, 3);
      expect(pr.noCode, 1);
      await freshDb();
      final rep = await Importer.commit(pr);
      expect(rep.added, 2);
      expect(rep.altAdded, 3);
      expect(rep.verified, true);
      expect((await Db.byBarcode('222222'))!.name, 'Panadol');
      final v = await Db.byBarcode('888888');
      expect(v!.name, 'فيتامين');
      expect(v.barcode, '999999');
    });
  });
}
