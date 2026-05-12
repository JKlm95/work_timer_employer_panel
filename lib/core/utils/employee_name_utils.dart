import '../../models/tracked_employee.dart';

/// Display names from `displayName` with email fallback (no separate firstName/lastName fields yet).
String employeeFullName(TrackedEmployee t) {
  final d = t.displayName?.trim();
  if (d != null && d.isNotEmpty) return d;
  return t.employeeEmail;
}

String employeeFirstName(TrackedEmployee t) {
  final d = t.displayName?.trim();
  if (d == null || d.isEmpty) return '';
  final parts = d.split(RegExp(r'\s+'));
  return parts.isNotEmpty ? parts.first : '';
}

String employeeLastName(TrackedEmployee t) {
  final d = t.displayName?.trim();
  if (d == null || d.isEmpty) return '';
  final parts = d.split(RegExp(r'\s+'));
  if (parts.length < 2) return '';
  return parts.sublist(1).join(' ');
}

String employeeInitials(TrackedEmployee t) {
  final full = employeeFullName(t);
  final parts = full.split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final s = parts.single;
    if (s.length >= 2) return (s[0] + s[1]).toUpperCase();
    return s.isNotEmpty ? s[0].toUpperCase() : '?';
  }
  return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
}
