import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jo_pos_mobile/db.dart';
import 'package:jo_pos_mobile/lan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A stand-in for the desktop receiver (jo_lan.py): same paths, header, request and reply shapes.
class FakeDesktop {
  late HttpServer server;
  final String token;
  final seen = <String>{};
  final received = <Map>[];
  String rev = 'r1';
  FakeDesktop(this.token);

  int get port => server.port;

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      Future<void> send(int code, Object? obj, {bool gz = false}) async {
        final raw = utf8.encode(jsonEncode(obj));
        req.response.statusCode = code;
        req.response.headers.contentType = ContentType.json;
        if (gz) {
          final z = gzip.encode(raw);
          req.response.headers.set('Content-Encoding', 'gzip');
          req.response.contentLength = z.length;
          req.response.add(z);
        } else {
          req.response.add(raw);
        }
        await req.response.close();
      }

      if (req.headers.value('X-JO-Token') != token) return send(401, {'ok': false, 'error': 'bad_token'});
      final path = req.uri.path;
      if (path == '/ping') return send(200, {'ok': true, 'v': 1, 'name': 'Test Pharmacy', 'eta_skipped': true});
      if (path == '/catalog/rev') return send(200, {'ok': true, 'rev': rev});
      if (path == '/catalog') {
        return send(200, {
          'rev': rev,
          'cols': ['id', 'barcode', 'name', 'name_ar', 'price', 'units_per_pack', 'strip_size', 'stock_units'],
          'rows': [
            [1, '6221031234567', 'Panadol', 'بنادول', 12.5, 1, 0, 50],
            [2, '', '', 'فيتامين', 7, 1, 0, 3],
          ],
          'codes': [
            ['6221031234567', 1],
            ['555555', 1],
            ['777777', 2]
          ],
        }, gz: true);
      }
      if (path == '/sales' && req.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        final results = [];
        for (final inv in body['invoices'] as List) {
          received.add(inv as Map);
          final cid = inv['client_sale_id'] as String;
          final items = inv['items'] as List;
          final bc = (items.first as Map)['barcode'];
          final dup = !seen.add(cid);
          if (bc == 'FAIL001') {
            results.add({'client_sale_id': cid, 'status': 'failed', 'error': 'no_stock', 'retryable': false, 'unmatched': []});
          } else if (bc == '9999999') {
            results.add({
              'client_sale_id': cid,
              'status': 'partial',
              'duplicate': dup,
              'unmatched': [
                {'barcode': bc, 'qty': 1, 'unit': 'pack', 'reason': 'unknown', 'status': 'open'}
              ]
            });
          } else {
            results.add({'client_sale_id': cid, 'status': 'done', 'receipt_no': 'R1', 'net': 20, 'duplicate': dup, 'unmatched': []});
          }
        }
        return send(200, {'ok': true, 'results': results});
      }
      return send(404, {'ok': false});
    });
  }

  Future<void> stop() => server.close(force: true);
}

Future<void> sale(String code, int qty, {String pay = 'Cash', double discount = 0}) =>
    Db.createSale([CartLine(Product(id: 1, barcode: code, name: 'P$code', price: 10), qty)], discount, pay, 'admin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late FakeDesktop pc;

  setUpAll(() => HttpOverrides.global = null); // flutter_test blocks real HTTP by default

  setUp(() async {
    await Db.reset();
    await Db.useForTest(await Db.openAt(inMemoryDatabasePath));
    pc = FakeDesktop('tok123');
    await pc.start();
  });
  tearDown(() => pc.stop());

  test('QR and manual pairing parse', () {
    final p = Pairing.parseQr('{"v":1,"ip":"192.168.1.5","port":8765,"token":"abc"}')!;
    expect([p.ip, p.port, p.token], ['192.168.1.5', 8765, 'abc']);
    expect(p.base, 'http://192.168.1.5:8765');
    expect(Pairing.parseQr('hello'), isNull);
    expect(Pairing.parseQr('{"ip":"x","port":1,"token":"t"}'), isNull);
    expect(Pairing.parseQr('{"ip":"192.168.1.5","port":8765}'), isNull);
    final m = Pairing.parseManual('192.168.1.9', ' tok ')!;
    expect([m.ip, m.port, m.token], ['192.168.1.9', 8765, 'tok']);
    expect(Pairing.parseManual('192.168.1.9:9000', 't')!.port, 9000);
    expect(Pairing.parseManual('', 't'), isNull);
  });

  test('wrong code is refused and nothing is saved', () async {
    await expectLater(Lan.pair(Pairing('127.0.0.1', pc.port, 'wrong')), throwsA(isA<LanException>()));
    expect(await Lan.load(), isNull);
  });

  test('pair, then unsent invoices go to the PC in the desktop format and are marked synced', () async {
    expect(await Lan.pair(Pairing('127.0.0.1', pc.port, 'tok123')), 'Test Pharmacy');
    await Db.setSetting('device_name', 'Ahmed phone');
    await sale('1000001', 2, pay: 'Wallet', discount: 5);
    await sale('2000002', 1);
    expect(await Db.unsyncedCount(), 2);
    final r = await Lan.push();
    expect(r.booked, 2);
    expect(r.failed, 0);
    expect(await Db.unsyncedCount(), 0);
    final inv = pc.received.first;
    expect((inv['client_sale_id'] as String).length, inInclusiveRange(8, 64));
    expect(inv['payment_method'], 'Wallet');
    expect(inv['discount'], 5);
    expect(inv['cashier'], 'admin');
    expect(inv['device_name'], 'Ahmed phone');
    expect(inv['created_at'], matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$')));
    expect(inv['items'], [
      {'barcode': '1000001', 'qty': 2, 'unit': 'pack'}
    ]);
    // nothing left: a second push sends nothing
    final again = await Lan.push();
    expect(again.total, 0);
    expect(pc.received.length, 2);
  });

  test('already-known invoices count as duplicates; unknown barcodes and refusals are flagged', () async {
    await Lan.pair(Pairing('127.0.0.1', pc.port, 'tok123'));
    await sale('9999999', 1);
    await sale('FAIL001', 1);
    final r = await Lan.push();
    expect(r.unmatched, 1);
    expect(r.failed, 1);
    final sales = await Db.recentSales();
    final unknown = sales.firstWhere((s) => s.receiptNo.endsWith('0001'));
    final failed = sales.firstWhere((s) => s.receiptNo.endsWith('0002'));
    expect(unknown.synced, true);
    expect(unknown.note, isNotEmpty);
    expect(failed.synced, false);
    expect(failed.note, contains('no_stock'));
    // the refused one is offered again, the accepted one is not
    final r2 = await Lan.push();
    expect(r2.failed, 1);
    expect(r2.total, 1);
  });

  test('a lost reply never double-books: resending is a duplicate on the PC', () async {
    await Lan.pair(Pairing('127.0.0.1', pc.port, 'tok123'));
    await sale('1000001', 1);
    await Lan.push();
    await Db.markAllSynced();
    final d = await Db.db;
    await d.update('sales', {'synced': 0}); // pretend the phone never saw the reply
    final r = await Lan.push();
    expect(r.duplicates, 1);
    expect(r.booked, 0);
    expect(await Db.unsyncedCount(), 0);
  });

  test('PC not reachable: error, invoices stay unsent', () async {
    await Lan.pair(Pairing('127.0.0.1', pc.port, 'tok123'));
    await sale('1000001', 1);
    await pc.stop();
    await expectLater(Lan.push(rediscover: false), throwsA(isA<LanException>().having((e) => e.unreachable, 'unreachable', true)));
    expect(await Db.unsyncedCount(), 1);
  });

  test('catalog: names, prices, extra barcodes; second pull is skipped while unchanged', () async {
    await Lan.pair(Pairing('127.0.0.1', pc.port, 'tok123'));
    final rep = await Lan.pullCatalog();
    expect(rep, isNotNull);
    expect(rep!.added, 2);
    expect(rep.altAdded, 1); // 555555 (777777 becomes the primary barcode of the medicine that had none)
    expect(rep.verified, true);
    expect((await Db.byBarcode('555555'))!.name, 'Panadol');
    expect((await Db.byBarcode('777777'))!.name, 'فيتامين');
    expect(await Lan.pullCatalog(), isNull);
    pc.rev = 'r2';
    final rep2 = await Lan.pullCatalog();
    expect(rep2, isNotNull);
    expect(rep2!.added, 0);
  });

  test('exported file uses the same invoice shape', () async {
    await sale('1000001', 3);
    final list = await Db.lanInvoices(onlyUnsynced: false);
    expect(list.length, 1);
    expect(list.first.keys, containsAll(['client_sale_id', 'created_at', 'cashier', 'device_name', 'payment_method', 'discount', 'items']));
  });
}
