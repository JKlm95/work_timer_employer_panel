import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employer_workspace_lookup.dart';
import 'package:work_timer_employer_panel/models/workspace.dart';

void main() {
  test('lookup key matches Firestore trackedWorkspaces doc id pattern', () {
    expect(employerWorkspaceLookupKey('uidA', 'default'), 'uidA_default');
  });

  test('buildWorkspaceLookupByScopedKey disambiguates same workspace id', () {
    const w1 = Workspace(id: 'default', name: 'P1');
    const w2 = Workspace(id: 'default', name: 'P2');
    final m1 = buildWorkspaceLookupByScopedKey('alice', [w1]);
    final m2 = buildWorkspaceLookupByScopedKey('bob', [w2]);
    expect(m1['alice_default']?.name, 'P1');
    expect(m2['bob_default']?.name, 'P2');
    expect(workspaceForEmployerEntry(m1, 'alice', 'default')?.name, 'P1');
    expect(workspaceForEmployerEntry(m2, 'alice', 'default'), isNull);
  });
}
