import 'package:flutter/material.dart';
import '../codes.dart';
import '../db.dart';
import '../i18n.dart';
import 'import_flow.dart';
import '../services.dart';
import '../theme.dart';
import 'home.dart';
import 'scan.dart';

/// Quick "unknown barcode" dialog used by the sell screen: name + price only.
Future<Product?> quickAddProduct(BuildContext context, String code) async {
  final name = TextEditingController();
  final price = TextEditingController();
  String? err;
  final res = await showDialog<Product>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        backgroundColor: JC.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
        title: Text(tr('unknown_title'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('unknown_msg'), style: const TextStyle(color: JC.silverDim)),
            const SizedBox(height: 8),
            Text(code, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: name, autofocus: true, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('name'))),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: JC.silver),
              decoration: InputDecoration(labelText: tr('price')),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: JC.danger))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
          GoldButton(
            label: tr('save'),
            compact: true,
            onPressed: () async {
              final pr = double.tryParse(price.text.trim().replaceAll(',', '.'));
              if (name.text.trim().isEmpty) return setS(() => err = tr('required'));
              if (pr == null || pr < 0) return setS(() => err = tr('bad_number'));
              final p = Product(barcode: code, name: name.text.trim(), price: pr);
              final id = await Db.insertProduct(p);
              if (id == null) return setS(() => err = tr('dup_barcode'));
              p.id = id;
              if (c.mounted) Navigator.pop(c, p);
            },
          ),
        ],
      ),
    ),
  );
  return res;
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _page = 60;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  List<Product> _items = [];
  int _matching = 0;
  int _total = 0;
  bool _busy = false;
  bool _loadingMore = false;
  bool _noPrice = false;
  ProductSort _sort = ProductSort.name;
  final Set<int> _sel = {};
  bool _selecting = false;
  int _gen = 0; // drops answers of outdated searches

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _more();
    });
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    await startImport(context);
    if (mounted) setState(() => _busy = false);
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    final r = await Db.searchProducts(_q.text, limit: _page, sort: _sort, noPrice: _noPrice);
    final m = await Db.countMatching(_q.text, noPrice: _noPrice);
    final n = await Db.productCount();
    if (!mounted || g != _gen) return;
    setState(() {
      _items = r;
      _matching = m;
      _total = n;
      if (n == 0) {
        _sel.clear();
        _selecting = false;
      }
    });
  }

  Future<void> _more() async {
    if (_loadingMore || _items.length >= _matching) return;
    _loadingMore = true;
    final g = _gen;
    final r = await Db.searchProducts(_q.text, limit: _page, offset: _items.length, sort: _sort, noPrice: _noPrice);
    if (mounted && g == _gen) setState(() => _items = [..._items, ...r]);
    _loadingMore = false;
  }

  Future<void> _open(Product p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(product: p)));
    _load();
  }

  Future<void> _add() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm()));
    _load();
  }

  void _toggle(Product p) {
    setState(() {
      _sel.contains(p.id) ? _sel.remove(p.id) : _sel.add(p.id!);
      if (_sel.isEmpty) _selecting = false;
    });
  }

  void _exitSelect() => setState(() {
        _sel.clear();
        _selecting = false;
      });

  Future<void> _selectAll() async {
    final ids = await Db.idsMatching(_q.text, noPrice: _noPrice);
    if (mounted) setState(() => _sel..clear()..addAll(ids));
  }

  Future<void> _deleteSelected() async {
    final n = _sel.length;
    if (n == 0) return;
    if (!await confirmDialog(context, tr('sel_delete_q', [n]), tr('delete'), tr('cancel'), danger: true)) return;
    setState(() => _busy = true);
    final done = await Db.deleteProducts(_sel.toList());
    _exitSelect();
    if (mounted) {
      setState(() => _busy = false);
      toast(context, tr('sel_deleted', [done]));
    }
    _load();
  }

  Future<void> _deleteAll() async {
    if (_total == 0) return;
    if (!await confirmDialog(context, tr('del_all_q', [_total]), tr('delete'), tr('cancel'), danger: true)) return;
    if (!mounted) return;
    if (!await confirmDialog(context, tr('del_all_q2'), tr('delete'), tr('cancel'), danger: true)) return;
    setState(() => _busy = true);
    final done = await Db.deleteAllProducts();
    _exitSelect();
    if (mounted) {
      setState(() => _busy = false);
      toast(context, tr('sel_deleted', [done]));
    }
    _load();
  }

  Future<void> _adjust() async {
    final ids = _sel.isNotEmpty ? _sel.toList() : await Db.idsMatching(_q.text, noPrice: _noPrice);
    if (ids.isEmpty || !mounted) return;
    final c = TextEditingController();
    final v = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: JC.surface2,
        title: Text(tr('adjust_price'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('adjust_q', [ids.length]), style: const TextStyle(color: JC.silverDim)),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            autofocus: true,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(color: JC.silver),
            decoration: const InputDecoration(suffixText: '%'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
          TextButton(
            onPressed: () {
              final x = double.tryParse(c.text.trim().replaceAll(',', '.'));
              if (x != null && x > -100 && x != 0) Navigator.pop(d, x);
            },
            child: Text(tr('ok'), style: const TextStyle(color: JC.gold)),
          ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    final n = await Db.adjustPrices(ids, v);
    if (mounted) toast(context, tr('adjust_done', [n]));
    _load();
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'import':
        return _import();
      case 'export':
        return Files.shareProducts();
      case 'adjust':
        return _adjust();
      case 'delall':
        return _deleteAll();
      case 'nop':
        setState(() => _noPrice = !_noPrice);
        return _load();
      case 'select':
        return setState(() => _selecting = true);
    }
  }

  PopupMenuItem<String> _mi(String v, IconData i, String t, {Color c = JC.silver}) => PopupMenuItem<String>(
        value: v,
        child: Row(children: [Icon(i, size: 20, color: c), const SizedBox(width: 10), Flexible(child: Text(t, style: TextStyle(color: c)))]),
      );

  Widget _topBar() {
    if (_selecting) {
      return Container(
        color: JC.surface2,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close, color: JC.silver), onPressed: _exitSelect),
          Expanded(child: Text(tr('sel_count', [_sel.length]), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800, fontSize: 16))),
          TextButton(
            onPressed: _sel.length >= _matching ? _exitSelect : _selectAll,
            child: Text(_sel.length >= _matching ? tr('sel_none') : tr('sel_all', [_matching]), style: const TextStyle(color: JC.gold)),
          ),
          IconButton(tooltip: tr('adjust_price'), icon: const Icon(Icons.percent, color: JC.gold), onPressed: _sel.isEmpty ? null : _adjust),
          IconButton(tooltip: tr('sel_delete'), icon: const Icon(Icons.delete_outline, color: JC.danger), onPressed: _sel.isEmpty ? null : _deleteSelected),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _q,
            onChanged: (_) => _load(),
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(hintText: tr('search_hint'), prefixIcon: const Icon(Icons.search, color: JC.gold)),
          ),
        ),
        PopupMenuButton<ProductSort>(
          tooltip: tr('sort_by'),
          color: JC.surface3,
          icon: const Icon(Icons.sort, color: JC.gold),
          initialValue: _sort,
          onSelected: (s) {
            _sort = s;
            _load();
          },
          itemBuilder: (_) => [
            for (final e in {
              ProductSort.name: tr('sort_name'),
              ProductSort.newest: tr('sort_newest'),
              ProductSort.priceAsc: tr('sort_price_asc'),
              ProductSort.priceDesc: tr('sort_price_desc'),
            }.entries)
              PopupMenuItem(value: e.key, child: Text(e.value, style: TextStyle(color: e.key == _sort ? JC.gold : JC.silver))),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: tr('more_menu'),
          color: JC.surface3,
          icon: const Icon(Icons.more_vert, color: JC.gold),
          onSelected: _menu,
          itemBuilder: (_) => [
            _mi('select', Icons.checklist, tr('sel_mode')),
            _mi('nop', _noPrice ? Icons.check_box : Icons.check_box_outline_blank, tr('filter_no_price'), c: _noPrice ? JC.gold : JC.silver),
            _mi('adjust', Icons.percent, tr('adjust_price')),
            _mi('import', Icons.upload_file, tr('import_file')),
            _mi('export', Icons.ios_share, tr('export_products')),
            _mi('delall', Icons.delete_forever, tr('del_all'), c: JC.danger),
          ],
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelect();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                backgroundColor: JC.gold,
                foregroundColor: JC.onGold,
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(tr('add_product'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
        body: Column(children: [
          PageTitle('${tr('nav_products')}  ($_total)'),
          if (_busy) const LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3),
          _topBar(),
          if (!_selecting && (_noPrice || _q.text.isNotEmpty) && _total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(tr('showing', [_items.length, _matching]), style: const TextStyle(color: JC.muted, fontSize: 12)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _items.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: tr('no_products'),
                    action: _total == 0 ? GhostButton(label: tr('import_file'), icon: Icons.upload_file, onPressed: _busy ? null : _import) : null,
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      final on = _sel.contains(p.id);
                      return GestureDetector(
                        onLongPress: () {
                          if (!_selecting) setState(() => _selecting = true);
                          _toggle(p);
                        },
                        child: JCard(
                          borderColor: on ? JC.gold : null,
                          onTap: () => _selecting ? _toggle(p) : _open(p),
                          child: Row(children: [
                            if (_selecting)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 10),
                                child: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? JC.gold : JC.muted),
                              ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(p.barcode, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 11)),
                                if (p.stock != null)
                                  Text(tr('stock_of', [p.stock!]), style: TextStyle(color: p.stock! <= 0 ? JC.danger : JC.muted, fontSize: 11)),
                              ]),
                            ),
                            FutureBuilder<int>(
                              future: Db.altCount(p.id!),
                              builder: (c, s) => (s.data ?? 0) == 0
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsetsDirectional.only(end: 10),
                                      child: Chip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(Icons.compare_arrows, size: 14, color: JC.info),
                                        label: Text('${s.data}', style: const TextStyle(color: JC.info, fontSize: 12)),
                                        backgroundColor: JC.surface3,
                                        side: const BorderSide(color: JC.border),
                                      ),
                                    ),
                            ),
                            Text(fmtMoney(p.price),
                                style: TextStyle(color: p.price <= 0 ? JC.warn : JC.gold, fontWeight: FontWeight.w900, fontSize: 16)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  final Product? product;
  const ProductForm({super.key, this.product});
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final TextEditingController _code = TextEditingController(text: widget.product?.barcode ?? '');
  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _price =
      TextEditingController(text: widget.product == null ? '' : fmtMoney(widget.product!.price));
  List<Product> _alts = [];
  final _extra = TextEditingController();
  late final TextEditingController _nameAr = TextEditingController(text: widget.product?.nameAr ?? '');
  late final TextEditingController _upp = TextEditingController(text: '${widget.product?.unitsPerPack ?? 1}');
  late final TextEditingController _strip = TextEditingController(text: '${widget.product?.stripSize ?? 0}');
  late final TextEditingController _stock = TextEditingController(text: widget.product?.stock?.toString() ?? '');
  late Product? _cur = widget.product;
  String? _err;

  @override
  void initState() {
    super.initState();
    final id = widget.product?.id;
    if (id != null) {
      Db.altsOf(id).then((a) => mounted ? setState(() => _alts = a) : null);
      Db.codesOf(id).then((c) => mounted ? setState(() => _extra.text = c.join('\n')) : null);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code != null) setState(() => _code.text = code);
  }

  Future<void> _pickAlts() async {
    final res = await Navigator.push<List<Product>>(
      context,
      MaterialPageRoute(builder: (_) => AltPicker(selected: _alts, excludeId: widget.product?.id)),
    );
    if (res != null) setState(() => _alts = res);
  }

  Future<void> _save() async {
    final pr = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) return setState(() => _err = tr('required'));
    if (pr == null || pr < 0) return setState(() => _err = tr('bad_number'));
    final p = _cur ??= Product(barcode: '', name: '', price: 0);
    p.barcode = _code.text.trim();
    p.name = _name.text.trim();
    p.price = pr;
    p.nameAr = _nameAr.text.trim();
    p.unitsPerPack = (int.tryParse(_upp.text.trim()) ?? 1).clamp(1, 100000);
    p.stripSize = (int.tryParse(_strip.text.trim()) ?? 0).clamp(0, 100000);
    if (p.stripSize >= p.unitsPerPack) p.stripSize = 0; // a strip must be smaller than the pack
    p.stock = _stock.text.trim().isEmpty ? null : (int.tryParse(_stock.text.trim()) ?? 0).clamp(0, 100000000);
    if (p.id == null) {
      final id = await Db.insertProduct(p);
      if (id == null) return setState(() => _err = tr('dup_barcode'));
      p.id = id;
    } else {
      if (!await Db.updateProduct(p)) return setState(() => _err = tr('dup_barcode'));
    }
    await Db.setAlts(p.id!, _alts.map((e) => e.id!).toList());
    final refused = await Db.setCodes(p.id!, Codes.splitMany(_extra.text));
    if (refused.isNotEmpty) {
      if (mounted) setState(() => _err = tr('codes_refused', [refused.join(', ')]));
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (await confirmDialog(context, tr('confirm_delete'), tr('delete'), tr('cancel'), danger: true)) {
      await Db.deleteProduct(widget.product!.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: L.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.product == null ? tr('add_product') : tr('edit_product')),
          actions: [
            if (widget.product != null) IconButton(icon: const Icon(Icons.delete_outline, color: JC.danger), onPressed: _delete),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _code,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(
              labelText: tr('barcode'),
              suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner, color: JC.gold), onPressed: _scan),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('name'))),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(labelText: '${tr('price')} (${tr('currency')})'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _nameAr, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('name_ar_label'))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _upp,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: JC.silver),
                decoration: InputDecoration(labelText: tr('units_per_pack')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _strip,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: JC.silver),
                decoration: InputDecoration(labelText: tr('strip_size')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(labelText: tr('stock_label')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extra,
            minLines: 1,
            maxLines: 5,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(labelText: tr('extra_codes'), helperText: tr('extra_codes_hint'), helperMaxLines: 2),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.compare_arrows, color: JC.info),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('alternatives'), style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w800, fontSize: 16))),
            GhostButton(label: tr('add_alt'), icon: Icons.add, onPressed: _pickAlts),
          ]),
          const SizedBox(height: 10),
          if (_alts.isEmpty)
            Text(tr('no_alts'), style: const TextStyle(color: JC.muted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in _alts)
                InputChip(
                  label: Text('${a.name} · ${fmtMoney(a.price)}'),
                  backgroundColor: JC.surface3,
                  labelStyle: const TextStyle(color: JC.silver),
                  deleteIconColor: JC.danger,
                  side: const BorderSide(color: JC.borderHi),
                  onDeleted: () => setState(() => _alts.remove(a)),
                ),
            ]),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_err!, style: const TextStyle(color: JC.danger))),
          const SizedBox(height: 24),
          GoldButton(label: tr('save'), icon: Icons.save_outlined, onPressed: _save),
        ]),
      ),
    );
  }
}

/// Multi-select list used to choose a product's alternatives.
class AltPicker extends StatefulWidget {
  final List<Product> selected;
  final int? excludeId;
  const AltPicker({super.key, required this.selected, this.excludeId});
  @override
  State<AltPicker> createState() => _AltPickerState();
}

class _AltPickerState extends State<AltPicker> {
  final _q = TextEditingController();
  late final Map<int, Product> _sel = {for (final p in widget.selected) p.id!: p};
  List<Product> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Db.searchProducts(_q.text, limit: 100);
    if (mounted) setState(() => _items = r.where((p) => p.id != widget.excludeId).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: L.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('pick_alts')),
          actions: [TextButton(onPressed: () => Navigator.pop(context, _sel.values.toList()), child: Text(tr('done'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)))],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              onChanged: (_) => _load(),
              style: const TextStyle(color: JC.silver),
              decoration: InputDecoration(hintText: tr('search_hint'), prefixIcon: const Icon(Icons.search, color: JC.gold)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final p = _items[i];
                return CheckboxListTile(
                  value: _sel.containsKey(p.id),
                  onChanged: (v) => setState(() => v == true ? _sel[p.id!] = p : _sel.remove(p.id)),
                  title: Text(p.name, style: const TextStyle(color: JC.silver)),
                  subtitle: Text('${p.barcode}  ·  ${fmtMoney(p.price)}', style: const TextStyle(color: JC.muted, fontSize: 12)),
                  activeColor: JC.gold,
                  checkColor: JC.onGold,
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
