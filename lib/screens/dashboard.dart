import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../services.dart';
import '../theme.dart';
import 'home.dart';

/// Manager's day view: sales, payment split, best sellers, low stock and the cashier shift.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DayReport? _r;
  List<Product> _low = [];
  int _stockKnown = 0;
  List<Product> _exp = [];
  int _expDays = 90;
  int _lowAt = 5;
  Map<String, Object?>? _shift;
  double _expected = 0;
  List<Map<String, Object?>> _past = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = DateTime.now();
    final r = await Db.report(day: '${n.year}-${two(n.month)}-${two(n.day)}');
    final at = int.tryParse(await Db.getSetting('low_stock', '5')) ?? 5;
    final low = await Db.lowStock(threshold: at);
    final known = await Db.stockKnownCount();
    final expDays = int.tryParse(await Db.getSetting('expiry_days', '90')) ?? 90;
    final expList = await Db.expiringSoon(days: expDays);
    final sh = await Db.openShift();
    final exp = sh == null ? 0.0 : await Db.expectedCash(sh);
    final past = await Db.lastShifts();
    if (!mounted) return;
    setState(() {
      _r = r;
      _low = low;
      _lowAt = at;
      _stockKnown = known;
      _exp = expList;
      _expDays = expDays;
      _shift = sh;
      _expected = exp;
      _past = past;
    });
  }

  Future<double?> _askAmount(String title, String label) async {
    final c = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: JC.surface2,
        title: Text(title, style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: JC.silver),
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
          GoldButton(
            label: tr('confirm'),
            compact: true,
            onPressed: () {
              final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
              Navigator.pop(d, v ?? (c.text.trim().isEmpty ? 0.0 : null));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openShift() async {
    final v = await _askAmount(tr('shift_open'), tr('shift_opening'));
    if (v == null) return;
    await Db.startShift(v < 0 ? 0 : v, app.user);
    _load();
  }

  Future<void> _closeShift() async {
    final sh = _shift;
    if (sh == null) return;
    final v = await _askAmount(tr('shift_close'), tr('shift_counted'));
    if (v == null) return;
    final diff = await Db.closeShift(sh['id'] as int, v);
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: JC.surface2,
          title: Text(tr('shift_closed'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
          content: Text(
            '${tr('shift_expected')}: ${fmtMoney(_expected)}\n${tr('shift_counted')}: ${fmtMoney(v)}\n${tr('shift_diff')}: ${diff >= 0 ? '+' : ''}${fmtMoney(diff)}',
            style: TextStyle(color: diff.abs() < 0.005 ? JC.success : JC.warn, fontSize: 16, height: 1.6, fontWeight: FontWeight.w700),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('ok'), style: const TextStyle(color: JC.gold)))],
        ),
      );
    }
    _load();
  }

  Widget _stat(String label, String value, {Color color = JC.gold}) => Expanded(
        child: JCard(
          child: Column(children: [
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: JC.muted, fontSize: 11)),
          ]),
        ),
      );

  Widget _box(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: JCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _kv(String k, String v, {Color c = JC.silver}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: JC.silverDim))),
          Text(v, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
        ]),
      );

  String _payName(String k) => switch (k) {
        'Cash' => tr('cash'),
        'Card' => tr('card'),
        'Wallet' => tr('wallet'),
        'Credit' => tr('pay_credit'),
        _ => k,
      };

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return RefreshIndicator(
      color: JC.gold,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
        PageTitle(tr('nav_today')),
        if (r == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: JC.gold)))
        else ...[
          Row(children: [
            _stat('${tr('net_sales')} (${tr('currency')})', fmtMoney(r.net)),
            const SizedBox(width: 8),
            _stat(tr('sales_count'), '${r.count}', color: JC.silver),
            const SizedBox(width: 8),
            _stat(tr('returns_label'), fmtMoney(r.returns), color: r.returns > 0 ? JC.warn : JC.silver),
          ]),
          const SizedBox(height: 12),
          _box(tr('shift_title'), [
            if (_shift == null) ...[
              Text(tr('shift_none'), style: const TextStyle(color: JC.muted)),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: GoldButton(label: tr('shift_open'), icon: Icons.lock_open, onPressed: _openShift)),
            ] else ...[
              _kv(tr('shift_since'), '${_shift!['opened_at']}'),
              _kv(tr('shift_opening'), fmtMoney(_shift!['opening'] as num)),
              _kv(tr('shift_expected'), fmtMoney(_expected), c: JC.gold),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: GoldButton(label: tr('shift_close'), icon: Icons.lock_outline, onPressed: _closeShift)),
            ],
            if (_past.isNotEmpty) ...[
              const Divider(height: 22),
              for (final p in _past)
                _kv('${p['closed_at']}'.substring(0, 16), '${fmtMoney((p['counted'] as num) - (p['expected'] as num))}',
                    c: ((p['counted'] as num) - (p['expected'] as num)).abs() < 0.005 ? JC.success : JC.warn),
            ],
          ]),
          if (r.byPayment.isNotEmpty)
            _box(tr('by_payment'), [for (final e in r.byPayment.entries) _kv(_payName(e.key), fmtMoney(e.value))]),
          if (r.top.isNotEmpty)
            _box(tr('top_today'), [for (final t in r.top) _kv(t.name, '${t.qty}  ·  ${fmtMoney(t.total)}')]),
          _box('${tr('low_stock_title')} (≤ $_lowAt)', [
            if (_stockKnown == 0)
              Text(tr('stock_not_synced'), style: const TextStyle(color: JC.muted, height: 1.5))
            else if (_low.isEmpty)
              Text(tr('low_none'), style: const TextStyle(color: JC.success))
            else
              for (final p in _low.take(30)) _kv(p.name, '${p.stock}', c: (p.stock ?? 0) <= 0 ? JC.danger : JC.warn),
          ]),
          if (_stockKnown > 0)
            _box('${tr('expiring_title')} (≤ $_expDays)', [
              if (_exp.isEmpty)
                Text(tr('expiring_none'), style: const TextStyle(color: JC.success))
              else
                for (final p in _exp.take(30)) _kv(p.name, p.expiry, c: (p.daysToExpiry ?? 0) < 0 ? JC.danger : JC.warn),
            ]),
        ],
      ]),
    );
  }
}
