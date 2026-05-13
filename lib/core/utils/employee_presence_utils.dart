import '../../models/employee_live_status.dart';

/// UI presence derived from [EmployeeLiveStatus] (timer state first; slug does not gate Working/Paused).
enum WorkPresenceState {
  working,
  paused,
  online,
  offline,
  unknown,
}

const Duration kOnlineLastSeenThreshold = Duration(minutes: 2);

/// Working / Paused follow [EmployeeLiveStatus.timerState] only (no [TrackedEmployee.companySlug] gate).
///
/// Online: `timerState` idle (or empty) **and** `isOnline == true` **and** not offline by freshness / flag.
/// Offline: missing doc (caller passes null), `isOnline == false`, or `lastSeenAt`/`updatedAt` older than [kOnlineLastSeenThreshold].
WorkPresenceState resolveWorkPresence({
  required EmployeeLiveStatus? live,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();

  if (live == null) {
    return WorkPresenceState.offline;
  }

  final ts = live.timerStateLower;

  if (ts == 'running') {
    return WorkPresenceState.working;
  }
  if (ts == 'paused') {
    return WorkPresenceState.paused;
  }

  // idle or unknown non-running state → online/offline rules
  final last = live.lastSeenAt ?? live.updatedAt;
  final stale = last == null || clock.difference(last) > kOnlineLastSeenThreshold;

  if (live.isOnline == false) {
    return WorkPresenceState.offline;
  }
  if (stale) {
    return WorkPresenceState.offline;
  }
  if (live.isOnline == true) {
    return WorkPresenceState.online;
  }

  return WorkPresenceState.unknown;
}
