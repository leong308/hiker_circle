// NearbySosEvent parses the limited location and timing data exposed for nearby emergencies.
import 'dart:math' as math;

import 'sos_models.dart';

/// Represents nearby sos event.
class NearbySosEvent {
  /// Creates nearby sos event.
  const NearbySosEvent({
    required this.ownerPhoneNumber,
    required this.eventKey,
    required this.deviceId,
    required this.receivedAt,
    required this.updatedAt,
    this.counter,
    this.rssi,
    this.location,
    this.detectorLocation,
  });

  static const Duration activeDuration = Duration(hours: 1);
  static const double activeRadiusMeters = 2000;

  final String ownerPhoneNumber;
  final String eventKey;
  final String deviceId;
  final int? counter;
  final int? rssi;
  final DateTime receivedAt;
  final DateTime updatedAt;
  final SosTriggerLocation? location;
  final SosTriggerLocation? detectorLocation;

  /// Returns has reported location.
  bool get hasReportedLocation => _isValidLocation(location);

  /// Computes age at.
  Duration ageAt(DateTime now) {
    final age = now.toUtc().difference(receivedAt.toUtc());
    return age.isNegative ? Duration.zero : age;
  }

  /// Computes distance meters from.
  double? distanceMetersFrom(SosTriggerLocation? phoneLocation) {
    final target = location;
    if (!_isValidLocation(target) || !_isValidLocation(phoneLocation)) {
      return null;
    }
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(phoneLocation!.latitude);
    final lat2 = _radians(target!.latitude);
    final deltaLat = _radians(target.latitude - phoneLocation.latitude);
    final deltaLon = _radians(target.longitude - phoneLocation.longitude);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final safeA = a.clamp(0.0, 1.0);
    final centralAngle = 2 * math.atan2(math.sqrt(safeA), math.sqrt(1 - safeA));
    return earthRadiusMeters * centralAngle;
  }

  /// Checks whether active at.
  bool isActiveAt({required DateTime now, SosTriggerLocation? phoneLocation}) {
    if (ageAt(now) > activeDuration) return false;
    final distance = distanceMetersFrom(phoneLocation);
    return distance == null || distance <= activeRadiusMeters;
  }

  /// Computes event key for.
  static String eventKeyFor({
    required String deviceId,
    required DateTime receivedAt,
    int? counter,
  }) {
    final normalizedDeviceId = deviceId.trim().isEmpty
        ? 'unknown'
        : deviceId.trim().toLowerCase();
    final eventId =
        counter ?? receivedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    return '$normalizedDeviceId:$eventId';
  }

  /// Checks whether valid location.
  static bool _isValidLocation(SosTriggerLocation? value) {
    return value != null &&
        value.latitude.isFinite &&
        value.longitude.isFinite &&
        value.latitude >= -90 &&
        value.latitude <= 90 &&
        value.longitude >= -180 &&
        value.longitude <= 180;
  }

  /// Computes radians.
  static double _radians(double degrees) => degrees * math.pi / 180;
}
