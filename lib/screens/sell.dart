import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../services.dart';
import '../theme.dart';
import 'home.dart';
import 'products.dart';
import 'scan.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  List<Product> _results = [];

  @override
  void initState() {
    super.initState();
    app.addListener(_onApp);
  }

  void _onApp() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search(String s) async {
    if (s.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final r = await Db.searchProducts(s, limit: 8);
    if (mounted) setState(() => _results = r);
  }

  /// Resolve a scanned/typed code: known -> add to cart; unknown -> quick-add dialog.
  Future<Product?> _resolve(String code) async {
    var p = await Db.byBarcode(code);
    p ??= await quickAddProduct(context, code);
    if (p != null) app.addToCart(p);
    return p;
  }

  Future<void> _submit(String s) async {
    final text = s.trim();
    if (text.isEmpty) return;
    final exact = await Db.byBarcode(text);
    if (exact != null) {
      app.addToCart(exact);
    } else if (_results.length == 1) {
      app.addToCart(_results.first);
    } else if (_results.isEmpty) {
      await _resolve(text); // unknown barcode typed / hardware-scanned
    } else {
      return; // several matches: let the cashier pick one
    }
    _q.clear();
    setState(() => _results = []);
    _focus.requestFocus();
  }

  Future<void> _scan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanPage(
          continuous: true,
          onCode: (code) async {
            final p = await _resolve(code);
            return p == null ? null : tr('added', [p.name]);
          },
          footer: () => '${tr('total')}: ${fmtMoney(app.cartTotal)} ${tr('currency')}',
        ),
      ),
    );
  }

  Future<void> _checkout() async {
    final done = await showDialog<bool>(context: context, builder: (_) => const _CheckoutDialog());
    if (done == true && mounted) toast(context, tr('sale_saved'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PageTitle(tr('nav_sell'), actions: [
        if (app.cart.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              if (await confirmDialog(context, tr('confirm_clear'), tr('confirm'), tr('cancel'), danger: true)) app.clearCart();
            },
            icon: const Icon(Icons.delete_sweep_outlined, color: JC.danger, size: 20),
            label: Text(tr('clear_cart'), style: const TextStyle(color: JC.danger)),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              focusNode: _focus,
              onChanged: _search,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: JC.silver),
              decoration: InputDecoration(
                hintText: tr('search_hint'),
                prefixIcon: const Icon(Icons.search, color: JC.gold),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: JC.muted),
                        onPressed: () {
                          _q.clear();
                          _search('');
                        }),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: GoldButton(label: tr('scan'), icon: Icons.qr_code_scanner, onPressed: _scan, compact: true),
          ),
        ]),
      ),
      if (_results.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(color: JC.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.borderHi)),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _results.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = _results[i];
              return ListTile(
                dense: true,
                title: Text(p.name, style: const TextStyle(color: JC.silver)),
                subtitle: Text(p.barcode, style: const TextStyle(color: JC.muted, fontSize: 11)),
                trailing: Text(fmtMoney(p.price), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
                onTap: () {
                  app.addToCart(p);
                  _q.clear();
                  setState(() => _results = []);
                },
              );
            },
          ),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: app.cart.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shopping_cart_outlined, color: JC.goldDark, size: 64),
                  const SizedBox(height: 12),
                  Text(tr('cart_empty'), textAlign: TextAlign.center, style: const TextStyle(color: JC.muted, fontSize: 15)),
                ]),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: app.cart.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CartTile(line: app.cart[i]),
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(color: JC.surface, border: Border(top: BorderSide(color: JC.borderHi))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr('total')}  (${app.cartCount})', style: const TextStyle(color: JC.silverDim, fontSize: 12)),
              Text('${fmtMoney(app.cartTotal)} ${tr('currency')}',
                  style: const TextStyle(color: JC.gold, fontSize: 24, fontWeight: FontWeight.w900)),
            ]),
          ),
          GoldButton(label: tr('checkout'), icon: Icons.payments_outlined, onPressed: app.cart.isEmpty ? null : _checkout),
        ]),
      ),
    ]);
  }
}

class _CartTile extends StatelessWidget {
  final CartLine line;
  const _CartTile({required this.line});

  Future<void> _alts(BuildContext context) async {
    final id = line.product.id;
    if (id == null) return;
    final alts = await Db.altsOf(id);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('alternatives')} — ${line.product.name}', style: const TextStyle(color: JC.gold, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (alts.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('no_alts'), style: const TextStyle(color: JC.muted))),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final a in alts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.name, style: const TextStyle(color: JC.silver)),
                    subtitle: Text('${fmtMoney(a.price)} ${tr('currency')}', style: const TextStyle(color: JC.gold)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tr('replace_with'),
                        icon: const Icon(Icons.swap_horiz, color: JC.gold),
                        onPressed: () {
                          app.replaceLine(line, a);
                          Navigator.pop(c);
                        },
                      ),
                      IconButton(
                        tooltip: tr('add'),
                        icon: const Icon(Icons.add_circle_outline, color: JC.success),
                        onPressed: () {
                          app.addToCart(a);
                          Navigator.pop(c);
                        },
                      ),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = line.product;
    return JCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text('${fmtMoney(p.price)} × ${line.qty} = ${fmtMoney(line.subtotal)}', style: const TextStyle(color: JC.gold, fontSize: 13)),
            if (p.id != null)
              FutureBuilder<int>(
                future: Db.altCount(p.id!),
                builder: (c, s) => (s.data ?? 0) == 0
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: InkWell(
                          onTap: () => _alts(context),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.compare_arrows, color: JC.info, size: 16),
                            const SizedBox(width: 4),
                            Text('${tr('alternatives')} (${s.data})', style: const TextStyle(color: JC.info, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
              ),
          ]),
        ),
        _QtyBtn(icon: Icons.remove, onTap: () => app.setQty(line, line.qty - 1)),
        SizedBox(width: 30, child: Text('${line.qty}', textAlign: TextAlign.center, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w800, fontSize: 16))),
        _QtyBtn(icon: Icons.add, onTap: () => app.setQty(line, line.qty + 1)),
      ]),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: JC.surface3, borderRadius: BorderRadius.circular(10), border: Border.all(color: JC.borderHi)),
          child: Icon(icon, color: JC.gold, size: 20),
        ),
      );
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog();
  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  String _pay = 'Cash';
  final _disc = TextEditingController();
  bool _busy = false;

  double get _d => (double.tryParse(_disc.text.trim().replaceAll(',', '.')) ?? 0).clamp(0, app.cartTotal).toDouble();

  @override
  void dispose() {
    _disc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await Db.createSale(List.of(app.cart), _d, _pay, app.user);
    app.clearCart();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final methods = {'Cash': tr('cash'), 'Card': tr('card'), 'Wallet': tr('wallet')};
    return AlertDialog(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
      title: Text(tr('checkout'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('payment'), style: const TextStyle(color: JC.silverDim)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final e in methods.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _pay == e.key,
                selectedColor: JC.gold,
                backgroundColor: JC.surface3,
                labelStyle: TextStyle(color: _pay == e.key ? JC.onGold : JC.silver, fontWeight: FontWeight.bold),
                onSelected: (_) => setState(() => _pay = e.key),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _disc,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: JC.silver),
            decoration: InputDecoration(labelText: tr('discount')),
          ),
          const SizedBox(height: 14),
          Text('${tr('net')}: ${fmtMoney(app.cartTotal - _d)} ${tr('currency')}',
              style: const TextStyle(color: JC.gold, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
        GoldButton(label: tr('confirm'), icon: Icons.check, compact: true, onPressed: _busy ? null : _save),
      ],
    );
  }
}
