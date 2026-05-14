import '../../models/work_entry.dart';
import '../../models/workspace.dart';

/// Firestore doc id under `employers/{employerUid}/trackedWorkspaces/{accessId}`.
String trackedWorkspaceAccessDocId(String employeeUid, String workspaceId) {
  final u = employeeUid.trim();
  final w = workspaceId.trim();
  return '${u}_$w';
}

/// Whether [w] is visible/linkable for this employer when linking by **employee work email**
/// and **employer account email domain** (no `linkedEmployerEmails`, no employer email on workspace).
bool workspaceQualifiesForEmployerPanel({
  required Workspace w,
  required String employeeWorkEmailLower,
  required String employerDomain,
}) {
  final wEmail = (w.employeeWorkEmail ?? '').trim().toLowerCase();
  if (wEmail != employeeWorkEmailLower) return false;
  final wsDomain = w.employeeWorkEmailDomain?.trim().toLowerCase();
  if (wsDomain == null || wsDomain.isEmpty || wsDomain != employerDomain) {
    return false;
  }
  if (w.isSharedWithEmployer != true) return false;
  return true;
}

/// Applies [workspaceQualifiesForEmployerPanel] to loaded workspace docs (dedupe by [Workspace.id]).
List<Workspace> filterWorkspacesForEmployerWorkEmailAccess(
  Iterable<Workspace> workspaces, {
  required String employeeWorkEmailLower,
  required String employerDomain,
}) {
  final byId = <String, Workspace>{};
  for (final w in workspaces) {
    if (!workspaceQualifiesForEmployerPanel(
      w: w,
      employeeWorkEmailLower: employeeWorkEmailLower,
      employerDomain: employerDomain,
    )) {
      continue;
    }
    byId[w.id] = w;
  }
  return byId.values.toList();
}

/// Filters [entries] to those whose [WorkEntry.workspaceId] is allowed.
List<WorkEntry> filterEntriesByTrackedWorkspaces(
  Iterable<WorkEntry> entries,
  Set<String> allowedWorkspaceIds,
) {
  if (allowedWorkspaceIds.isEmpty) return [];
  return entries
      .where((e) => allowedWorkspaceIds.contains(e.workspaceId))
      .toList();
}

bool employerCanAccessWorkspaceSync(
  Set<String> allowedWorkspaceIds,
  String workspaceId,
) {
  return allowedWorkspaceIds.contains(workspaceId.trim());
}
