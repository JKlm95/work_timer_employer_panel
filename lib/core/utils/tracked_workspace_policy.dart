import '../../models/work_entry.dart';
import '../../models/workspace.dart';

/// Firestore doc id under `employers/{employerUid}/trackedWorkspaces/{accessId}`.
String trackedWorkspaceAccessDocId(String employeeUid, String workspaceId) {
  final u = employeeUid.trim();
  final w = workspaceId.trim();
  return '${u}_$w';
}

/// Whether [w] should be linked into employer panel access for this employer context.
bool workspaceQualifiesForEmployerPanel({
  required Workspace w,
  required String employeeEmailLower,
  required String employerDomain,
  required String normalizedCompanySlug,
  required String employerEmailLower,
}) {
  final wEmail = w.employeeWorkEmail?.trim().toLowerCase();
  if (wEmail != employeeEmailLower) return false;
  final wSlug = (w.companySlug ?? '').trim().toLowerCase();
  if (wSlug != normalizedCompanySlug) return false;
  final wsDomain = w.employeeWorkEmailDomain?.trim().toLowerCase();
  if (wsDomain == null || wsDomain.isEmpty || wsDomain != employerDomain) {
    return false;
  }
  if (w.isSharedWithEmployer != true) return false;
  final links = w.linkedEmployerEmails;
  if (links != null && links.isNotEmpty) {
    final set = links.map((e) => e.trim().toLowerCase()).toSet();
    if (!set.contains(employerEmailLower)) return false;
  }
  return true;
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
