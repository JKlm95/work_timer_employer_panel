import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/entry_amount_breakdown.dart';
import 'package:work_timer_employer_panel/models/work_entry.dart';
import 'package:work_timer_employer_panel/models/workspace.dart';

WorkEntry _closed({String? entryType, double? billingPct, String wid = 'w1'}) {
  return WorkEntry(
    id: 'e1',
    workspaceId: wid,
    start: DateTime(2026, 5, 10, 9, 0),
    end: DateTime(2026, 5, 10, 17, 0),
    entryType: entryType,
    billingRatePercent: billingPct,
  );
}

void main() {
  group('EntryAmountResult', () {
    test('computes amount with billing percent', () {
      const ws = Workspace(
        id: 'w1',
        name: 'P',
        hourlyRate: 50,
        currency: 'PLN',
      );
      final r = EntryAmountResult.compute(_closed(billingPct: 80), ws);
      expect(r.skipReason, EntryAmountSkipReason.none);
      expect(r.amountValue, closeTo(320.0, 0.01));
      expect(r.displayAmount, '320.00');
      expect(r.formulaLine.contains('80%'), true);
    });

    test('null entryType label is Unspecified', () {
      expect(EntryAmountResult.entryTypeLabel(null), 'Unspecified');
    });

    test('No rate when hourlyRate missing', () {
      const ws = Workspace(id: 'w1', name: 'P');
      final r = EntryAmountResult.compute(_closed(), ws);
      expect(r.displayAmount, 'No rate');
      expect(r.skipReason, EntryAmountSkipReason.noRate);
    });

    test('no workspace id', () {
      final e = WorkEntry(
        id: 'x',
        workspaceId: '',
        start: DateTime(2026, 5, 1, 8, 0),
        end: DateTime(2026, 5, 1, 9, 0),
      );
      final r = EntryAmountResult.compute(e, null);
      expect(r.skipReason, EntryAmountSkipReason.noWorkspace);
    });
  });
}
