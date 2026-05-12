import '../../models/employee_live_status.dart';
import '../../models/tracked_employee.dart';
import '../../models/workspace.dart';

/// In-memory estimate only — not persisted to Firestore.
Map<String, double> liveRunningAmountByCurrency({
  required List<TrackedEmployee> tracked,
  required Map<String, EmployeeLiveStatus?> liveByEmployeeUid,
  required Map<String, Map<String, Workspace>> workspaceMapsByEmployeeUid,
  required DateTime at,
}) {
  final out = <String, double>{};
  for (final t in tracked) {
    final live = liveByEmployeeUid[t.employeeUid];
    if (live == null) continue;
    if (live.timerStateLower != 'running') continue;
    final slug = t.companySlug.trim().toLowerCase();
    final a = (live.activeCompanySlug ?? '').trim().toLowerCase();
    if (a.isEmpty || a != slug) continue;

    final wsId = live.activeWorkspaceId?.trim();
    if (wsId == null || wsId.isEmpty) continue;

    final wsMap = workspaceMapsByEmployeeUid[t.employeeUid] ?? const <String, Workspace>{};
    final ws = wsMap[wsId];
    final rate = ws?.hourlyRate;
    if (rate == null || rate <= 0) continue;

    final secs = live.currentAccumulatedSeconds(at);
    final hours = secs / 3600.0;
    final pct = live.billingRatePercent ?? 100.0;
    final currency = (ws?.currency ?? 'PLN').toUpperCase();
    out[currency] = (out[currency] ?? 0) + hours * rate * pct / 100.0;
  }
  return out;
}
