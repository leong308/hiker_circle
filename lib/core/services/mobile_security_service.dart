// MobileSecurityService binds login activation and revocation to the installation and current
// Firebase mobile session claim.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../../app/Data/local_session_database.dart';
import '../../authentication/Data/auth_flow_diagnostics.dart';

/// Represents mobile security service.
abstract final class MobileSecurityService {
  static const channel = MethodChannel('hiker_circle/security');

  /// Computes device.
  static Future<Map<String, dynamic>> device() async {
    AuthFlowDiagnostics.event('local-installation-id', 'start');
    final String id;
    try {
      id = await LocalSessionDatabase().loadOrCreateAppInstanceId();
    } catch (error) {
      AuthFlowDiagnostics.event(
        'local-installation-id',
        'failure',
        error: error,
      );
      rethrow;
    }
    AuthFlowDiagnostics.event('local-installation-id', 'success');
    AuthFlowDiagnostics.event('native-device-info', 'start');
    final Map<String, dynamic>? details;
    try {
      details = await channel.invokeMapMethod<String, dynamic>('deviceInfo');
    } catch (error) {
      AuthFlowDiagnostics.event('native-device-info', 'failure', error: error);
      rethrow;
    }
    AuthFlowDiagnostics.event('native-device-info', 'success');
    return <String, dynamic>{
      ...?details,
      'name':
          '${details?['name'] ?? 'Phone'} • ${id.substring(id.length - 6).toUpperCase()}',
      'appInstanceId': id,
    };
  }

  // prepareLogin requests the server-side login decision for the current installation before
  // activation.
  /// Prepares login.
  static Future<Map<String, dynamic>> prepareLogin() async {
    final deviceDetails = await device();
    AuthFlowDiagnostics.event('prepare-mobile-session-call', 'start');
    // Update cloud: prepare mobile login session
    final result = await FirebaseFunctions.instance
        .httpsCallable('prepareMobileSession')
        .call({'device': deviceDetails});
    AuthFlowDiagnostics.event('prepare-mobile-session-call', 'success');
    return Map<String, dynamic>.from(result.data as Map);
  }

  // activateLogin confirms which previous mobile session may be replaced, preventing an
  // unconfirmed takeover.
  /// Computes activate login.
  static Future<void> activateLogin(String expectedPreviousSessionId) async {
    // Update cloud: activate mobile session
    await FirebaseFunctions.instance
        .httpsCallable('activateMobileSession')
        .call({'expectedPreviousSessionId': expectedPreviousSessionId});
  }

  /// Computes current session id.
  static Future<String> currentSessionId() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
    return token?.claims?['mobileSessionId'] as String? ?? '';
  }

  /// Ends session.
  static Future<void> endSession() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    // Update cloud: end mobile session
    await FirebaseFunctions.instance.httpsCallable('endMobileSession').call();
  }
}
