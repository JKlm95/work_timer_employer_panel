import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employee_presence_utils.dart';
import 'package:work_timer_employer_panel/models/employee_live_status.dart';
import 'package:work_timer_employer_panel/models/tracked_employee.dart';

TrackedEmployee _tr({String slug = 'acme'}) {
  return TrackedEmployee(
    id: 'tid',
    employeeUid: 'uid1',
    employeeEmail: 'a@b.c',
    employeeEmailLower: 'a@b.c',
    companyName: 'Acme',
    companySlug: slug,
  );
}

void main() {
  test('running + matching slug => working', () {
    final live = EmployeeLiveStatus(
      isOnline: true,
      timerState: 'running',
      activeCompanySlug: 'acme',
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live, tracked: _tr()), WorkPresenceState.working);
  });

  test('no live doc => offline', () {
    expect(resolveWorkPresence(live: null, tracked: _tr()), WorkPresenceState.offline);
  });

  test('paused + matching slug => paused', () {
    final live = EmployeeLiveStatus(
      timerState: 'paused',
      activeCompanySlug: 'Acme',
      lastSeenAt: DateTime.now(),
    );
    expect(resolveWorkPresence(live: live, tracked: _tr()), WorkPresenceState.paused);
  });
}
