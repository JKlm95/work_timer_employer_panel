import 'package:flutter_test/flutter_test.dart';
import 'package:work_timer_employer_panel/core/utils/employer_workspace_query_utils.dart';
import 'package:work_timer_employer_panel/models/tracked_workspace_access.dart';

void main() {
  group('normalizedWorkspaceIdSet', () {
    test('drops null, empty, trims, dedupes', () {
      expect(normalizedWorkspaceIdSet(['  a ', '', null, 'a', 'b']), {
        'a',
        'b',
      });
    });
  });

  group('workspaceIdChunksForWhereIn', () {
    test('empty set yields no chunks', () {
      expect(workspaceIdChunksForWhereIn({}), isEmpty);
    });

    test('never yields empty inner chunk', () {
      final chunks = workspaceIdChunksForWhereIn({'x'});
      expect(chunks, [
        ['x'],
      ]);
      for (final c in chunks) {
        expect(c, isNotEmpty);
      }
    });

    test('chunks max 10 and splits 11 ids', () {
      final ids = {for (var i = 1; i <= 11; i++) 'w$i'};
      final chunks = workspaceIdChunksForWhereIn(ids);
      expect(chunks.length, 2);
      expect(chunks[0].length, 10);
      expect(chunks[1].length, 1);
      final flat = chunks.expand((e) => e).toSet();
      expect(flat.length, 11);
    });

    test('dedupes duplicate ids into fewer chunks', () {
      final repeated = normalizedWorkspaceIdSet(['a', 'a', 'b']);
      final chunks = workspaceIdChunksForWhereIn(repeated);
      expect(chunks.length, 1);
      expect(chunks.first.toSet(), {'a', 'b'});
    });
  });

  group('dedupeTrackedWorkspaceAccessDocs', () {
    test('keeps one doc per employee+workspace, prefers canonical id', () {
      final canonical = TrackedWorkspaceAccess(
        accessId: 'emp_ws1',
        employeeUid: 'emp',
        workspaceId: 'ws1',
        employeeEmailLower: 'a@b.c',
        companyName: 'C',
        companySlug: 'c',
        workspaceName: 'W',
      );
      final wrongId = TrackedWorkspaceAccess(
        accessId: 'legacy_random',
        employeeUid: 'emp',
        workspaceId: 'ws1',
        employeeEmailLower: 'x@b.c',
        companyName: 'X',
        companySlug: 'x',
        workspaceName: 'X',
      );
      final otherWs = TrackedWorkspaceAccess(
        accessId: 'emp_ws2',
        employeeUid: 'emp',
        workspaceId: 'ws2',
        employeeEmailLower: 'a@b.c',
        companyName: 'C',
        companySlug: 'c',
        workspaceName: 'W2',
      );
      final out = dedupeTrackedWorkspaceAccessDocs([
        wrongId,
        canonical,
        otherWs,
      ]);
      expect(out.length, 2);
      final byWs = {for (final o in out) o.workspaceId: o};
      expect(byWs['ws1']!.accessId, 'emp_ws1');
      expect(byWs['ws2']!.accessId, 'emp_ws2');
    });
  });
}
