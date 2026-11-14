import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../lan.dart';
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
  List<Product> _top = [];
  int _held = 0;

  @override
  void initState() {
    super.initState();
    app.addListener(_onApp);
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final t = await Db.topSold();
    final h = await Db.heldList();
    if (mounted) setState(() {
      _top = t;
      _held = h.length;
    });
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
    // like the desktop: warn when something is sold with no (or not enough) stock
    final expired = [for (final l in app.cart) if (l.product.expired) l];
    if (expired.isNotEmpty) {
      final names = expired.map((l) => '• ${l.product.name}  (${tr('exp_expired', [l.product.expiry])})').join('\n');
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: JC.surface2,
          title: Text(tr('app'), style: const TextStyle(color: JC.danger, fontWeight: FontWeight.bold)),
          content: Text('${tr('expired_block')}\n\n$names', style: const TextStyle(color: JC.silver, height: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('ok')))],
        ),
      );
      return;
    }
    final short = [for (final l in app.cart) if (l.product.available != null && l.baseUnits > l.product.available!) l];
    if (short.isNotEmpty) {
      final names = short.map((l) => '• ${l.product.name}  (${tr('avail_of', [l.product.available!])})').join('\n');
      if (!await confirmDialog(context, '${tr('short_msg')}\n\n$names', tr('sell_anyway'), tr('cancel'), danger: true)) return;
    }
    if (!mounted) return;
    final receipt = await showDialog<String>(context: context, barrierDismissible: false, builder: (_) => const _CheckoutDialog());
    if (receipt != null && mounted) {
      _loadExtras();
      await showReceipt(context, receipt);
    }
  }

  Future<void> _holdDialog() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: JC.surface2,
        title: Text(tr('hold'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
        content: TextField(controller: c, autofocus: true, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('held_label'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
          GoldButton(label: tr('hold'), compact: true, onPressed: () => Navigator.pop(d, true)),
        ],
      ),
    );
    if (ok == true) {
      await app.holdCurrent(c.text);
      await _loadExtras();
      if (mounted) toast(context, tr('held_ok'));
    }
  }

  Future<void> _heldSheet() async {
    final list = await Db.heldList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('held_title'), style: const TextStyle(color: JC.gold, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('held_none'), style: const TextStyle(color: JC.muted))),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final h in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.pause_circle_outline, color: JC.gold),
                      title: Text('${h['label']}', style: const TextStyle(color: JC.silver)),
                      subtitle: Text('${h['created_at']}  ·  ${h['count']}', textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 12)),
                      onTap: () async {
                        await app.recall(h['id'] as int);
                        if (c.mounted) Navigator.pop(c);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: JC.danger),
                        onPressed: () async {
                          await Db.deleteHeld(h['id'] as int);
                          list.remove(h);
                          setS(() {});
                        },
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    await _loadExtras();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PageTitle(tr('nav_sell'), actions: [
        if (app.canUndo) IconButton(tooltip: tr('undo'), icon: const Icon(Icons.undo, color: JC.gold), onPressed: app.undo),
        if (app.cart.isNotEmpty) IconButton(tooltip: tr('hold'), icon: const Icon(Icons.pause_circle_outline, color: JC.gold), onPressed: _holdDialog),
        IconButton(
          tooltip: tr('held_title'),
          icon: Badge(isLabelVisible: _held > 0, label: Text('$_held'), child: const Icon(Icons.history, color: JC.gold)),
          onPressed: _heldSheet,
        ),
        if (app.cart.isNotEmpty)
          IconButton(
            tooltip: tr('clear_cart'),
            icon: const Icon(Icons.delete_sweep_outlined, color: JC.danger),
            onPressed: () async {
              if (await confirmDialog(context, tr('confirm_clear'), tr('confirm'), tr('cancel'), danger: true)) app.clearCart();
            },
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
                subtitle: Text(
                    [p.barcode, if (p.stock != null) tr('stock_of', [p.stock!]), if (p.expiry.isNotEmpty) (p.expired ? tr('exp_expired', [p.expiry]) : tr('exp_line', [p.expiry]))].join('  ·  '),
                    style: TextStyle(color: (p.stock ?? 1) <= 0 || p.expired ? JC.danger : ((p.daysToExpiry ?? 999) <= 90 ? JC.warn : JC.muted), fontSize: 11)),
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
      if (_results.isEmpty && _top.isNotEmpty)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            children: [
              Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: Center(child: Text(tr('fast_title'), style: const TextStyle(color: JC.muted, fontSize: 12)))),
              for (final p in _top)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ActionChip(
                    label: Text(p.name.length > 22 ? '${p.name.substring(0, 22)}…' : p.name),
                    labelStyle: const TextStyle(color: JC.silver, fontSize: 12),
                    backgroundColor: JC.surface3,
                    side: const BorderSide(color: JC.borderHi),
                    onPressed: () => app.addToCart(p),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: app.cart.isEmpty
            ? EmptyState(
                icon: Icons.shopping_cart_outlined,
                title: tr('cart_empty').split('\n').first,
                subtitle: tr('cart_empty').contains('\n') ? tr('cart_empty').split('\n').last : null)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: app.cart.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CartTile(line: app.cart[i]),
              ),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: JC.surface2.withOpacity(0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: JC.gold.withOpacity(0.45)),
          boxShadow: [BoxShadow(color: JC.gold.withOpacity(0.1), blurRadius: 18)],
        ),
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
            if (p.unitOptions.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, children: [
                  for (final u in p.unitOptions)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tr('unit_$u')),
                      selected: line.unit == u,
                      selectedColor: JC.gold,
                      backgroundColor: JC.surface3,
                      labelStyle: TextStyle(color: line.unit == u ? JC.onGold : JC.silver, fontSize: 12, fontWeight: FontWeight.bold),
                      onSelected: (_) => app.setUnit(line, u),
                    ),
                ]),
              ),
            const SizedBox(height: 4),
            Text('${fmtMoney(line.price)} × ${line.qty} = ${fmtMoney(line.subtotal)}', style: const TextStyle(color: JC.gold, fontSize: 13)),
            if (p.stock != null)
              Text(
                  [tr('stock_of', [p.stock!]), if (p.expiry.isNotEmpty) (p.expired ? tr('exp_expired', [p.expiry]) : tr('exp_line', [p.expiry]))].join('  ·  '),
                  style: TextStyle(
                      color: (p.available != null && line.baseUnits > p.available!) || p.expired ? JC.danger : ((p.daysToExpiry ?? 999) <= 90 ? JC.warn : JC.muted),
                      fontSize: 11,
                      fontWeight: (p.available != null && line.baseUnits > p.available!) || p.expired ? FontWeight.w800 : FontWeight.w400)),
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
  bool _pct = false;
  final _disc = TextEditingController();
  final _cust = TextEditingController();
  final _recv = TextEditingController();
  double _taxRate = 0;
  String? _err;
  bool _busy = false;
  double? _bal; // credit balance the PC reported for the typed customer
  List<({String name, String phone, double balance})> _sugg = [];

  Future<void> _custChanged(String v, {bool suggest = true}) async {
    final b = await Db.customerBalance(v);
    final s = suggest ? await Db.searchCustomers(v) : <({String name, String phone, double balance})>[];
    if (!mounted) return;
    setState(() {
      _bal = b;
      _sugg = s.where((c) => c.name.toLowerCase() != v.trim().toLowerCase()).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    Db.getSetting('tax_rate', '0').then((v) {
      final t = double.tryParse(v.replaceAll(',', '.')) ?? 0;
      if (mounted) setState(() => _taxRate = t.clamp(0, 100).toDouble());
    });
  }

  @override
  void dispose() {
    _disc.dispose();
    _cust.dispose();
    _recv.dispose();
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  double get _sub => app.cartTotal;
  double get _d {
    final v = _pct ? _sub * _num(_disc).clamp(0, 100) / 100 : _num(_disc).clamp(0, _sub);
    return double.parse(v.toDouble().toStringAsFixed(2));
  }

  double get _tax => double.parse(((_sub - _d) * _taxRate / 100).toStringAsFixed(2));
  double get _net => double.parse((_sub - _d + _tax).toStringAsFixed(2));

  Future<void> _save() async {
    if (_pay == 'Credit' && _cust.text.trim().isEmpty) return setState(() => _err = tr('credit_need_customer'));
    final recv = _pay == 'Cash' ? _num(_recv) : 0.0;
    if (_pay == 'Cash' && _recv.text.trim().isNotEmpty && recv + 0.0001 < _net) return setState(() => _err = tr('received_less'));
    setState(() => _busy = true);
    final no = await Db.createSale(List.of(app.cart), _d, _pay, app.user, customer: _cust.text, received: recv, tax: _tax);
    app.finishSale();
    Lan.afterSale(); // sends it to the PC right away when the PC is reachable
    if (mounted) Navigator.pop(context, no);
  }

  @override
  Widget build(BuildContext context) {
    final methods = {'Cash': tr('cash'), 'Card': tr('card'), 'Wallet': tr('wallet'), 'Credit': tr('pay_credit')};
    final recv = _num(_recv);
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
                onSelected: (_) => setState(() {
                  _pay = e.key;
                  _err = null;
                }),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _cust,
            style: const TextStyle(color: JC.silver),
            onChanged: (v) => _custChanged(v),
            decoration: InputDecoration(labelText: _pay == 'Credit' ? '${tr('customer')} *' : tr('customer'), helperText: _bal == null ? tr('customer_walkin') : tr('cust_balance', [fmtMoney(_bal!)])),
          ),
          if (_sugg.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (final c in _sugg)
                ActionChip(
                  label: Text(c.name, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _cust.text = c.name;
                    _custChanged(c.name, suggest: false);
                  },
                ),
            ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _disc,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: JC.silver),
                decoration: InputDecoration(labelText: tr('discount'), suffixText: _pct ? '%' : tr('currency')),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [ButtonSegment(value: false, label: Text(tr('currency'))), const ButtonSegment(value: true, label: Text('%'))],
              selected: {_pct},
              onSelectionChanged: (v) => setState(() => _pct = v.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? JC.gold : JC.surface3),
                foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? JC.onGold : JC.silver),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text('${tr('total')}: ${fmtMoney(_sub)}', style: const TextStyle(color: JC.silverDim)),
          if (_d > 0) Text('${tr('discount')}: -${fmtMoney(_d)}', style: const TextStyle(color: JC.warn)),
          if (_tax > 0) Text('${tr('tax')} (${fmtMoney(_taxRate)}%): ${fmtMoney(_tax)}', style: const TextStyle(color: JC.silverDim)),
          const SizedBox(height: 4),
          Text('${tr('net')}: ${fmtMoney(_net)} ${tr('currency')}', style: const TextStyle(color: JC.gold, fontSize: 22, fontWeight: FontWeight.w900)),
          if (_pay == 'Cash') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _recv,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _err = null),
              style: const TextStyle(color: JC.silver),
              decoration: InputDecoration(labelText: tr('received')),
            ),
            if (_recv.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  recv + 0.0001 >= _net ? '${tr('change')}: ${fmtMoney(recv - _net)} ${tr('currency')}' : '${tr('remaining')}: ${fmtMoney(_net - recv)} ${tr('currency')}',
                  style: TextStyle(color: recv + 0.0001 >= _net ? JC.success : JC.danger, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
          ],
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: JC.danger))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
        GoldButton(label: tr('confirm'), icon: Icons.check, compact: true, onPressed: _busy ? null : _save),
      ],
    );
  }
}

/// Receipt of a saved sale: lines, totals, and sharing as text (WhatsApp / print apps).
Future<void> showReceipt(BuildContext context, String receiptNo) async {
  final text = await Files.receiptText(receiptNo);
  if (text == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
      title: Row(children: [
        const Icon(Icons.check_circle, color: JC.success),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('sale_saved'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold))),
      ]),
      content: SingleChildScrollView(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(text, style: const TextStyle(color: JC.silver, fontFamily: 'monospace', fontSize: 12, height: 1.4)),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Files.shareText(text),
          icon: const Icon(Icons.ios_share, color: JC.gold, size: 18),
          label: Text(tr('share_receipt'), style: const TextStyle(color: JC.gold)),
        ),
        GoldButton(label: tr('new_sale'), compact: true, onPressed: () => Navigator.pop(c)),
      ],
    ),
  );
}
