import 'package:equatable/equatable.dart';

enum DateRangePreset { thisMonth, previousMonth, custom }

class ReportPeriod extends Equatable {
  const ReportPeriod({required this.start, required this.endInclusive});

  final DateTime start;
  /// End of day inclusive for queries (23:59:59.999 same calendar day).
  final DateTime endInclusive;

  @override
  List<Object?> get props => [start, endInclusive];
}

ReportPeriod monthContaining(DateTime day) {
  final start = DateTime(day.year, day.month);
  final end = DateTime(day.year, day.month + 1, 0, 23, 59, 59, 999);
  return ReportPeriod(start: start, endInclusive: end);
}

ReportPeriod previousMonthFrom(DateTime reference) {
  final firstThisMonth = DateTime(reference.year, reference.month);
  final lastPrev = firstThisMonth.subtract(const Duration(days: 1));
  return monthContaining(lastPrev);
}
