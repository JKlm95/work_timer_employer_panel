import '../../models/workspace.dart';
import 'tracked_workspace_policy.dart' show trackedWorkspaceAccessDocId;

/// Same segment layout as `employers/{employerUid}/trackedWorkspaces/{accessId}`.
/// Use for **map keys** when caching [Workspace] rows per employee — `workspaceId`
/// alone is only unique under `users/{employeeUid}/workspaces`.
String employerWorkspaceLookupKey(String employeeUid, String workspaceId) =>
    trackedWorkspaceAccessDocId(employeeUid, workspaceId);

/// Builds a lookup map keyed by [employerWorkspaceLookupKey] for one employee.
Map<String, Workspace> buildWorkspaceLookupByScopedKey(
  String employeeUid,
  Iterable<Workspace> workspaces,
) {
  final u = employeeUid.trim();
  final out = <String, Workspace>{};
  for (final w in workspaces) {
    out[employerWorkspaceLookupKey(u, w.id)] = w;
  }
  return out;
}

Workspace? workspaceForEmployerEntry(
  Map<String, Workspace> workspaceByLookupKey,
  String employeeUid,
  String entryWorkspaceId,
) =>
    workspaceByLookupKey[employerWorkspaceLookupKey(
      employeeUid,
      entryWorkspaceId,
    )];
