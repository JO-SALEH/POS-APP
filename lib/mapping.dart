import 'codes.dart';
import 'db.dart';
import 'tableio.dart';

/// Which column holds what (null = not in the file). Mirrors the desktop "map the columns" step.
class ColumnMap {
  int? barcode, name, nameAr, price;
  Set<int> alts;
  ColumnMap({this.barcode, this.name, this.nameAr, this.price, Set<int>? alts}) : alts = alts ?? {};
  ColumnMap copy() => ColumnMap(barcode: barcode, name: name, nameAr: nameAr, price: price, alts: {...alts});
  bool get usable => barcode != null && (name != null || nameAr != null);
}

class ImportOptions {
  final bool preferArabic; // when a row has both an English and an Arabic name, show the Arabic one
  final ImportMode mode;
  const ImportOptions({this.preferArabic = false, this.mode = ImportMode.all});
}

/// Column detection and row cleaning, ported from the JØ PHARMA import:
/// header row found by synonyms (Arabic / English), columns guessed by their titles AND their content.
class Mapper {
  static const fields = [
    'name', 'barcode', 'qty', 'cost', 'price', 'expiry', 'upp', 'strip', 'loose', 'min', 'margin', 'name_ar', 'sci',
    'manufacturer', 'category', 'supplier', 'location', 'batch', 'alt'
  ];
  static const _syn = {
  'barcode': 'barcode|bar code|code|item code|product code|sku|ean|upc|gtin|باركود|بار كود|الباركود|كود|كود الصنف|رقم الصنف|كود المنتج|رمز الصنف|الرمز',
  'name': 'name|item|item name|product|product name|drug|drug name|medicine|description|trade name|commercial name|brand|اسم|الاسم|اسم الصنف|الصنف|اسم المنتج|المنتج|اسم الدواء|الدواء|البيان|الاسم التجاري|اسم الصنف انجليزي',
  'name_ar': 'arabic name|name ar|arabic|اسم عربي|الاسم العربي|اسم الصنف عربي|عربي|اسم الصنف بالعربي|الاسم بالعربي',
  'sci': 'active|active ingredient|generic|generic name|scientific name|composition|ingredient|المادة الفعالة|الاسم العلمي|التركيب|الفعال|جنريك',
  'manufacturer': 'company|manufacturer|mfr|mfg|maker|producer|شركة|الشركة|المصنع|الشركة المصنعة',
  'category': 'category|class|group|type|department|تصنيف|التصنيف|القسم|المجموعة|الفئة|النوع',
  'qty': 'quantity|qty|stock|balance|on hand|in stock|available|current stock|closing stock|الكمية|الرصيد|رصيد|المخزون|المتاح|الرصيد الحالي|عدد|الكمية الحالية',
  'loose': 'loose|loose qty|loose units|pieces|كمية فرط|فرط|وحدات فرط',
  'upp': 'units per pack|pack size|pack|pieces per pack|items per pack|عدد الاقراص|عدد الوحدات|حجم العبوة|الوحدات بالعبوة|عدد الوحدات بالعلبة|عدد في العلبة',
  'strip': 'strip size|units per strip|tablets per strip|حجم الشريط|عدد الشريط|حبوب الشريط',
  'cost': 'cost|cost price|purchase price|purchase|buy price|buying price|wholesale|net price|سعر الشراء|الشراء|التكلفة|سعر التكلفة|سعر الجملة',
  'price': 'price|sell price|selling price|sale price|retail|retail price|public price|unit price|سعر البيع|السعر|البيع|سعر الجمهور|سعر المستهلك|سعر العلبة|سعر',
  'margin': 'margin|profit|profit %|markup|هامش|نسبة الربح|الربح|هامش الربح',
  'expiry': 'expiry|expiration|expiry date|exp|exp date|expire|expires|valid until|best before|تاريخ الانتهاء|الصلاحية|تاريخ الصلاحية|انتهاء الصلاحية|انتهاء',
  'min': 'min|min qty|minimum|reorder level|reorder point|minimum stock|حد الطلب|الحد الادنى|اقل كمية|نقطة اعادة الطلب|الحد الأدنى',
  'location': 'location|shelf|rack|bin|الرف|مكان|الموقع|رف',
  'supplier': 'supplier|vendor|distributor|المورد|الموزع|شركة التوزيع|مورد',
  'batch': 'batch|lot|batch no|lot no|رقم التشغيلة|تشغيلة|باتش',
  'alt': 'alt|alt codes|alt barcodes|other codes|other barcodes|aliases|extra barcodes|اكواد اخري|اكواد بديله|باركودات اخري|باركود اضافي',
  };
  static const _weak = {'description', 'brand', 'البيان', 'item'};

  static String fold(String s) {
    final sb = StringBuffer();
    for (final u in s.runes) {
      switch (u) {
        case 0x623: // أ
        case 0x625: // إ
        case 0x622: // آ
        case 0x671: // ٱ
          sb.write('ا');
          break;
        case 0x629: // ة
          sb.write('ه');
          break;
        case 0x649: // ى
        case 0x626: // ئ
          sb.write('ي');
          break;
        case 0x624: // ؤ
          sb.write('و');
          break;
        default:
          sb.writeCharCode(u);
      }
    }
    return sb.toString();
  }

  static String normHeader(Object? h) {
    final s = fold('${h ?? ''}'.replaceAll('﻿', '').toLowerCase());
    return s.replaceAll(RegExp('[^0-9a-zء-ي]+'), '');
  }

  static final Map<String, List<String>> syn = {
    for (final e in _syn.entries)
      e.key: ({for (final x in e.value.split('|')) if (normHeader(x).length >= 2) normHeader(x)}.toList()
        ..sort((a, b) => b.length.compareTo(a.length)))
  };

  static int _score(String h, String s) {
    if (h.isEmpty) return 0;
    if (h == s) return _weak.contains(s) ? 900 : 1000;
    if (s.length >= 4 && h.contains(s)) return s.length;
    return 0;
  }

  static int scoreFor(String field, String header) {
    final h = normHeader(header);
    var best = 0;
    for (final s in syn[field] ?? const <String>[]) {
      final x = _score(h, s);
      if (x > best) best = x;
    }
    return best;
  }

  static int headerMatches(List<String> row) {
    var n = 0;
    for (final c in row) {
      final h = normHeader(c);
      if (h.isEmpty) continue;
      if (syn.values.any((l) => l.any((s) => _score(h, s) > 0))) n++;
    }
    return n;
  }

  /// Index of the header row (titles may sit under a pharmacy name), or -1 when no row looks like a header.
  static int detectHeader(List<List<String>> rows) {
    var best = 0, bi = -1;
    for (var i = 0; i < rows.length && i < 20; i++) {
      final m = headerMatches(rows[i]);
      if (m > best) {
        best = m;
        bi = i;
      }
    }
    return best >= 2 ? bi : -1;
  }

  static final _bcRe = RegExp(r'^\d{8,14}$');

  /// field -> column index (exactly like the desktop auto_map).
  static Map<String, int> autoMap(List<String> headers, List<List<String>> sample) {
    final cand = <List<Object>>[]; // [-score, fieldIndex, column, field]
    for (var ci = 0; ci < headers.length; ci++) {
      final hn = normHeader(headers[ci]);
      for (final f in syn.keys) {
        var sc = 0;
        for (final s in syn[f]!) {
          final x = _score(hn, s);
          if (x > sc) sc = x;
        }
        if (sc > 0) cand.add([-sc, fields.indexOf(f) < 0 ? 99 : fields.indexOf(f), ci, f]);
      }
    }
    cand.sort((a, b) {
      for (var k = 0; k < 3; k++) {
        final c = (a[k] as int).compareTo(b[k] as int);
        if (c != 0) return c;
      }
      return 0;
    });
    final mapping = <String, int>{};
    final used = <int>{};
    for (final c in cand) {
      final f = c[3] as String, ci = c[2] as int;
      if (mapping.containsKey(f) || used.contains(ci)) continue;
      mapping[f] = ci;
      used.add(ci);
    }
    if (!mapping.containsKey('barcode') && sample.isNotEmpty) {
      // a column that is mostly 8-14 digit numbers
      for (var ci = 0; ci < headers.length; ci++) {
        if (used.contains(ci)) continue;
        final vals = [
          for (final r in sample.take(60))
            if (ci < r.length && r[ci].trim().isNotEmpty) Codes.latinDigits(r[ci].trim())
        ];
        if (vals.length >= 3 && vals.where(_bcRe.hasMatch).length >= 0.7 * vals.length) {
          mapping['barcode'] = ci;
          used.add(ci);
          break;
        }
      }
    }
    return mapping;
  }

  /// The mapping the app proposes for a table.
  static ColumnMap propose(List<List<String>> rows, int hidx) {
    final width = rows.take(30).fold<int>(0, (a, r) => r.length > a ? r.length : a);
    final heads = hidx >= 0 ? rows[hidx] : [for (var i = 0; i < width; i++) '#${i + 1}'];
    final body = hidx >= 0 ? rows.sublist(hidx + 1) : rows;
    final m = autoMap(heads, body);
    final map = ColumnMap(barcode: m['barcode'], name: m['name'], nameAr: m['name_ar'], price: m['price']);
    final used = {...m.values};
    if (m['alt'] != null) map.alts.add(m['alt']!);
    // more barcode-like columns (Barcode 2, باركود 2 ...) are extra barcodes of the same product
    for (var i = 0; i < heads.length; i++) {
      if (!used.contains(i) && scoreFor('barcode', heads[i]) > 0) {
        map.alts.add(i);
        used.add(i);
      }
    }
    if (hidx < 0 && map.barcode != null) {
      // no titles at all: first text column = name, first numeric column = price
      bool numeric(int c) {
        final v = [for (final r in body.take(60)) if (c < r.length && r[c].trim().isNotEmpty) r[c]];
        return v.length >= 3 && v.where((x) => TableIO.parseNumber(x) != null && !RegExp(r'[^\d.,\s٠-٩]').hasMatch(x)).length >= 0.8 * v.length;
      }

      bool texty(int c) {
        final v = [for (final r in body.take(60)) if (c < r.length && r[c].trim().isNotEmpty) r[c]];
        return v.length >= 2 && v.where((x) => RegExp(r'[A-Za-zء-ي]').hasMatch(x)).length >= 0.6 * v.length;
      }

      for (var c = 0; c < width; c++) {
        if (c == map.barcode || map.alts.contains(c)) continue;
        if (map.name == null && texty(c)) {
          map.name = c;
        } else if (map.price == null && numeric(c)) {
          map.price = c;
        }
      }
    }
    return map;
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Rows -> products. Rows are cleaned like the desktop does; every problem becomes a count in the report.
  /// The same barcode twice is merged (the first row wins, missing data is filled from the next). [limit] = preview.
  static ParseResult build(List<List<String>> rows, int hidx, ColumnMap m, {ImportOptions opts = const ImportOptions(), int? limit}) {
    final pr = ParseResult();
    final byCode = <String, int>{};
    final start = hidx + 1;
    String cell(List<String> r, int? i) => (i != null && i >= 0 && i < r.length) ? r[i] : '';
    for (var ri = start; ri < rows.length; ri++) {
      if (limit != null && pr.rows >= limit) break;
      final r = rows[ri];
      if (!r.any((c) => c.trim().isNotEmpty)) continue;
      pr.rows++;
      final rawCode = cell(r, m.barcode);
      if (Codes.isSci(rawCode)) pr.sci++;
      final codes = Codes.splitMany(rawCode);
      final alts = <String>[...codes.skip(1)];
      for (final i in m.alts) {
        if (Codes.isSci(cell(r, i))) pr.sci++;
        alts.addAll(Codes.splitMany(cell(r, i)));
      }
      final nameEn = _clean(cell(r, m.name)), nameAr = _clean(cell(r, m.nameAr));
      var name = opts.preferArabic ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
      if (codes.isEmpty) {
        if (name.isNotEmpty || alts.isNotEmpty) {
          pr.noCode++;
        } else {
          pr.other++;
        }
        continue;
      }
      final code = codes.first;
      var fromCode = false;
      if (name.isEmpty) {
        name = code; // like the desktop: a product without a name is named by its barcode (rename it later)
        fromCode = true;
      }
      var price = 0.0;
      final rawPrice = cell(r, m.price);
      if (rawPrice.trim().isNotEmpty) {
        final v = TableIO.parseNumber(rawPrice);
        if (v == null) {
          pr.badNumbers++;
        } else {
          price = v.abs();
        }
      }
      final at = byCode[code];
      if (at != null) {
        pr.merged++;
        final o = pr.items[at];
        final op = o.product;
        final merged = <String>{...o.altCodes, ...alts}..remove(code);
        pr.items[at] = ImportItem(
          Product(
              barcode: code,
              name: (fromCode || op.name != op.barcode) ? op.name : name,
              price: op.price > 0 ? op.price : price),
          merged.toList(),
        );
        continue;
      }
      if (fromCode) pr.namedByCode++;
      if (price <= 0) pr.noPrice++;
      byCode[code] = pr.items.length;
      pr.items.add(ImportItem(Product(barcode: code, name: name, price: price), alts.where((a) => a != code).toSet().toList()));
    }
    return pr;
  }
}
