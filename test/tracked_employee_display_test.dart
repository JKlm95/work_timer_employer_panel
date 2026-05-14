import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employee_name_utils.dart';
import 'package:work_timer_employer_panel/models/tracked_employee.dart';
import 'package:work_timer_employer_panel/models/user_email_index.dart';

TrackedEmployee _employee({
  String email = 'a@b.c',
  String? firstName,
  String? lastName,
  String? displayName,
}) {
  final el = email.toLowerCase();
  return TrackedEmployee(
    id: '1',
    employeeUid: 'uid',
    employeeEmail: email,
    employeeEmailLower: el,
    employeeWorkEmailLower: el,
    employeeWorkEmailDomain: 'b.c',
    firstName: firstName,
    lastName: lastName,
    displayName: displayName,
    companyName: 'Co',
    companySlug: 'co',
  );
}

void main() {
  group('TrackedEmployee.fullName', () {
    test('combines first and last when present', () {
      expect(
        _employee(firstName: 'Jan', lastName: 'Kowalski').fullName,
        'Jan Kowalski',
      );
      expect(_employee(firstName: 'Jan', lastName: null).fullName, 'Jan');
      expect(
        _employee(firstName: null, lastName: 'Kowalski').fullName,
        'Kowalski',
      );
    });

    test('uses displayName when first/last empty', () {
      expect(_employee(displayName: 'JK').fullName, 'JK');
    });

    test('falls back to work email', () {
      expect(_employee(email: 'work@corp.test').fullName, 'work@corp.test');
    });
  });

  group('employeeInitials', () {
    test('uses first and last when present', () {
      expect(
        employeeInitials(_employee(firstName: 'Jan', lastName: 'Kowalski')),
        'JK',
      );
    });

    test('uses two letters from email when no names', () {
      expect(employeeInitials(_employee(email: 'ab@cd.ef')), 'AB');
    });
  });

  group('employeeShowEmailAsSubtitle', () {
    test('false when primary label is already the email', () {
      expect(
        employeeShowEmailAsSubtitle(_employee(email: 'only@email.test')),
        false,
      );
    });

    test('true when name differs from email', () {
      expect(
        employeeShowEmailAsSubtitle(
          _employee(email: 'work@corp.test', firstName: 'Jan', lastName: 'K'),
        ),
        true,
      );
    });
  });

  group('TrackedEmployee.mergedWithUserEmailIndex', () {
    test('replaces cached names with index-only values', () {
      final stale = _employee(
        email: 'old@x.com',
        firstName: 'Stale',
        lastName: 'Name',
        displayName: 'Stale Display',
      );
      final index = UserEmailIndex(
        uid: 'u2',
        email: 'user@example.com',
        emailLower: 'user@example.com',
        firstName: 'Jan',
        lastName: 'Kowalski',
        displayName: 'Jan Kowalski',
      );
      final m = stale.mergedWithUserEmailIndex(index);
      expect(m.firstName, 'Jan');
      expect(m.lastName, 'Kowalski');
      expect(m.displayName, 'Jan Kowalski');
      expect(m.employeeEmail, 'user@example.com');
      expect(m.employeeUid, 'u2');
      expect(m.fullName, 'Jan Kowalski');
    });

    test('returns this when index is null', () {
      final t = _employee(firstName: 'Only');
      expect(identical(t.mergedWithUserEmailIndex(null), t), true);
    });
  });
}
