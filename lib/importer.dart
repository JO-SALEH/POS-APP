import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'codes.dart';
import 'db.dart';
import 'i18n.dart';
import 'mapping.dart';
import 'tableio.dart';

/// Shown to the user as is (already translated).
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// A file the user picked, read and ready: either a table that still needs its columns mapped,
/// or products already read from a database (JO PHARMA / JO POS), which need no mapping.
class ImportSource {
  final String fileName;
  final List<List<String>>? rows;
  final ParseResult? parsed;
  ImportSource(this.fileName, {this.rows, this.parsed});
}

Object _readIsolate(String path) {
  try {
    return TableIO.readFile(path);
  } on FormatException catch (e) {
    return e.message;
  } catch (e) {
    return 'ERR:$e';
  }
}

/// Product import, the way the desktop does it: any file (Excel, CSV / TXT in any encoding, JSON, JO PHARMA database),
/// columns detected from their titles and content, mapped by the user when needed, imported in one verified step.
class Importer {
  // ------------------------------------------------------------------ entry
  /// Reads the file. Heavy parsing runs in a background isolate so the screen never freezes.
  static Future<ImportSource> open(String path) async {
    final f = File(path);
    if (!await f.exists()) throw ImportException(tr('import_empty'));
    final name = path.split(RegExp(r'[\\/]')).last;
    final head = await _readHead(f);
    if (_isSqlite(head)) return ImportSource(name, parsed: await _readSqliteFile(path));
    final res = await compute(_readIsolate, path);
    if (res is String) {
      throw ImportException(switch (res) {
        'OLD_XLS' => tr('import_xls'),
        'EMPTY' => tr('import_empty'),
        'TOO_BIG' => tr('import_big'),
        _ => tr('import_fail', [res]),
      });
    }
    final rows = res as List<List<String>>;
    if (rows.isEmpty) throw ImportException(tr('import_empty'));
    return ImportSource(name, rows: rows);
  }

  /// No mapping step: the proposed columns are used as they are (CSV text, tests, scripts).
  static ParseResult fromRows(List<List<String>> rows, {ImportOptions opts = const ImportOptions()}) {
    final h = Mapper.detectHeader(rows);
    return Mapper.build(rows, h, Mapper.propose(rows, h), opts: opts);
  }

  @visibleForTesting
  static List<List<String>> rowsFromXlsx(Uint8List bytes) => TableIO.readXlsx(bytes);

  /// Imports a parsed file; throws when it holds no usable product.
  static Future<ImportReport> commit(ParseResult pr, {ImportMode mode = ImportMode.all}) async {
    if (pr.items.isEmpty) throw ImportException(tr('import_empty'));
    final rep = ImportReport()
      ..rows = pr.rows
      ..skippedNoCode = pr.noCode
      ..skippedNoName = pr.noName
      ..skippedOther = pr.other
      ..sciWarnings = pr.sci
      ..duplicatesInFile = pr.merged
      ..badNumbers = pr.badNumbers
      ..noPrice = pr.noPrice
      ..namedByCode = pr.namedByCode;
    return Db.importBatch(pr.items, into: rep, mode: mode);
  }

  static Future<Uint8List> _readHead(File f) async {
    final raf = await f.open();
    try {
      return await raf.read(16);
    } finally {
      await raf.close();
    }
  }

  static bool _isSqlite(Uint8List h) {
    const sig = 'SQLite format 3';
    if (h.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (h[i] != sig.codeUnitAt(i)) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ SQLite file
  static Future<ParseResult> _readSqliteFile(String path) async {
    final dir = await getTemporaryDirectory();
    final copy = File('${dir.path}/jo_import_${DateTime.now().millisecondsSinceEpoch}.db');
    await File(path).copy(copy.path); // always work on a copy: the picked file is never touched
    Database? src;
    try {
      src = await openDatabase(copy.path, singleInstance: false);
      return await readSqlite(src);
    } on DatabaseException {
      throw ImportException(tr('import_db_unknown'));
    } finally {
      try {
        await src?.close();
      } catch (_) {}
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        try {
          final x = File('${copy.path}$suffix');
          if (await x.exists()) await x.delete();
        } catch (_) {}
      }
    }
  }

  /// One medicine of the desktop (database row or LAN catalog row): primary barcode + its extra codes.
  static void _addMedicine(ParseResult pr, Object? id, Object? barcode, Object? name, Object? nameAr, Object? price,
      Map<int, List<String>> extra,
      {Object? upp, Object? strip, Object? stock, Object? expiry, Object? minStock, Object? sellable, bool meta = false}) {
    pr.rows++;
    var code = Codes.norm('${barcode ?? ''}');
    final alts = [...?(id is int ? extra[id] : null)];
    if (Codes.isJunk(code) && alts.isNotEmpty) code = alts.removeAt(0); // known only by its extra codes
    var n = '${name ?? ''}'.trim();
    if (n.isEmpty) n = '${nameAr ?? ''}'.trim();
    if (Codes.isJunk(code)) {
      pr.noCode++;
      return;
    }
    if (n.isEmpty) {
      pr.noName++;
      return;
    }
    final pv = price is num ? price.toDouble() : (double.tryParse('${price ?? ''}'.replaceAll(',', '.')) ?? 0);
    int asInt(Object? v, int d) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? d);
    final pack = asInt(upp, 1).clamp(1, 100000);
    pr.items.add(ImportItem(
        Product(
            barcode: code,
            name: n,
            price: pv,
            nameAr: '${nameAr ?? ''}'.trim(),
            unitsPerPack: pack,
            stripSize: asInt(strip, 0).clamp(0, 100000),
            stock: stock == null ? null : asInt(stock, 0),
            expiry: '${expiry ?? ''}'.trim(),
            minStock: asInt(minStock, 0).clamp(0, 100000000),
            sellable: sellable == null ? null : asInt(sellable, 0),
            hasMeta: meta),
        alts));
  }

  /// The JSON of the desktop LAN receiver (GET /catalog): {"rev","cols","rows","codes":[[code, med_id]]}.
  static ParseResult fromCatalog(Map<String, dynamic> j) {
    final cols = ((j['cols'] ?? []) as List).map((e) => '$e').toList();
    final iId = cols.indexOf('id'), iBc = cols.indexOf('barcode'), iName = cols.indexOf('name');
    final iAr = cols.indexOf('name_ar'), iPrice = cols.indexOf('price');
    final iUpp = cols.indexOf('units_per_pack'), iStrip = cols.indexOf('strip_size'), iStock = cols.indexOf('stock_units');
    final iExp = cols.indexOf('expiry'), iMin = cols.indexOf('min_stock'), iSell = cols.indexOf('sellable_units');
    if (iId < 0 || iBc < 0 || iName < 0 || iPrice < 0) throw ImportException(tr('import_db_unknown'));
    final extra = <int, List<String>>{};
    for (final c in ((j['codes'] ?? []) as List)) {
      if (c is List && c.length >= 2 && c[1] is int) {
        final code = Codes.norm('${c[0]}');
        if (!Codes.isJunk(code)) (extra[c[1] as int] ??= []).add(code);
      }
    }
    final pr = ParseResult();
    for (final r in ((j['rows'] ?? []) as List)) {
      if (r is! List || r.length <= iPrice) continue;
      Object? at(int i) => i >= 0 && i < r.length ? r[i] : null;
      _addMedicine(pr, r[iId], r[iBc], r[iName], iAr >= 0 && iAr < r.length ? r[iAr] : '', r[iPrice], extra,
          upp: at(iUpp), strip: at(iStrip), stock: at(iStock), expiry: at(iExp), minStock: at(iMin), sellable: at(iSell), meta: true);
    }
    return pr;
  }

  /// JO PHARMA database (medications + item_codes) or a JO POS backup (products + product_codes).
  @visibleForTesting
  static Future<ParseResult> readSqlite(Database src) async {
    final tables = (await src.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => '${r['name']}')
        .toSet();
    final pr = ParseResult();
    double priceOf(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0);

    if (tables.contains('medications')) {
      // every extra barcode of every medicine (desktop table item_codes), in the order they were added
      final extra = <int, List<String>>{};
      if (tables.contains('item_codes')) {
        for (final r in await src.rawQuery('SELECT code, med_id FROM item_codes ORDER BY rowid')) {
          final id = r['med_id'];
          final c = Codes.norm('${r['code'] ?? ''}');
          if (id is int && !Codes.isJunk(c)) (extra[id] ??= []).add(c);
        }
      }
      final cols = (await src.rawQuery('PRAGMA table_info(medications)')).map((r) => '${r['name']}').toSet();
      final arCol = cols.contains('name_ar') ? 'name_ar' : "'' AS name_ar";
      final uppCol = cols.contains('units_per_pack') ? 'units_per_pack' : '1 AS units_per_pack';
      final stripCol = cols.contains('strip_size') ? 'strip_size' : '0 AS strip_size';
      final stockCol = cols.contains('quantity') && cols.contains('unit_quantity')
          ? '(COALESCE(quantity,0) * MAX(1, COALESCE(units_per_pack,1)) + COALESCE(unit_quantity,0)) AS stock_units'
          : 'NULL AS stock_units';
      var offset = 0;
      while (true) {
        final rows = await src.rawQuery(
            'SELECT id, barcode, name, $arCol, price, $uppCol, $stripCol, $stockCol FROM medications ORDER BY id LIMIT 5000 OFFSET ?', [offset]);
        if (rows.isEmpty) break;
        for (final r in rows) {
          _addMedicine(pr, r['id'], r['barcode'], r['name'], r['name_ar'], r['price'], extra,
              upp: r['units_per_pack'], strip: r['strip_size'], stock: r['stock_units'], meta: true);
        }
        offset += rows.length;
        if (rows.length < 5000) break;
      }
    } else if (tables.contains('products')) {
      final extra = <int, List<String>>{};
      if (tables.contains('product_codes')) {
        for (final r in await src.rawQuery('SELECT code, product_id FROM product_codes ORDER BY rowid')) {
          final id = r['product_id'];
          if (id is int) (extra[id] ??= []).add('${r['code']}');
        }
      }
      for (final r in await src.rawQuery('SELECT id, barcode, name, price FROM products')) {
        pr.rows++;
        final code = Codes.norm('${r['barcode'] ?? ''}');
        final name = '${r['name'] ?? ''}'.trim();
        if (Codes.isJunk(code)) {
          pr.noCode++;
          continue;
        }
        if (name.isEmpty) {
          pr.noName++;
          continue;
        }
        final id = r['id'];
        pr.items.add(ImportItem(Product(barcode: code, name: name, price: priceOf(r['price'])), [...?(id is int ? extra[id] : null)]));
      }
    } else {
      throw ImportException(tr('import_db_unknown'));
    }
    return pr;
  }
}
