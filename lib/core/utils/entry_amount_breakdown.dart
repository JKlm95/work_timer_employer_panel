import '../../models/work_entry.dart';
import '../../models/workspace.dart';

/// Reason when [displayAmount] is not a numeric string.
enum EntryAmountSkipReason { none, noDuration, noWorkspace, noRate }

/// Transparent line-item amount for timesheet / tooltips.
class EntryAmountResult {
  const EntryAmountResult({
    required this.displayAmount,
    required this.formulaLine,
    required this.skipReason,
    required this.amountValue,
    required this.currency,
  });

  /// e.g. `320.00` or `No rate` / `—`.
  final String displayAmount;

  /// e.g. `8.0 h × 50 PLN × 80% = 320.00 PLN`.
  final String formulaLine;

  final EntryAmountSkipReason skipReason;

  /// Null when not computable.
  final double? amountValue;

  final String currency;

  static const _unspecifiedTypeLabel = 'Unspecified';

  static String entryTypeLabel(String? entryType) {
    final t = entryType?.trim();
    if (t == null || t.isEmpty) return _unspecifiedTypeLabel;
    switch (t) {
      case 'work':
        return 'Work';
      case 'vacation':
        return 'Vacation';
      case 'sickLeave':
        return 'Sick leave';
      case 'businessTrip':
        return 'Business trip';
      case 'other':
        return 'Other';
      default:
        return t;
    }
  }

  /// `billingRatePercent` from Firestore is source of truth; null → 100%.
  static EntryAmountResult compute(WorkEntry entry, Workspace? workspace) {
    final duration = entry.duration;
    if (duration == null) {
      return const EntryAmountResult(
        displayAmount: '—',
        formulaLine: '',
        skipReason: EntryAmountSkipReason.noDuration,
        amountValue: null,
        currency: 'PLN',
      );
    }

    if (entry.workspaceId.trim().isEmpty || workspace == null) {
      return EntryAmountResult(
        displayAmount: '—',
        formulaLine: '',
        skipReason: EntryAmountSkipReason.noWorkspace,
        amountValue: null,
        currency: _currencyOf(workspace),
      );
    }

    final hours = duration.inMinutes / 60.0;
    final rate = workspace.hourlyRate;
    if (rate == null || rate <= 0) {
      return EntryAmountResult(
        displayAmount: 'No rate',
        formulaLine: '${_fmtHours(hours)} h × (no hourly rate)',
        skipReason: EntryAmountSkipReason.noRate,
        amountValue: null,
        currency: _currencyOf(workspace),
      );
    }

    final pct = entry.billingRatePercent ?? 100.0;
    final currency = _currencyOf(workspace);
    final amount = hours * rate * pct / 100.0;
    final formula =
        '${_fmtHours(hours)} h × ${rate.toStringAsFixed(2)} $currency × ${pct.toStringAsFixed(0)}% = ${amount.toStringAsFixed(2)} $currency';

    return EntryAmountResult(
      displayAmount: amount.toStringAsFixed(2),
      formulaLine: formula,
      skipReason: EntryAmountSkipReason.none,
      amountValue: amount,
      currency: currency,
    );
  }

  static String _currencyOf(Workspace? w) {
    final c = w?.currency?.trim();
    if (c == null || c.isEmpty) return 'PLN';
    return c.toUpperCase();
  }

  static String _fmtHours(double h) => h.toStringAsFixed(1);
}
