import 'package:flutter/services.dart';

import '../Model/hike_session_models.dart';

class ActiveHikeLiveStatusService {
  const ActiveHikeLiveStatusService();

  static const MethodChannel _channel = MethodChannel(
    'hiker_circle/active_hike_live_status',
  );

  Future<void> startOrUpdate(ActiveHikeSession activeHike) async {
    try {
      await _channel.invokeMethod<void>(
        'startOrUpdateActiveHikeLiveStatus',
        _activeHikeToPlatformMap(activeHike),
      );
    } on MissingPluginException {
      // iOS requires a WidgetKit/ActivityKit extension target before this can
      // be implemented natively. Android handles this channel in MainActivity.
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopActiveHikeLiveStatus');
    } on MissingPluginException {
      // Optional platform surface.
    }
  }

  Map<String, Object?> _activeHikeToPlatformMap(ActiveHikeSession activeHike) {
    return {
      'sessionId': activeHike.sessionId,
      'trailName': activeHike.trail.name,
      'startedAtMillis': activeHike.startedAt.millisecondsSinceEpoch,
      'expectedReturnAtMillis':
          activeHike.draft.expectedReturnTime.millisecondsSinceEpoch,
      'checkIns': activeHike.checkIns,
      'manualPins': activeHike.manualPins,
      'queuedUpdates': activeHike.queuedUpdates,
      'batteryLevel': activeHike.batteryLevel,
    };
  }
}
