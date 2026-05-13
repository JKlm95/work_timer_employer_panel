import '../../models/tracked_workspace_access.dart';

/// Firestore `whereIn` supports at most this many values per query.
const int kFirestoreWhereInMax = 10;

/// Non-empty trimmed workspace ids, deduplicated.
Set<String> normalizedWorkspaceIdSet(Iterable<String?> raw) {
  final out = <String>{};
  for (final r in raw) {
    final s = r?.trim() ?? '';
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// Chunks for `whereIn` — never returns an empty inner list; returns an empty outer list
/// when [ids] is empty (caller must not run `whereIn` at all).
List<List<String>> workspaceIdChunksForWhereIn(
  Set<String> ids, {
  int max = kFirestoreWhereInMax,
}) {
  if (ids.isEmpty) return const [];
  final list = ids.toList()..sort();
  final chunks = <List<String>>[];
  for (var i = 0; i < list.length; i += max) {
    final end = i + max > list.length ? list.length : i + max;
    final chunk = list.sublist(i, end);
    if (chunk.isNotEmpty) chunks.add(chunk);
  }
  return chunks;
}

/// One logical row per `(employeeUid, workspaceId)`; prefers doc whose id matches canonical [TrackedWorkspaceAccess.docIdFor].
List<TrackedWorkspaceAccess> dedupeTrackedWorkspaceAccessDocs(
  List<TrackedWorkspaceAccess> docs,
) {
  final byKey = <String, TrackedWorkspaceAccess>{};
  for (final d in docs) {
    final u = d.employeeUid.trim();
    final w = d.workspaceId.trim();
    if (u.isEmpty || w.isEmpty) continue;
    final canonical = TrackedWorkspaceAccess.docIdFor(u, w);
    final prev = byKey[canonical];
    if (prev == null) {
      byKey[canonical] = d;
      continue;
    }
    if (d.accessId == canonical) {
      byKey[canonical] = d;
    } else if (prev.accessId != canonical) {
      byKey[canonical] = d;
    }
  }
  return byKey.values.toList();
}
