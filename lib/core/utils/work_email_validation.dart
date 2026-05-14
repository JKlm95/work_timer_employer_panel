/// Normalizes and validates an employee work email for linking.
String normalizeWorkEmailLower(String input) => input.trim().toLowerCase();

/// Minimal RFC-style check: local@domain with domain containing a dot.
bool isPlausibleWorkEmail(String trimmedLowercase) {
  final s = trimmedLowercase.trim().toLowerCase();
  if (s.isEmpty || s.contains(' ') || s.contains('..')) return false;
  final at = s.indexOf('@');
  if (at <= 0 || at >= s.length - 1) return false;
  final domain = s.substring(at + 1);
  if (domain.isEmpty || !domain.contains('.')) return false;
  final local = s.substring(0, at);
  return local.isNotEmpty;
}
