import 'package:flutter/material.dart';

/// All 15-minute [TimeOfDay] slots in a day, plus [include] if not already present.
/// Used so [DropdownButtonFormField] value always exists in the item list.
List<TimeOfDay> quarterHourSlotsIncluding(TimeOfDay include) {
  final slots = <TimeOfDay>{};
  for (var h = 0; h < 24; h++) {
    for (final m in [0, 15, 30, 45]) {
      slots.add(TimeOfDay(hour: h, minute: m));
    }
  }
  slots.add(include);
  final sorted = slots.toList()
    ..sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );
  return sorted;
}
