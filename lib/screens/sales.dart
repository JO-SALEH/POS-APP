import 'dart:async';
import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../lan.dart';
import '../services.dart';
import '../theme.dart';
import 'home.dart';
import 'sell.dart' show showReceipt;

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<SaleHeader> _sales = [];
  int _unsynced = 0;
  int _todayCount = 0;
  double _todayTotal = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Lan.status.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Lan.status.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Db.recentSales();
    final u = await Db.unsyncedCount();
    final t = await Db.todayStats();
    if (!mounted) return;
    setState(() {
      _sales = s;
      _unsynced = u;
      _todayCount = t.count;
      _todayTotal = t.total;
    });
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await Lan.push();
      if (mounted) toast(context, r.total == 0 ? tr('lan_all_sent') : tr('lan_sent', [r.booked, r.duplicates, r.unmatched, r.failed]));
    } on LanException catch (e) {
      if (mounted) toast(context, e.message);
    }
    unawaited(Lan.tick());
    if (mounted) setState(() => _busy = false);
    _load();
  }

  Future<void> _detail(SaleHeader s) async {
    final items = await Db.itemsOf(s.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('invoice')} ${s.receiptNo}', textDirection: TextDirection.ltr, style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${s.createdAt}  ·  ${s.payment}', textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 12)),
            const Divider(height: 20),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text('${i['name']}${'${i['unit']}' == 'pack' ? '' : '  (${tr('unit_${i['unit']}')})'}', style: const TextStyle(color: JC.silver))),
                      Text('${fmtMoney(i['price'] as num)} × ${i['qty']}  =  ${fmtMoney(i['subtotal'] as num)}', style: const TextStyle(color: JC.silverDim, fontSize: 13)),
                    ]),
                  ),
              ]),
            ),
            const Divider(height: 20),
            if (s.note.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s.note, style: const TextStyle(color: JC.warn, fontSize: 13, height: 1.4))),
            if (s.discount > 0) Text('${tr('discount')}: ${fmtMoney(s.discount)}', style: const TextStyle(color: JC.warn)),
            if (s.customer.isNotEmpty) Text('${tr('customer')}: ${s.customer}', style: const TextStyle(color: JC.silverDim)),
            Text('${tr('net')}: ${fmtMoney(s.net)} ${tr('currency')}', style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GhostButton(
                  label: tr('receipt'),
                  icon: Icons.receipt_long_outlined,
                  onPressed: () {
                    Navigator.pop(c);
                    showReceipt(context, s.receiptNo);
                  },
                ),
              ),
              if (app.isManager) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: tr('return_btn'),
                    icon: Icons.assignment_return_outlined,
                    color: JC.warn,
                    onPressed: () {
                      Navigator.pop(c);
                      _return(s);
                    },
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _return(SaleHeader s) async {
    final items = await Db.returnable(s.id);
    if (!mounted) return;
    final qty = <int, int>{for (final i in items) i.itemId: 0};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) {
          var total = 0.0;
          for (final i in items) {
            total += i.price * (qty[i.itemId] ?? 0);
          }
          return AlertDialog(
            backgroundColor: JC.surface2,
            title: Text('${tr('return_btn')} — ${s.receiptNo}', textDirection: TextDirection.ltr, style: const TextStyle(color: JC.warn, fontSize: 15, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final i in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.name, style: const TextStyle(color: JC.silver, fontSize: 14)),
                          Text('${tr('sold_returned', [i.qty, i.returned])}', style: const TextStyle(color: JC.muted, fontSize: 11)),
                        ]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: JC.gold),
                        onPressed: (qty[i.itemId] ?? 0) > 0 ? () => setS(() => qty[i.itemId] = qty[i.itemId]! - 1) : null,
                      ),
                      Text('${qty[i.itemId]}', style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: JC.gold),
                        onPressed: (qty[i.itemId] ?? 0) < i.qty - i.returned ? () => setS(() => qty[i.itemId] = qty[i.itemId]! + 1) : null,
                      ),
                    ]),
                  ),
                const Divider(),
                Text('${tr('refund')}: ${fmtMoney(total)} ${tr('currency')}', style: const TextStyle(color: JC.warn, fontWeight: FontWeight.w900, fontSize: 18)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
              GoldButton(label: tr('confirm'), compact: true, onPressed: total > 0 ? () => Navigator.pop(d, true) : null),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      final no = await Db.createReturn(s.id, qty, app.user);
      if (mounted && no != null) toast(context, tr('return_done', [no]));
      _load();
    }
  }

  Widget _stat(String label, String value, {Color color = JC.gold}) => Expanded(
        child: JCard(
          child: Column(children: [
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: JC.muted, fontSize: 11)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      PageTitle(tr('nav_sales'), actions: [
        if (app.isManager) PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: JC.gold),
          color: JC.surface3,
          onSelected: (v) async {
            if (v == 'mark' && await confirmDialog(context, tr('mark_synced'), tr('confirm'), tr('cancel'))) {
              await Db.markAllSynced();
              _load();
            }
          },
          itemBuilder: (_) => [PopupMenuItem(value: 'mark', child: Text(tr('mark_synced'), style: const TextStyle(color: JC.silver)))],
        ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          _stat('${tr('today')} (${tr('currency')})', fmtMoney(_todayTotal)),
          const SizedBox(width: 8),
          _stat(tr('sales_count'), '$_todayCount', color: JC.silver),
          const SizedBox(width: 8),
          _stat(tr('unsynced'), '$_unsynced', color: _unsynced > 0 ? JC.warn : JC.success),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(children: [
          SizedBox(width: double.infinity, child: GoldButton(label: tr('sync_wifi'), icon: Icons.wifi, onPressed: _busy ? null : _sync)),
          const SizedBox(height: 8),
          if (app.isManager)
            Row(children: [
              Expanded(child: GhostButton(label: tr('export_json'), icon: Icons.data_object, onPressed: () => Files.shareJson())),
              const SizedBox(width: 8),
              Expanded(child: GhostButton(label: tr('export_csv'), icon: Icons.table_chart_outlined, onPressed: () => Files.shareCsv())),
            ]),
        ]),
      ),
      if (_busy) const LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3),
      Expanded(
        child: _sales.isEmpty
            ? EmptyState(icon: Icons.receipt_long_outlined, title: tr('no_sales'))
            : RefreshIndicator(
                color: JC.gold,
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: _sales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _sales[i];
                    return JCard(
                      onTap: () => _detail(s),
                      child: Row(children: [
                        Icon(s.synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: s.synced ? JC.success : JC.warn, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.receiptNo, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(s.createdAt, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 11)),
                            if (s.note.isNotEmpty) Text(s.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JC.warn, fontSize: 11)),
                          ]),
                        ),
                        Text('${fmtMoney(s.net)} ${tr('currency')}', style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w900)),
                      ]),
                    );
                  },
                ),
              ),
      ),
    ]);
  }
}
