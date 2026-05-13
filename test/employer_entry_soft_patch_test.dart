import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/employer_entry_soft_patch.dart';

void main() {
  test('employerEntrySoftDeletePatch sets flags and audit fields', () {
    final p = employerEntrySoftDeletePatch('employerA');
    expect(p['isDeleted'], true);
    expect(p['editedBy'], 'employerA');
    expect(p['updatedAt'], isA<FieldValue>());
    expect(p['editedAt'], isA<FieldValue>());
    expect(p.keys.toSet(), {'isDeleted', 'updatedAt', 'editedAt', 'editedBy'});
  });

  test('employerEntryRestorePatch clears deleted flag', () {
    final p = employerEntryRestorePatch('employerB');
    expect(p['isDeleted'], false);
    expect(p['editedBy'], 'employerB');
    expect(p['updatedAt'], isA<FieldValue>());
    expect(p['editedAt'], isA<FieldValue>());
    expect(p.keys.toSet(), {'isDeleted', 'updatedAt', 'editedAt', 'editedBy'});
  });
}
