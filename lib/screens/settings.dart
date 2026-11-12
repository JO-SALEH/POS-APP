import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../importer.dart';
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
  final _url = TextEditingController();
  final _key = TextEditingController();
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
    _url.text = await Db.getSetting('server_url');
    _key.text = await Db.getSetting('pair_key');
    _dev.text = await Db.getSetting('device_name');
    _user.text = await Db.getSetting('username', 'admin');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_url, _key, _dev, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveServer() async {
    await Db.setSetting('server_url', _url.text.trim());
    await Db.setSetting('pair_key', _key.text.trim());
    if (_dev.text.trim().isNotEmpty) await Db.setSetting('device_name', _dev.text.trim());
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on SyncException catch (e) {
      if (mounted) toast(context, tr('sync_fail', [e.message]));
    } on ImportException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
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
      _section(tr('server'), [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: JC.silver),
          decoration: InputDecoration(labelText: tr('server'), hintText: tr('server_hint')),
        ),
        _gap(),
        TextField(controller: _key, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('pair_key'))),
        _gap(),
        TextField(controller: _dev, style: const TextStyle(color: JC.silver), decoration: InputDecoration(labelText: tr('device_name'))),
        _gap(),
        Row(children: [
          Expanded(child: GoldButton(label: tr('save'), compact: true, onPressed: () => _run(() async {
            await _saveServer();
            if (mounted) toast(context, tr('saved'));
          }))),
          const SizedBox(width: 8),
          Expanded(
            child: GhostButton(
              label: tr('test_conn'),
              icon: Icons.wifi_tethering,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await _saveServer();
                        final name = await SyncService.ping();
                        if (mounted) toast(context, tr('conn_ok', [name]));
                      }),
            ),
          ),
        ]),
        _gap(),
        SizedBox(
          width: double.infinity,
          child: GhostButton(
            label: tr('pull_products'),
            icon: Icons.download,
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await _saveServer();
                      final n = await SyncService.pullProducts();
                      if (mounted) toast(context, tr('import_ok', [n]));
                    }),
          ),
        ),
      ]),
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
                : () => _run(() async {
                      final rep = await Files.importProducts();
                      if (rep != null && mounted) await showImportReport(context, rep);
                    }),
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
