import 'package:flutter/material.dart';
import '../i18n.dart';
import '../services.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController(text: 'admin');
  final _p = TextEditingController();
  bool _remember = true;
  bool _hide = true;
  String? _err;
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final ok = await app.login(_u.text, _p.text, _remember);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = ok ? null : tr('bad_login');
    });
  }

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.7), radius: 1.2, colors: [Color(0xFF1A1508), JC.bg]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => app.setLang(L.ar ? 'en' : 'ar'),
                      icon: const Icon(Icons.language, color: JC.gold, size: 18),
                      label: Text(L.ar ? 'English' : 'العربية', style: const TextStyle(color: JC.gold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const JoLogo(size: 52),
                  const SizedBox(height: 18),
                  Text(tr('app'), style: const TextStyle(color: JC.gold, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(tr('tagline'), style: const TextStyle(color: JC.silverDim)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _u,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: JC.silver),
                    decoration: InputDecoration(labelText: tr('username'), prefixIcon: const Icon(Icons.person_outline, color: JC.gold)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _p,
                    obscureText: _hide,
                    onSubmitted: (_) => _go(),
                    style: const TextStyle(color: JC.silver),
                    decoration: InputDecoration(
                      labelText: tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline, color: JC.gold),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_off : Icons.visibility, color: JC.muted),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('remember'), style: const TextStyle(color: JC.silverDim)),
                  ),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_err!, style: const TextStyle(color: JC.danger)),
                    ),
                  SizedBox(width: double.infinity, child: GoldButton(label: tr('login'), icon: Icons.login, onPressed: _busy ? null : _go)),
                  const SizedBox(height: 18),
                  Text(tr('default_hint'), style: const TextStyle(color: JC.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(tr('free_note'), style: const TextStyle(color: JC.goldDark, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
