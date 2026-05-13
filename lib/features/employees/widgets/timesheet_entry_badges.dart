import 'package:flutter/material.dart';

import '../../../core/utils/entry_amount_breakdown.dart';
import '../../../models/work_entry.dart';

/// Small visual tags for timesheet rows (display-only).
class TimesheetEntryBadges extends StatelessWidget {
  const TimesheetEntryBadges({
    super.key,
    required this.entry,
    this.dense = false,
  });

  final WorkEntry entry;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (entry.billingRatePercent ?? 100).round();
    final bill = entry.effectiveBillable;
    final chips = <Widget>[
      _typeChip(context, EntryAmountResult.entryTypeLabel(entry.entryType)),
      _tonalChip(
        context,
        '$pct%',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.percent_rounded,
      ),
      _tonalChip(
        context,
        bill ? 'Billable' : 'Non-bill.',
        bill
            ? scheme.primaryContainer.withValues(alpha: 0.85)
            : scheme.surfaceContainerHighest,
        bill ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        bill ? Icons.attach_money_rounded : Icons.money_off_outlined,
      ),
      if (entry.isDeleted)
        _tonalChip(
          context,
          'Deleted',
          scheme.errorContainer.withValues(alpha: 0.55),
          scheme.onErrorContainer,
          Icons.delete_outline_rounded,
        ),
      if (entry.editedAt != null && !entry.isDeleted)
        _tonalChip(
          context,
          'Edited',
          scheme.tertiaryContainer.withValues(alpha: 0.75),
          scheme.onTertiaryContainer,
          Icons.edit_note_rounded,
        ),
    ];
    return Wrap(
      spacing: dense ? 4 : 6,
      runSpacing: dense ? 4 : 6,
      children: chips,
    );
  }

  static Widget _typeChip(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    return _tonalChip(
      context,
      label,
      scheme.surfaceContainerHigh,
      scheme.onSurfaceVariant,
      Icons.label_outline_rounded,
    );
  }

  static Widget _tonalChip(
    BuildContext context,
    String label,
    Color bg,
    Color fg,
    IconData icon,
  ) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
