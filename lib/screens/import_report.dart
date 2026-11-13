import 'package:flutter/material.dart';
import '../db.dart';
import '../i18n.dart';
import '../theme.dart';

/// Shows exactly what an import did, so the user can trust it (or see what to fix in the file).
Future<void> showImportReport(BuildContext context, ImportReport r) {
  Widget row(String label, int n, {Color? color, bool show = true}) => !show
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: JC.silverDim))),
            Text('$n', textDirection: TextDirection.ltr, style: TextStyle(color: color ?? JC.silver, fontWeight: FontWeight.w800)),
          ]),
        );
  final ok = r.verified;
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: JC.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JC.borderHi)),
      title: Row(children: [
        Icon(ok ? Icons.verified : Icons.error_outline, color: ok ? JC.gold : JC.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(ok ? tr('rep_title_ok') : tr('rep_title_bad'),
              style: TextStyle(color: ok ? JC.gold : JC.danger, fontWeight: FontWeight.bold)),
        ),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          row(tr('rep_rows'), r.rows),
          const Divider(color: JC.border),
          row(tr('rep_added'), r.added),
          row(tr('rep_updated'), r.updated),
          row(tr('rep_unchanged'), r.unchanged),
          row(tr('rep_alt_added'), r.altAdded, show: r.altAdded + r.altExisting > 0),
          const Divider(color: JC.border),
          row(tr('rep_skip_code'), r.skippedNoCode, color: JC.danger, show: r.skippedNoCode > 0),
          row(tr('rep_skip_name'), r.skippedNoName, color: JC.danger, show: r.skippedNoName > 0),
          row(tr('rep_skip_other'), r.skippedOther, color: JC.danger, show: r.skippedOther > 0),
          row(tr('rep_dups'), r.duplicatesInFile, color: JC.warn, show: r.duplicatesInFile > 0),
          row(tr('rep_named_code'), r.namedByCode, color: JC.warn, show: r.namedByCode > 0),
          row(tr('rep_no_price'), r.noPrice, color: JC.warn, show: r.noPrice > 0),
          row(tr('rep_bad_num'), r.badNumbers, color: JC.danger, show: r.badNumbers > 0),
          row(tr('rep_conflicts'), r.altConflicts, color: JC.danger, show: r.altConflicts > 0),
          row(tr('rep_sci'), r.sciWarnings, color: JC.danger, show: r.sciWarnings > 0),
          row(tr('rep_mismatch'), r.mismatches, color: JC.danger, show: r.mismatches > 0),
          const Divider(color: JC.border),
          row(tr('rep_total_products'), r.productsAfter),
          row(tr('rep_total_codes'), r.codesAfter),
          const SizedBox(height: 8),
          Text(ok ? tr('rep_verified') : tr('rep_not_verified'),
              style: TextStyle(color: ok ? JC.silverDim : JC.danger, fontSize: 12)),
          if (r.sciWarnings > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('rep_sci_hint'), style: const TextStyle(color: JC.muted, fontSize: 12)),
            ),
          if (r.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final n in r.notes.take(8))
              Text(n, textDirection: TextDirection.ltr, style: const TextStyle(color: JC.muted, fontSize: 11)),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('ok'), style: const TextStyle(color: JC.gold)))],
    ),
  );
}
