import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/tracked_workspace_policy.dart';
import 'package:work_timer_employer_panel/models/work_entry.dart';
import 'package:work_timer_employer_panel/models/workspace.dart';

void main() {
  group('workspaceQualifiesForEmployerPanel', () {
    test('employer A: shared + slug + domain + optional linked emails', () {
      final w = Workspace(
        id: 'wa',
        name: 'A',
        companySlug: 'acme',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: true,
        linkedEmployerEmails: ['boss@acme.com'],
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: 'bob@acme.com',
          employerDomain: 'acme.com',
          normalizedCompanySlug: 'acme',
          employerEmailLower: 'boss@acme.com',
        ),
        true,
      );
    });

    test('employer B: wrong linkedEmployerEmails → false', () {
      final w = Workspace(
        id: 'wb',
        name: 'B',
        companySlug: 'beta',
        employeeWorkEmail: 'bob@beta.com',
        employeeWorkEmailDomain: 'beta.com',
        isSharedWithEmployer: true,
        linkedEmployerEmails: ['other@beta.com'],
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: 'bob@beta.com',
          employerDomain: 'beta.com',
          normalizedCompanySlug: 'beta',
          employerEmailLower: 'boss@beta.com',
        ),
        false,
      );
    });

    test('private: isSharedWithEmployer false → false', () {
      final w = Workspace(
        id: 'p',
        name: 'Private',
        companySlug: 'acme',
        employeeWorkEmail: 'bob@acme.com',
        employeeWorkEmailDomain: 'acme.com',
        isSharedWithEmployer: false,
      );
      expect(
        workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: 'bob@acme.com',
          employerDomain: 'acme.com',
          normalizedCompanySlug: 'acme',
          employerEmailLower: 'boss@acme.com',
        ),
        false,
      );
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
