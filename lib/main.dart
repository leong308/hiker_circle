import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';
import 'core/services/device_notification_log_service.dart';

@pragma('vm:entry-point')
Future<void> hikerCircleFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseBootstrapResult = await FirebaseBootstrap.initialize();
  if (!firebaseBootstrapResult.isAvailable) {
    return;
  }
  await DeviceNotificationLogService.recordFcmMessage(
    message,
    source: 'fcm_background',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await dotenv.load(fileName: '.env');
  final token = dotenv.env['MAPBOX_ACCESS_TOKEN']?.trim();
  if (token != null && token.isNotEmpty) {
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
