import 'employer_workspace_lookup.dart';
import 'entry_amount_breakdown.dart';
import '../../models/work_entry.dart';
import '../../models/workspace.dart';

/// Aggregates for employer timesheet (uses same amount formula as [EntryAmountResult]).
class TimesheetMonthSummary {
  const TimesheetMonthSummary({
    required this.totalDuration,
    required this.billableWorkDuration,
    required this.nonBillableWorkDuration,
    required this.amountByCurrency,
    required this.durationByEntryTypeLabel,
    required this.durationByBillingPercent,
  });

  final Duration totalDuration;
  final Duration billableWorkDuration;
  final Duration nonBillableWorkDuration;
  final Map<String, double> amountByCurrency;

  /// Label from [EntryAmountResult.entryTypeLabel] → total duration.
  final Map<String, Duration> durationByEntryTypeLabel;

  /// Percent bucket (50, 80, …) → total duration for closed entries.
  final Map<int, Duration> durationByBillingPercent;

  static TimesheetMonthSummary compute(
    List<WorkEntry> entries,
    Map<String, Workspace> workspaceByLookupKey,
    String employeeUid,
  ) {
    var total = Duration.zero;
    var billWork = Duration.zero;
    var nonBillWork = Duration.zero;
    final money = <String, double>{};
    final byType = <String, Duration>{};
    final byPct = <int, Duration>{};

    for (final e in entries) {
      if (e.isDeleted) continue;
      final d = e.duration;
      if (d == null) continue;

      total += d;

      final typeKey = EntryAmountResult.entryTypeLabel(e.entryType);
      byType[typeKey] = (byType[typeKey] ?? Duration.zero) + d;

      final pct = (e.billingRatePercent ?? 100.0).round();
      byPct[pct] = (byPct[pct] ?? Duration.zero) + d;

      final t = e.entryType ?? 'work';
      if (t == 'work') {
        if (e.effectiveBillable) {
          billWork += d;
        } else {
          nonBillWork += d;
        }
      }

      final ws = workspaceForEmployerEntry(
        workspaceByLookupKey,
        employeeUid,
        e.workspaceId,
      );
      final ar = EntryAmountResult.compute(e, ws);
      if (ar.amountValue != null && ar.currency.isNotEmpty) {
        money[ar.currency] = (money[ar.currency] ?? 0) + ar.amountValue!;
      }
    }

    return TimesheetMonthSummary(
      totalDuration: total,
      billableWorkDuration: billWork,
      nonBillableWorkDuration: nonBillWork,
      amountByCurrency: money,
      durationByEntryTypeLabel: byType,
      durationByBillingPercent: byPct,
    );
  }
}
