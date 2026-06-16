import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final firebaseBootstrapResult = await FirebaseBootstrap.initialize();
  runApp(HikerCircleApp(firebaseBootstrapResult: firebaseBootstrapResult));
}
