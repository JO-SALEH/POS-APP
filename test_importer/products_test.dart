import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jo_pos_mobile/db.dart';
import 'package:jo_pos_mobile/importer.dart';
import 'package:jo_pos_mobile/mapping.dart';
import 'package:jo_pos_mobile/tableio.dart';
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

  group('parseNumber', () {
    test('formats', () {
      expect(TableIO.parseNumber('35'), 35);
      expect(TableIO.parseNumber('35.25'), 35.25);
      expect(TableIO.parseNumber('1,234.50'), 1234.5);
      expect(TableIO.parseNumber('1.234,50'), 1234.5);
      expect(TableIO.parseNumber('12,5'), 12.5);
      expect(TableIO.parseNumber('٣٫٥'), 3.5);
      expect(TableIO.parseNumber('EGP 12'), 12);
      expect(TableIO.parseNumber('12 ج.م'), 12);
      expect(TableIO.parseNumber('abc'), isNull);
      expect(TableIO.parseNumber(''), isNull);
    });
  });

  group('reading text files', () {
    test('delimiter is detected (semicolon, tab) and quotes respected', () {
      final a = TableIO.parseDelimited('code;name;price\n111;"A; B";1,5\n222;C;2');
      expect(a[1], ['111', 'A; B', '1,5']);
      final b = TableIO.parseDelimited('code\tname\tprice\n111\tA\t1\n');
      expect(b[1], ['111', 'A', '1']);
    });
    test('UTF-8 with BOM and Windows-1256 (old Arabic Excel CSV)', () {
      final u = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('باركود')]);
      expect(TableIO.decode(u), 'باركود');
      // "الاسم" in cp1256: ا=C7 ل=E1 ا=C7 س=D3 م=E3
      expect(TableIO.decode(Uint8List.fromList([0xC7, 0xE1, 0xC7, 0xD3, 0xE3])), 'الاسم');
    });
  });

  group('column detection', () {
    test('title row is found after junk rows and columns are mapped', () {
      final rows = <List<String>>[
        ['Pharmacy stock'],
        <String>[],
        ['الباركود', 'اسم الصنف', 'السعر'],
        ['6221031234567', 'Panadol', '12.5'],
        ['6221031000011', 'Augmentin', '1,234.50'],
      ];
      final h = Mapper.detectHeader(rows);
      expect(h, 2);
      final m = Mapper.propose(rows, h);
      expect([m.barcode, m.name, m.price], [0, 1, 2]);
      final pr = Mapper.build(rows, h, m);
      expect(pr.items.length, 2);
      expect(pr.items[1].product.price, 1234.5); // "1,234.50" is not 0
    });
    test('no title row: barcode, name, price guessed from content', () {
      final rows = [
        ['6221031234567', 'Panadol', '12.5'],
        ['6221031000011', 'Augmentin', '45'],
        ['6221031000028', 'Amoxil', '8'],
      ];
      final h = Mapper.detectHeader(rows);
      expect(h, -1);
      final pr = Importer.fromRows(rows);
      expect(pr.items.length, 3);
      expect(pr.items[2].product.name, 'Amoxil');
      expect(pr.items[2].product.price, 8);
    });
    test('manual mapping and Arabic-name preference', () {
      final rows = [
        ['a', 'b', 'c', 'd'],
        ['6221031234567', 'Panadol', 'بنادول', '5'],
      ];
      final m = ColumnMap(barcode: 0, name: 1, nameAr: 2, price: 3);
      expect(Mapper.build(rows, 0, m).items.first.product.name, 'Panadol');
      expect(Mapper.build(rows, 0, m, opts: const ImportOptions(preferArabic: true)).items.first.product.name, 'بنادول');
    });
  });

  group('import modes', () {
    test('price 0 in the file never wipes a price; priceOnly keeps names; newOnly changes nothing', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'Old name', 10)]);
      await Db.importBatch([item('1000001', 'New name', 0)]);
      var p = (await Db.byBarcode('1000001'))!;
      expect([p.name, p.price], ['New name', 10]);
      await Db.importBatch([item('1000001', 'Other', 20)], mode: ImportMode.priceOnly);
      p = (await Db.byBarcode('1000001'))!;
      expect([p.name, p.price], ['New name', 20]);
      final r = await Db.importBatch([item('1000001', 'X', 99), item('1000002', 'Fresh', 5)], mode: ImportMode.newOnly);
      p = (await Db.byBarcode('1000001'))!;
      expect([p.name, p.price], ['New name', 20]);
      expect(r.added, 1);
      expect(r.verified, true);
    });
    test('a barcode used as name does not replace a real name', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'Real', 10)]);
      final r = await Db.importBatch([item('1000001', '1000001', 12)]);
      expect((await Db.byBarcode('1000001'))!.name, 'Real');
      expect((await Db.byBarcode('1000001'))!.price, 12);
      expect(r.verified, true);
    });
  });

  group('products list', () {
    Future<void> seed() async {
      await freshDb();
      await Db.importBatch([
        for (var i = 1; i <= 25; i++) item('${9000000 + i}', 'Item $i', i == 3 ? 0 : i.toDouble(), i == 1 ? ['5550001'] : []),
      ]);
    }

    test('count, ids, paging, sort, no-price filter', () async {
      await seed();
      expect(await Db.countMatching(''), 25);
      expect((await Db.idsMatching('')).length, 25);
      expect(await Db.countMatching('', noPrice: true), 1);
      expect((await Db.searchProducts('', limit: 10, offset: 20)).length, 5);
      final top = await Db.searchProducts('', limit: 1, sort: ProductSort.priceDesc);
      expect(top.first.price, 25);
      expect(await Db.countMatching('Item 1'), greaterThan(1));
    });
    test('delete selected removes extra codes and alternatives too', () async {
      await seed();
      final one = (await Db.byBarcode('5550001'))!;
      final other = (await Db.byBarcode('9000002'))!;
      await Db.setAlts(other.id!, [one.id!]);
      expect(await Db.deleteProducts([one.id!]), 1);
      expect(await Db.byBarcode('5550001'), isNull);
      expect(await Db.codeCount(), 0);
      expect(await Db.altCount(other.id!), 0);
      expect(await Db.productCount(), 24);
    });
    test('delete many (over the chunk size) and delete all', () async {
      await freshDb();
      await Db.importBatch([for (var i = 0; i < 1000; i++) item('${1000000 + i}', 'P$i', 1)]);
      final ids = await Db.idsMatching('');
      expect(await Db.deleteProducts(ids.take(900)), 900);
      expect(await Db.productCount(), 100);
      expect(await Db.deleteAllProducts(), 100);
      expect(await Db.productCount(), 0);
    });
    test('adjust prices by percent', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'A', 10), item('1000002', 'B', 3.33)]);
      final ids = await Db.idsMatching('');
      expect(await Db.adjustPrices(ids, 10), 2);
      expect((await Db.byBarcode('1000001'))!.price, 11);
      expect((await Db.byBarcode('1000002'))!.price, 3.66);
      await Db.adjustPrices(ids, -50);
      expect((await Db.byBarcode('1000001'))!.price, 5.5);
    });
    test('extra codes: set, refuse a code of another product, export', () async {
      await freshDb();
      await Db.importBatch([item('1000001', 'A', 1), item('1000002', 'B', 2, ['7777777'])]);
      final a = (await Db.byBarcode('1000001'))!;
      final refused = await Db.setCodes(a.id!, ['8888888', '7777777', '1000001']);
      expect(refused, ['7777777']);
      expect(await Db.codesOf(a.id!), ['8888888']);
      final rows = await Db.exportRows();
      expect(rows.length, 2);
      expect(rows.first[0], '1000001');
      expect(rows.first[3], contains('8888888'));
    });
  });
}
