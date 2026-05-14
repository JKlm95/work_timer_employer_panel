import 'package:flutter/foundation.dart';

/// Szczegółowe logi ścieżki wpisów pracownika (fetch miesiąca, stream, dashboard, timesheet).
///
/// Włącz tylko na sesję debug, np. w `main()`:
/// ```dart
/// EmployerEntriesDebugConfig.verboseTrace = true;
/// EmployerEntriesDebugConfig.focusEmployeeUid = '<uid pracownika>';
/// EmployerEntriesDebugConfig.focusEntryId = '<doc id entries/...>'; // opcjonalnie
/// ```
///
/// Bez [focusEmployeeUid] **albo** [focusEntryId] szczegółowe ślady się nie włączą
/// (żeby nie zalać konsoli przy samym `verboseTrace`).
class EmployerEntriesDebugConfig {
  EmployerEntriesDebugConfig._();

  static bool verboseTrace = false;

  /// Ogranicza logi do jednego pracownika (trimowane).
  static String? focusEmployeeUid;

  /// Dodatkowy laser na jeden dokument `users/{uid}/entries/{id}`.
  static String? focusEntryId;

  /// `kDebugMode` + [verboseTrace] + ustawiony co najmniej jeden focus.
  static bool get traceDetailed =>
      kDebugMode &&
      verboseTrace &&
      (((focusEmployeeUid ?? '').trim().isNotEmpty) ||
          ((focusEntryId ?? '').trim().isNotEmpty));

  static bool matchesFocusEmployee(String employeeUid) {
    final f = focusEmployeeUid?.trim();
    if (f == null || f.isEmpty) return false;
    return employeeUid.trim() == f;
  }

  static bool matchesFocusEntry(String entryId) {
    final f = focusEntryId?.trim();
    if (f == null || f.isEmpty) return false;
    return entryId == f;
  }

  /// Czy logować fetch/stream/dashboard/timesheet dla tego [employeeUid].
  ///
  /// Gdy [focusEmployeeUid] jest ustawiony — tylko ten UID. Gdy nie ma filtra
  /// pracownika (np. sam [focusEntryId]) — każda ścieżka (żeby znaleźć dokument).
  static bool tracePipelineForEmployee(String employeeUid) {
    if (!traceDetailed) return false;
    final fe = focusEmployeeUid?.trim() ?? '';
    if (fe.isNotEmpty) {
      return employeeUid.trim() == fe;
    }
    return true;
  }
}
