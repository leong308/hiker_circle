// main initializes public configuration, Firebase, native background handlers and persisted app settings.
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/Data/app_settings_controller.dart';
import 'achievements/Model/achievement_catalog.dart';
import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';
import 'core/config/google_api_config.dart';
import 'core/services/device_notification_log_service.dart';
import 'firebase_options.dart';
import 'home/ModelView/hike_safety_background_dispatcher.dart';

@pragma('vm:entry-point')
/// Android invokes this entrypoint in a headless engine for persisted hike safety events.
Future<void> hikeSafetyBackgroundDispatcher() async {
  await runHikeSafetyBackgroundDispatcher();
}

@pragma('vm:entry-point')
/// Initialize Firebase in this isolate before recording the received FCM notification locally.
Future<void> hikerCircleFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Native startup installs App Check before headless Firebase calls.
  // Logging the received notification remains local-only.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await DeviceNotificationLogService.recordFcmMessage(
    message,
    source: 'fcm_background',
  );
  await DeviceNotificationLogService.presentBackgroundChat(message);
}

/// Finish Firebase and settings initialization before building the first themed screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['GPS Location Animation — Hamad khan'],
      await rootBundle.loadString('assets/animations/gps_location.LICENSE.txt'),
    );
  });
  await AchievementCatalog.load();
  final settings = AppSettingsController.instance;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Only the public Mapbox token is packaged; provider secrets stay in Firebase.
  await dotenv.load(fileName: '.env.public');
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

  // Resolve the saved override before the login page's first frame. With no
  // override, ThemeMode.system continues to follow platform brightness changes.
  await settings.ready;
  runApp(HikerCircleApp(firebaseBootstrapResult: firebaseBootstrapResult));
}
