part of '../hiker_circle_app_feature.dart';

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

/// Builds snack bar theme.
SnackBarThemeData _buildSnackBarTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final foreground = isDark ? const Color(0xFFEAF4EE) : const Color(0xFF183122);
  return SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: isDark ? const Color(0xFF17221B) : const Color(0xFFF7FBF8),
    contentTextStyle: TextStyle(
      color: foreground,
      fontFamily: _appFontFamily,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    actionTextColor: isDark ? const Color(0xFF7AD69C) : const Color(0xFF3F8F5E),
    disabledActionTextColor: foreground.withValues(alpha: 0.5),
    closeIconColor: foreground.withValues(alpha: 0.72),
    showCloseIcon: true,
    elevation: 10,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: isDark ? const Color(0xFF365442) : const Color(0xFFCFE5D6),
      ),
    ),
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  );
}

/// Own the root navigator, account lifecycle and app-wide presentation settings.
class HikerCircleApp extends StatefulWidget {
  /// Creates hiker circle app.
  const HikerCircleApp({
    super.key,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final FirebaseBootstrapResult firebaseBootstrapResult;

  /// Creates the presentation state for this widget.
  @override
  State<HikerCircleApp> createState() => _HikerCircleAppState();
}

/// Manages the hiker circle app presentation and lifecycle.
class _HikerCircleAppState extends State<HikerCircleApp> {
  late final _HikerCircleAppStateViewModel _screenModel;

  /// Returns app view model.
  AppViewModel get _appViewModel => _screenModel.stateAppViewModel;

  /// Updates app view model.
  set _appViewModel(AppViewModel value) =>
      _screenModel.stateAppViewModel = value;

  /// Returns settings controller.
  AppSettingsController get _settingsController =>
      _screenModel.stateSettingsController;

  /// Returns checking launch lock.
  bool get _checkingLaunchLock => _screenModel.stateCheckingLaunchLock;

  /// Returns launch locked.
  bool get _launchLocked => _screenModel.stateLaunchLocked;

  /// Updates launch locked.
  set _launchLocked(bool value) => _screenModel.stateLaunchLocked = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  String? _pendingPlatformDeepLink;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _showingSecurityNotice = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikerCircleAppStateViewModel()
      ..addListener(_renderScreenModel);

    _appViewModel = AppViewModel(
      firebaseAvailable: widget.firebaseBootstrapResult.isAvailable,
      sessionRepository: SessionRepository(
        firebaseUserRepository: FirebaseUserRepository(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
    _appViewModel.addListener(_refresh);
    _settingsController.addListener(_refresh);
    _initializeLaunch();
  }

  /// Delegates initialize launch to the ViewModel.
  Future<void> _initializeLaunch() => _screenModel.commandInitializeLaunch();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _appViewModel.removeListener(_refresh);
    _settingsController.removeListener(_refresh);
    _appViewModel.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Refreshes.
  void _refresh() {
    if (!mounted) return;
    setState(() {
      if (_appViewModel.session == null) {
        _launchLocked = false;
      }
    });
    final message = _appViewModel.securityMessage;
    if (message != null && !_showingSecurityNotice) {
      _showingSecurityNotice = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final navigator = _navigatorKey.currentState;
        final context = _navigatorKey.currentContext;
        if (navigator == null || context == null) {
          _showingSecurityNotice = false;
          return;
        }
        _appViewModel.acknowledgeSecurityMessage();
        navigator.popUntil((route) => route.isFirst);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => SessionEndedDialog(message: message),
        );
        _showingSecurityNotice = false;
      });
    }
  }

  /// Builds root.
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
    if (_checkingLaunchLock) return const _StartupPage();
    if (_launchLocked && _appViewModel.session != null) {
      return PrivateScreenUnlockPage(
        key: ValueKey('unlock:${_appViewModel.session!.phoneNumber}'),
        onUnlocked: () => setState(() => _launchLocked = false),
        onSignOut: () {
          setState(() => _launchLocked = false);
          _appViewModel.signOut();
        },
      );
    }
    return _appViewModel.isInitializing
        ? const _StartupPage()
        : _appViewModel.session == null
        ? PhoneSignInPage(onSignedIn: _appViewModel.completeSignIn)
        : _appViewModel.session!.requiresOnboarding
        ? FirstTimeOnboardingFlow(
            key: ValueKey('onboarding:${_appViewModel.session!.phoneNumber}'),
            session: _appViewModel.session!,
            onCompleted: _appViewModel.completeOnboarding,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          )
        : HikerHomePage(
            key: ValueKey('home:${_appViewModel.session!.phoneNumber}'),
            session: _appViewModel.session!,
            onSignOut: _appViewModel.signOut,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
            initialDeepLink: platformDeepLink,
          );
  }

  /// Computes deep link from platform route.
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

  /// Computes root route.
  Route<void> _rootRoute({String? initialDeepLink, RouteSettings? settings}) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) => _buildRoot(initialDeepLink: initialDeepLink),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return BetterFeedback(
      feedbackBuilder: (context, onSubmit, scrollController) =>
          HikerFeedbackCaptureForm(
            onSubmit: onSubmit,
            scrollController: scrollController,
          ),
      themeMode: _settingsController.themeMode,
      theme: FeedbackThemeData(
        background: const Color(0xFFEAF7EE),
        feedbackSheetColor: Colors.white,
        activeFeedbackModeColor: _appGreen,
        colorScheme: ColorScheme.fromSeed(seedColor: _appGreen),
      ),
      darkTheme: FeedbackThemeData(
        background: const Color(0xFF0C120F),
        feedbackSheetColor: const Color(0xFF183625),
        activeFeedbackModeColor: const Color(0xFF7AD69C),
        bottomSheetDescriptionStyle: const TextStyle(color: Colors.white),
        bottomSheetTextInputStyle: const TextStyle(color: Colors.white),
        colorScheme: ColorScheme.fromSeed(
          seedColor: _appGreen,
          brightness: Brightness.dark,
        ),
      ),
      child: MaterialApp(
        title: 'HikerCircle',
        navigatorKey: _navigatorKey,
        navigatorObservers: [passwordRouteObserver],
        debugShowCheckedModeBanner: false,
        themeMode: _settingsController.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: _appFontFamily,
          appBarTheme: PageHeaderStyle.appBarTheme,
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
          snackBarTheme: _buildSnackBarTheme(Brightness.light),
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
          appBarTheme: PageHeaderStyle.appBarTheme,
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
          snackBarTheme: _buildSnackBarTheme(Brightness.dark),
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
              borderSide: const BorderSide(
                color: Color(0xFF7AD69C),
                width: 1.5,
              ),
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
          return _rootRoute(
            initialDeepLink: initialDeepLink,
            settings: settings,
          );
        },
        onUnknownRoute: (settings) {
          final routeName = settings.name;
          final uri = routeName == null ? null : Uri.tryParse(routeName);
          final routeLabel = uri == null
              ? routeName
              : '${uri.scheme.isEmpty ? '' : '${uri.scheme}://'}'
                    '${uri.host}${uri.path}';
          debugPrint(
            'HikerCircle ignored unsupported navigation route: $routeLabel',
          );
          return _rootRoute(
            settings: const RouteSettings(name: Navigator.defaultRouteName),
          );
        },
      ),
    );
  }
}

/// Present the startup state while bootstrap and account restoration determine the next route.
class _StartupPage extends StatelessWidget {
  /// Creates startup page.
  const _StartupPage();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: HikerCircleLoadingView(
          message: 'Getting HikerCircle ready…',
          detail: 'Loading your account and saved hike information.',
        ),
      ),
    );
  }
}
