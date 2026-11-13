import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'codes.dart';
import 'db.dart';
import 'i18n.dart';

/// Shown to the user as is (already translated).
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Products found in a file, before they are written to the database.
class ParseResult {
  final List<ImportItem> items = [];
  int rows = 0, noCode = 0, noName = 0, other = 0, sci = 0;
}

/// Product import from any file the user picks:
///  * Excel .xlsx            (own zip + XML reader: no extra package, tolerant of styles / Arabic / numeric barcodes)
///  * JO PHARMA database     (jo_pharmacy.db: table `medications`)  or a JO POS backup (table `products`)
///  * CSV / TSV / JSON       (handled by [parseText], passed in by the caller)
/// Columns are found by their header names (English or Arabic); without a header the order is barcode, name, price.
class Importer {
  // ------------------------------------------------------------------ entry
  /// Reads the file, imports everything in one transaction and returns the verified report.
  static Future<ImportReport> importPath(String path, {required ParseResult Function(String text) parseText}) async {
    final f = File(path);
    if (!await f.exists()) throw ImportException(tr('import_empty'));
    final head = await _readHead(f);
    if (_isSqlite(head)) return importSqlite(path);
    ParseResult pr;
    if (head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B) {
      pr = fromRows(rowsFromXlsx(await f.readAsBytes()));
    } else if (head.length >= 4 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0) {
      throw ImportException(tr('import_xls'));
    } else {
      var text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      pr = parseText(text);
    }
    return commit(pr);
  }

  /// Imports a parsed file; throws when it holds no usable product.
  static Future<ImportReport> commit(ParseResult pr) async {
    if (pr.items.isEmpty) throw ImportException(tr('import_empty'));
    final rep = ImportReport()
      ..rows = pr.rows
      ..skippedNoCode = pr.noCode
      ..skippedNoName = pr.noName
      ..skippedOther = pr.other
      ..sciWarnings = pr.sci;
    if (pr.sci > 0) rep.note('sci: ${pr.sci}');
    return Db.importBatch(pr.items, into: rep);
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
  static Future<ImportReport> importSqlite(String path) async {
    final dir = await getTemporaryDirectory();
    final copy = File('${dir.path}/jo_import_${DateTime.now().millisecondsSinceEpoch}.db');
    await File(path).copy(copy.path); // always work on a copy: the picked file is never touched
    Database? src;
    try {
      src = await openDatabase(copy.path, singleInstance: false);
      return await commit(await readSqlite(src));
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
      Map<int, List<String>> extra) {
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
    pr.items.add(ImportItem(Product(barcode: code, name: n, price: pv), alts));
  }

  /// The JSON of the desktop LAN receiver (GET /catalog): {"rev","cols","rows","codes":[[code, med_id]]}.
  static ParseResult fromCatalog(Map<String, dynamic> j) {
    final cols = ((j['cols'] ?? []) as List).map((e) => '$e').toList();
    final iId = cols.indexOf('id'), iBc = cols.indexOf('barcode'), iName = cols.indexOf('name');
    final iAr = cols.indexOf('name_ar'), iPrice = cols.indexOf('price');
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
      _addMedicine(pr, r[iId], r[iBc], r[iName], iAr >= 0 && iAr < r.length ? r[iAr] : '', r[iPrice], extra);
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
      var offset = 0;
      while (true) {
        final rows = await src.rawQuery(
            'SELECT id, barcode, name, $arCol, price FROM medications ORDER BY id LIMIT 5000 OFFSET ?', [offset]);
        if (rows.isEmpty) break;
        for (final r in rows) {
          _addMedicine(pr, r['id'], r['barcode'], r['name'], r['name_ar'], r['price'], extra);
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

  // ------------------------------------------------------- header detection
  static const _kBarcode = [
    'barcode', 'bar code', 'barcodes', 'code', 'item code', 'itemcode', 'sku', 'ean', 'upc', 'كود', 'الكود', 'باركود',
    'الباركود', 'كود الصنف', 'رقم الصنف', 'رمز', 'الرمز'
  ];
  static const _kName = [
    'name', 'item name', 'item', 'product name', 'product', 'description', 'desc', 'اسم', 'الاسم', 'الصنف', 'اسم الصنف',
    'المنتج', 'اسم المنتج', 'البيان', 'الدواء', 'اسم الدواء'
  ];
  static const _kPrice = [
    'price', 'sell price', 'selling price', 'sale price', 'retail price', 'retail', 'unit price', 'سعر', 'السعر',
    'سعر البيع', 'سعر الجمهور', 'الجمهور', 'سعر الوحدة'
  ];

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_\-\.:*]+'), ' ').trim();

  /// 2 = exact match, 1 = the header contains a keyword, 0 = no match.
  static int _score(String header, List<String> keys) {
    final h = _norm(header);
    if (h.isEmpty) return 0;
    for (final k in keys) {
      if (h == k) return 2;
    }
    for (final k in keys) {
      if (k.length >= 3 && h.contains(k)) return 1;
    }
    return 0;
  }

  static int _best(List<String> row, List<String> keys, Set<int> taken) {
    var bestI = -1, bestS = 0;
    for (var i = 0; i < row.length; i++) {
      if (taken.contains(i)) continue;
      final s = _score(row[i], keys);
      if (s > bestS) {
        bestS = s;
        bestI = i;
      }
    }
    return bestI;
  }

  static double? _price(String raw) {
    final s = Codes.latinDigits(raw).trim().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(s);
  }

  /// Rows of a sheet -> products. Besides the main barcode column, EVERY other column whose header
  /// looks like a barcode (Barcode 2, باركود 2, ...) and every extra code written in the barcode cell
  /// ("111, 222") is imported as an extra barcode of the same product.
  static ParseResult fromRows(List<List<String>> rows) {
    var hRow = -1, cCode = 0, cName = 1, cPrice = 2;
    final extraCols = <int>[];
    final scan = rows.length < 15 ? rows.length : 15;
    for (var r = 0; r < scan; r++) {
      final taken = <int>{};
      final c = _best(rows[r], _kBarcode, taken);
      if (c < 0) continue;
      taken.add(c);
      final n = _best(rows[r], _kName, taken);
      if (n < 0) continue;
      taken.add(n);
      final p = _best(rows[r], _kPrice, taken);
      if (p >= 0) taken.add(p);
      hRow = r;
      cCode = c;
      cName = n;
      cPrice = p; // -1 when the file has no price column: price 0, can be edited later
      for (var i = 0; i < rows[r].length; i++) {
        if (!taken.contains(i) && _score(rows[r][i], _kBarcode) > 0) extraCols.add(i);
      }
      break;
    }
    final pr = ParseResult();
    for (var r = hRow + 1; r < rows.length; r++) {
      final row = rows[r];
      String at(int i) => (i >= 0 && i < row.length) ? row[i] : '';
      pr.rows++;
      final rawCode = at(cCode);
      if (Codes.isSci(rawCode)) pr.sci++;
      final codes = Codes.splitMany(rawCode);
      final name = at(cName).trim();
      final alts = <String>[...codes.skip(1)];
      for (final i in extraCols) {
        if (Codes.isSci(at(i))) pr.sci++;
        alts.addAll(Codes.splitMany(at(i)));
      }
      if (codes.isEmpty) {
        // an extra-code-only row is still not importable: no primary barcode
        if (name.isNotEmpty || alts.isNotEmpty) pr.noCode++;
        continue;
      }
      if (name.isEmpty) {
        pr.noName++;
        continue;
      }
      double? price = cPrice < 0 ? 0.0 : _price(at(cPrice));
      if (price == null) {
        if (hRow >= 0) {
          price = 0.0;
        } else {
          pr.other++; // no header and the 3rd cell is not a number: header-like / junk row
          continue;
        }
      }
      pr.items.add(ImportItem(Product(barcode: codes.first, name: name, price: price), alts));
    }
    return pr;
  }

  // ------------------------------------------------------------- xlsx (zip)
  @visibleForTesting
  static List<List<String>> rowsFromXlsx(Uint8List bytes) {
    final entries = _zipEntries(bytes);
    final shared = <String>[];
    final ss = entries['xl/sharedStrings.xml'];
    if (ss != null) {
      final xml = utf8.decode(_zipRead(bytes, ss), allowMalformed: true);
      for (final m in RegExp(r'<si\b[^>]*?(?:/>|>(.*?)</si>)', dotAll: true).allMatches(xml)) {
        var body = m.group(1) ?? '';
        body = body.replaceAll(RegExp(r'<rPh\b.*?</rPh>', dotAll: true), ''); // phonetic hints are not text
        final sb = StringBuffer();
        for (final t in RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true).allMatches(body)) {
          sb.write(_unescape(t.group(1) ?? ''));
        }
        shared.add(sb.toString());
      }
    }
    final sheets = entries.keys.where((k) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(k)).toList()
      ..sort((a, b) {
        int n(String s) => int.parse(RegExp(r'(\d+)\.xml$').firstMatch(s)!.group(1)!);
        return n(a).compareTo(n(b));
      });
    if (sheets.isEmpty) throw ImportException(tr('import_empty'));
    List<List<String>> best = const [];
    for (final name in sheets) {
      final rows = _readSheet(utf8.decode(_zipRead(bytes, entries[name]!), allowMalformed: true), shared);
      if (rows.length > best.length) best = rows;
      if (fromRows(rows).items.isNotEmpty) return rows; // the first sheet that really holds products
    }
    return best;
  }

  static int _colIndex(String letters) {
    var n = 0;
    for (final u in letters.codeUnits) {
      n = n * 26 + (u - 64);
    }
    return n - 1;
  }

  static List<List<String>> _readSheet(String xml, List<String> shared) {
    final rows = <List<String>>[];
    final cellRe = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
    for (final rm in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true).allMatches(xml)) {
      final body = rm.group(1);
      if (body == null) continue;
      final row = <String>[];
      var seq = 0;
      for (final cm in cellRe.allMatches(body)) {
        final attrs = cm.group(1) ?? '';
        final inner = cm.group(2) ?? '';
        final ref = RegExp(r'(?:^|\s)r="([A-Za-z]+)\d+"').firstMatch(attrs);
        final col = ref != null ? _colIndex(ref.group(1)!.toUpperCase()) : seq;
        seq = col + 1;
        final type = RegExp(r'(?:^|\s)t="([^"]*)"').firstMatch(attrs)?.group(1) ?? 'n';
        String value = '';
        if (type == 'inlineStr') {
          final sb = StringBuffer();
          for (final t in RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true).allMatches(inner)) {
            sb.write(_unescape(t.group(1) ?? ''));
          }
          value = sb.toString();
        } else {
          final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner)?.group(1) ?? '';
          if (type == 's') {
            final i = int.tryParse(v.trim());
            value = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          } else {
            value = _unescape(v);
          }
        }
        while (row.length <= col) {
          row.add('');
        }
        row[col] = value;
      }
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  // A minimal zip reader (central directory + stored / deflate entries): everything an .xlsx needs.
  static Map<String, _ZipEntry> _zipEntries(Uint8List b) {
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    var eocd = -1;
    for (var i = b.length - 22; i >= 0 && i >= b.length - 22 - 65535; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ImportException(tr('import_empty'));
    final total = bd.getUint16(eocd + 10, Endian.little);
    var p = bd.getUint32(eocd + 16, Endian.little);
    final out = <String, _ZipEntry>{};
    for (var n = 0; n < total; n++) {
      if (p + 46 > b.length || bd.getUint32(p, Endian.little) != 0x02014b50) break;
      final method = bd.getUint16(p + 10, Endian.little);
      final compSize = bd.getUint32(p + 20, Endian.little);
      final nameLen = bd.getUint16(p + 28, Endian.little);
      final extraLen = bd.getUint16(p + 30, Endian.little);
      final commentLen = bd.getUint16(p + 32, Endian.little);
      final localOff = bd.getUint32(p + 42, Endian.little);
      final name = utf8.decode(b.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
      out[name] = _ZipEntry(method, compSize, localOff);
      p += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  static List<int> _zipRead(Uint8List b, _ZipEntry e) {
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    if (bd.getUint32(e.localOffset, Endian.little) != 0x04034b50) throw ImportException(tr('import_empty'));
    final nameLen = bd.getUint16(e.localOffset + 26, Endian.little);
    final extraLen = bd.getUint16(e.localOffset + 28, Endian.little);
    final start = e.localOffset + 30 + nameLen + extraLen;
    final data = b.sublist(start, start + e.compSize);
    if (e.method == 0) return data;
    if (e.method == 8) return ZLibDecoder(raw: true).convert(data);
    throw ImportException(tr('import_empty'));
  }
}

class _ZipEntry {
  final int method;
  final int compSize;
  final int localOffset;
  _ZipEntry(this.method, this.compSize, this.localOffset);
}
