import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employee_presence_utils.dart';
import 'package:work_timer_employer_panel/models/employee_live_status.dart';

void main() {
  test('running shows working regardless of activeCompanySlug', () {
    final live = EmployeeLiveStatus(
      timerState: 'running',
      activeCompanySlug: 'other-company',
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live), WorkPresenceState.working);
  });

  test('no live doc => offline', () {
    expect(resolveWorkPresence(live: null), WorkPresenceState.offline);
  });

  test('paused shows paused', () {
    final live = EmployeeLiveStatus(
      timerState: 'paused',
      activeCompanySlug: 'Acme',
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live), WorkPresenceState.paused);
  });

  test('idle + isOnline true + fresh lastSeen => online', () {
    final live = EmployeeLiveStatus(
      timerState: 'idle',
      isOnline: true,
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live), WorkPresenceState.online);
  });

  test('idle + isOnline true but stale lastSeen => offline', () {
    final live = EmployeeLiveStatus(
      timerState: 'idle',
      isOnline: true,
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    expect(resolveWorkPresence(live: live), WorkPresenceState.offline);
  });

  test('idle + isOnline null => unknown', () {
    final live = EmployeeLiveStatus(
      timerState: 'idle',
      isOnline: null,
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live), WorkPresenceState.unknown);
  });
}
