/// Helpers for employer ↔ employee email domain checks (MVP access rules).
String? emailLocalPart(String email) {
  final normalized = email.trim().toLowerCase();
  final at = normalized.indexOf('@');
  if (at <= 0) return null;
  return normalized.substring(0, at);
}

String? emailDomain(String email) {
  final normalized = email.trim().toLowerCase();
  final at = normalized.indexOf('@');
  if (at < 0 || at >= normalized.length - 1) return null;
  return normalized.substring(at + 1);
}
