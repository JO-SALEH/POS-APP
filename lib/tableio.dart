import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'codes.dart';

/// Reading any table file into rows of text (pure Dart: runs in a background isolate, no Flutter needed).
/// Mirrors the desktop reader: CSV / TXT / TSV in any encoding (UTF-8, UTF-16, Windows-1256) and delimiter,
/// Excel .xlsx (the sheet with the most cells), JSON. Errors are FormatException('OLD_XLS' | 'EMPTY' | 'TOO_BIG').
class TableIO {
  static const maxRows = 300000;
  static const maxBytes = 200 * 1024 * 1024;

  static List<List<String>> readFile(String path) {
    final f = File(path);
    if (!f.existsSync()) throw const FormatException('EMPTY');
    if (f.lengthSync() > maxBytes) throw const FormatException('TOO_BIG');
    final rows = readBytes(f.readAsBytesSync());
    if (rows.isEmpty) throw const FormatException('EMPTY');
    return rows;
  }

  static List<List<String>> readBytes(Uint8List raw) {
    if (raw.length >= 4 && raw[0] == 0x50 && raw[1] == 0x4B) return readXlsx(raw);
    if (raw.length >= 4 && raw[0] == 0xD0 && raw[1] == 0xCF && raw[2] == 0x11 && raw[3] == 0xE0) {
      throw const FormatException('OLD_XLS');
    }
    final text = decode(raw);
    final t = text.trimLeft();
    if (t.startsWith('[') || t.startsWith('{')) {
      final j = _jsonRows(t);
      if (j != null) return j;
    }
    return parseDelimited(text);
  }

  // ------------------------------------------------------------- encodings
  static const _cp1256 = <int>[
    0x20ac, 0x67e, 0x201a, 0x192, 0x201e, 0x2026, 0x2020, 0x2021,
    0x2c6, 0x2030, 0x679, 0x2039, 0x152, 0x686, 0x698, 0x688,
    0x6af, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
    0x6a9, 0x2122, 0x691, 0x203a, 0x153, 0x200c, 0x200d, 0x6ba,
    0xa0, 0x60c, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0x6be, 0xab, 0xac, 0xad, 0xae, 0xaf,
    0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
    0xb8, 0xb9, 0x61b, 0xbb, 0xbc, 0xbd, 0xbe, 0x61f,
    0x6c1, 0x621, 0x622, 0x623, 0x624, 0x625, 0x626, 0x627,
    0x628, 0x629, 0x62a, 0x62b, 0x62c, 0x62d, 0x62e, 0x62f,
    0x630, 0x631, 0x632, 0x633, 0x634, 0x635, 0x636, 0xd7,
    0x637, 0x638, 0x639, 0x63a, 0x640, 0x641, 0x642, 0x643,
    0xe0, 0x644, 0xe2, 0x645, 0x646, 0x647, 0x648, 0xe7,
    0xe8, 0xe9, 0xea, 0xeb, 0x649, 0x64a, 0xee, 0xef,
    0x64b, 0x64c, 0x64d, 0x64e, 0xf4, 0x64f, 0x650, 0xf7,
    0x651, 0xf9, 0x652, 0xfb, 0xfc, 0x200e, 0x200f, 0x6d2,
  ];

  static String decode(Uint8List raw) {
    if (raw.length >= 2 && ((raw[0] == 0xFF && raw[1] == 0xFE) || (raw[0] == 0xFE && raw[1] == 0xFF))) {
      final le = raw[0] == 0xFF;
      final units = <int>[];
      for (var i = 2; i + 1 < raw.length; i += 2) {
        units.add(le ? raw[i] | (raw[i + 1] << 8) : (raw[i] << 8) | raw[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    var b = raw;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = Uint8List.sublistView(b, 3);
    try {
      return utf8.decode(b);
    } on FormatException {
      final sb = StringBuffer();
      for (final x in b) {
        sb.writeCharCode(x < 128 ? x : _cp1256[x - 128]);
      }
      return sb.toString();
    }
  }

  // ------------------------------------------------------------------ text
  static List<List<String>> parseDelimited(String text) {
    final lines = text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty).take(40).toList();
    if (lines.isEmpty) return [];
    var best = ',';
    var bestScore = -1;
    for (final d in const [',', ';', '\t', '|']) {
      final counts = [for (final l in lines) d.allMatches(l).length];
      final nz = counts.where((c) => c > 0).toList();
      if (nz.isEmpty) continue;
      final freq = <int, int>{};
      for (final c in nz) {
        freq[c] = (freq[c] ?? 0) + 1;
      }
      var mode = nz.first, modeN = 0;
      freq.forEach((k, v) {
        if (v > modeN) {
          mode = k;
          modeN = v;
        }
      });
      final sc = counts.where((c) => c == mode).length * 1000 + mode; // the delimiter that splits most lines the same way
      if (sc > bestScore) {
        best = d;
        bestScore = sc;
      }
    }
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    final delim = best.codeUnitAt(0);
    final n = text.length;
    void endCell() {
      row.add(cell.toString().trim());
      cell.clear();
    }

    void endRow() {
      endCell();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < n && rows.length <= maxRows; i++) {
      final ch = text.codeUnitAt(i);
      if (quoted) {
        if (ch == 0x22) {
          if (i + 1 < n && text.codeUnitAt(i + 1) == 0x22) {
            cell.writeCharCode(0x22);
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.writeCharCode(ch);
        }
      } else if (ch == 0x22 && cell.isEmpty) {
        quoted = true;
      } else if (ch == delim) {
        endCell();
      } else if (ch == 0x0A) {
        endRow();
      } else if (ch == 0x0D) {
        if (i + 1 < n && text.codeUnitAt(i + 1) == 0x0A) i++;
        endRow();
      } else {
        cell.writeCharCode(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  static List<List<String>>? _jsonRows(String t) {
    try {
      var data = jsonDecode(t);
      if (data is Map) {
        data = data.values.firstWhere((v) => v is List, orElse: () => const []);
      }
      if (data is! List) return null;
      final keys = <String>[];
      for (final d in data.take(2000)) {
        if (d is Map) {
          for (final k in d.keys) {
            if (!keys.contains('$k')) keys.add('$k');
          }
        }
      }
      if (keys.isEmpty) return null;
      String v(Object? x) => x == null ? '' : (x is List ? x.join(',') : '$x');
      return [
        keys,
        for (final d in data)
          if (d is Map) [for (final k in keys) v(d[k])]
      ];
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ xlsx (zip)
  static List<List<String>> readXlsx(Uint8List bytes) {
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
    if (sheets.isEmpty) throw const FormatException('EMPTY');
    var best = <List<String>>[];
    var bestCells = -1;
    for (final name in sheets) {
      final rows = _readSheet(utf8.decode(_zipRead(bytes, entries[name]!), allowMalformed: true), shared);
      final cells = rows.fold<int>(0, (a, r) => a + r.length);
      if (cells > bestCells) {
        best = rows; // like the desktop: the sheet with the most data
        bestCells = cells;
      }
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
        row[col] = value.trim();
      }
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      if (rows.length > maxRows) break;
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

  static Map<String, _ZipEntry> _zipEntries(Uint8List b) {
    final bd = ByteData.view(b.buffer, b.offsetInBytes, b.length);
    var eocd = -1;
    for (var i = b.length - 22; i >= 0 && i >= b.length - 22 - 65535; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('EMPTY');
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
    if (bd.getUint32(e.localOffset, Endian.little) != 0x04034b50) throw const FormatException('EMPTY');
    final nameLen = bd.getUint16(e.localOffset + 26, Endian.little);
    final extraLen = bd.getUint16(e.localOffset + 28, Endian.little);
    final start = e.localOffset + 30 + nameLen + extraLen;
    final data = b.sublist(start, start + e.compSize);
    if (e.method == 0) return data;
    if (e.method == 8) return ZLibDecoder(raw: true).convert(data);
    throw const FormatException('EMPTY');
  }

  // ---------------------------------------------------------------- numbers
  /// Any numeric text -> double or null: 35 / 35.25 / 1,234.50 / 1.234,50 / 12,5 / ٣٫٥ / (5) / 5- / "EGP 12" / "12 ج.م".
  static double? parseNumber(String? s) {
    if (s == null) return null;
    var t = Codes.latinDigits(s).replaceAll('٫', '.').replaceAll('٬', ',').replaceAll(' ', ' ').trim();
    if (t.isEmpty) return null;
    var neg = (t.startsWith('(') && t.endsWith(')')) || RegExp(r'\d\s*-\s*$').hasMatch(t);
    final m = RegExp("[-+]?\\d(?:[\\d.,'   ]*\\d)?").firstMatch(t);
    if (m == null) return null;
    t = m.group(0)!;
    if (t.startsWith('-')) neg = true;
    t = t.replaceFirst(RegExp(r'^[+-]+'), '');
    t = t.replaceAll(RegExp("[ '  ]"), '');
    t = t.replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');
    if (t.isEmpty) return null;
    if (t.contains(',') && t.contains('.')) {
      if (t.lastIndexOf(',') > t.lastIndexOf('.')) {
        t = t.replaceAll('.', '').replaceAll(',', '.');
      } else {
        t = t.replaceAll(',', '');
      }
    }
    for (final sep in const [',', '.']) {
      final other = sep == ',' ? '.' : ',';
      if (t.contains(sep) && !t.contains(other)) {
        final parts = t.split(sep);
        if (parts.length > 2) {
          t = parts.skip(1).every((x) => x.length == 3) ? t.replaceAll(sep, '') : '${parts[0]}.${parts.skip(1).join()}';
        } else if (sep == ',') {
          final grouping = parts[1].length == 3 && parts[0].isNotEmpty && parts[0].length <= 3 && parts[0] != '0';
          t = grouping ? t.replaceAll(',', '') : t.replaceAll(',', '.');
        }
        break;
      }
    }
    final v = double.tryParse(t);
    if (v == null) return null;
    return neg ? -v.abs() : v;
  }
}

class _ZipEntry {
  final int method;
  final int compSize;
  final int localOffset;
  _ZipEntry(this.method, this.compSize, this.localOffset);
}
