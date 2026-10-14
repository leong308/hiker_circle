import 'dart:async';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:hiker_circle/home/Model/hike_preparation_sharing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/planned_hike_state_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/Model/hike_shirt_color.dart';
import 'package:hiker_circle/home/View/final_preparation_review_page.dart';
import 'next_hike_briefing_test.dart' as fixtures;
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/home/Model/route_gear_assessment.dart';

Future<void> openPage(
  WidgetTester tester, {
  bool host = true,
  bool joiningTeam = false,
  double textScale = 1,
  Future<void> Function()? cancel,
  Future<void> Function(PlannedHike)? save,
  PlannedHike? initialPlan,
  ValueChanged<PlannedHike>? ready,
  ValueChanged<String?>? onFinished,
  Future<TrailWeather> Function()? weather,
  Future<RouteGearAssessment> Function(bool)? route,
  List<EmergencyContact> contacts = const [],
  Future<List<EmergencyContact>> Function()? loadContacts,
  Future<void> Function()? editContacts,
  Future<int?> Function()? battery,
  Future<HikePreparationSharing?> Function()? loadSharing,
  Future<void> Function(HikePreparationSharing)? saveSharing,
}) async {
  final hike = fixtures.testHike();
  final plan =
      initialPlan ??
      PlannedHikeStateResolver.resolve(
        upcomingHike: hike,
        liveTrails: [],
        emergencyContactsSelected: false,
        phoneBatteryLevel: 40,
      );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push<String>(
                  MaterialPageRoute(
                    builder: (_) => FinalPreparationReviewPage(
                      hike: hike,
                      isHost: host,
                      canStart: host || joiningTeam,
                      primaryActionLabel: joiningTeam
                          ? 'Continue to team readiness'
                          : null,
                      plan: plan,
                      onCancel: cancel,
                      onPlanChanged: save,
                      onReady: ready,
                      loadWeather: weather,
                      loadRouteAnalysis: route,
                      initialContacts: contacts,
                      loadContacts: loadContacts,
                      onEditContacts: editContacts,
                      loadBatteryLevel: battery,
                      loadSharing: loadSharing,
                      saveSharing: saveSharing,
                    ),
                  ),
                )
                .then((result) => onFinished?.call(result)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (route != null || weather != null) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    150,
    scrollable: find
        .descendant(
          of: find.byType(FinalPreparationReviewPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

PlannedHike testPlan({bool packed = false}) {
  final plan = PlannedHikeStateResolver.resolve(
    upcomingHike: fixtures.testHike(),
    liveTrails: [],
    emergencyContactsSelected: true,
    phoneBatteryLevel: 80,
  );
  return packed
      ? plan
            .copyWith(completedChecklistItems: plan.gearPlan.requiredItems)
            .withGearProgress()
      : plan;
}

FilledButton continueButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('preparation-continue')),
);

Future<void> tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).hitTestable());
  // Bounded pumps also work while route/weather futures are still pending.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> closeShirtColorGuidance(WidgetTester tester) async {
  final closeButton = find.byKey(const ValueKey('close-shirt-color-guidance'));
  await tester.ensureVisible(closeButton);
  await tester.pumpAndSettle();
  await tester.tap(closeButton);
  await tester.pumpAndSettle();
}

Future<void> finishGuide(WidgetTester tester, {bool pack = true}) async {
  for (var i = 0; i < 40; i++) {
    if (find.text('FINAL REVIEW').evaluate().isNotEmpty) return;
    if (find.text('Yes, packed').evaluate().isNotEmpty ||
        find.text('Keep packed').evaluate().isNotEmpty) {
      if (pack) {
        await tester.tap(find.byKey(const ValueKey('preparation-continue')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      } else {
        await tap(tester, 'Not yet');
      }
    } else if (find.text('Skip extras').evaluate().isNotEmpty) {
      await tap(tester, 'Skip extras');
    } else if (find
            .byKey(const ValueKey('shirt-color-white'))
            .evaluate()
            .isNotEmpty &&
        continueButton(tester).onPressed == null) {
      final white = find.byKey(const ValueKey('shirt-color-white'));
      await tester.ensureVisible(white);
      await tester.pumpAndSettle();
      await tester.tap(white);
      await tester.pump();
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('close-shirt-color-guidance'))
          .evaluate()
          .isNotEmpty) {
        await closeShirtColorGuidance(tester);
      }
    } else {
      await tap(tester, 'Continue');
    }
  }
  fail('Preparation did not reach the final review.');
}

Future<void> openCancelMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Hike options'));
  await tester.pumpAndSettle();
  await tap(tester, 'Cancel upcoming hike');
}

void main() {
  testWidgets(
    'one Start hike tap survives a conditions refresh beginning during the tap',
    (tester) async {
      final refresh = Completer<TrailWeather>();
      var weatherCalls = 0, starts = 0;
      String? result;
      final oldWeather = TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      final base = testPlan(packed: true);
      await openPage(
        tester,
        initialPlan: base.copyWith(
          trail: base.trail.copyWith(weather: oldWeather),
        ),
        save: (_) async {},
        ready: (_) => starts++,
        onFinished: (value) => result = value,
        weather: () => ++weatherCalls == 1
            ? Future.error(StateError('Weather refresh failed'))
            : refresh.future,
        route: (_) => Future.error(StateError('Route unavailable')),
      );
      await tester.pumpAndSettle();
      await finishGuide(tester);
      final button = find.byKey(const ValueKey('preparation-continue'));
      await tester.ensureVisible(button);
      final originalStart = continueButton(tester).onPressed!;
      final gesture = await tester.startGesture(tester.getCenter(button));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await gesture.up();
      originalStart();
      originalStart();
      await tester.pump();
      expect(weatherCalls, 2);
      expect(starts, 0);
      refresh.completeError(StateError('Weather refresh failed'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(result, 'start');
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a queued start still requires new gear from the latest forecast',
    (tester) async {
      final refresh = Completer<TrailWeather>();
      var weatherCalls = 0;
      PlannedHike? reviewed;
      final base = testPlan(packed: true);
      final oldWeather = TrailWeather(
        summary: '',
        temperatureRange: '',
        rainProbability: 0,
        cachedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      await openPage(
        tester,
        initialPlan: base.copyWith(
          trail: base.trail.copyWith(weather: oldWeather),
        ),
        save: (_) async {},
        ready: (value) => reviewed = value,
        weather: () => ++weatherCalls == 1
            ? Future.error(StateError('Weather unavailable'))
            : refresh.future,
      );
      await tester.pumpAndSettle();
      await finishGuide(tester);
      final button = find.byKey(const ValueKey('preparation-continue'));
      final gesture = await tester.startGesture(tester.getCenter(button));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await gesture.up();
      await tester.pump();
      final forecast = fixtures.testForecast(base.plannedStartTime);
      final hourly = forecast.forecastData['hourly'] as Map;
      hourly['temperature_2m'] = List.filled(96, 14);
      hourly['precipitation_probability'] = List.filled(96, 0);
      refresh.complete(forecast);
      await tester.pumpAndSettle();
      expect(reviewed, isNull);
      expect(find.text('Pack 1 missing item'), findsOneWidget);
      expect(
        find.textContaining('latest checks require more gear'),
        findsOneWidget,
      );
      await tap(tester, 'Pack 1 missing item');
      expect(find.text('Emergency blanket'), findsOneWidget);
      await tap(tester, 'Yes, packed');
      await tester.tap(find.byKey(const ValueKey('preparation-continue')));
      await tester.pumpAndSettle();
      expect(
        reviewed!.completedChecklistItems,
        containsAll([
          'Drinking water',
          'Energy snack',
          'First-aid kit',
          'Emergency blanket',
        ]),
      );
      expect(reviewed!.requiredGearReady, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a failed preparation handoff shows an error and retains the completed pack',
    (tester) async {
      var calls = 0;
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (_) async {},
        ready: (_) {
          calls++;
          if (calls == 1) throw StateError('Handoff unavailable');
        },
      );
      await finishGuide(tester);
      await tester.tap(find.byKey(const ValueKey('preparation-continue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your preparation is kept'), findsOneWidget);
      expect(find.text('Your pack is ready'), findsOneWidget);
      expect(calls, 1);
      await tester.tap(find.byKey(const ValueKey('preparation-continue')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rapid repeated start submits the reviewed pack only once', (
    tester,
  ) async {
    var starts = 0;
    await openPage(
      tester,
      initialPlan: testPlan(packed: true),
      save: (_) async {},
      ready: (_) => starts++,
    );
    await finishGuide(tester);
    final start = continueButton(tester).onPressed!;
    start();
    start();
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
    'shows one question, saves answers, and lets users revise a previous answer',
    (tester) async {
      final saves = <PlannedHike>[];
      await openPage(tester, save: (plan) async => saves.add(plan));
      expect(find.text('Drinking water'), findsOneWidget);
      expect(find.text('Energy snack'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Start hike'), findsNothing);
      await tap(tester, 'Yes, packed');
      expect(saves.last.completedChecklistItems, contains('Drinking water'));
      expect(find.text('Energy snack'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous question'));
      await tester.pumpAndSettle();
      expect(find.text('Already in your pack'), findsOneWidget);
      await tap(tester, 'Not yet');
      expect(
        saves.last.completedChecklistItems,
        isNot(contains('Drinking water')),
      );
      expect(find.text('Energy snack'), findsOneWidget);
    },
  );

  testWidgets('small screens and large text keep guided actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPage(
      tester,
      textScale: 1.6,
      save: (_) async {},
      cancel: () async {},
    );
    expect(find.text('Yes, packed').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Hike options').hitTestable(), findsOneWidget);
    await finishGuide(tester);
    expect(find.text('Start hike').hitTestable(), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets(
    'cancellation is confirmed, cannot submit twice, and waits for success',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await openPage(
        tester,
        cancel: () {
          calls++;
          return pending.future;
        },
      );
      await openCancelMenu(tester);
      await tap(tester, 'Keep hike');
      expect(calls, 0);
      await openCancelMenu(tester);
      await tap(tester, 'Cancel hike');
      expect(calls, 1);
      expect(find.byType(FinalPreparationReviewPage), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
    },
  );

  testWidgets('failed cancellation stays open with an error and allows retry', (
    tester,
  ) async {
    await openPage(
      tester,
      cancel: () async {
        throw Exception('Connect to the internet and retry.');
      },
    );
    await openCancelMenu(tester);
    await tap(tester, 'Cancel hike');
    expect(find.text('Connect to the internet and retry.'), findsOneWidget);
    expect(find.byType(FinalPreparationReviewPage), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isTrue,
    );
  });

  testWidgets(
    'participants save their pack but cannot cancel or start the organizer session',
    (tester) async {
      PlannedHike? saved;
      await openPage(
        tester,
        host: false,
        cancel: () async {},
        save: (plan) async => saved = plan,
      );
      expect(find.byTooltip('Hike options'), findsNothing);
      await finishGuide(tester);
      expect(saved!.requiredGearReady, isTrue);
      expect(find.text('Waiting for organizer'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);
      expect(
        find.text(
          'Your preparation is saved. The organizer starts the session.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'failed save stays on its question, rolls back, and can be retried',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await openPage(
        tester,
        save: (_) {
          calls++;
          return calls == 1 ? pending.future : Future.value();
        },
      );
      await tap(tester, 'Yes, packed');
      expect(find.text('Drinking water'), findsOneWidget);
      expect(find.text('Energy snack'), findsNothing);
      expect(continueButton(tester).onPressed, isNull);
      expect(calls, 1);
      pending.completeError(Exception('Offline'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your checklist. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Yes, packed'), findsOneWidget);
      await tap(tester, 'Yes, packed');
      expect(calls, 2);
      expect(find.text('Energy snack'), findsOneWidget);
    },
  );

  testWidgets(
    'deferred gear is named at the end and guided back to completion',
    (tester) async {
      final plan = testPlan();
      PlannedHike? reviewed;
      await openPage(
        tester,
        initialPlan: plan,
        save: (_) async {},
        ready: (value) => reviewed = value,
      );
      await tap(tester, 'Not yet');
      await finishGuide(tester);
      expect(find.text('Start hike'), findsNothing);
      expect(find.text('Next up: Drinking water'), findsOneWidget);
      await tap(tester, 'Pack 1 missing item');
      expect(find.text('Drinking water'), findsOneWidget);
      await tap(tester, 'Yes, packed');
      expect(find.text('FINAL REVIEW'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNotNull);
      await tap(tester, 'Start hike');
      await tester.pumpAndSettle();
      expect(reviewed!.requiredGearReady, isTrue);
      expect(reviewed!.checklistCompleted, lessThan(reviewed!.checklistTotal));
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
    },
  );

  testWidgets(
    'saved required gear resumes at optional extras and safety appears one topic at a time',
    (tester) async {
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (_) async {},
      );
      expect(find.text('A few useful extras?'), findsOneWidget);
      await tap(tester, 'Skip extras');
      expect(find.text('Who can help if you need it?'), findsOneWidget);
      expect(find.text('Is your phone ready for the trail?'), findsNothing);
      await tap(tester, 'Continue');
      expect(find.text('Is your phone ready for the trail?'), findsOneWidget);
      await finishGuide(tester);
      expect(find.text('Start hike'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'shirt colour is saved and dark daytime clothing shows a clear warning',
    (tester) async {
      final saves = <PlannedHike>[];
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (value) async => saves.add(value),
      );
      await tap(tester, 'Skip extras');
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');
      await tap(tester, 'Continue');

      expect(find.text('What colour shirt will you wear?'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);
      expect(find.text('Black'), findsNothing);
      expect(find.byTooltip('Black'), findsOneWidget);
      final black = find.byKey(const ValueKey('shirt-color-black'));
      await tester.ensureVisible(black);
      await tester.pumpAndSettle();
      await tester.tap(black);
      await tester.pumpAndSettle();

      expect(
        saves.last.completedChecklistItems,
        contains(HikeShirtColor.black.preference),
      );
      expect(find.textContaining('absorbs more solar heat'), findsOneWidget);
      await closeShirtColorGuidance(tester);
      expect(find.text('Continue with warning'), findsOneWidget);

      final lightBlue = find.byKey(const ValueKey('shirt-color-lightBlue'));
      await tester.ensureVisible(lightBlue);
      await tester.pumpAndSettle();
      await tester.tap(lightBlue);
      await tester.pumpAndSettle();
      expect(
        saves.last.completedChecklistItems,
        contains(HikeShirtColor.lightBlue.preference),
      );
      expect(
        saves.last.completedChecklistItems,
        isNot(contains(HikeShirtColor.black.preference)),
      );
      expect(find.text('Good choice for hiking'), findsAtLeastNWidgets(1));
      await closeShirtColorGuidance(tester);
      expect(find.text('Light blue'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'optional gear can be saved or skipped without blocking departure',
    (tester) async {
      PlannedHike? saved;
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (value) async => saved = value,
      );
      await tap(tester, 'Review optional gear');
      expect(find.text('Emergency whistle'), findsOneWidget);
      await tap(tester, 'Yes, packed');
      expect(saved!.completedChecklistItems, contains('Emergency whistle'));
      for (
        var i = 0;
        i < 40 && find.text('Skip this item').evaluate().isNotEmpty;
        i++
      ) {
        await tap(tester, 'Skip this item');
      }
      await finishGuide(tester);
      expect(continueButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'rechecking saved gear can remove it and blocks start with an explicit next action',
    (tester) async {
      PlannedHike? saved;
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (value) async => saved = value,
      );
      await finishGuide(tester);
      await reveal(tester, 'Recheck required gear');
      await tap(tester, 'Recheck required gear');
      expect(find.text('Drinking water'), findsOneWidget);
      await tap(tester, 'Not yet');
      await finishGuide(tester);
      expect(saved!.completedChecklistItems, isNot(contains('Drinking water')));
      expect(find.text('Pack 1 missing item'), findsOneWidget);
    },
  );

  testWidgets(
    'late route findings keep start blocked and guide newly required poles',
    (tester) async {
      final pending = Completer<RouteGearAssessment>();
      await openPage(
        tester,
        initialPlan: testPlan(packed: true),
        save: (_) async {},
        route: (_) => pending.future,
      );
      await finishGuide(tester);
      expect(find.text('Checking conditions…'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);
      pending.complete(
        RouteGearAssessment(
          routeKey: 'x',
          checkedAt: DateTime.now(),
          status: 'complete',
          rough: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Next up: Trekking poles'), findsOneWidget);
      await tap(tester, 'Pack 1 missing item');
      expect(
        find.text('Uneven terrain detected along your route'),
        findsOneWidget,
      );
      await tap(tester, 'Yes, packed');
      expect(find.text('Start hike'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'forecast arriving during a save retains both the answer and new cold requirement',
    (tester) async {
      final plan = testPlan();
      final weather = Completer<TrailWeather>();
      final save = Completer<void>();
      var calls = 0;
      PlannedHike? reviewed;
      await openPage(
        tester,
        initialPlan: plan.copyWith(
          completedChecklistItems: plan.gearPlan.requiredItems.difference({
            'Drinking water',
          }),
        ),
        save: (_) {
          calls++;
          return calls == 1 ? save.future : Future.value();
        },
        weather: () => weather.future,
        ready: (value) => reviewed = value,
      );
      await tap(tester, 'Yes, packed');
      final forecast = fixtures.testForecast(plan.plannedStartTime);
      final hourly = forecast.forecastData['hourly'] as Map;
      hourly['temperature_2m'] = List.filled(96, 14);
      hourly['precipitation_probability'] = List.filled(96, 0);
      weather.complete(forecast);
      await tester.pump();
      save.complete();
      await tester.pumpAndSettle();
      expect(find.text('Emergency blanket'), findsOneWidget);
      expect(
        find.text('Forecast temperature below 15°C during this hike'),
        findsOneWidget,
      );
      await finishGuide(tester);
      await tap(tester, 'Start hike');
      expect(
        reviewed!.completedChecklistItems,
        containsAll(['Drinking water', 'Emergency blanket']),
      );
      expect(reviewed!.trail.weather, forecast);
    },
  );

  testWidgets('unavailable condition checks are disclosed and can be retried', (
    tester,
  ) async {
    var calls = 0;
    await openPage(
      tester,
      initialPlan: testPlan(packed: true),
      save: (_) async {},
      route: (_) async {
        calls++;
        if (calls == 1) throw Exception('Offline');
        return RouteGearAssessment(
          routeKey: 'x',
          checkedAt: DateTime.now(),
          status: 'complete',
        );
      },
    );
    await tap(tester, 'Skip extras');
    for (var i = 0; i < 3; i++) {
      await tap(tester, 'Continue');
    }
    final white = find.byKey(const ValueKey('shirt-color-white'));
    await tester.ensureVisible(white);
    await tester.pumpAndSettle();
    await tester.tap(white);
    await tester.pumpAndSettle();
    await closeShirtColorGuidance(tester);
    await tap(tester, 'Continue');
    expect(
      find.textContaining('Route conditions are unavailable.'),
      findsAtLeastNWidgets(1),
    );
    await reveal(tester, 'Refresh conditions');
    await tap(tester, 'Refresh conditions');
    expect(calls, 2);
    expect(
      find.text('Route checked. Map data © OpenStreetMap contributors.'),
      findsOneWidget,
    );
    await finishGuide(tester);
    expect(continueButton(tester).onPressed, isNotNull);
  });

  testWidgets(
    'participant team readiness still requires their own completed pack',
    (tester) async {
      await openPage(
        tester,
        host: false,
        joiningTeam: true,
        initialPlan: testPlan(),
        save: (_) async {},
      );
      await finishGuide(tester, pack: false);
      expect(find.text('Continue to team readiness'), findsNothing);
      expect(find.textContaining('missing items'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await openPage(
        tester,
        host: false,
        joiningTeam: true,
        initialPlan: testPlan(packed: true),
        save: (_) async {},
      );
      await finishGuide(tester);
      expect(find.text('Continue to team readiness'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNotNull);
    },
  );
}
