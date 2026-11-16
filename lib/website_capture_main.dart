// Temporary, isolated device-capture entry point for the website refresh.
// Build only with HC_CAPTURE_ONLY=1 so Android uses the separate .showcase app.
// Production widgets below render local demonstration state. This entry point
// never initializes Firebase, signs in, creates a real share or sends an alert.
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'app/Data/firebase_bootstrap.dart';
import 'app/Model/app_session.dart';
import 'authentication/Data/privacy_consent_repository.dart';
import 'authentication/Model/privacy_consent_receipt.dart';
import 'authentication/signup_privacy_consent_feature.dart';
import 'core/services/emergency_number_service.dart';
import 'core/config/google_api_config.dart';
import 'core/services/network_reachability_service.dart';
import 'core/widgets/page_header_style.dart';
import 'home/View/first_aid_guide_page.dart';
import 'home/View/gears_required_page.dart';
import 'me/Data/account_deletion_service.dart';
import 'me/Data/live_location_sharing_service.dart';
import 'me/Model/live_location_models.dart';
import 'me/View/account_deletion_dialog.dart';
import 'me/View/disclaimer_page.dart';
import 'me/View/help_center_page.dart';
import 'me/View/location_sharing_page.dart';
import 'navigation/View/hiker_bottom_nav_bar.dart';
import 'showcase_safety_main.dart' as safety;
import 'sos/Model/sos_models.dart';
import 'sos/View/sos_page.dart';
import 'sos/View/sos_triggered_page.dart';
import 'website_capture_product_pages.dart';
import 'website_capture_extra_pages.dart';

const _offline = FirebaseBootstrapResult.unavailable('Local demonstration');
const _demoPhone = '+10000000000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only the already-packaged public map token is loaded. Native map tiles
  // render the fictional route coordinates; all Dart HTTP remains blocked.
  await dotenv.load(fileName: '.env.public');
  final mapToken = GoogleApiConfig.mapboxAccessToken;
  if (mapToken.startsWith('pk.')) MapboxOptions.setAccessToken(mapToken);
  HttpOverrides.global = _NoCaptureNetwork();
  runApp(const WebsiteCaptureApp());
}

// Any accidentally introduced Dart HTTP request fails before opening a socket.
class _NoCaptureNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network is disabled in the isolated website capture.');
}

class WebsiteCaptureApp extends StatefulWidget {
  const WebsiteCaptureApp({super.key});

  @override
  State<WebsiteCaptureApp> createState() => _WebsiteCaptureAppState();
}

class _WebsiteCaptureAppState extends State<WebsiteCaptureApp> {
  static const _links = MethodChannel('hiker_circle/deeplinks');
  final _navigator = GlobalKey<NavigatorState>();
  late final Map<String, WidgetBuilder> _pages = {
    ...websiteCaptureProductPages(),
    ...websiteCaptureExtraPages(),
    'help': (_) => const HelpCenterPage(),
    'basics': (_) => const HikeBasicsPage(),
    'first-aid': (_) => const FirstAidGuidePage(
      emergencyLatitude: 5.4141,
      emergencyLongitude: 100.3288,
      emergencyNumberResolver: _DemoEmergencyNumber(),
    ),
    'gear': (_) => const GearsRequiredPage(),
    'disclaimer': (_) => const DisclaimerPage(),
    'sharing-off': (_) => _SharingCapture(active: false),
    'sharing-on': (_) => _SharingCapture(active: true),
    'signup-privacy': (_) => const _DialogCapture(privacy: true),
    'account-closure': (_) => const _DialogCapture(privacy: false),
    'sos': (_) => const _SosCapture(),
    'sos-countdown': (_) => const _SosCapture(countdown: true),
    'sos-duress': (context) => SosTriggeredPage(
      mode: SosAlertMode.duress,
      statusText: 'Alert submitted for your 3 emergency contacts.',
      detailsText: 'Local demonstration · no messages were sent.',
      alarmActive: false,
      onSlideToCancel: () async => _open('sos'),
    ),
    'sos-triggered': (context) => SosTriggeredPage(
      mode: SosAlertMode.manual,
      statusText: 'Alert submitted for your 3 emergency contacts.',
      detailsText: 'Local demonstration · no messages were sent.',
      alarmActive: false,
      onSlideToCancel: () async => _open('sos'),
    ),
  };

  @override
  void initState() {
    super.initState();
    _links.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') _openLink('${call.arguments}');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await _links.invokeMethod<String>(
        'consumeInitialDeepLink',
      );
      if (!mounted) return;
      if (initial != null) _openLink(initial);
    });
  }

  void _openLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    final name =
        uri.queryParameters['screen'] ??
        (uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last);
    _open(name);
  }

  void _open(String name) {
    final builder = _pages[name];
    if (!mounted || builder == null) return;
    _navigator.currentState?.pushAndRemoveUntil<void>(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: '/capture/$name'),
        pageBuilder: (context, _, _) => builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    theme: _captureDarkTheme(),
    home: Builder(
      builder: (context) =>
          _pages[const String.fromEnvironment(
            'WEBSITE_CAPTURE_SCREEN',
            defaultValue: 'help',
          )]!(context),
    ),
  );
}

// The current production dark-theme values, copied from HikerCircleApp.
ThemeData _captureDarkTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Inter',
  appBarTheme: PageHeaderStyle.appBarTheme,
  cupertinoOverrideTheme: const NoDefaultCupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: Color(0xFF7AD69C),
    primaryContrastingColor: Color(0xFF07100A),
    scaffoldBackgroundColor: Color(0xFF0C120F),
  ),
  scaffoldBackgroundColor: const Color(0xFF0C120F),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F8F5E),
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
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF17221B),
    contentTextStyle: const TextStyle(
      color: Color(0xFFEAF4EE),
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    actionTextColor: const Color(0xFF7AD69C),
    disabledActionTextColor: const Color(0xFFEAF4EE).withValues(alpha: .5),
    closeIconColor: const Color(0xFFEAF4EE).withValues(alpha: .72),
    showCloseIcon: true,
    elevation: 10,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF365442)),
    ),
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  ),
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
);

class _DemoEmergencyNumber implements EmergencyNumberResolver {
  const _DemoEmergencyNumber();

  @override
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
  }) async => EmergencyNumberService.malaysiaFallback;
}

class _MemoryConsent extends PrivacyConsentRepository {
  PrivacyConsentReceipt? _receipt;

  @override
  Future<PrivacyConsentReceipt?> load(String owner) async => _receipt;

  @override
  Future<void> accept(String owner, {required String languageCode}) async {
    _receipt = PrivacyConsentReceipt(
      acceptedAt: DateTime.utc(2026, 11, 16),
      languageCode: languageCode,
    );
  }

  @override
  Future<void> flush(String owner) async {}
}

class _DialogCapture extends StatefulWidget {
  const _DialogCapture({required this.privacy});
  final bool privacy;

  @override
  State<_DialogCapture> createState() => _DialogCaptureState();
}

class _DialogCaptureState extends State<_DialogCapture> {
  final _consent = _MemoryConsent();
  final _deletion = AccountDeletionService(
    currentOwner: () async => _demoPhone,
    signOut: () async {},
    call: (_, _) async => throw StateError(
      'Account deletion is disabled in the local demonstration.',
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.privacy) {
        unawaited(
          requestSignupPrivacyConsent(
            context,
            phoneNumber: _demoPhone,
            repository: _consent,
          ),
        );
      } else {
        unawaited(
          showAccountDeletionConfirmations(
            context,
            ownerPhoneNumber: _demoPhone,
            service: _deletion,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _deletion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const HelpCenterPage();
}

class _SharingCapture extends StatefulWidget {
  const _SharingCapture({required this.active});
  final bool active;

  @override
  State<_SharingCapture> createState() => _SharingCaptureState();
}

class _SharingCaptureState extends State<_SharingCapture> {
  late final _state = _LocalSharingState(widget.active);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LocationSharingPage(
    phoneNumber: _demoPhone,
    firebaseBootstrapResult: _offline,
    sharingService: _state,
  );
}

class _LocalSharingState extends LiveLocationSharingService {
  _LocalSharingState(this.active);
  final bool active;
  bool _automatic = false;
  Duration _interval = const Duration(seconds: 30);

  @override
  bool get isActive => active;
  @override
  bool get isBusy => false;
  @override
  bool get isPreferenceBusy => false;
  @override
  bool get isSharing => false;
  // An active-hike supplied fix prevents this page from requesting phone GPS.
  // This fixed public demonstration coordinate also wins over any cached fix.
  @override
  bool get hasActiveHike => true;
  @override
  bool get autoShareOnHikeStart => _automatic;
  @override
  Duration get updateInterval => _interval;
  @override
  SosTriggerLocation? get latestHikeLocation => SosTriggerLocation(
    latitude: 5.4141,
    longitude: 100.3288,
    capturedAt: DateTime.now().toUtc(),
    accuracyMeters: 20,
  );
  @override
  LiveLocationShare? get share => active
      ? LiveLocationShare(
          id: 'LOCAL_DEMONSTRATION_ONLY',
          shareUrl: 'https://example.invalid/live-location?share=local-demo',
          isActive: true,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
        )
      : null;
  @override
  String? get errorMessage => null;
  @override
  String? get contactNotificationStatus => null;
  @override
  bool get isNotifyingContacts => false;
  @override
  bool get canRetryContactNotifications => false;
  @override
  Future<void> loadExisting({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) async {}
  @override
  Future<void> activate({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
    bool manual = true,
  }) async => _blocked();
  @override
  Future<void> deactivate({bool manual = true}) async => _blocked();
  @override
  Future<void> shareLiveLocation({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
    bool renewExisting = false,
  }) async => _blocked();
  @override
  Future<void> retryStandaloneContactNotifications() async => _blocked();
  @override
  Future<void> publishLatest() async => _blocked();
  @override
  Future<bool> setUpdateInterval(Duration interval) async {
    _interval = interval;
    notifyListeners();
    return true;
  }

  @override
  Future<void> setAutoShareOnHikeStart({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
    required bool enabled,
  }) async {
    _automatic = enabled;
    notifyListeners();
  }

  Never _blocked() => throw StateError(
    'Live publication is disabled in the local demonstration.',
  );
}

class _SosCapture extends StatelessWidget {
  const _SosCapture({this.countdown = false});
  final bool countdown;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    bottomNavigationBar: HikerBottomNavBar(
      currentIndex: 1,
      onDestinationSelected: (_) {},
    ),
    body: SosPage(
      session: AppSession(
        phoneNumber: _demoPhone,
        signedInAt: DateTime(2026, 11, 16),
        username: 'Alex · Demo',
      ),
      firebaseBootstrapResult: _offline,
      networkStatusOverride: const NetworkReachabilitySnapshot(
        state: NetworkReachabilityState.online,
      ),
      manualSosRequestId: countdown ? 1 : 0,
      sosAlertRepository: safety.DemoAlerts(),
      emergencyContactsRepository: const safety.DemoContacts(),
      nearbySosEventRepository: safety.DemoNearby(),
    ),
  );
}
