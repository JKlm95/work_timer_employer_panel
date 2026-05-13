import 'package:equatable/equatable.dart';

import '../core/utils/report_period.dart';
import '../models/work_entry.dart';
import '../models/workspace.dart';

/// Aggregates hours and amounts according to MVP billing rules.
class ReportCalculationService {
  /// Billable-only filter: only applies to entries counted toward money totals.
  List<WorkEntry> visibleEntries(
    List<WorkEntry> raw, {
    required ReportPeriod period,
    bool billableOnly = false,
    String? entryTypeFilter,
    bool includeNonWorkTypesInTable = true,
  }) {
    final list = raw.where((e) {
      if (e.isDeleted) return false;
      if (e.end == null) return false;
      if (e.start.isBefore(period.start)) return false;
      if (e.start.isAfter(period.endInclusive)) return false;
      return true;
    }).toList();

    var filtered = list;
    if (entryTypeFilter != null &&
        entryTypeFilter.isNotEmpty &&
        entryTypeFilter != 'all') {
      filtered = filtered
          .where((e) => (e.entryType ?? 'work') == entryTypeFilter)
          .toList();
    }
    if (billableOnly) {
      filtered = filtered.where((e) => e.effectiveBillable).toList();
    }
    return filtered;
  }

  double hoursForEntries(
    List<WorkEntry> entries, {
    bool billableOnlyForWork = false,
  }) {
    var sum = 0.0;
    for (final e in entries) {
      if (!e.isWorkEntry) continue;
      if (billableOnlyForWork && !e.effectiveBillable) continue;
      final d = e.duration;
      if (d == null) continue;
      sum += d.inMinutes / 60.0;
    }
    return sum;
  }

  /// Billing only for `work` (or null entryType). Missing rate => 0 amount (caller shows "—").
  Map<String, double> estimatedAmountByCurrency({
    required List<WorkEntry> entries,
    required Map<String, Workspace> workspaceById,
  }) {
    final map = <String, double>{};
    for (final e in entries) {
      if (!e.isWorkEntry) continue;
      if (!e.effectiveBillable) continue;
      final ws = workspaceById[e.workspaceId];
      final rate = ws?.hourlyRate;
      if (rate == null || rate <= 0) continue;
      final d = e.duration;
      if (d == null) continue;
      final currency = (ws?.currency ?? 'PLN').toUpperCase();
      final hours = d.inMinutes / 60.0;
      map[currency] = (map[currency] ?? 0) + hours * rate;
    }
    return map;
  }

  WorkHoursSplit splitHours(List<WorkEntry> entries) {
    double billableWork = 0;
    double nonBillableWork = 0;
    var vacation = 0;
    var sick = 0;
    var trip = 0;
    var otherNonWork = 0;

    for (final e in entries) {
      final d = e.duration;
      if (d == null) continue;
      final hours = d.inMinutes / 60.0;
      final type = e.entryType ?? 'work';
      switch (type) {
        case 'vacation':
          vacation++;
          break;
        case 'sickLeave':
          sick++;
          break;
        case 'businessTrip':
          trip++;
          break;
        case 'work':
          if (e.effectiveBillable) {
            billableWork += hours;
          } else {
            nonBillableWork += hours;
          }
          break;
        default:
          if (type == 'other') {
            otherNonWork++;
          } else {
            otherNonWork++;
          }
      }
    }

    return WorkHoursSplit(
      billableWorkHours: billableWork,
      nonBillableWorkHours: nonBillableWork,
      vacationEntries: vacation,
      sickEntries: sick,
      businessTripEntries: trip,
      otherNonWorkEntries: otherNonWork,
    );
  }
}

class WorkHoursSplit extends Equatable {
  const WorkHoursSplit({
    required this.billableWorkHours,
    required this.nonBillableWorkHours,
    required this.vacationEntries,
    required this.sickEntries,
    required this.businessTripEntries,
    required this.otherNonWorkEntries,
  });

  final double billableWorkHours;
  final double nonBillableWorkHours;
  final int vacationEntries;
  final int sickEntries;
  final int businessTripEntries;
  final int otherNonWorkEntries;

  double get totalWorkHours => billableWorkHours + nonBillableWorkHours;

  @override
  List<Object?> get props => [
    billableWorkHours,
    nonBillableWorkHours,
    vacationEntries,
    sickEntries,
    businessTripEntries,
    otherNonWorkEntries,
  ];
}

/// Row for payroll-style tables.
class PayrollLine extends Equatable {
  const PayrollLine({
    required this.trackedId,
    required this.employeeLabel,
    this.employeeEmailSubtitle,
    required this.companyName,
    required this.groupLabels,
    required this.totalHours,
    required this.billableHours,
    required this.nonBillableHours,
    required this.vacationCount,
    required this.sickCount,
    required this.amountByCurrency,
    required this.amountDisplay,
    required this.currencyDisplay,
  });

  final String trackedId;
  final String employeeLabel;

  /// Shown under [employeeLabel] when different from the primary label (avoids duplicate email).
  final String? employeeEmailSubtitle;
  final String companyName;
  final String groupLabels;
  final double totalHours;
  final double billableHours;
  final double nonBillableHours;
  final int vacationCount;
  final int sickCount;
  final Map<String, double> amountByCurrency;
  final String amountDisplay;
  final String currencyDisplay;

  @override
  List<Object?> get props => [trackedId];
}

extension MapMerge on Map<String, double> {
  Map<String, double> merged(Map<String, double> other) {
    final out = Map<String, double>.from(this);
    other.forEach((k, v) {
      out[k] = (out[k] ?? 0) + v;
    });
    return out;
  }
}
