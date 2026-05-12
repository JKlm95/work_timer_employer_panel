import '../../models/tracked_employee.dart';

/// Display helpers for [TrackedEmployee]. First/last name values come from `userEmailIndex`
/// (merged in [FirestoreService.trackedEmployeesStream] / [TrackedEmployee.mergedWithUserEmailIndex]),
/// never from workspace documents.

/// Primary label for lists — same as [TrackedEmployee.fullName].
String employeeFullName(TrackedEmployee t) => t.fullName;

/// When [TrackedEmployee.fullName] is already the work email, skip a second line with the same text.
bool employeeShowEmailAsSubtitle(TrackedEmployee t) {
  final e = t.employeeEmail.trim().toLowerCase();
  final f = t.fullName.trim().toLowerCase();
  return f != e;
}

String employeeFirstName(TrackedEmployee t) => t.firstName?.trim() ?? '';

String employeeLastName(TrackedEmployee t) => t.lastName?.trim() ?? '';

String employeeInitials(TrackedEmployee t) {
  final fn = employeeFirstName(t);
  final ln = employeeLastName(t);
  if (fn.isNotEmpty && ln.isNotEmpty) {
    return '${fn[0]}${ln[0]}'.toUpperCase();
  }
  if (fn.length >= 2) return fn.substring(0, 2).toUpperCase();
  if (fn.isNotEmpty) return fn[0].toUpperCase();
  final full = t.fullName;
  final parts = full.split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.single;
    if (s.length >= 2) return (s[0] + s[1]).toUpperCase();
    return s.isNotEmpty ? s[0].toUpperCase() : '?';
  }
  return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
}
