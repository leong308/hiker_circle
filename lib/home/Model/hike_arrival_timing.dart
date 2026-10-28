import 'hike_session_models.dart';

/// Keeps the calculated earliest arrival and the hiker's latest-arrival allowance together.
abstract final class HikeArrivalTiming {
  static const maximumHikeDuration = Duration(days: 7);

  /// Reuses a valid planned duration, falling back to the trail estimate.
  static Duration plannedDuration(HikeSessionDraft draft) {
    final duration = draft.expectedArrivalTime.difference(draft.departureTime);
    return duration > Duration.zero
        ? duration
        : Duration(
            minutes: draft.trail.estimatedDurationMinutes > 0
                ? draft.trail.estimatedDurationMinutes
                : 1,
          );
  }

  /// Retains the hiker's allowance when the departure or estimated duration changes.
  static HikeSessionDraft retime(
    HikeSessionDraft draft, {
    required DateTime departure,
    Duration? duration,
  }) {
    final earliest = departure.add(duration ?? plannedDuration(draft));
    final allowance = draft.expectedReturnTime.difference(
      draft.expectedArrivalTime,
    );
    final latest = earliest.add(
      allowance.isNegative ? Duration.zero : allowance,
    );
    final maximum = departure.add(maximumHikeDuration);
    return draft.copyWith(
      departureTime: departure,
      expectedArrivalTime: earliest,
      expectedReturnTime: latest.isAfter(maximum) && !earliest.isAfter(maximum)
          ? maximum
          : latest,
    );
  }

  /// Rounds up because a minute picker cannot select fractional minutes.
  static DateTime minimumLatestArrival(HikeSessionDraft draft) {
    final earliest = draft.expectedArrivalTime;
    final minute = earliest.subtract(
      Duration(
        seconds: earliest.second,
        milliseconds: earliest.millisecond,
        microseconds: earliest.microsecond,
      ),
    );
    return minute.isBefore(earliest)
        ? minute.add(const Duration(minutes: 1))
        : minute;
  }

  /// Matches the existing server limit for a hike's complete planning window.
  static DateTime maximumLatestArrival(HikeSessionDraft draft) =>
      draft.departureTime.add(maximumHikeDuration);

  /// Validates the editable latest arrival without changing the calculated earliest arrival.
  static HikeSessionDraft withLatestArrival(
    HikeSessionDraft draft,
    DateTime latest,
  ) {
    if (latest.isBefore(draft.expectedArrivalTime) ||
        latest.isAfter(maximumLatestArrival(draft))) {
      throw ArgumentError.value(
        latest,
        'latest',
        'Choose an arrival within the hike planning window.',
      );
    }
    return draft.copyWith(expectedReturnTime: latest);
  }
}
