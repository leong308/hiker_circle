import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Bridges the durable native warning independently of fall detection and SOS controls.
class HikeArrivalSafetyService {
  /// Allows platform calls to be replaced by isolated fixtures.
  const HikeArrivalSafetyService({
    this.channel = const MethodChannel('hiker_circle/arrival_safety'),
  });
  final MethodChannel channel;

  /// Restores the confirmation popup when a native deadline event occurs in the foreground.
  void onChanged(Future<void> Function()? callback) =>
      channel.setMethodCallHandler(
        callback == null
            ? null
            : (call) async {
                if (call.method == 'onArrivalSafetyChanged') await callback();
              },
      );

  /// Persists the plan and schedules its spoken local notification before cloud arming.
  Future<Map<String, dynamic>?> configure(Map<String, dynamic> data) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'configure',
      data,
    );
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  /// Saves the hiker's explicit safe response locally before attempting any network request.
  Future<Map<String, dynamic>?> confirmSafe(
    String owner,
    String trackingKey,
  ) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'confirmSafe',
      {'owner': owner, 'trackingKey': trackingKey},
    );
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  /// Restores the pending confirmation even when local session restoration is delayed.
  Future<Map<String, dynamic>?> read(String owner) async {
    final result = await channel.invokeMapMethod<String, dynamic>('read', {
      'owner': owner,
    });
    return result == null ? null : Map<String, dynamic>.from(result);
  }

  /// Removes warning work when the active hike ends.
  Future<void> stop(String owner) =>
      channel.invokeMethod<void>('stop', {'owner': owner});
}

/// Uses authenticated cloud calls; destination, contacts and escalation time remain server-validated.
class HikeArrivalSafetyRepository {
  /// Accepts an optional Functions instance for isolated transport tests.
  const HikeArrivalSafetyRepository({this.functions});
  final FirebaseFunctions? functions;

  /// Returns the server's arming or delivery state using the existing signed-in account.
  Future<Map<String, dynamic>?> call(
    String action,
    Map<String, dynamic> data,
  ) async {
    // Update cloud: submit arrival safety action
    final response = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          action,
          options: HttpsCallableOptions(
            timeout: Duration(
              seconds: action == 'checkHikeArrivalSafety' ? 60 : 10,
            ),
          ),
        )
        .call<dynamic>(data);
    return response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : null;
  }
}
