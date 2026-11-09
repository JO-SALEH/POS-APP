import 'package:flutter/material.dart';

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
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: JC.bg,
    canvasColor: JC.surface,
    dividerColor: JC.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: JC.surface,
      foregroundColor: JC.gold,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: JC.gold, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JC.surface3,
      labelStyle: const TextStyle(color: JC.silverDim),
      hintStyle: const TextStyle(color: JC.muted),
      border: ob(JC.border),
      enabledBorder: ob(JC.border),
      focusedBorder: ob(JC.gold, 1.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: JC.surface,
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
        color: JC.surface2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderColor ?? JC.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
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
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [JC.goldHi, JC.gold, JC.goldDark]),
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
          side: BorderSide(color: color.withOpacity(0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}

/// "JØ" brand mark.
class JoLogo extends StatelessWidget {
  final double size;
  const JoLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Container(
        width: size * 1.6,
        height: size * 1.6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: JC.gold, width: 2),
          gradient: const RadialGradient(colors: [JC.surface3, JC.bg]),
          boxShadow: [BoxShadow(color: JC.gold.withOpacity(0.25), blurRadius: 24)],
        ),
        alignment: Alignment.center,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [JC.goldHi, JC.gold, JC.goldDark]).createShader(r),
          child: Text('JØ',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: size * 0.7, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      );
}

Future<bool> confirmDialog(BuildContext context, String message, String okLabel, String cancelLabel,
    {bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
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
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}
