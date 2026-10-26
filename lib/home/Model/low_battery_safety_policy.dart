import '../../app/Data/app_settings_controller.dart';
import '../Data/location_update_interval_controller.dart';
import 'hike_session_models.dart';
import 'location_update_interval.dart';

/// Temporary state belongs to the active hike and its durable snapshot.
/// Exactly 30% keeps the current mode; recovery requires a reading above 30%.
ActiveHikeSession applyLowBatterySafety(ActiveHikeSession hike, int battery) {
  if (battery < 0 || battery > 100) return hike;
  var updated = hike.copyWith(batteryLevel: battery);
  if (hike.batterySafetyAdjusted) {
    // Migrate an already-running hike from the old one-way adjustment.
    final originalInterval = _originalInterval(hike);
    final originalSensitivity = _originalSensitivity(hike);
    if (battery > 30) {
      return updated.copyWith(
        batterySafetyAdjusted: false,
        batterySafetyRevision: hike.batterySafetyRevision + 1,
        clearBatterySafetyOriginals: true,
        draft: _withSettings(hike.draft, originalInterval, originalSensitivity),
      );
    }
    if (hike.batteryOriginalFootprintIntervalSeconds == null ||
        hike.batteryOriginalSensorSensitivity == null) {
      updated = updated.copyWith(
        batterySafetyRevision: hike.batterySafetyRevision + 1,
        batteryOriginalFootprintIntervalSeconds: originalInterval.inSeconds,
        batteryOriginalSensorSensitivity: originalSensitivity,
      );
    }
    return updated;
  }
  if (battery >= 30) return updated;
  return updated.copyWith(
    batterySafetyAdjusted: true,
    batterySafetyRevision: hike.batterySafetyRevision + 1,
    batteryOriginalFootprintIntervalSeconds:
        hike.draft.locationRecordingInterval.inSeconds,
    batteryOriginalSensorSensitivity:
        hike.draft.fallDetectionSettings.sensorSensitivity,
    draft: _withSettings(hike.draft, const Duration(minutes: 1), 5),
  );
}

/// A newer native revision may describe entry OR recovery while Flutter was
/// stopped. Never overwrite it with an older UI snapshot.
ActiveHikeSession reconcileNativeBatterySafety(
  ActiveHikeSession hike,
  Map<String, dynamic>? state,
) {
  if (state == null || state['sessionId'] != hike.sessionId) return hike;
  final revision = state['batterySafetyRevision'];
  final version = revision is num && revision.isFinite ? revision.toInt() : 0;
  final active = state['batterySafetyAdjusted'] == true;
  final legacyEntry =
      version == 0 &&
      hike.batterySafetyRevision == 0 &&
      active &&
      !hike.batterySafetyAdjusted;
  if (version <= hike.batterySafetyRevision && !legacyEntry) return hike;
  final interval = state['intervalSeconds'];
  final sensitivity = state['sensorSensitivity'];
  if (interval is! num ||
      !interval.isFinite ||
      !LocationUpdateInterval.options.contains(
        Duration(seconds: interval.toInt()),
      ) ||
      sensitivity is! num ||
      !sensitivity.isFinite ||
      sensitivity < 1 ||
      sensitivity > 10) {
    return hike;
  }
  final originalInterval = state['batteryOriginalFootprintIntervalSeconds'];
  final originalSensitivity = state['batteryOriginalSensorSensitivity'];
  return hike.copyWith(
    batterySafetyAdjusted: active,
    batterySafetyRevision: version,
    clearBatterySafetyOriginals: !active,
    batteryOriginalFootprintIntervalSeconds:
        active && originalInterval is num && originalInterval.isFinite
        ? originalInterval.toInt()
        : null,
    batteryOriginalSensorSensitivity:
        active && originalSensitivity is num && originalSensitivity.isFinite
        ? originalSensitivity.toDouble()
        : null,
    draft: _withSettings(
      hike.draft,
      Duration(seconds: interval.toInt()),
      sensitivity.toDouble(),
    ),
  );
}

/// Computes original interval.
Duration _originalInterval(ActiveHikeSession hike) {
  final value = hike.batteryOriginalFootprintIntervalSeconds;
  return value != null &&
          LocationUpdateInterval.options.contains(Duration(seconds: value))
      ? Duration(seconds: value)
      : LocationUpdateIntervalController.instance.preferredInterval;
}

/// Computes original sensitivity.
double _originalSensitivity(ActiveHikeSession hike) {
  final value = hike.batteryOriginalSensorSensitivity;
  return value != null && value.isFinite && value >= 1 && value <= 10
      ? value
      : AppSettingsController.instance.fallSensorSensitivity;
}

/// Applies settings.
HikeSessionDraft _withSettings(
  HikeSessionDraft draft,
  Duration interval,
  double sensitivity,
) => draft.copyWith(
  locationRecordingInterval: interval,
  fallDetectionSettings: FallDetectionSettings(
    sensorSensitivity: sensitivity,
    fallResponseDuration: draft.fallDetectionSettings.fallResponseDuration,
    longestRestDuration: draft.fallDetectionSettings.longestRestDuration,
  ),
);
