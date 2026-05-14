import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employer_group_ids_utils.dart';
import 'package:work_timer_employer_panel/models/employer_group.dart';
import 'package:work_timer_employer_panel/models/tracked_employee.dart';

TrackedEmployee _te(String id, List<String> groupIds) {
  return TrackedEmployee(
    id: id,
    employeeUid: 'u$id',
    employeeEmail: 'e$id@test.dev',
    employeeEmailLower: 'e$id@test.dev',
    employeeWorkEmailLower: 'e$id@test.dev',
    employeeWorkEmailDomain: 'test.dev',
    companyName: 'Co',
    companySlug: 'co',
    groupIds: groupIds,
  );
}

void main() {
  group('parseAndDedupeGroupIds', () {
    test('dedupes and trims', () {
      expect(parseAndDedupeGroupIds([' a ', 'b', 'a', '', 'b']), ['a', 'b']);
    });

    test('non-list yields empty', () {
      expect(parseAndDedupeGroupIds(null), isEmpty);
      expect(parseAndDedupeGroupIds('x'), isEmpty);
    });
  });

  group('employeeHasAnyValidGroupAssignment', () {
    test('true when any id exists', () {
      expect(
        employeeHasAnyValidGroupAssignment(['x', 'g2'], {'g1', 'g2'}),
        isTrue,
      );
    });

    test('false when only unknown ids', () {
      expect(
        employeeHasAnyValidGroupAssignment(['orphan', 'gone'], {'g1'}),
        isFalse,
      );
    });
  });

  group('employerGroupNameCollides', () {
    test('case insensitive', () {
      final groups = [const EmployerGroup(id: '1', name: 'Finance')];
      expect(employerGroupNameCollides('finance', groups), isTrue);
      expect(
        employerGroupNameCollides('finance', groups, ignoreGroupId: '1'),
        isFalse,
      );
    });
  });

  group('Ungrouped vs members (logic)', () {
    test('orphan groupIds treated as ungrouped for UI', () {
      final existing = {'g1'}.map((e) => e).toSet();
      final t = _te('1', ['missing']);
      expect(employeeHasAnyValidGroupAssignment(t.groupIds, existing), isFalse);
    });

    test('multi-group membership preserved in list', () {
      final t = _te('1', ['g1', 'g2']);
      expect(t.groupIds, ['g1', 'g2']);
    });
  });
}
