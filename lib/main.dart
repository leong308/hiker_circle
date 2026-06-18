import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final token = dotenv.env['MAPBOX_ACCESS_TOKEN']?.trim();
  if (token != null && token.isNotEmpty) {
    MapboxOptions.setAccessToken(token);
  }
  final firebaseBootstrapResult = await FirebaseBootstrap.initialize();

  runApp(HikerCircleApp(firebaseBootstrapResult: firebaseBootstrapResult));
}
