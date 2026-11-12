/// Barcode normalisation shared by import, scan, search and manual entry.
/// Mirrors the desktop app (norm_code): the same physical barcode always becomes the same text.
class Codes {
  static const _junk = {'NULL', 'NONE', 'NAN', 'N/A', 'NA', '-', '--', '0'};

  /// Arabic-Indic (٠-٩) and Persian (۰-۹) digits -> 0-9.
  static String latinDigits(String s) {
    final sb = StringBuffer();
    for (final u in s.runes) {
      if (u >= 0x0660 && u <= 0x0669) {
        sb.writeCharCode(0x30 + u - 0x0660);
      } else if (u >= 0x06F0 && u <= 0x06F9) {
        sb.writeCharCode(0x30 + u - 0x06F0);
      } else {
        sb.writeCharCode(u);
      }
    }
    return sb.toString();
  }

  static final _hidden = RegExp('[\\s ​-‏‪-‮⁠﻿\u0000-\u001F\u007F\'"`´‘’“”]');
  static final _scannerPrefix = RegExp(r'^\][A-Za-z][0-9A-Za-z]');

  /// Canonical form: Latin digits, no scanner prefix (]E0 ...), no spaces / quotes / hidden characters,
  /// Excel artefacts removed (1234.0, 1.23E+12), upper case.
  static String norm(String? raw) {
    if (raw == null) return '';
    var s = latinDigits(raw.trim());
    s = s.replaceFirst(_scannerPrefix, '');
    s = s.replaceAll(_hidden, '');
    if (RegExp(r'^\d+\.0+$').hasMatch(s)) s = s.substring(0, s.indexOf('.'));
    if (RegExp(r'^\d+(\.\d+)?[eE][+-]?\d+$').hasMatch(s)) {
      final d = double.tryParse(s);
      if (d != null && d.isFinite && d.abs() < 1e18) s = d.toStringAsFixed(0);
    }
    return s.toUpperCase();
  }

  /// True when [raw] is the scientific-notation form Excel produces for long numbers
  /// (its digits beyond the 15th are lost: the code must be re-checked by the user).
  static bool isSci(String raw) => RegExp(r'^\s*\d+(\.\d+)?[eE][+-]?\d+\s*$').hasMatch(latinDigits(raw));

  /// Empty or a placeholder such as null / nan / -.
  static bool isJunk(String normalized) => normalized.isEmpty || _junk.contains(normalized);

  /// Same code without leading zeros (EAN-13 "0123456789012" == UPC-A "123456789012").
  /// Only for all-digit codes that stay at least 7 digits long, like the desktop's loose match.
  static String loose(String normalized) {
    if (!RegExp(r'^\d+$').hasMatch(normalized)) return normalized;
    final t = normalized.replaceFirst(RegExp(r'^0+'), '');
    return t.length >= 7 ? t : normalized;
  }

  /// Splits one cell holding several codes ("111, 222 | 333") into normalised codes.
  /// A code written with spaces for readability ("6 221 031 234 567") stays ONE code.
  static List<String> splitMany(String? raw) {
    if (raw == null) return const [];
    final out = <String>[];
    for (final part in latinDigits(raw).split(RegExp(r'[,;|،\n\r]+'))) {
      final toks = part.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (toks.isEmpty) continue;
      final digits = toks.every((t) => RegExp(r'^\d+$').hasMatch(t));
      if (toks.length > 1 && digits && toks.any((t) => t.length < 4)) {
        out.add(norm(toks.join()));
      } else {
        out.addAll(toks.map(norm));
      }
    }
    return out.where((c) => !isJunk(c)).toList();
  }
}
