/// Allowed `billingRatePercent` values for employer-written entries (Firestore rules align).
const kAllowedBillingPercents = [50, 80, 100, 150, 200];

class TimeEntryValidationException implements Exception {
  TimeEntryValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

void assertValidBillingPercent(num? value) {
  if (value == null) return;
  final i = value is int ? value : value.round();
  if (!kAllowedBillingPercents.contains(i)) {
    throw TimeEntryValidationException(
      'billingRatePercent must be one of: ${kAllowedBillingPercents.join(', ')}.',
    );
  }
}

void assertClosedInterval(DateTime start, DateTime end) {
  if (!end.isAfter(start)) {
    throw TimeEntryValidationException('End time must be after start time.');
  }
}
