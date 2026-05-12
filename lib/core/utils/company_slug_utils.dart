/// Normalizes user-entered company name to compare with [Workspace.companySlug].
/// Mobile apps often store slugs as lowercase hyphenated strings.
String normalizeCompanySlugInput(String raw) {
  var s = raw.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), '-');
  s = s.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  s = s.replaceAll(RegExp(r'-+'), '-');
  return s.replaceAll(RegExp(r'^-|-$'), '');
}
