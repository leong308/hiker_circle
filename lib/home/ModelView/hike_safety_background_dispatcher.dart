import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/local_session_database.dart';
import '../../sos/Data/sos_alert_repository.dart';
import '../../sos/Model/sos_models.dart';

const _channel = MethodChannel('hiker_circle/hike_safety_background');

/// Runs in a headless Flutter engine owned by the Android safety service.
///
/// This is deliberately UI-free: it restores the signed-in session and local
/// contacts, durably queues the alert first, and then attempts cloud delivery.
Future<void> runHikeSafetyBackgroundDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'dispatchSafetyEvent') {
      throw MissingPluginException('Unknown safety background method.');
    }
    final arguments = Map<Object?, Object?>.from(
      call.arguments as Map? ?? const <Object?, Object?>{},
    );
    final eventId = arguments['eventId']?.toString().trim() ?? '';
    final expectedSessionId = arguments['sessionId']?.toString().trim() ?? '';
    if (eventId.isEmpty || expectedSessionId.isEmpty) {
      throw StateError('The native safety event is incomplete.');
    }

    final database = LocalSessionDatabase();
    final session = await database.loadSession();
    if (session == null) {
      throw StateError('No signed-in HikerCircle session is available.');
    }
    final activeHike = await database.loadActiveHikeSession(
      phoneNumber: session.phoneNumber,
    );
    if (activeHike == null || activeHike.sessionId != expectedSessionId) {
      throw StateError('The native event does not match the active hike.');
    }

    final contacts = await database.loadEmergencyContacts(
      phoneNumber: session.phoneNumber,
    );
    if (contacts.isEmpty) {
      throw StateError('No emergency contacts are saved on this device.');
    }

    final bootstrap = await FirebaseBootstrap.initialize();
    final triggeredAtMillis =
        (arguments['triggeredAtMillis'] as num?)?.toInt() ?? 0;
    final triggeredAt = triggeredAtMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(triggeredAtMillis, isUtc: true)
        : DateTime.now().toUtc();
    final latitude = (arguments['latitude'] as num?)?.toDouble();
    final longitude = (arguments['longitude'] as num?)?.toDouble();
    final accuracy = (arguments['accuracyMeters'] as num?)?.toDouble();
    final capturedAtMillis = (arguments['capturedAtMillis'] as num?)?.toInt();
    final capturedAt = capturedAtMillis == null || capturedAtMillis <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(capturedAtMillis, isUtc: true);
    final fixAge = capturedAt == null
        ? null
        : triggeredAt.difference(capturedAt);
    final fresh =
        fixAge != null &&
        fixAge >= const Duration(seconds: -5) &&
        fixAge <= const Duration(seconds: 30);
    final location =
        fresh &&
            latitude != null &&
            longitude != null &&
            latitude.isFinite &&
            longitude.isFinite &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude >= -180 &&
            longitude <= 180 &&
            accuracy != null &&
            accuracy.isFinite &&
            accuracy >= 0 &&
            accuracy <= 500
        ? SosTriggerLocation(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            capturedAt: capturedAt,
          )
        : null;
    final mode = arguments['kind'] == 'fall_stillness'
        ? SosAlertMode.fallStillness
        : SosAlertMode.prolongedStillness;

    final result =
        await SosAlertRepository(
          localDatabase: database,
          firebaseBootstrapResult: bootstrap,
        ).triggerAlert(
          session: session,
          mode: mode,
          triggeredAt: triggeredAt,
          triggerLocation: location,
          contacts: contacts,
          triggerSource: SosAlertTriggerSource.automaticDetection,
        );
    return <String, Object?>{
      'eventId': eventId,
      'sentCount': result.alert.sentCount,
      'contactCount': result.alert.contactCount,
      'queuedForRetry': result.queuedForRetry,
      'queuedAlertCount': result.queuedAlertCount,
    };
  });
  await _channel.invokeMethod<void>('dispatcherReady');
}
