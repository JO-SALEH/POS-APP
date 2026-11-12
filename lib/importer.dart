import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'i18n.dart';

/// Shown to the user as is (already translated).
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// Product import from any file the user picks:
///  * Excel .xlsx            (own zip + XML reader: no extra package, tolerant of styles / Arabic / numeric barcodes)
///  * JO PHARMA database     (jo_pharmacy.db: table `medications`)  or a JO POS backup (table `products`)
///  * CSV / TSV / JSON       (handled by [parseText], passed in by the caller)
/// Columns are found by their header names (English or Arabic); without a header the order is barcode, name, price.
class Importer {
  // ------------------------------------------------------------------ entry
  static Future<int> importPath(String path, {required List<Product> Function(String text) parseText}) async {
    final f = File(path);
    if (!await f.exists()) throw ImportException(tr('import_empty'));
    final head = await _readHead(f);
    if (_isSqlite(head)) return importSqlite(path);
    if (head.length >= 4 && head[0] == 0x50 && head[1] == 0x4B) {
      final products = fromRows(_readXlsx(await f.readAsBytes()));
      if (products.isEmpty) throw ImportException(tr('import_empty'));
      return Db.bulkUpsert(products);
    }
    if (head.length >= 4 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0) {
      throw ImportException(tr('import_xls'));
    }
    var text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final products = parseText(text);
    if (products.isEmpty) throw ImportException(tr('import_empty'));
    return Db.bulkUpsert(products);
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
  static Future<int> importSqlite(String path) async {
    final dir = await getTemporaryDirectory();
    final copy = File('${dir.path}/jo_import_${DateTime.now().millisecondsSinceEpoch}.db');
    await File(path).copy(copy.path); // always work on a copy: the picked file is never touched
    Database? src;
    try {
      src = await openDatabase(copy.path, singleInstance: false);
      final tables = (await src.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => '${r['name']}')
          .toSet();
      final out = <Product>[];
      if (tables.contains('medications')) {
        final cols = (await src.rawQuery('PRAGMA table_info(medications)')).map((r) => '${r['name']}').toSet();
        final arCol = cols.contains('name_ar') ? 'name_ar' : "'' AS name_ar";
        var offset = 0;
        while (true) {
          final rows = await src.rawQuery(
              'SELECT barcode, name, $arCol, price FROM medications ORDER BY id LIMIT 5000 OFFSET ?',
              [offset]);
          if (rows.isEmpty) break;
          for (final r in rows) {
            final code = '${r['barcode'] ?? ''}'.trim();
            var name = '${r['name'] ?? ''}'.trim();
            if (name.isEmpty) name = '${r['name_ar'] ?? ''}'.trim();
            final price = (r['price'] is num) ? (r['price'] as num).toDouble() : (double.tryParse('${r['price']}') ?? 0);
            if (code.isNotEmpty && name.isNotEmpty) out.add(Product(barcode: code, name: name, price: price));
          }
          offset += rows.length;
          if (rows.length < 5000) break;
        }
      } else if (tables.contains('products')) {
        final rows = await src.rawQuery('SELECT barcode, name, price FROM products');
        for (final r in rows) {
          final code = '${r['barcode'] ?? ''}'.trim();
          final name = '${r['name'] ?? ''}'.trim();
          final price = (r['price'] is num) ? (r['price'] as num).toDouble() : 0.0;
          if (code.isNotEmpty && name.isNotEmpty) out.add(Product(barcode: code, name: name, price: price));
        }
      } else {
        throw ImportException(tr('import_db_unknown'));
      }
      if (out.isEmpty) throw ImportException(tr('import_empty'));
      return Db.bulkUpsert(out);
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

  static String _cleanCode(String raw) {
    var s = raw.trim();
    if (RegExp(r'^\d+\.0+$').hasMatch(s)) return s.substring(0, s.indexOf('.'));
    if (RegExp(r'^\d+(\.\d+)?[eE][+-]?\d+$').hasMatch(s)) {
      final d = double.tryParse(s);
      if (d != null && d.isFinite && d.abs() < 1e18) return d.toStringAsFixed(0);
    }
    return s;
  }

  static double? _price(String raw) {
    final s = raw.trim().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(s);
  }

  static List<Product> fromRows(List<List<String>> rows) {
    var hRow = -1, cCode = 0, cName = 1, cPrice = 2;
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
      hRow = r;
      cCode = c;
      cName = n;
      cPrice = p; // -1 when the file has no price column: price 0, can be edited later
      break;
    }
    final out = <Product>[];
    for (var r = hRow + 1; r < rows.length; r++) {
      final row = rows[r];
      String at(int i) => (i >= 0 && i < row.length) ? row[i] : '';
      final code = _cleanCode(at(cCode));
      final name = at(cName).trim();
      if (code.isEmpty || name.isEmpty) continue;
      double? price = cPrice < 0 ? 0.0 : _price(at(cPrice));
      if (price == null) {
        if (hRow >= 0) {
          price = 0.0;
        } else {
          continue; // no header and the 3rd cell is not a number: header-like / junk row
        }
      }
      out.add(Product(barcode: code, name: name, price: price));
    }
    return out;
  }

  // ------------------------------------------------------------- xlsx (zip)
  static List<List<String>> _readXlsx(Uint8List bytes) {
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
      if (fromRows(rows).isNotEmpty) return rows; // the first sheet that really holds products
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
