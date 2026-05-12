import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employee_name_utils.dart';
import 'package:work_timer_employer_panel/models/tracked_employee.dart';

TrackedEmployee _employee({
  String email = 'a@b.c',
  String? firstName,
  String? lastName,
  String? displayName,
}) {
  return TrackedEmployee(
    id: '1',
    employeeUid: 'uid',
    employeeEmail: email,
    employeeEmailLower: email.toLowerCase(),
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
      expect(_employee(firstName: 'Jan', lastName: 'Kowalski').fullName, 'Jan Kowalski');
      expect(_employee(firstName: 'Jan', lastName: null).fullName, 'Jan');
      expect(_employee(firstName: null, lastName: 'Kowalski').fullName, 'Kowalski');
    });

    test('uses displayName when first/last empty', () {
      expect(_employee(displayName: 'JK').fullName, 'JK');
    });

    test('falls back to work email', () {
      expect(_employee(email: 'work@corp.test').fullName, 'work@corp.test');
    });
  });

  group('employeeShowEmailAsSubtitle', () {
    test('false when primary label is already the email', () {
      expect(employeeShowEmailAsSubtitle(_employee(email: 'only@email.test')), false);
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
}
