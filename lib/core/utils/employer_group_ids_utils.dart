import '../../models/employer_group.dart';

/// Max length for `employers/.../groups` document `name` (UI + write validation).
const int kMaxEmployerGroupNameLength = 80;

/// Sentinel for "filter by employees with no valid group assignment" on Employees screen.
const String kEmployeesUngroupedFilterSentinel = '__ungrouped__';

/// Parses Firestore `groupIds`, trims, drops empties, preserves order, dedupes.
List<String> parseAndDedupeGroupIds(dynamic raw) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final e in raw) {
    final s = e?.toString().trim() ?? '';
    if (s.isEmpty) continue;
    if (seen.add(s)) out.add(s);
  }
  return out;
}

/// True if [groupIds] contains at least one id present in [existingGroupIds].
bool employeeHasAnyValidGroupAssignment(
  List<String> groupIds,
  Set<String> existingGroupIds,
) {
  for (final id in groupIds) {
    if (existingGroupIds.contains(id)) return true;
  }
  return false;
}

/// Case-insensitive duplicate name check within one employer's groups.
bool employerGroupNameCollides(
  String name,
  Iterable<EmployerGroup> groups, {
  String? ignoreGroupId,
}) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  for (final g in groups) {
    if (ignoreGroupId != null && g.id == ignoreGroupId) continue;
    if (g.name.trim().toLowerCase() == n) return true;
  }
  return false;
}
