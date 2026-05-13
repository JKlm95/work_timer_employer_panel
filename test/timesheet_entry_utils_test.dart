import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/time_entry_validation.dart';
import 'package:work_timer_employer_panel/core/utils/timesheet_entry_utils.dart';
import 'package:work_timer_employer_panel/models/work_entry.dart';

List<WorkEntry> _sample() {
  return [
    WorkEntry(
      id: 'a',
      workspaceId: 'w1',
      start: DateTime(2026, 5, 2, 10, 0),
      end: DateTime(2026, 5, 2, 12, 0),
      taskTitle: 'Alpha task',
      note: 'hello',
      isBillable: true,
      entryType: 'work',
    ),
    WorkEntry(
      id: 'b',
      workspaceId: 'w2',
      start: DateTime(2026, 5, 1, 10, 0),
      end: DateTime(2026, 5, 1, 11, 0),
      isDeleted: true,
    ),
    WorkEntry(
      id: 'c',
      workspaceId: 'w1',
      start: DateTime(2026, 5, 3, 10, 0),
      end: DateTime(2026, 5, 3, 14, 0),
      isBillable: false,
      entryType: 'work',
    ),
  ];
}

void main() {
  group('filterTimesheetEntries', () {
    test('filters by workspace', () {
      final f = filterTimesheetEntries(
        _sample(),
        workspaceId: 'w1',
        entryType: 'all',
        billableOnly: null,
        showDeleted: false,
        searchQuery: '',
      );
      expect(f.map((e) => e.id).toList(), ['a', 'c']);
    });

    test('search taskTitle and note', () {
      final f = filterTimesheetEntries(
        _sample(),
        workspaceId: null,
        entryType: 'all',
        billableOnly: null,
        showDeleted: false,
        searchQuery: 'hello',
      );
      expect(f.length, 1);
      expect(f.single.id, 'a');
    });

    test('hide deleted by default', () {
      final f = filterTimesheetEntries(
        _sample(),
        workspaceId: null,
        entryType: 'all',
        billableOnly: null,
        showDeleted: false,
        searchQuery: '',
      );
      expect(f.any((e) => e.id == 'b'), false);
    });

    test('show deleted', () {
      final f = filterTimesheetEntries(
        _sample(),
        workspaceId: null,
        entryType: 'all',
        billableOnly: null,
        showDeleted: true,
        searchQuery: '',
      );
      expect(f.any((e) => e.id == 'b'), true);
    });

    test('billable only', () {
      final f = filterTimesheetEntries(
        _sample(),
        workspaceId: null,
        entryType: 'all',
        billableOnly: true,
        showDeleted: false,
        searchQuery: '',
      );
      expect(f.map((e) => e.id).toList(), ['a']);
    });
  });

  group('sortTimesheetEntries', () {
    test('newest first', () {
      final s = sortTimesheetEntries(
        _sample(),
        TimesheetSort.newestFirst,
        amountOf: (_) => 0,
      );
      expect(s.first.id, 'c');
    });

    test('duration descending', () {
      final s = sortTimesheetEntries(
        _sample(),
        TimesheetSort.durationDesc,
        amountOf: (_) => 0,
      );
      expect(s.first.id, 'c');
    });
  });

  group('time_entry_validation', () {
    test('start before end', () {
      expect(
        () => assertClosedInterval(
          DateTime(2026, 5, 1, 10, 0),
          DateTime(2026, 5, 1, 9, 0),
        ),
        throwsA(isA<TimeEntryValidationException>()),
      );
    });

    test('billing percent allowed', () {
      assertValidBillingPercent(80);
    });

    test('billing percent invalid', () {
      expect(
        () => assertValidBillingPercent(77),
        throwsA(isA<TimeEntryValidationException>()),
      );
    });
  });
}
