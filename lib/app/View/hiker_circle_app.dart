import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../authentication/View/phone_sign_in_page.dart';
import '../../home/View/hiker_home_page.dart';
import '../../onboarding/View/first_time_onboarding_flow.dart';
import '../Data/app_settings_controller.dart';
import '../Data/firebase_bootstrap.dart';
import '../Data/firebase_user_repository.dart';
import '../Data/session_repository.dart';
import '../ModelView/app_view_model.dart';

const _appFontFamily = 'Inter';
const _appGreen = Color(0xFF3F8F5E);
const _appLightGreen = Color(0xFFEAF7EE);
const _appGreenLine = Color(0xFFCFE5D6);
const _cupertinoBodyTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 17,
  letterSpacing: 0,
  color: CupertinoColors.label,
  decoration: TextDecoration.none,
);
const _cupertinoActionTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 17,
  letterSpacing: 0,
  color: _appGreen,
  decoration: TextDecoration.none,
);
const _cupertinoSmallActionTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 15,
  letterSpacing: 0,
  color: _appGreen,
  decoration: TextDecoration.none,
);
const _cupertinoTabTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 10,
  fontWeight: FontWeight.w500,
  letterSpacing: 0,
  color: CupertinoColors.inactiveGray,
  decoration: TextDecoration.none,
);
const _cupertinoTitleTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 17,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
  color: CupertinoColors.label,
  decoration: TextDecoration.none,
);
const _cupertinoLargeTitleTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 34,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  color: CupertinoColors.label,
  decoration: TextDecoration.none,
);
const _cupertinoPickerTextStyle = TextStyle(
  inherit: false,
  fontFamily: _appFontFamily,
  fontSize: 21,
  letterSpacing: 0,
  color: CupertinoColors.label,
  decoration: TextDecoration.none,
);

class HikerCircleApp extends StatefulWidget {
  const HikerCircleApp({
    super.key,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<HikerCircleApp> createState() => _HikerCircleAppState();
}

class _HikerCircleAppState extends State<HikerCircleApp> {
  late final AppViewModel _appViewModel;
  final AppSettingsController _settingsController =
      AppSettingsController.instance;
  String? _pendingPlatformDeepLink;

  @override
  void initState() {
    super.initState();
    _appViewModel = AppViewModel(
      sessionRepository: SessionRepository(
        firebaseUserRepository: FirebaseUserRepository(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
    _appViewModel.addListener(_refresh);
    _settingsController.addListener(_refresh);
    _appViewModel.initialize();
  }

  @override
  void dispose() {
    _appViewModel.removeListener(_refresh);
    _settingsController.removeListener(_refresh);
    _appViewModel.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  Widget _buildRoot({String? initialDeepLink}) {
    final platformDeepLink = initialDeepLink ?? _pendingPlatformDeepLink;
    if (platformDeepLink != null &&
        !_appViewModel.isInitializing &&
        _appViewModel.session != null &&
        !_appViewModel.session!.requiresOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingPlatformDeepLink == platformDeepLink) {
          _pendingPlatformDeepLink = null;
        }
      });
    }
    return _appViewModel.isInitializing
        ? const _StartupPage()
        : _appViewModel.session == null
        ? PhoneSignInPage(onSignedIn: _appViewModel.completeSignIn)
        : _appViewModel.session!.requiresOnboarding
        ? FirstTimeOnboardingFlow(
            session: _appViewModel.session!,
            onCompleted: _appViewModel.completeOnboarding,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          )
        : HikerHomePage(
            session: _appViewModel.session!,
            onSignOut: _appViewModel.signOut,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
            initialDeepLink: platformDeepLink,
          );
  }

  String? _deepLinkFromPlatformRoute(String? routeName) {
    if (routeName == null || routeName == Navigator.defaultRouteName) {
      return null;
    }
    final uri = Uri.tryParse(routeName);
    if (uri == null) {
      return null;
    }
    if (uri.scheme == 'hikercircle') {
      return uri.toString();
    }
    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    if (path == '/help' ||
        path == '/manual' ||
        path == '/instant' ||
        path == '/medical' ||
        path == '/duress' ||
        path == '/paired' ||
        path == '/nearby-button' ||
        path == '/nearby-button-location') {
      return Uri(
        scheme: 'hikercircle',
        host: 'sos',
        path: path,
        queryParameters: uri.queryParameters.isEmpty
            ? null
            : uri.queryParameters,
      ).toString();
    }
    return null;
  }

  Route<void> _rootRoute({String? initialDeepLink, RouteSettings? settings}) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => _buildRoot(initialDeepLink: initialDeepLink),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HikerCircle',
      debugShowCheckedModeBanner: false,
      themeMode: _settingsController.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: _appFontFamily,
        cupertinoOverrideTheme: const NoDefaultCupertinoThemeData(
          primaryColor: _appGreen,
          primaryContrastingColor: Colors.white,
          scaffoldBackgroundColor: Colors.white,
          textTheme: CupertinoTextThemeData(
            primaryColor: _appGreen,
            textStyle: _cupertinoBodyTextStyle,
            actionTextStyle: _cupertinoActionTextStyle,
            actionSmallTextStyle: _cupertinoSmallActionTextStyle,
            tabLabelTextStyle: _cupertinoTabTextStyle,
            navTitleTextStyle: _cupertinoTitleTextStyle,
            navLargeTitleTextStyle: _cupertinoLargeTitleTextStyle,
            navActionTextStyle: _cupertinoActionTextStyle,
            pickerTextStyle: _cupertinoPickerTextStyle,
            dateTimePickerTextStyle: _cupertinoPickerTextStyle,
          ),
        ),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _appGreen,
          brightness: Brightness.light,
          primary: _appGreen,
          secondary: _appLightGreen,
          primaryContainer: _appLightGreen,
          surface: Colors.white,
        ),
        cardColor: Colors.white,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _appGreenLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _appGreenLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _appGreen, width: 1.5),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: _appFontFamily,
        cupertinoOverrideTheme: const NoDefaultCupertinoThemeData(
          brightness: Brightness.dark,
          primaryColor: Color(0xFF7AD69C),
          primaryContrastingColor: Color(0xFF07100A),
          scaffoldBackgroundColor: Color(0xFF0C120F),
        ),
        scaffoldBackgroundColor: const Color(0xFF0C120F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: _appGreen,
          brightness: Brightness.dark,
          primary: const Color(0xFF7AD69C),
          secondary: const Color(0xFF9FDDB2),
          primaryContainer: const Color(0xFF183625),
          secondaryContainer: const Color(0xFF1B2E23),
          surface: const Color(0xFF141C17),
          surfaceContainerHighest: const Color(0xFF1B261F),
          outline: const Color(0xFF2B3A31),
        ),
        cardColor: const Color(0xFF141C17),
        dividerColor: const Color(0xFF2B3A31),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111915),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF294535)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF294535)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF7AD69C), width: 1.5),
          ),
        ),
      ),
      onGenerateInitialRoutes: (initialRouteName) {
        final initialDeepLink = _deepLinkFromPlatformRoute(initialRouteName);
        _pendingPlatformDeepLink = initialDeepLink;
        return [
          _rootRoute(
            initialDeepLink: initialDeepLink,
            settings: const RouteSettings(name: Navigator.defaultRouteName),
          ),
        ];
      },
      onGenerateRoute: (settings) {
        final initialDeepLink = _deepLinkFromPlatformRoute(settings.name);
        if (initialDeepLink == null) {
          return null;
        }
        return _rootRoute(initialDeepLink: initialDeepLink, settings: settings);
      },
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
