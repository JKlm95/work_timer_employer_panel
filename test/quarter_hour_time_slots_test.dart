import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:work_timer_employer_panel/core/utils/quarter_hour_time_slots.dart';

void main() {
  group('quarterHourSlotsIncluding', () {
    test('includes arbitrary minute not on 15m grid', () {
      const odd = TimeOfDay(hour: 9, minute: 7);
      final list = quarterHourSlotsIncluding(odd);
      expect(list.contains(odd), isTrue);
      expect(list.length, 24 * 4 + 1);
    });

    test('does not duplicate quarter slot', () {
      const onGrid = TimeOfDay(hour: 14, minute: 30);
      final list = quarterHourSlotsIncluding(onGrid);
      expect(list.where((t) => t.hour == 14 && t.minute == 30).length, 1);
      expect(list.length, 24 * 4);
    });

    test('sorted chronologically', () {
      final list = quarterHourSlotsIncluding(
        const TimeOfDay(hour: 23, minute: 59),
      );
      for (var i = 1; i < list.length; i++) {
        final a = list[i - 1].hour * 60 + list[i - 1].minute;
        final b = list[i].hour * 60 + list[i].minute;
        expect(a <= b, isTrue);
      }
    });
  });
}
