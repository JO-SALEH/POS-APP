import 'dart:async';
import 'package:flutter/material.dart';
import 'scan.dart';
import '../db.dart';
import '../i18n.dart';
import '../importer.dart';
import '../lan.dart';
import 'import_flow.dart';
import 'import_report.dart';
import '../services.dart';
import '../theme.dart';
import 'home.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dev = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _dev.text = await Db.getSetting('device_name');
    _user.text = await Db.getSetting('username', 'admin');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_dev, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on LanException catch (e) {
      if (mounted) toast(context, e.message);
    } on ImportException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
  }


  // ------------------------------------------------------------- PC link
  Future<void> _scanQr() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code == null || !mounted) return;
    final p = Pairing.parseQr(code);
    if (p == null) return toast(context, tr('lan_not_qr'));
    await _run(() async {
      final name = await Lan.pair(p);
      if (mounted) toast(context, tr('lan_paired_ok', [name]));
      unawaited(Lan.tick());
    });
  }

  Future<void> _manual() async {
    final addr = TextEditingController();
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: JC.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
        title: Text(tr('lan_manual'), style: const TextStyle(color: JC.gold, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: addr, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('lan_address'))),
          const SizedBox(height: 10),
          TextField(controller: code, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('lan_code'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'), style: const TextStyle(color: JC.muted))),
          GoldButton(label: tr('lan_connect'), compact: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    final a = addr.text, t = code.text;
    addr.dispose();
    code.dispose();
    if (ok != true || !mounted) return;
    final p = Pairing.parseManual(a, t);
    if (p == null) return toast(context, tr('lan_bad_input'));
    await _run(() async {
      final name = await Lan.pair(p);
      if (mounted) toast(context, tr('lan_paired_ok', [name]));
      unawaited(Lan.tick());
    });
  }

  Future<void> _sendNow() => _run(() async {
        final r = await Lan.push();
        if (!mounted) return;
        toast(context, r.total == 0 ? tr('lan_all_sent') : tr('lan_sent', [r.booked, r.duplicates, r.unmatched, r.failed]));
        await Lan.tick();
      });

  Future<void> _pullProducts() => _run(() async {
        final p = await Lan.load();
        if (p == null) throw LanException(tr('lan_not_paired'));
        final rep = await Lan.pullCatalog(force: true);
        if (mounted && rep != null) await showImportReport(context, rep);
      });

  Future<void> _find() => _run(() async {
        final p = await Lan.load();
        if (p == null) throw LanException(tr('lan_not_paired'));
        final np = await Lan.findDesktop(p);
        if (!mounted) return;
        toast(context, np == null ? tr('lan_not_found') : tr('lan_found', ['${np.ip}:${np.port}']));
        await Lan.tick();
      });

  Future<void> _test() => _run(() async {
        final p = await Lan.load();
        if (p == null) throw LanException(tr('lan_not_paired'));
        final name = await Lan.ping(p);
        if (mounted) toast(context, tr('conn_ok', [name]));
        await Lan.tick();
      });

  Widget _lanSection() {
    return ValueListenableBuilder<LanStatus>(
      valueListenable: Lan.status,
      builder: (context, st, _) {
        final String line;
        final Color color;
        if (!st.paired) {
          line = tr('lan_none');
          color = JC.muted;
        } else if (st.busy) {
          line = tr('lan_syncing');
          color = JC.gold;
        } else if (st.online) {
          line = tr('lan_connected', [st.name ?? 'JO PHARMA']);
          color = JC.success;
        } else {
          line = tr('lan_offline');
          color = JC.warn;
        }
        return _section(tr('lan_title'), [
          Row(children: [
            Icon(st.online ? Icons.wifi : Icons.wifi_off, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(line, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
          ]),
          if (st.paired)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(st.unsynced > 0 ? tr('lan_waiting', [st.unsynced]) : tr('lan_all_sent'),
                  style: TextStyle(color: st.unsynced > 0 ? JC.warn : JC.silverDim, fontSize: 13)),
            ),
          if (st.paired && !st.online && st.error != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(st.error!, style: const TextStyle(color: JC.muted, fontSize: 12, height: 1.4))),
          if (!st.paired) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('lan_help'), style: const TextStyle(color: JC.muted, fontSize: 12, height: 1.5))),
          _gap(),
          SizedBox(width: double.infinity, child: GoldButton(label: tr('lan_scan'), icon: Icons.qr_code_scanner, onPressed: _busy ? null : _scanQr)),
          _gap(),
          SizedBox(width: double.infinity, child: GhostButton(label: tr('lan_manual'), icon: Icons.keyboard, onPressed: _busy ? null : _manual)),
          if (st.paired) ...[
            _gap(),
            Row(children: [
              Expanded(child: GhostButton(label: tr('lan_send_now'), icon: Icons.cloud_upload_outlined, onPressed: _busy ? null : _sendNow)),
              const SizedBox(width: 8),
              Expanded(child: GhostButton(label: tr('lan_test'), icon: Icons.wifi_tethering, onPressed: _busy ? null : _test)),
            ]),
            _gap(),
            SizedBox(width: double.infinity, child: GhostButton(label: tr('lan_get_products'), icon: Icons.download, onPressed: _busy ? null : _pullProducts)),
            _gap(),
            SizedBox(width: double.infinity, child: GhostButton(label: tr('lan_find'), icon: Icons.search, onPressed: _busy ? null : _find)),
            _gap(),
            SizedBox(
              width: double.infinity,
              child: GhostButton(
                label: tr('lan_unpair'),
                icon: Icons.link_off,
                color: JC.danger,
                onPressed: _busy
                    ? null
                    : () async {
                        if (await confirmDialog(context, tr('lan_unpair'), tr('confirm'), tr('cancel'), danger: true)) await Lan.unpair();
                      },
              ),
            ),
          ],
          _gap(),
          TextField(controller: _dev, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('device_name'))),
          _gap(),
          SizedBox(
            width: double.infinity,
            child: GhostButton(
              label: tr('save'),
              onPressed: () async {
                if (_dev.text.trim().isNotEmpty) await Db.setSetting('device_name', _dev.text.trim());
                if (mounted) toast(context, tr('lan_device_saved'));
              },
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _saveAccount() async {
    if (_user.text.trim().isEmpty) return toast(context, tr('required'));
    await Db.setSetting('username', _user.text.trim());
    if (_pass.text.isNotEmpty) await Db.setSetting('pw_hash', hashPassword(_pass.text));
    app.user = _user.text.trim();
    _pass.clear();
    if (mounted) toast(context, tr('saved'));
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: JCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: JC.gold, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _gap() => const SizedBox(height: 10);

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
      PageTitle(tr('nav_settings')),
      if (_busy) const LinearProgressIndicator(color: JC.gold, backgroundColor: JC.surface3),
      _section(tr('language'), [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'ar', label: Text('العربية')), ButtonSegment(value: 'en', label: Text('English'))],
          selected: {app.lang},
          onSelectionChanged: (s) => app.setLang(s.first),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? JC.gold : JC.surface3),
            foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? JC.onGold : JC.silver),
          ),
        ),
      ]),
      _lanSection(),
      _section(tr('import_file'), [
        Text(tr('import_hint'), style: const TextStyle(color: JC.muted, fontSize: 12, height: 1.5)),
        _gap(),
        SizedBox(
          width: double.infinity,
          child: GhostButton(
            label: tr('import_file'),
            icon: Icons.upload_file,
            onPressed: _busy
                ? null
                : () => startImport(context),
          ),
        ),
        _gap(),
        SizedBox(width: double.infinity, child: GhostButton(label: tr('export_db'), icon: Icons.backup_outlined, onPressed: () => Files.shareDb())),
      ]),
      _section(tr('account'), [
        TextField(controller: _user, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('new_username'))),
        _gap(),
        TextField(controller: _pass, obscureText: true, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('new_password'))),
        _gap(),
        Row(children: [
          Expanded(child: GoldButton(label: tr('save'), compact: true, onPressed: _saveAccount)),
          const SizedBox(width: 8),
          Expanded(child: GhostButton(label: tr('logout'), icon: Icons.logout, color: JC.danger, onPressed: () => app.logout())),
        ]),
      ]),
      _section(tr('about'), [
        Row(children: [
          const JoLogo(size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('about_text'), style: const TextStyle(color: JC.silverDim, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        Text('${tr('free_note')}  ·  v1.0.0', style: const TextStyle(color: JC.goldDark, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ]);
  }
}
