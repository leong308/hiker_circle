// Safety showcase entrypoint uses demo repositories for isolated SOS presentation previews.
// Separate media-capture entry point. No Firebase initialization or real dispatch.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/Model/app_session.dart';
import 'sos/View/sos_page.dart';
import 'sos/Data/sos_alert_repository.dart';
import 'sos/Data/emergency_contacts_repository.dart';
import 'sos/Data/nearby_sos_event_repository.dart';
import 'sos/Model/nearby_sos_event.dart';
import 'sos/Model/sos_models.dart';
import 'core/services/network_reachability_service.dart';
import 'navigation/View/hiker_bottom_nav_bar.dart';

/// Computes main.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CaptureApp());
}

/// Displays the capture app.
class CaptureApp extends StatefulWidget {
  /// Creates capture app.
  const CaptureApp({super.key});

  /// Creates the presentation state for this widget.
  @override
  State<CaptureApp> createState() => _CaptureAppState();
}

/// Manages the capture app presentation and lifecycle.
class _CaptureAppState extends State<CaptureApp> {
  static const channel = MethodChannel('hiker_circle/deeplinks');
  final session = AppSession(
    phoneNumber: '+10000000000',
    signedInAt: DateTime(2026),
    username: 'Alex',
  );
  final alerts = DemoAlerts();
  final nearby = DemoNearby();
  int request = 0;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink' &&
          '${call.arguments}'.contains('/duress')) {
        setState(() => request++);
      }
    });
    channel.invokeMethod<String>('consumeInitialDeepLink').then((link) {
      if (mounted && (link?.contains('/duress') ?? false)) {
        setState(() => request++);
      }
    });
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: const Color(0xff0b140f),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff79d59d),
        brightness: Brightness.dark,
      ),
    ),
    home: Scaffold(
      extendBody: true,
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: 1,
        onDestinationSelected: (_) {},
      ),
      body: SosPage(
        session: session,
        networkStatusOverride: const NetworkReachabilitySnapshot(
          state: NetworkReachabilityState.online,
        ),
        sosAlertRepository: alerts,
        emergencyContactsRepository: const DemoContacts(),
        nearbySosEventRepository: nearby,
        immediateSosRequestId: request,
        immediateSosMode: SosAlertMode.duress,
        immediateSosTriggerSource: SosAlertTriggerSource.mobilePhone,
      ),
    ),
  );
}

const demoContacts = [
  EmergencyContact(
    name: 'Jamie',
    phoneNumber: '+10000000001',
    relationship: 'Friend',
  ),
  EmergencyContact(
    name: 'Sam',
    phoneNumber: '+10000000002',
    relationship: 'Family',
  ),
  EmergencyContact(
    name: 'Taylor',
    phoneNumber: '+10000000003',
    relationship: 'Friend',
  ),
];

/// Represents demo contacts.
class DemoContacts extends EmergencyContactsRepository {
  /// Creates demo contacts.
  const DemoContacts();

  /// Loads emergency contacts.
  @override
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async => demoContacts;

  /// Loads cached emergency contacts.
  @override
  Future<List<EmergencyContact>> loadCachedEmergencyContacts({
    required AppSession session,
  }) async => demoContacts;
}

/// Represents demo nearby.
class DemoNearby extends NearbySosEventRepository {
  /// Loads.
  @override
  Future<List<NearbySosEvent>> load({
    required String ownerPhoneNumber,
    int limit = 200,
  }) async => [];
}

/// Represents demo alerts.
class DemoAlerts extends SosAlertRepository {
  /// Loads custom whats app notes.
  @override
  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
    bool cacheOnly = false,
  }) async => {};

  /// Loads alert logs.
  @override
  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) async => [];

  /// Computes count queued alerts.
  @override
  Future<int> countQueuedAlerts({required AppSession session}) async => 0;

  /// Loads queued dispatches.
  @override
  Future<List<SosQueuedDispatch>> loadQueuedDispatches({
    required AppSession session,
    int? limit,
  }) async => [];

  /// Flushes queued alerts.
  @override
  Future<SosQueueFlushResult> flushQueuedAlerts({
    required AppSession session,
    required List<EmergencyContact> contacts,
    int? limit,
  }) async => const SosQueueFlushResult(attempted: 0, sent: 0, remaining: 0);

  /// Computes submit alert.
  @override
  Future<SosAlertSubmission> submitAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    String? customMessageNote,
    SosAlertTriggerSource? triggerSource,
  }) async {
    final result = SosAlertResult(
      alert: SosAlert(
        id: 'demo-only',
        mode: mode,
        status: SosAlertStatus.sent,
        triggeredAt: triggeredAt,
        triggeredByPhoneNumber: session.phoneNumber,
        contactCount: 3,
        sentCount: 3,
        failedCount: 0,
        dispatches: demoContacts
            .map(
              (c) => SosContactDispatch(
                contactName: c.name,
                phoneNumber: c.phoneNumber,
                wasSent: true,
              ),
            )
            .toList(),
        message: 'Demo Duress SOS',
        triggerLocation: triggerLocation,
        triggerSource: triggerSource ?? SosAlertTriggerSource.mobilePhone,
      ),
    );
    return SosAlertSubmission(
      submittedResult: result,
      acknowledgement: Future.value(result),
    );
  }
}
