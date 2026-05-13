import '../../models/work_entry.dart';

/// Client-side filters for employer timesheet (month query already applied in Firestore).
List<WorkEntry> filterTimesheetEntries(
  List<WorkEntry> entries, {
  required String? workspaceId,
  required String? entryType,
  required bool? billableOnly,
  required bool showDeleted,
  required String searchQuery,
}) {
  final q = searchQuery.trim().toLowerCase();
  return entries.where((e) {
    if (!showDeleted && e.isDeleted) return false;
    if (workspaceId != null &&
        workspaceId.isNotEmpty &&
        e.workspaceId != workspaceId) {
      return false;
    }
    if (entryType != null && entryType.isNotEmpty && entryType != 'all') {
      final t = e.entryType ?? 'work';
      if (t != entryType) return false;
    }
    if (billableOnly != null) {
      if (billableOnly && !e.effectiveBillable) return false;
      if (!billableOnly && e.effectiveBillable) return false;
    }
    if (q.isNotEmpty) {
      final title = (e.taskTitle ?? '').toLowerCase();
      final note = (e.note ?? '').toLowerCase();
      if (!title.contains(q) && !note.contains(q)) return false;
    }
    return true;
  }).toList();
}

enum TimesheetSort { newestFirst, oldestFirst, durationDesc, amountDesc }

/// [amountOf] must return comparable amount for `amountDesc` (e.g. from [EntryAmountResult.amountValue] or 0).
List<WorkEntry> sortTimesheetEntries(
  List<WorkEntry> entries,
  TimesheetSort sort, {
  required double Function(WorkEntry e) amountOf,
}) {
  final copy = List<WorkEntry>.from(entries);
  switch (sort) {
    case TimesheetSort.newestFirst:
      copy.sort((a, b) => b.start.compareTo(a.start));
      break;
    case TimesheetSort.oldestFirst:
      copy.sort((a, b) => a.start.compareTo(b.start));
      break;
    case TimesheetSort.durationDesc:
      int secs(WorkEntry e) => e.duration?.inSeconds ?? -1;
      copy.sort((a, b) => secs(b).compareTo(secs(a)));
      break;
    case TimesheetSort.amountDesc:
      copy.sort((a, b) => amountOf(b).compareTo(amountOf(a)));
      break;
  }
  return copy;
}
