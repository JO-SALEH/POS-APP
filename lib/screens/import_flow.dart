import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../importer.dart';
import '../mapping.dart';
import '../theme.dart';
import 'import_report.dart';

/// The whole import, like the desktop: pick a file -> (map the columns) -> import -> verified report.
/// Returns true when something was imported.
Future<bool> startImport(BuildContext context) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
  if (res == null || res.files.isEmpty || !context.mounted) return false;
  final path = res.files.first.path;
  if (path == null) {
    toast(context, tr('import_empty'));
    return false;
  }
  try {
    final src = await _loading(context, () => Importer.open(path));
    if (!context.mounted) return false;
    ImportReport? rep;
    if (src.parsed != null) {
      rep = await _loading(context, () => Importer.commit(src.parsed!));
    } else {
      rep = await Navigator.push<ImportReport>(context, MaterialPageRoute(builder: (_) => ImportMapScreen(src: src)));
    }
    if (rep != null && context.mounted) {
      await showImportReport(context, rep);
      return true;
    }
  } on ImportException catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (e) {
    if (context.mounted) toast(context, tr('import_fail', ['$e']));
  }
  return false;
}

Future<T> _loading<T>(BuildContext context, Future<T> Function() job) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: JCard(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: JC.gold),
            const SizedBox(height: 14),
            Text(tr('import_reading'), style: const TextStyle(color: JC.silver, decoration: TextDecoration.none, fontSize: 14)),
          ]),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 50)); // let the spinner paint before heavy work
  try {
    return await job();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Step 2 for table files: shows what was found, lets the user correct which column is which, previews the result.
class ImportMapScreen extends StatefulWidget {
  final ImportSource src;
  const ImportMapScreen({super.key, required this.src});
  @override
  State<ImportMapScreen> createState() => _ImportMapScreenState();
}

class _ImportMapScreenState extends State<ImportMapScreen> {
  late final List<List<String>> rows = widget.src.rows!;
  late int hidx;
  late ColumnMap map;
  bool preferArabic = false;
  ImportMode mode = ImportMode.all;
  ParseResult? prev;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    hidx = Mapper.detectHeader(rows);
    map = Mapper.propose(rows, hidx);
    _refresh();
  }

  int get _width => rows.take(30).fold<int>(0, (a, r) => r.length > a ? r.length : a);

  List<String> get _heads {
    final h = hidx >= 0 ? rows[hidx] : <String>[];
    return [for (var i = 0; i < _width; i++) (i < h.length && h[i].trim().isNotEmpty) ? h[i].trim() : '#${i + 1}'];
  }

  String _label(int i) {
    final t = '${i + 1}: ${_heads[i]}';
    return t.length > 34 ? '${t.substring(0, 34)}…' : t;
  }

  void _refresh() {
    setState(() => prev = map.usable ? Mapper.build(rows, hidx, map, opts: ImportOptions(preferArabic: preferArabic, mode: mode), limit: 2000) : null);
  }

  Future<void> _go() async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final pr = Mapper.build(rows, hidx, map, opts: ImportOptions(preferArabic: preferArabic, mode: mode));
      final rep = await Importer.commit(pr, mode: mode);
      if (mounted) Navigator.pop(context, rep);
    } on ImportException catch (e) {
      if (mounted) {
        toast(context, e.message);
        setState(() => busy = false);
      }
    } catch (e) {
      if (mounted) {
        toast(context, tr('import_fail', ['$e']));
        setState(() => busy = false);
      }
    }
  }

  Widget _col(String label, int? value, void Function(int?) set, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<int?>(
          value: (value != null && value < _width) ? value : null,
          isExpanded: true,
          dropdownColor: JC.surface3,
          style: const TextStyle(color: JC.silver, fontSize: 14),
          decoration: InputDecoration(labelText: required ? '$label *' : label),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(tr('map_none'), style: const TextStyle(color: JC.muted))),
            for (var i = 0; i < _width; i++) DropdownMenuItem<int?>(value: i, child: Text(_label(i), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            set(v);
            map.alts.removeWhere((a) => a == map.barcode || a == map.name || a == map.nameAr || a == map.price);
            _refresh();
          },
        ),
      );

  Widget _line(String text, {Color color = JC.silverDim}) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(text, style: TextStyle(color: color, fontSize: 13)));

  Widget _segment<T>(String label, T value, Map<T, String> options, void Function(T) set) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: JC.silverDim, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [for (final e in options.entries) ButtonSegment<T>(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 12)))],
            selected: {value},
            onSelectionChanged: (s) {
              set(s.first);
              _refresh();
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? JC.gold : JC.surface3),
              foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? JC.onGold : JC.silver),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = prev;
    final body = hidx >= 0 ? rows.length - hidx - 1 : rows.length;
    final candidates = [for (var i = 0; i < _width; i++) if (i != map.barcode && i != map.name && i != map.nameAr && i != map.price) i];
    return Directionality(
      textDirection: L.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(tr('map_title'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          Text(tr('map_file', [widget.src.fileName, body]), style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr('map_hint'), style: const TextStyle(color: JC.muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: hidx.clamp(-1, rows.length - 1),
            isExpanded: true,
            dropdownColor: JC.surface3,
            style: const TextStyle(color: JC.silver, fontSize: 14),
            decoration: InputDecoration(labelText: tr('map_header')),
            items: [
              DropdownMenuItem(value: -1, child: Text(tr('map_header_none'))),
              for (var i = 0; i < rows.length && i < 20; i++)
                DropdownMenuItem(value: i, child: Text(tr('map_row', [i + 1, rows[i].take(3).join(' · ')]), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              hidx = v ?? -1;
              map = Mapper.propose(rows, hidx);
              _refresh();
            },
          ),
          const SizedBox(height: 10),
          _col(tr('map_barcode'), map.barcode, (v) => map.barcode = v, required: true),
          _col(tr('map_name'), map.name, (v) => map.name = v, required: true),
          _col(tr('map_name_ar'), map.nameAr, (v) => map.nameAr = v),
          _col(tr('map_price'), map.price, (v) => map.price = v),
          Text(tr('map_extra'), style: const TextStyle(color: JC.silverDim, fontSize: 13)),
          const SizedBox(height: 6),
          if (candidates.isEmpty)
            Text(tr('map_none'), style: const TextStyle(color: JC.muted))
          else
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final i in candidates)
                FilterChip(
                  label: Text(_label(i)),
                  selected: map.alts.contains(i),
                  selectedColor: JC.goldDark,
                  backgroundColor: JC.surface3,
                  checkmarkColor: JC.silver,
                  labelStyle: const TextStyle(color: JC.silver, fontSize: 12),
                  side: const BorderSide(color: JC.borderHi),
                  onSelected: (v) {
                    v ? map.alts.add(i) : map.alts.remove(i);
                    _refresh();
                  },
                ),
            ]),
          _segment<bool>(tr('map_name_use'), preferArabic, {false: tr('map_use_name'), true: tr('map_use_ar')}, (v) => preferArabic = v),
          _segment<ImportMode>(tr('map_existing'), mode,
              {ImportMode.all: tr('map_all'), ImportMode.priceOnly: tr('map_price_only'), ImportMode.newOnly: tr('map_new_only')}, (v) => mode = v),
          const SizedBox(height: 16),
          JCard(
            borderColor: JC.borderHi,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('map_preview'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (p == null)
                _line(tr('map_need'), color: JC.danger)
              else ...[
                _line(tr('map_ready', [p.items.length]), color: JC.silver),
                if (body > 2000) _line(tr('map_sample'), color: JC.muted),
                if (p.noCode + p.other > 0) _line(tr('rep_skip_code') + ': ${p.noCode + p.other}', color: JC.danger),
                if (p.merged > 0) _line(tr('rep_dups') + ': ${p.merged}', color: JC.warn),
                if (p.namedByCode > 0) _line(tr('rep_named_code') + ': ${p.namedByCode}', color: JC.warn),
                if (p.noPrice > 0) _line(tr('rep_no_price') + ': ${p.noPrice}', color: JC.warn),
                if (p.badNumbers > 0) _line(tr('rep_bad_num') + ': ${p.badNumbers}', color: JC.danger),
                if (p.sci > 0) _line(tr('rep_sci') + ': ${p.sci}', color: JC.danger),
                const Divider(color: JC.border),
                for (final it in p.items.take(4))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JC.silver, fontSize: 13)),
                          Text('${it.product.barcode}${it.altCodes.isEmpty ? '' : '  +${it.altCodes.length}'}',
                              textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 11)),
                        ]),
                      ),
                      Text(fmtMoney(it.product.price), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800)),
                    ]),
                  ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          if (busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3)),
          GoldButton(label: tr('map_go'), icon: Icons.download_done, onPressed: (p == null || busy) ? null : _go),
        ]),
      ),
    );
  }
}
