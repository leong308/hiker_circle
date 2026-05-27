import 'package:flutter/material.dart';

import '../../authentication/View/phone_sign_in_page.dart';
import '../../home/View/hiker_home_page.dart';
import '../Data/session_repository.dart';
import '../ModelView/app_view_model.dart';

class HikerCircleApp extends StatefulWidget {
  const HikerCircleApp({super.key});

  @override
  State<HikerCircleApp> createState() => _HikerCircleAppState();
}

class _HikerCircleAppState extends State<HikerCircleApp> {
  late final AppViewModel _appViewModel;

  @override
  void initState() {
    super.initState();
    _appViewModel = AppViewModel(sessionRepository: SessionRepository());
    _appViewModel.addListener(_refresh);
  }

  @override
  void dispose() {
    _appViewModel.removeListener(_refresh);
    _appViewModel.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3F8F5E);
    const lightGreen = Color(0xFFEAF7EE);
    const greenLine = Color(0xFFCFE5D6);

    return MaterialApp(
      title: 'HikerCircle',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
          primary: green,
          secondary: lightGreen,
          primaryContainer: lightGreen,
          surface: Colors.white,
        ),
        cardColor: Colors.white,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: greenLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: greenLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: green, width: 1.5),
          ),
        ),
      ),
      home: _appViewModel.session == null
          ? PhoneSignInPage(onSignedIn: _appViewModel.completeSignIn)
          : HikerHomePage(
              session: _appViewModel.session!,
              onSignOut: _appViewModel.signOut,
            ),
    );
  }
}
