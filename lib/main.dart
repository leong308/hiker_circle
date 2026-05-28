import 'package:flutter/material.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/View/hiker_circle_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseBootstrapResult = await FirebaseBootstrap.initialize();
  runApp(HikerCircleApp(firebaseBootstrapResult: firebaseBootstrapResult));
}
