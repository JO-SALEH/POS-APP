import 'package:flutter_test/flutter_test.dart';
import 'package:jo_pos_mobile/db.dart';
import 'package:jo_pos_mobile/importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> freshDb() async {
  await Db.reset();
  await Db.useForTest(await Db.openAt(inMemoryDatabasePath));
}

Product med(String code, String name, double price, {int upp = 10, int strip = 5, int? stock = 100}) =>
    Product(barcode: code, name: name, price: price, unitsPerPack: upp, stripSize: strip, stock: stock, hasMeta: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Product> seed() async {
    await freshDb();
    await Db.importBatch([ImportItem(med('1000001', 'Panadol', 20))]);
    return (await Db.byBarcode('1000001'))!;
  }

  group('units like the desktop', () {
    test('pack / strip / unit prices and options', () async {
      final p = await seed();
      expect(p.unitOptions, ['pack', 'strip', 'unit']);
      expect(p.priceFor('pack'), 20);
      expect(p.priceFor('strip'), 10); // 20 * 5 / 10
      expect(p.priceFor('unit'), 2);
      expect(p.multOf('strip'), 5);
      final plain = Product(barcode: '1', name: 'x', price: 5);
      expect(plain.unitOptions, ['pack']);
    });
    test('catalog rows carry pack size and stock', () async {
      await freshDb();
      final pr = Importer.fromCatalog({
        'cols': ['id', 'barcode', 'name', 'name_ar', 'price', 'units_per_pack', 'strip_size', 'stock_units'],
        'rows': [
          [1, '2000001', 'Augmentin', 'اوجمنتين', 45, 14, 7, 140]
        ],
        'codes': []
      });
      await Importer.commit(pr);
      final p = (await Db.byBarcode('2000001'))!;
      expect([p.nameAr, p.unitsPerPack, p.stripSize, p.stock], ['اوجمنتين', 14, 7, 140]);
      // a later stock change updates quietly and does not count as an edited product
      final pr2 = Importer.fromCatalog({
        'cols': ['id', 'barcode', 'name', 'name_ar', 'price', 'units_per_pack', 'strip_size', 'stock_units'],
        'rows': [
          [1, '2000001', 'Augmentin', 'اوجمنتين', 45, 14, 7, 98]
        ],
        'codes': []
      });
      final rep = await Importer.commit(pr2);
      expect(rep.updated, 0);
      expect((await Db.byBarcode('2000001'))!.stock, 98);
    });
  });

  group('sale', () {
    test('stores unit, takes stock, sends the unit to the PC', () async {
      final p = await seed();
      final no = await Db.createSale([CartLine(p, 2, 'strip'), CartLine(p, 1, 'pack')], 0, 'Credit', 'admin', customer: 'Ali', received: 0);
      expect((await Db.byBarcode('1000001'))!.stock, 100 - 10 - 10);
      final inv = (await Db.lanInvoices()).single;
      expect(inv['customer_name'], 'Ali');
      expect(inv['payment_method'], 'Credit');
      expect([for (final i in inv['items'] as List) (i as Map)['unit']], ['strip', 'pack']);
      expect(no.startsWith('MB-'), true);
    });
    test('discount, tax and totals', () async {
      final p = await seed();
      await Db.createSale([CartLine(p, 3)], 10, 'Cash', 'admin', tax: 5, received: 100);
      final s = (await Db.recentSales()).single;
      expect([s.subtotal, s.discount, s.tax, s.net, s.received], [60, 10, 5, 55, 100]);
    });
  });

  group('held invoices', () {
    test('hold, list, recall once', () async {
      final p = await seed();
      await Db.holdCart([CartLine(p, 2, 'unit')], 'Mr Ahmed');
      final l = await Db.heldList();
      expect(l.single['label'], 'Mr Ahmed');
      final back = await Db.takeHeld(l.single['id'] as int);
      expect([back.single.qty, back.single.unit], [2, 'unit']);
      expect(await Db.heldList(), isEmpty);
    });
  });

  group('returns, report, shift', () {
    test('return is limited to what was sold and restores stock', () async {
      final p = await seed();
      await Db.createSale([CartLine(p, 3)], 0, 'Cash', 'admin');
      final sale = (await Db.recentSales()).single;
      final items = await Db.returnable(sale.id);
      final id = items.single.itemId;
      expect(await Db.createReturn(sale.id, {id: 5}, 'admin'), isNotNull); // asks 5, only 3 were sold
      expect((await Db.byBarcode('1000001'))!.stock, 100); // 100-30+30
      expect((await Db.returnable(sale.id)).single.returned, 3);
      expect(await Db.createReturn(sale.id, {id: 1}, 'admin'), isNull); // nothing left
    });
    test('day report and shift cash', () async {
      final p = await seed();
      await Db.startShift(100, 'admin');
      await Db.createSale([CartLine(p, 2)], 0, 'Cash', 'admin'); // 40 cash
      await Db.createSale([CartLine(p, 1)], 0, 'Card', 'admin'); // 20 card
      final sale = (await Db.recentSales()).last; // the first (cash) sale
      await Db.createReturn(sale.id, {(await Db.returnable(sale.id)).single.itemId: 1}, 'admin'); // -20 cash
      final n = DateTime.now();
      final r = await Db.report(day: '${n.year}-${two(n.month)}-${two(n.day)}');
      expect([r.count, r.sales, r.returns, r.net], [2, 60, 20, 40]);
      expect(r.byPayment['Cash'], 40);
      final sh = (await Db.openShift())!;
      expect(await Db.expectedCash(sh), 100 + 40 - 20);
      final diff = await Db.closeShift(sh['id'] as int, 115);
      expect(diff, -5);
      expect(await Db.openShift(), isNull);
    });
    test('top sold and low stock', () async {
      final p = await seed();
      await Db.importBatch([ImportItem(med('1000002', 'Low', 5, stock: 2))]);
      await Db.createSale([CartLine(p, 4)], 0, 'Cash', 'admin');
      expect((await Db.topSold()).first.barcode, '1000001');
      expect((await Db.lowStock(threshold: 5)).map((e) => e.barcode), ['1000002']);
    });
  });

  group('desktop v2 data', () {
    test('catalog carries expiry, reorder level, sellable and customers', () async {
      await freshDb();
      final yr = DateTime.now().year;
      final pr = Importer.fromCatalog({
        'cols': ['id', 'barcode', 'name', 'name_ar', 'price', 'units_per_pack', 'strip_size', 'stock_units', 'expiry', 'min_stock', 'sellable_units'],
        'rows': [
          [1, '3000001', 'Old', '', 10, 10, 5, 40, '${yr - 1}-01-01', 3, 0],
          [2, '3000002', 'Soon', '', 10, 10, 5, 40, '${yr + 5}-01-01', 3, 40],
        ],
        'codes': []
      });
      await Importer.commit(pr);
      final old = (await Db.byBarcode('3000001'))!;
      expect([old.minStock, old.sellable, old.expired], [3, 0, true]);
      expect((await Db.byBarcode('3000002'))!.expired, false);
      expect((await Db.byBarcode('3000002'))!.available, 40);
      // 40 units <= 3 packs * 10 -> low even above the plain threshold of 5? 40 > 30 so no
      expect((await Db.lowStock(threshold: 5)).length, 0);
      expect((await Db.expiringSoon(days: 90)).map((e) => e.barcode), ['3000001']);
      await Db.replaceCustomers([
        [1, 'Ali Hassan', '079', 12.5],
        [2, 'Sara', '', 0]
      ]);
      expect(await Db.customerBalance('ali hassan'), 12.5);
      expect((await Db.searchCustomers('sar')).single.name, 'Sara');
    });
    test('returns go to the PC only after their sale is synced', () async {
      final p = await seed();
      final no = await Db.createSale([CartLine(p, 2, 'unit')], 0, 'Cash', 'admin');
      final sale = (await Db.recentSales()).single;
      await Db.createReturn(sale.id, {(await Db.returnable(sale.id)).single.itemId: 1}, 'admin');
      expect(await Db.unsyncedReturns(), 1);
      expect(await Db.lanReturns(), isEmpty); // sale not on the PC yet
      await Db.markSynced([no]);
      final r = (await Db.lanReturns()).single;
      expect(r['client_sale_id'], endsWith('-$no'));
      expect((r['items'] as List).single, {'barcode': '1000001', 'qty': 1, 'unit': 'unit'});
      await Db.setReturnResult((r['client_return_id'] as String).split('-').sublist(1).join('-'), 1);
      expect(await Db.unsyncedReturns(), 0);
    });
  });
}
