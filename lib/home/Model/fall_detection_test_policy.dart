import 'package:flutter/foundation.dart';
import 'hike_session_models.dart';

/// Return the native trigger level for the selected sensitivity.
double fallTestImpactThreshold(double sensitivity, {bool? ios}) {
  final settings = FallDetectionSettings(sensorSensitivity: sensitivity);
  return (ios ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS))
      ? settings.impactAccelerationThreshold
      : settings.directImpactAccelerationThreshold;
}
