import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/tracked_workspace_policy.dart';
import 'package:work_timer_employer_panel/models/work_entry.dart';
import 'package:work_timer_employer_panel/models/workspace.dart';

void main() {
  group('workspaceQualifiesForEmployerPanel', () {
    test('shared + work email + domain match', () {
      final w = Workspace(
        id: 'wa',
        name: 'A',
        companySlug: 'acme',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: true,
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeWorkEmailLower: 'bob@acme.com',
          employerDomain: 'acme.com',
        ),
        true,
      );
    });

    test('linkedEmployerEmails ignored — not used for access', () {
      final w = Workspace(
        id: 'wb',
        name: 'B',
        employeeWorkEmail: 'bob@beta.com',
        employeeWorkEmailDomain: 'beta.com',
        isSharedWithEmployer: true,
        linkedEmployerEmails: ['other@beta.com'],
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeWorkEmailLower: 'bob@beta.com',
          employerDomain: 'beta.com',
        ),
        true,
      );
    });

    test('wrong work email → false', () {
      final w = Workspace(
        id: 'w',
        name: 'W',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: true,
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeWorkEmailLower: 'other@acme.com',
          employerDomain: 'acme.com',
        ),
        false,
      );
    });

    test('domain mismatch → false', () {
      final w = Workspace(
        id: 'w',
        name: 'W',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: true,
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeWorkEmailLower: 'bob@acme.com',
          employerDomain: 'other.com',
        ),
        false,
      );
    });

    test('private: isSharedWithEmployer false → false', () {
      final w = Workspace(
        id: 'p',
        name: 'Private',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: false,
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeWorkEmailLower: 'bob@acme.com',
          employerDomain: 'acme.com',
        ),
        false,
      );
    });
  });

  group('filterWorkspacesForEmployerWorkEmailAccess', () {
    test('dedupes by workspace id and keeps both workspaces same email', () {
      final w1 = Workspace(
        id: 'a',
        name: 'A',
        employeeWorkEmail: 'kuba@firma.pl',
        employeeWorkEmailDomain: 'firma.pl',
        isSharedWithEmployer: true,
      );
      final w2 = Workspace(
        id: 'b',
        name: 'B',
        employeeWorkEmail: 'kuba@firma.pl',
        employeeWorkEmailDomain: 'firma.pl',
        isSharedWithEmployer: true,
      );
      final out = filterWorkspacesForEmployerWorkEmailAccess(
        [w1, w2, w1],
        employeeWorkEmailLower: 'kuba@firma.pl',
        employerDomain: 'firma.pl',
      );
      expect(out.length, 2);
      expect(out.map((e) => e.id).toSet(), {'a', 'b'});
    });
  });

  group('filterEntriesByTrackedWorkspaces', () {
    test('drops entries from non-listed workspace ids', () {
      final entries = [
        WorkEntry(
          id: '1',
          workspaceId: 'a',
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 1, 1),
          isDeleted: false,
        ),
        WorkEntry(
          id: '2',
          workspaceId: 'private',
          start: DateTime(2026, 1, 2),
          end: DateTime(2026, 1, 2, 1),
          isDeleted: false,
        ),
      ];
      final out = filterEntriesByTrackedWorkspaces(entries, {'a'});
      expect(out.map((e) => e.id).toList(), ['1']);
    });
  });
}
