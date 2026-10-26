import 'hike_session_models.dart';
import 'location_update_interval.dart';

/// Only personal safety choices are restored; route, roster and packing stay current.
abstract final class HikeSafetyPreferences {
  static const responseOptions = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 5),
  ];
  static const restOptions = [
    Duration(minutes: 3),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];
  static const _fields = {
    'shareLiveLocation',
    'locationRecordingIntervalSeconds',
    'fallDetectionEnabled',
    'fallDetectionPreferenceVersion',
    'fallDetectionSettings',
    'pathDeviationEnabled',
    'pathDeviationDistanceMeters',
  };

  /// Creates from draft.
  static Map<String, dynamic> fromDraft(HikeSessionDraft draft) {
    final data = normalized(draft).toPersistence();
    return {for (final key in _fields) key: data[key]};
  }

  /// Applies to draft.
  static HikeSessionDraft applyToDraft(HikeSessionDraft draft, Object? saved) {
    if (saved is! Map) return normalized(draft);
    final parsed = HikeSessionDraft.fromPersistence({
      ...draft.toPersistence(),
      for (final key in _fields)
        if (saved.containsKey(key)) key: saved[key],
    });
    return normalized(
      draft.copyWith(
        shareLiveLocation: parsed.shareLiveLocation,
        locationRecordingInterval:
            LocationUpdateInterval.options.contains(
              parsed.locationRecordingInterval,
            )
            ? parsed.locationRecordingInterval
            : draft.locationRecordingInterval,
        fallDetectionEnabled: parsed.fallDetectionEnabled,
        fallDetectionSettings: parsed.fallDetectionSettings,
        pathDeviationEnabled:
            !draft.trail.isUnlisted && parsed.pathDeviationEnabled,
        pathDeviationDistanceMeters: parsed.pathDeviationDistanceMeters,
      ),
    );
  }

  /// Computes normalized.
  static HikeSessionDraft normalized(HikeSessionDraft draft) {
    final fall = draft.fallDetectionSettings;
    return draft.copyWith(
      pathDeviationEnabled:
          !draft.trail.isUnlisted && draft.pathDeviationEnabled,
      locationRecordingInterval: LocationUpdateInterval.normalize(
        draft.locationRecordingInterval,
      ),
      fallDetectionSettings: FallDetectionSettings(
        sensorSensitivity: fall.sensorSensitivity.clamp(1, 10),
        fallResponseDuration:
            responseOptions.contains(fall.fallResponseDuration)
            ? fall.fallResponseDuration
            : const Duration(seconds: 30),
        longestRestDuration: restOptions.contains(fall.longestRestDuration)
            ? fall.longestRestDuration
            : const Duration(minutes: 3),
      ),
    );
  }
}
