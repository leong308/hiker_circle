import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/services/network_reachability_service.dart';
import 'package:hiker_circle/sos/Data/emergency_contacts_repository.dart';
import 'package:hiker_circle/sos/Data/nearby_sos_event_repository.dart';
import 'package:hiker_circle/sos/Data/sos_alert_repository.dart';
import 'package:hiker_circle/sos/Model/nearby_sos_event.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:hiker_circle/sos/View/sos_page.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 14);
  final session = AppSession(phoneNumber: '+60111111111', signedInAt: now);

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(NetworkReachabilityService.instance.stop);
  }

  testWidgets(
    'removes redundant readiness UI and explains the combined SOS gesture',
    (tester) async {
      final repository = _FakeSosAlertRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SosPage(
              session: session,
              sosAlertRepository: repository,
              emergencyContactsRepository:
                  const _FakeEmergencyContactsRepository(),
              nearbySosEventRepository: _EmptyNearbySosRepository(),
              firebaseBootstrapResult:
                  const FirebaseBootstrapResult.unavailable('Offline test'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('SOS ready'), findsNothing);
      expect(find.text('Latest'), findsNothing);
      expect(find.text('Queued'), findsOneWidget);
      expect(find.textContaining('Tap: Manual SOS'), findsOneWidget);
      expect(find.textContaining('Hold: silent Duress SOS'), findsOneWidget);

      final emergencyButton = find.byKey(const Key('sos-emergency-button'));
      await tester.ensureVisible(emergencyButton);
      await tester.pump();
      expect(
        find.descendant(of: emergencyButton, matching: find.text('SOS')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: emergencyButton,
          matching: find.byIcon(Icons.sos_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: emergencyButton,
          matching: find.text('Tap or hold'),
        ),
        findsOneWidget,
      );
      final infoButtonWidget = tester.widget<IconButton>(
        find.byKey(const Key('sos-gesture-info-button')),
      );
      expect(infoButtonWidget.iconSize, 18);
      final detector = tester.widget<GestureDetector>(emergencyButton);
      detector.onTapDown!(TapDownDetails());
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.text('DURESS'), findsOneWidget);
      detector.onTapUp!(TapUpDetails(kind: PointerDeviceKind.touch));
      await tester.pump();
      expect(find.text('Cancel SOS'), findsNothing);

      final infoButton = find.byTooltip('How Manual and Duress SOS work');
      await tester.ensureVisible(infoButton);
      await tester.tap(infoButton);
      await tester.pumpAndSettle();
      expect(find.text('Manual & Duress SOS'), findsOneWidget);
      expect(find.text('DEMO ONLY · NO ALERT WILL BE SENT'), findsOneWidget);

      final demoButton = find.byKey(const Key('sos-gesture-demo-button'));
      await tester.ensureVisible(demoButton);
      await tester.tap(demoButton);
      await tester.pumpAndSettle();
      expect(find.text('Manual SOS gesture'), findsOneWidget);
      await tester.longPress(demoButton);
      await tester.pumpAndSettle();
      expect(find.text('Duress SOS gesture'), findsOneWidget);

      await disposePage(tester);
    },
  );

  testWidgets('queued SOS dispatches are view-only', (tester) async {
    final repository = _FakeSosAlertRepository(
      queuedDispatches: [
        SosQueuedDispatch(
          id: 7,
          mode: SosAlertMode.manual,
          triggeredAt: now,
          createdAt: now,
          sendStatus: 'retry',
          retryCount: 2,
          contactCount: 2,
          pendingContactCount: 1,
          lastError: 'No internet connection.',
          message: 'Protected message snapshot',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosPage(
            session: session,
            sosAlertRepository: repository,
            emergencyContactsRepository:
                const _FakeEmergencyContactsRepository(),
            nearbySosEventRepository: _EmptyNearbySosRepository(),
            firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
              'Offline test',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    final queuedMetric = find.ancestor(
      of: find.text('Queued'),
      matching: find.byType(InkWell),
    );
    expect(queuedMetric, findsOneWidget);
    await tester.tap(queuedMetric);
    await tester.pumpAndSettle();

    expect(find.text('Queued SOS dispatches'), findsOneWidget);
    expect(find.text('View only'), findsOneWidget);
    expect(find.textContaining('cannot be removed here'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Remove'), findsNothing);

    await tester.tap(find.text('Manual SOS'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only dispatch record'), findsOneWidget);
    expect(
      find.textContaining('protected from manual removal'),
      findsOneWidget,
    );
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Remove'), findsNothing);

    await disposePage(tester);
  });

  testWidgets('short press keeps the Manual SOS cancel window', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosPage(
            session: session,
            sosAlertRepository: _FakeSosAlertRepository(),
            emergencyContactsRepository:
                const _FakeEmergencyContactsRepository(),
            nearbySosEventRepository: _EmptyNearbySosRepository(),
            firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
              'Offline test',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    final emergencyButton = find.byKey(const Key('sos-emergency-button'));
    await tester.ensureVisible(emergencyButton);
    await tester.tap(emergencyButton);
    await tester.pump();
    expect(find.text('Cancel SOS'), findsOneWidget);
    expect(find.textContaining('Sending in 10 seconds'), findsOneWidget);

    await tester.tap(find.text('Cancel SOS'));
    await tester.pumpAndSettle();
    await disposePage(tester);
  });
}

class _FakeSosAlertRepository extends SosAlertRepository {
  _FakeSosAlertRepository({this.queuedDispatches = const []});

  final List<SosQueuedDispatch> queuedDispatches;
  final List<SosAlertMode> triggeredModes = [];

  @override
  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
  }) async => const {};

  @override
  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) async => const [];

  @override
  Future<int> countQueuedAlerts({required AppSession session}) async =>
      queuedDispatches.length;

  @override
  Future<List<SosQueuedDispatch>> loadQueuedDispatches({
    required AppSession session,
    int limit = 20,
  }) async => queuedDispatches;

  @override
  Future<SosQueueFlushResult> flushQueuedAlerts({
    required AppSession session,
    required List<EmergencyContact> contacts,
    int limit = 10,
  }) async => SosQueueFlushResult(
    attempted: 0,
    sent: 0,
    remaining: queuedDispatches.length,
  );

  @override
  Future<SosAlertResult> triggerAlert({
    required AppSession session,
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    required List<EmergencyContact> contacts,
    String? customMessageNote,
    SosAlertTriggerSource? triggerSource,
  }) async {
    triggeredModes.add(mode);
    return SosAlertResult(
      alert: SosAlert(
        id: 'test-${mode.firestoreValue}',
        mode: mode,
        status: SosAlertStatus.noContacts,
        triggeredAt: triggeredAt,
        triggeredByPhoneNumber: session.phoneNumber,
        contactCount: 0,
        sentCount: 0,
        failedCount: 0,
        dispatches: const [],
        message: 'Test message',
        triggerLocation: triggerLocation,
        triggerSource: triggerSource ?? SosAlertTriggerSource.mobilePhone,
      ),
      queuedAlertCount: queuedDispatches.length,
    );
  }
}

class _FakeEmergencyContactsRepository extends EmergencyContactsRepository {
  const _FakeEmergencyContactsRepository();

  @override
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async => const [];
}

class _EmptyNearbySosRepository extends NearbySosEventRepository {
  _EmptyNearbySosRepository();

  @override
  Future<List<NearbySosEvent>> load({
    required String ownerPhoneNumber,
    int limit = 200,
  }) async => const [];
}
