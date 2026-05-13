import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/models/employee_live_status.dart';

void main() {
  group('EmployeeLiveStatus.fromMap', () {
    test('parses timerState and running path', () {
      final m = <String, dynamic>{
        'timerState': 'RUNNING',
        'isOnline': true,
        'lastSeenAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      };
      final s = EmployeeLiveStatus.fromMap(m);
      expect(s.timerStateLower, 'running');
      expect(s.isOnline, true);
    });

    test('parses paused', () {
      final s = EmployeeLiveStatus.fromMap({'timerState': 'Paused'});
      expect(s.timerStateLower, 'paused');
    });

    test('idle when timerState missing', () {
      final s = EmployeeLiveStatus.fromMap(<String, dynamic>{});
      expect(s.timerStateLower, 'idle');
    });

    test('parses bool from string and int', () {
      expect(EmployeeLiveStatus.fromMap({'isOnline': 'true'}).isOnline, true);
      expect(EmployeeLiveStatus.fromMap({'isOnline': '0'}).isOnline, false);
      expect(EmployeeLiveStatus.fromMap({'isOnline': 1}).isOnline, true);
    });

    test('parses hourlyRate and currency', () {
      final s = EmployeeLiveStatus.fromMap({
        'hourlyRate': '120.5',
        'currency': 'eur',
      });
      expect(s.hourlyRate, 120.5);
      expect(s.currency, 'eur');
    });

    test('null hourlyRate when empty or invalid', () {
      expect(EmployeeLiveStatus.fromMap({'hourlyRate': ''}).hourlyRate, isNull);
      expect(
        EmployeeLiveStatus.fromMap({'hourlyRate': 'x'}).hourlyRate,
        isNull,
      );
    });

    test('currentAccumulatedSeconds adds delta when running', () {
      final start = DateTime(2026, 5, 1, 12, 0, 0);
      final at = DateTime(2026, 5, 1, 12, 0, 30);
      final s = EmployeeLiveStatus(
        timerState: 'running',
        accumulatedSecondsBeforePause: 60,
        sessionStartedAt: start,
      );
      expect(s.currentAccumulatedSeconds(at), 90);
    });

    test('currentAccumulatedSeconds base only when paused', () {
      final s = EmployeeLiveStatus(
        timerState: 'paused',
        accumulatedSecondsBeforePause: 125,
        sessionStartedAt: DateTime(2026, 5, 1),
      );
      expect(s.currentAccumulatedSeconds(DateTime(2026, 5, 2)), 125);
    });
  });
}
