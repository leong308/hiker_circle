import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/active_hike_live_status_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/final_preparation_review_page.dart';
import 'package:hiker_circle/home/View/ios_hike_safety_setup_dialog.dart';

import 'final_preparation_review_page_test.dart' as preparation;
import 'next_hike_briefing_test.dart' as fixtures;

const channel = MethodChannel('hiker_circle/active_hike_live_status');
const service = ActiveHikeLiveStatusService();
const dialogKey = ValueKey('ios-hike-safety-setup');

Map<String, Object> status({
  bool always = false,
  bool notifications = true,
  bool motion = true,
}) => {
  'platform': 'ios',
  'fineLocationGranted': true,
  'backgroundLocationGranted': always,
  'notificationsAuthorized': notifications,
  'notificationAuthorizationStatus': notifications ? 'authorized' : 'denied',
  'motionGranted': motion,
  'motionAuthorizationStatus': motion ? 'authorized' : 'denied',
  // Optional capabilities must never block the required permission check.
  'timeSensitiveGranted': false,
  'liveActivitiesGranted': false,
};

class SettingsBridge {
  Map<String, Object>? current = status();
  int opens = 0, reads = 0;
  Completer<Map<String, Object>?>? pendingRead;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'openIosSafetySettings':
              opens++;
              return null;
            case 'getNativeSafetyStatus':
              reads++;
              return pendingRead?.future ?? current;
            default:
              throw StateError('Unexpected method ${call.method}');
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }
}

Future<void> returnFromSettings(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

Future<void> openGate(
  WidgetTester tester,
  SettingsBridge bridge,
  void Function(bool) completed, {
  bool fallDetection = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => completed(
              await showIosHikeSafetySetupDialog(
                context: context,
                service: service,
                initialStatus: NativeHikeSafetyStatus.fromPlatform(
                  bridge.current,
                ),
                fallDetectionEnabled: fallDetection,
              ),
            ),
            child: const Text('Start prepared hike'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Start prepared hike'));
  await tester.pumpAndSettle();
}

Future<void> tapAction(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets(
    'opening Settings keeps the same gate and waits for a permission check',
    (tester) async {
      final bridge = SettingsBridge()..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add);
      final original = tester.state(find.byKey(dialogKey));
      await tapAction(tester, 'Open Settings');
      await tester.pumpAndSettle();
      expect(bridge.opens, 1);
      expect(bridge.reads, 0);
      expect(results, isEmpty);
      expect(tester.state(find.byKey(dialogKey)), same(original));

      await returnFromSettings(tester);
      expect(bridge.reads, 1);
      expect(results, isEmpty);
      expect(find.textContaining('Location: Always'), findsOneWidget);
      expect(tester.state(find.byKey(dialogKey)), same(original));

      // Another visit still resumes the original attempt, not a new checklist.
      await tapAction(tester, 'Open Settings');
      await tester.pumpAndSettle();
      bridge.current = status(always: true);
      await returnFromSettings(tester);
      expect(bridge.opens, 2);
      expect(results, [true]);
      expect(find.byKey(dialogKey), findsNothing);
      await returnFromSettings(tester);
      expect(results, [true]);
      expect(bridge.reads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial permission changes keep the dialog with only missing requirements',
    (tester) async {
      final bridge = SettingsBridge()
        ..current = status(notifications: false, motion: false)
        ..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add);
      await tapAction(tester, 'Open Settings');
      await tester.pumpAndSettle();
      bridge.current = status(
        always: true,
        notifications: false,
        motion: false,
      );
      await returnFromSettings(tester);
      expect(results, isEmpty);
      expect(find.textContaining('Location: Always'), findsNothing);
      expect(find.textContaining('Notifications: Allow'), findsOneWidget);
      expect(find.textContaining('Motion & Fitness: On'), findsOneWidget);
      bridge.current = status(always: true);
      await returnFromSettings(tester);
      expect(results, [true]);
    },
  );

  testWidgets(
    'location-only monitoring does not require fall detection permissions',
    (tester) async {
      final bridge = SettingsBridge()
        ..current = status(notifications: false, motion: false)
        ..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add, fallDetection: false);
      expect(find.textContaining('Notifications: Allow'), findsNothing);
      expect(find.textContaining('Motion & Fitness: On'), findsNothing);
      bridge.current = status(
        always: true,
        notifications: false,
        motion: false,
      );
      await returnFromSettings(tester);
      expect(results, [true]);
    },
  );

  testWidgets(
    'failed verification keeps preparation blocked and allows an explicit retry',
    (tester) async {
      final bridge = SettingsBridge()..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add);
      bridge.current = null;
      await returnFromSettings(tester);
      expect(results, isEmpty);
      expect(find.textContaining('Unable to verify'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      bridge.current = status(always: true);
      await tapAction(tester, 'Check again');
      await tester.pumpAndSettle();
      expect(results, [true]);
    },
  );

  testWidgets(
    'explicit cancellation ignores a later successful native response',
    (tester) async {
      final bridge = SettingsBridge()..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add);
      bridge.pendingRead = Completer();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Checking updated settings…'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel hike start'));
      await tester.tap(find.text('Cancel hike start'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      bridge.pendingRead!.complete(status(always: true));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a slow permission check queues a subsequent resume and starts once',
    (tester) async {
      final bridge = SettingsBridge()..install();
      final results = <bool>[];
      await openGate(tester, bridge, results.add);
      final firstRead = Completer<Map<String, Object>?>();
      bridge.pendingRead = firstRead;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      bridge.pendingRead = null;
      bridge.current = status(always: true);
      firstRead.complete(status());
      await tester.pumpAndSettle();
      expect(bridge.reads, 2);
      expect(results, [true]);
    },
  );

  testWidgets(
    'returning from Settings continues with the completed real preparation checklist',
    (tester) async {
      final bridge = SettingsBridge()..install();
      var reviews = 0, starts = 0;
      PlannedHike? reviewed, startedPlan;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  reviews++;
                  final action = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FinalPreparationReviewPage(
                        hike: fixtures.testHike(),
                        plan: preparation.testPlan(),
                        isHost: true,
                        canStart: true,
                        immediate: true,
                        onPlanChanged: (_) async {},
                        onReady: (plan) => reviewed = plan,
                      ),
                    ),
                  );
                  if (!context.mounted || action != 'start') return;
                  final ready = await showIosHikeSafetySetupDialog(
                    context: context,
                    service: service,
                    initialStatus: NativeHikeSafetyStatus.fromPlatform(
                      bridge.current,
                    ),
                    fallDetectionEnabled: true,
                  );
                  if (ready) {
                    starts++;
                    startedPlan = reviewed;
                  }
                },
                child: const Text('Prepare hike'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare hike'));
      await tester.pumpAndSettle();
      await preparation.finishGuide(tester);
      preparation.continueButton(tester).onPressed!();
      await tester.pumpAndSettle();
      final checkedItems = Set<String>.of(reviewed!.completedChecklistItems);
      expect(
        checkedItems,
        containsAll(['Drinking water', 'Energy snack', 'First-aid kit']),
      );
      expect(reviewed!.requiredGearReady, isTrue);
      await tapAction(tester, 'Open Settings');
      await tester.pumpAndSettle();
      await returnFromSettings(tester);
      expect(reviews, 1);
      expect(starts, 0);
      expect(find.byKey(dialogKey), findsOneWidget);
      bridge.current = status(always: true);
      await returnFromSettings(tester);
      expect(reviews, 1);
      expect(starts, 1);
      expect(startedPlan, same(reviewed));
      expect(startedPlan!.completedChecklistItems, checkedItems);
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
