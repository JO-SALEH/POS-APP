import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../i18n.dart';
import '../lan.dart';
import '../orders.dart';
import '../theme.dart';

/// Purchase orders sent from the PC: the list, open / share / save the PDF, delete.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Orders.screenOpen = true;
    unawaited(Orders.load());
  }

  @override
  void dispose() {
    Orders.screenOpen = false;
    unawaited(Orders.markAllSeen()); // "NEW" disappears only after the screen was left
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      await Lan.tick();
      await Orders.poll();
    } catch (e) {
      if (mounted) toast(context, e is LanException ? e.message : '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _share(PcOrder o) async {
    try {
      if (!await File(o.file).exists()) return toast(context, tr('orders_missing'));
      await Share.shareXFiles([XFile(o.file, mimeType: 'application/pdf')], subject: o.title);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _save(PcOrder o) async {
    try {
      final f = File(o.file);
      if (!await f.exists()) return toast(context, tr('orders_missing'));
      final bytes = await f.readAsBytes();
      final name = 'PO_${o.createdAt.replaceAll(RegExp(r'[^0-9]'), '').padRight(12, '0').substring(0, 12)}.pdf';
      final path = await FilePicker.platform.saveFile(dialogTitle: tr('orders_save'), fileName: name, bytes: bytes);
      if (path != null && mounted) toast(context, tr('orders_saved'));
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _delete(PcOrder o) async {
    if (await confirmDialog(context, tr('orders_delete_q'), tr('delete'), tr('cancel'), danger: true)) await Orders.delete(o);
  }

  String _size(int b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  Widget _card(PcOrder o) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: JCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!o.seen)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: JC.gold, borderRadius: BorderRadius.circular(10)),
                  child: Text(tr('orders_new'), style: const TextStyle(color: JC.onGold, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              Expanded(child: Text(o.title.isEmpty ? tr('orders_title') : o.title, style: const TextStyle(color: JC.silver, fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 6),
            Text('${o.createdAt}  ·  ${tr('orders_items', [o.items])}  ·  ${_size(o.size)}  ·  ${o.prices ? tr('orders_with_prices') : tr('orders_no_prices')}',
                style: const TextStyle(color: JC.silverDim, fontSize: 12, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GoldButton(label: tr('orders_open'), icon: Icons.picture_as_pdf, compact: true, onPressed: () => _share(o))),
              const SizedBox(width: 8),
              Expanded(child: GhostButton(label: tr('orders_save'), icon: Icons.download, onPressed: () => _save(o))),
              IconButton(onPressed: () => _delete(o), icon: const Icon(Icons.delete_outline, color: JC.danger)),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(tr('orders_title'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: _busy ? null : _check, icon: const Icon(Icons.refresh, color: JC.gold), tooltip: tr('orders_check'))],
      ),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3),
        Expanded(
          child: ValueListenableBuilder<List<PcOrder>>(
            valueListenable: Orders.list,
            builder: (context, rows, _) => rows.isEmpty
                ? EmptyState(icon: Icons.assignment_outlined, title: tr('orders_empty'), subtitle: tr('orders_empty_hint'))
                : ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [for (final o in rows) _card(o)]),
          ),
        ),
      ]),
    );
  }
}
