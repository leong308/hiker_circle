import 'hike_session_models.dart';
import 'location_update_interval.dart';

/// The hiker's choices for this session, independent of account-wide sharing.
class HikePreparationSharing {
  /// Creates hike preparation sharing.
  const HikePreparationSharing({required this.enabled, required this.interval});
  final bool enabled;
  final Duration interval;
  static const intervals = LocationUpdateInterval.options;

  /// Creates hike preparation sharing using from plan.
  factory HikePreparationSharing.fromPlan(PlannedHike plan) =>
      HikePreparationSharing(
        enabled: plan.liveLocationConfigured,
        interval: intervals.contains(plan.locationRecordingInterval)
            ? plan.locationRecordingInterval
            : HikeSessionDraft.defaultLocationRecordingInterval,
      );

  /// Creates from json.
  static HikePreparationSharing? fromJson(Object? value) {
    if (value is! Map ||
        value['enabled'] is! bool ||
        value['seconds'] is! int) {
      return null;
    }
    final interval = Duration(seconds: value['seconds'] as int);
    if (!intervals.contains(interval)) return null;
    return HikePreparationSharing(
      enabled: value['enabled'] as bool,
      interval: interval,
    );
  }

  /// Serializes this value as JSON.
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'seconds': interval.inSeconds,
  };

  /// Returns interval label.
  String get intervalLabel => LocationUpdateInterval.label(interval);
}
