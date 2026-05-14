import 'package:flutter/foundation.dart';

import '../debug/live_status_debug_config.dart';
import 'employer_workspace_lookup.dart';
import '../../models/employee_live_status.dart';
import '../../models/tracked_employee.dart';
import '../../models/workspace.dart';

/// In-memory estimate only — not persisted to Firestore.
///
/// [activeCompanySlug] is **not** required for counting a running timer; it can help pick a workspace
/// for rate when [EmployeeLiveStatus.hourlyRate] is null.
class LiveRunningMoneySummary {
  const LiveRunningMoneySummary({
    required this.byCurrency,
    required this.hasRunningWithoutRate,
  });

  final Map<String, double> byCurrency;

  /// At least one employee had `timerState == running` but no usable hourly rate.
  final bool hasRunningWithoutRate;

  String displayValue() {
    if (byCurrency.isNotEmpty) {
      return byCurrency.entries
          .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
          .join(' · ');
    }
    if (hasRunningWithoutRate) return 'No rate';
    return '—';
  }
}

double? _pickHourlyRate(
  EmployeeLiveStatus live,
  Map<String, Workspace> wsMap,
  String employeeUid,
) {
  final uid = employeeUid.trim();
  final direct = live.hourlyRate;
  if (direct != null && direct > 0) return direct;

  final id = live.activeWorkspaceId?.trim();
  if (id != null && id.isNotEmpty) {
    final r = wsMap[employerWorkspaceLookupKey(uid, id)]?.hourlyRate;
    if (r != null && r > 0) return r;
  }

  final slug = (live.activeCompanySlug ?? '').trim().toLowerCase();
  if (slug.isNotEmpty) {
    for (final w in wsMap.values) {
      if ((w.companySlug ?? '').trim().toLowerCase() == slug) {
        final r = w.hourlyRate;
        if (r != null && r > 0) return r;
      }
    }
  }

  for (final w in wsMap.values) {
    final r = w.hourlyRate;
    if (r != null && r > 0) return r;
  }
  return null;
}

String _pickCurrency(
  EmployeeLiveStatus live,
  Map<String, Workspace> wsMap,
  String employeeUid,
) {
  final uid = employeeUid.trim();
  final c = live.currency?.trim();
  if (c != null && c.isNotEmpty) return c.toUpperCase();

  final id = live.activeWorkspaceId?.trim();
  if (id != null && id.isNotEmpty) {
    final w = wsMap[employerWorkspaceLookupKey(uid, id)];
    final wc = w?.currency?.trim();
    if (wc != null && wc.isNotEmpty) return wc.toUpperCase();
  }

  final slug = (live.activeCompanySlug ?? '').trim().toLowerCase();
  if (slug.isNotEmpty) {
    for (final w in wsMap.values) {
      if ((w.companySlug ?? '').trim().toLowerCase() == slug) {
        final wc = w.currency?.trim();
        if (wc != null && wc.isNotEmpty) return wc.toUpperCase();
      }
    }
  }

  for (final w in wsMap.values) {
    final wc = w.currency?.trim();
    if (wc != null && wc.isNotEmpty) return wc.toUpperCase();
  }
  return 'PLN';
}

/// One row per running [employeeUid] (avoids double-counting duplicate tracked rows).
///
/// When [allowedWorkspaceIdsByEmployeeUid] contains [employeeUid], live money is counted only
/// if [EmployeeLiveStatus.activeWorkspaceId] is in that set (private/other workspace → no amount).
LiveRunningMoneySummary computeLiveRunningMoneySummary({
  required List<TrackedEmployee> tracked,
  required Map<String, EmployeeLiveStatus?> liveByEmployeeUid,
  required Map<String, Map<String, Workspace>> workspaceMapsByEmployeeUid,
  required DateTime at,
  Map<String, Set<String>> allowedWorkspaceIdsByEmployeeUid = const {},
}) {
  final out = <String, double>{};
  var missingRate = false;
  final seenRunning = <String>{};

  for (final t in tracked) {
    final uid = t.employeeUid.trim();
    if (uid.isEmpty) continue;

    final live = liveByEmployeeUid[uid];
    if (live == null) continue;
    if (live.timerStateLower != 'running') continue;
    if (seenRunning.contains(uid)) continue;
    seenRunning.add(uid);

    if (allowedWorkspaceIdsByEmployeeUid.containsKey(uid)) {
      final allowed = allowedWorkspaceIdsByEmployeeUid[uid] ?? {};
      final activeId = live.activeWorkspaceId?.trim() ?? '';
      if (activeId.isEmpty || !allowed.contains(activeId)) {
        continue;
      }
    }

    final wsMap =
        workspaceMapsByEmployeeUid[uid] ?? const <String, Workspace>{};
    final rate = _pickHourlyRate(live, wsMap, uid);
    final secs = live.currentAccumulatedSeconds(at);

    if (rate == null || rate <= 0) {
      missingRate = true;
      continue;
    }

    final hours = secs / 3600.0;
    final pct = live.billingRatePercent ?? 100.0;
    if (pct <= 0) {
      missingRate = true;
      continue;
    }

    final currency = _pickCurrency(live, wsMap, uid);
    final amount = hours * rate * pct / 100.0;
    out[currency] = (out[currency] ?? 0) + amount;
  }

  if (kDebugMode && LiveStatusDebugConfig.verboseLiveLogs) {
    debugPrint(
      '[LiveAmount] summary byCurrency=$out hasRunningWithoutRate=$missingRate '
      'runningUids=${seenRunning.length}',
    );
  }

  return LiveRunningMoneySummary(
    byCurrency: out,
    hasRunningWithoutRate: missingRate,
  );
}

/// @nodoc — backwards-compatible name.
Map<String, double> liveRunningAmountByCurrency({
  required List<TrackedEmployee> tracked,
  required Map<String, EmployeeLiveStatus?> liveByEmployeeUid,
  required Map<String, Map<String, Workspace>> workspaceMapsByEmployeeUid,
  required DateTime at,
  Map<String, Set<String>> allowedWorkspaceIdsByEmployeeUid = const {},
}) {
  return computeLiveRunningMoneySummary(
    tracked: tracked,
    liveByEmployeeUid: liveByEmployeeUid,
    workspaceMapsByEmployeeUid: workspaceMapsByEmployeeUid,
    at: at,
    allowedWorkspaceIdsByEmployeeUid: allowedWorkspaceIdsByEmployeeUid,
  ).byCurrency;
}
