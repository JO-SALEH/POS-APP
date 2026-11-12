import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../importer.dart';
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
  final _q = TextEditingController();
  List<Product> _items = [];
  int _total = 0;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Excel / JO PHARMA database / CSV / JSON -> products.
  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final n = await Files.importProducts();
      if (n != null && mounted) toast(context, tr('import_ok', [n]));
    } on ImportException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, tr('import_fail', ['$e']));
    }
    if (mounted) setState(() => _importing = false);
    _load();
  }

  Future<void> _load() async {
    final r = await Db.searchProducts(_q.text, limit: 200);
    final n = await Db.productCount();
    if (mounted) setState(() {
      _items = r;
      _total = n;
    });
  }

  Future<void> _open([Product? p]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(product: p)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: JC.gold,
        foregroundColor: JC.onGold,
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: Text(tr('add_product'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        PageTitle('${tr('nav_products')}  ($_total)'),
        if (_importing) const LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3),
        Padding(
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
            IconButton(
              tooltip: tr('import_file'),
              icon: const Icon(Icons.upload_file, color: JC.gold, size: 28),
              onPressed: _importing ? null : _import,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('no_products'), style: const TextStyle(color: JC.muted)),
                    const SizedBox(height: 14),
                    GhostButton(label: tr('import_file'), icon: Icons.upload_file, onPressed: _importing ? null : _import),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = _items[i];
                    return JCard(
                      onTap: () => _open(p),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(p.barcode, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 11)),
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
                        Text(fmtMoney(p.price), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w900, fontSize: 16)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
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
  String? _err;

  @override
  void initState() {
    super.initState();
    final id = widget.product?.id;
    if (id != null) Db.altsOf(id).then((a) => mounted ? setState(() => _alts = a) : null);
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
    final p = widget.product ?? Product(barcode: '', name: '', price: 0);
    p.barcode = _code.text.trim();
    p.name = _name.text.trim();
    p.price = pr;
    if (p.id == null) {
      final id = await Db.insertProduct(p);
      if (id == null) return setState(() => _err = tr('dup_barcode'));
      p.id = id;
    } else {
      if (!await Db.updateProduct(p)) return setState(() => _err = tr('dup_barcode'));
    }
    await Db.setAlts(p.id!, _alts.map((e) => e.id!).toList());
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
