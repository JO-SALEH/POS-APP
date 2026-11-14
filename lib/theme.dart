import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'i18n.dart';

/// Same palette as JO PHARMA desktop (Vanta black + metallic gold).
class JC {
  static const bg = Color(0xFF050505);
  static const surface = Color(0xFF0B0B0B);
  static const surface2 = Color(0xFF111111);
  static const surface3 = Color(0xFF191919);
  static const border = Color(0xFF202020);
  static const borderHi = Color(0xFF34302A);
  static const gold = Color(0xFFD4AF62);
  static const goldHi = Color(0xFFF4D58D);
  static const goldDark = Color(0xFF98752F);
  static const onGold = Color(0xFF080705);
  static const silver = Color(0xFFF5F5F5);
  static const silverDim = Color(0xFFC8C8C8);
  static const muted = Color(0xFF858585);
  static const danger = Color(0xFFD95757);
  static const success = Color(0xFF25A878);
  static const warn = Color(0xFFE8B13A);
  static const info = Color(0xFF7FB2E5);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: JC.gold,
    onPrimary: JC.onGold,
    secondary: JC.goldHi,
    surface: JC.surface,
    onSurface: JC.silver,
    error: JC.danger,
  );
  OutlineInputBorder ob(Color c, [double w = 1.2]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: JC.surface,
    dividerColor: JC.border,
    dialogTheme: DialogTheme(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: JC.borderHi)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          backgroundColor: JC.gold,
          foregroundColor: JC.onGold,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
          backgroundColor: JC.gold,
          foregroundColor: JC.onGold,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: JC.surface2.withOpacity(0.85),
      side: const BorderSide(color: JC.borderHi),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: JC.gold,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: JC.gold, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JC.surface2.withOpacity(0.92),
      labelStyle: const TextStyle(color: JC.silverDim),
      hintStyle: const TextStyle(color: JC.muted),
      border: ob(JC.border),
      enabledBorder: ob(JC.border),
      focusedBorder: ob(JC.gold, 1.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: JC.surface2,
      indicatorColor: JC.gold.withOpacity(0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? JC.gold : JC.muted,
          fontWeight: FontWeight.w600)),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? JC.gold : JC.muted)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: JC.surface3,
      contentTextStyle: const TextStyle(color: JC.silver),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: JC.gold)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? JC.gold : JC.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? JC.goldDark : JC.surface3),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? JC.gold : Colors.transparent),
      checkColor: WidgetStateProperty.all(JC.onGold),
      side: const BorderSide(color: JC.muted),
    ),
  );
}

/// Dark rounded card used everywhere (avoids CardTheme API differences between Flutter versions).
class JCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  const JCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.borderColor, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: JC.surface2.withOpacity(0.9),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), side: BorderSide(color: borderColor ?? JC.borderHi.withOpacity(0.8))),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Gold gradient button (primary action).
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool compact;
  const GoldButton({super.key, required this.label, this.icon, this.onPressed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Opacity(
      opacity: on ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [JC.goldHi, JC.gold, JC.goldDark]),
              border: Border.all(color: JC.goldHi.withOpacity(0.7)),
              boxShadow: [BoxShadow(color: JC.gold.withOpacity(on ? 0.28 : 0), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 10 : 14),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[Icon(icon, color: JC.onGold, size: 20), const SizedBox(width: 8)],
              Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: JC.onGold, fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary button.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color;
  const GhostButton({super.key, required this.label, this.icon, this.onPressed, this.color = JC.gold});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.7), width: 1.3),
          backgroundColor: JC.surface2.withOpacity(0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}

/// The official JØ PHARMA emblem (same artwork as the desktop program).
class JoLogo extends StatelessWidget {
  final double size;
  const JoLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final d = size * 1.6;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: JC.gold.withOpacity(0.25), blurRadius: 24)]),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          width: d,
          height: d,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: JC.surface3,
            alignment: Alignment.center,
            child: Text('JØ', style: TextStyle(fontSize: size * 0.7, fontWeight: FontWeight.w900, color: JC.gold)),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String message, String okLabel, String cancelLabel,
    {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: const BorderSide(color: JC.borderHi)),
      content: Text(message, style: const TextStyle(color: JC.silver, fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancelLabel, style: const TextStyle(color: JC.muted))),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(okLabel, style: TextStyle(color: danger ? JC.danger : JC.gold, fontWeight: FontWeight.bold))),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(msg), duration: Duration(seconds: msg.length > 60 ? 7 : 2)));
}


/// The wavy black-and-gold background, behind every screen.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: JC.bg),
        Image.asset('assets/bg.jpg', fit: BoxFit.cover, alignment: Alignment.center, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        child,
      ]);
}

/// Gold-gradient glyph on a glowing round plate: the "nothing here yet" picture of every screen.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [JC.gold.withOpacity(0.16), Colors.transparent]),
                border: Border.all(color: JC.gold.withOpacity(0.35)),
                boxShadow: [BoxShadow(color: JC.gold.withOpacity(0.22), blurRadius: 36)],
              ),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [JC.goldHi, JC.goldDark]).createShader(r),
                child: Icon(icon, size: 68, color: Colors.white),
              ),
            ),
            const SizedBox(height: 22),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 1, color: JC.gold.withOpacity(0.5)),
              const SizedBox(width: 12),
              Flexible(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: JC.gold, fontSize: 22, fontWeight: FontWeight.w800))),
              const SizedBox(width: 12),
              Container(width: 36, height: 1, color: JC.gold.withOpacity(0.5)),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: JC.silverDim, fontSize: 16, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ]),
        ),
      );
}

const _siteUrl = 'https://www.jo-royalty.vip';

/// "Full experience on the PC" + "Developed by JØ ROYALTY" (opens the website).
class BrandFooter extends StatelessWidget {
  const BrandFooter({super.key});

  Future<void> _open(BuildContext context) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(_siteUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) toast(context, 'www.jo-royalty.vip');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JC.surface2.withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JC.gold.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.desktop_windows_outlined, color: JC.gold, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(tr('footer_pc'), textAlign: TextAlign.center, style: const TextStyle(color: JC.silverDim, fontSize: 12.5, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text.rich(
                TextSpan(style: const TextStyle(color: JC.muted, fontSize: 12), children: [
                  TextSpan(text: '${tr('developed_by')} '),
                  const TextSpan(
                      text: 'JØ ROYALTY',
                      style: TextStyle(color: JC.gold, fontWeight: FontWeight.w800, letterSpacing: 0.6, decoration: TextDecoration.underline, decorationColor: JC.goldDark)),
                ]),
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ]),
      );
}
