import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employer_workspace_lookup.dart';
import 'package:work_timer_employer_panel/core/utils/live_running_amounts.dart';
import 'package:work_timer_employer_panel/models/employee_live_status.dart';
import 'package:work_timer_employer_panel/models/tracked_employee.dart';
import 'package:work_timer_employer_panel/models/workspace.dart';

TrackedEmployee _t(String uid) {
  return TrackedEmployee(
    id: 'tid',
    employeeUid: uid,
    employeeEmail: 'e@test',
    employeeEmailLower: 'e@test',
    employeeWorkEmailLower: 'e@test',
    employeeWorkEmailDomain: 'test',
    companyName: 'Co',
    companySlug: 'co',
  );
}

void main() {
  group('computeLiveRunningMoneySummary', () {
    test('sums running timer with rate from workspace map', () {
      const uid = 'emp1';
      final live = EmployeeLiveStatus(
        timerState: 'running',
        activeWorkspaceId: 'w1',
        accumulatedSecondsBeforePause: 0,
        sessionStartedAt: DateTime(2026, 5, 1, 10, 0, 0),
        billingRatePercent: 100,
      );
      final at = DateTime(2026, 5, 1, 11, 0, 0);
      final summary = computeLiveRunningMoneySummary(
        tracked: [_t(uid)],
        liveByEmployeeUid: {uid: live},
        workspaceMapsByEmployeeUid: {
          uid: {
            employerWorkspaceLookupKey(uid, 'w1'): const Workspace(
              id: 'w1',
              name: 'P',
              companySlug: 'co',
              hourlyRate: 60,
              currency: 'PLN',
            ),
          },
        },
        at: at,
      );
      expect(summary.byCurrency['PLN'], closeTo(60.0, 0.01));
      expect(summary.hasRunningWithoutRate, false);
    });

    test('hasRunningWithoutRate when running but no positive rate', () {
      const uid = 'emp1';
      final live = EmployeeLiveStatus(
        timerState: 'running',
        activeWorkspaceId: 'w1',
        sessionStartedAt: DateTime(2026, 5, 1),
        accumulatedSecondsBeforePause: 3600,
      );
      final summary = computeLiveRunningMoneySummary(
        tracked: [_t(uid)],
        liveByEmployeeUid: {uid: live},
        workspaceMapsByEmployeeUid: {
          uid: {
            employerWorkspaceLookupKey(uid, 'w1'): const Workspace(
              id: 'w1',
              name: 'P',
              companySlug: 'co',
              hourlyRate: 0,
              currency: 'PLN',
            ),
          },
        },
        at: DateTime(2026, 5, 1, 2, 0, 0),
      );
      expect(summary.byCurrency, isEmpty);
      expect(summary.hasRunningWithoutRate, true);
    });

    test('idle timer does not contribute', () {
      const uid = 'u';
      final live = EmployeeLiveStatus(timerState: 'idle', isOnline: true);
      final summary = computeLiveRunningMoneySummary(
        tracked: [_t(uid)],
        liveByEmployeeUid: {uid: live},
        workspaceMapsByEmployeeUid: {
          uid: {
            employerWorkspaceLookupKey(uid, 'w1'): const Workspace(
              id: 'w1',
              name: 'P',
              companySlug: 'co',
              hourlyRate: 100,
              currency: 'PLN',
            ),
          },
        },
        at: DateTime.now(),
      );
      expect(summary.byCurrency, isEmpty);
      expect(summary.hasRunningWithoutRate, false);
    });

    test('live amount skipped when active workspace not in employer gate', () {
      const uid = 'emp1';
      final live = EmployeeLiveStatus(
        timerState: 'running',
        activeWorkspaceId: 'private_ws',
        accumulatedSecondsBeforePause: 0,
        sessionStartedAt: DateTime(2026, 5, 1, 10, 0, 0),
        billingRatePercent: 100,
        hourlyRate: 100,
        currency: 'PLN',
      );
      final at = DateTime(2026, 5, 1, 11, 0, 0);
      final summary = computeLiveRunningMoneySummary(
        tracked: [_t(uid)],
        liveByEmployeeUid: {uid: live},
        workspaceMapsByEmployeeUid: {
          uid: {
            employerWorkspaceLookupKey(uid, 'shared'): const Workspace(
              id: 'shared',
              name: 'Shared',
              companySlug: 'co',
              hourlyRate: 60,
              currency: 'PLN',
            ),
          },
        },
        at: at,
        allowedWorkspaceIdsByEmployeeUid: {
          uid: {'shared'},
        },
      );
      expect(summary.byCurrency, isEmpty);
      expect(summary.hasRunningWithoutRate, false);
    });

    test('displayValue No rate when running without amount', () {
      const s = LiveRunningMoneySummary(
        byCurrency: {},
        hasRunningWithoutRate: true,
      );
      expect(s.displayValue(), 'No rate');
    });

    test('displayValue em dash when nothing running', () {
      const s = LiveRunningMoneySummary(
        byCurrency: {},
        hasRunningWithoutRate: false,
      );
      expect(s.displayValue(), '—');
    });
  });
}
