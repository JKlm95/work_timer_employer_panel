import '../../models/employee_live_status.dart';
import '../../models/tracked_employee.dart';

/// UI presence derived from [EmployeeLiveStatus] + employer's tracked company slug.
enum WorkPresenceState {
  working,
  paused,
  online,
  offline,
  unknown,
}

const Duration kOnlineLastSeenThreshold = Duration(minutes: 2);

bool _slugMatchesLive(EmployeeLiveStatus live, String trackedCompanySlugLower) {
  final a = (live.activeCompanySlug ?? '').trim().toLowerCase();
  return a.isNotEmpty && a == trackedCompanySlugLower;
}

WorkPresenceState resolveWorkPresence({
  required EmployeeLiveStatus? live,
  required TrackedEmployee tracked,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final slug = tracked.companySlug.trim().toLowerCase();

  if (live == null) {
    return WorkPresenceState.offline;
  }

  final ts = live.timerStateLower;
  if (ts == 'running' && _slugMatchesLive(live, slug)) {
    return WorkPresenceState.working;
  }
  if (ts == 'paused' && _slugMatchesLive(live, slug)) {
    return WorkPresenceState.paused;
  }

  final last = live.lastSeenAt ?? live.updatedAt;
  if (live.isOnline == true && last != null && clock.difference(last) <= kOnlineLastSeenThreshold) {
    return WorkPresenceState.online;
  }

  if (live.isOnline == false) {
    return WorkPresenceState.offline;
  }
  if (last != null && clock.difference(last) > kOnlineLastSeenThreshold) {
    return WorkPresenceState.offline;
  }

  if (live.isOnline == true) {
    return WorkPresenceState.online;
  }

  return WorkPresenceState.unknown;
}
