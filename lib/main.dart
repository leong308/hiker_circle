import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';
import 'core/config/google_api_config.dart';
import 'core/services/device_notification_log_service.dart';
import 'firebase_options.dart';
import 'home/ModelView/hike_safety_background_dispatcher.dart';

@pragma('vm:entry-point')
Future<void> hikeSafetyBackgroundDispatcher() async {
  await runHikeSafetyBackgroundDispatcher();
}

@pragma('vm:entry-point')
Future<void> hikerCircleFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Logging an incoming message is local-only. Do not activate App Check from
  // the headless isolate: a locally signed release has no Activity channel
  // from which to read its development-only build flag.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await DeviceNotificationLogService.recordFcmMessage(
    message,
    source: 'fcm_background',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // `.env` is a declared Flutter asset, so the same mobile API configuration
  // is available in debug, profile, and release builds. Compile-time defines
  // remain the higher-priority option for CI/store builds.
  await dotenv.load(fileName: '.env');
  final token = GoogleApiConfig.mapboxAccessToken;
  if (token.isNotEmpty) {
    MapboxOptions.setAccessToken(token);
  }
  final firebaseBootstrapResult = await FirebaseBootstrap.initialize();
  if (firebaseBootstrapResult.isAvailable) {
    FirebaseMessaging.onBackgroundMessage(
      hikerCircleFirebaseMessagingBackgroundHandler,
    );
  }

  runApp(HikerCircleApp(firebaseBootstrapResult: firebaseBootstrapResult));
}
