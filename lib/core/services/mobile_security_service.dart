// MobileSecurityService binds login activation and revocation to the installation and current
// Firebase mobile session claim.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../../app/Data/local_session_database.dart';
import '../../authentication/Data/auth_flow_diagnostics.dart';

abstract final class MobileSecurityService {
  static const channel = MethodChannel('hiker_circle/security');

  static Future<Map<String, dynamic>> device() async {
    AuthFlowDiagnostics.event('local-installation-id', 'start');
    final id = await LocalSessionDatabase().loadOrCreateAppInstanceId();
    AuthFlowDiagnostics.event('local-installation-id', 'success');
    AuthFlowDiagnostics.event('native-device-info', 'start');
    final details = await channel.invokeMapMethod<String, dynamic>(
      'deviceInfo',
    );
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
  static Future<Map<String, dynamic>> prepareLogin() async {
    final deviceDetails = await device();
    AuthFlowDiagnostics.event('prepare-mobile-session-call', 'start');
    final result = await FirebaseFunctions.instance
        .httpsCallable('prepareMobileSession')
        .call({'device': deviceDetails});
    AuthFlowDiagnostics.event('prepare-mobile-session-call', 'success');
    return Map<String, dynamic>.from(result.data as Map);
  }

  // activateLogin confirms which previous mobile session may be replaced, preventing an
  // unconfirmed takeover.
  static Future<void> activateLogin(String expectedPreviousSessionId) async {
    await FirebaseFunctions.instance
        .httpsCallable('activateMobileSession')
        .call({'expectedPreviousSessionId': expectedPreviousSessionId});
  }

  static Future<String> currentSessionId() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
    return token?.claims?['mobileSessionId'] as String? ?? '';
  }

  static Future<void> endSession() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    await FirebaseFunctions.instance.httpsCallable('endMobileSession').call();
  }
}
