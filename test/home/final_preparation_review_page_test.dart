import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Data/planned_hike_state_service.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/final_preparation_review_page.dart';
import 'package:hiker_circle/home/View/trail_gear_checklist.dart';
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
  Future<TrailWeather> Function()? weather,
  Future<RouteGearAssessment> Function(bool)? route,
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
            onPressed: () => Navigator.of(context).push<String>(
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
                ),
              ),
            ),
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

void main() {
  testWidgets('small screens and large text keep the main actions visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPage(tester, textScale: 1.6, cancel: () async {});
    expect(tester.takeException(), isNull);
    await reveal(tester, 'Cancel upcoming hike');
    expect(find.text('Cancel upcoming hike').hitTestable(), findsOneWidget);
    expect(find.text('Start hike').hitTestable(), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets(
    'cancellation is confirmed, cannot submit twice and closes only after success',
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
      await reveal(tester, 'Cancel upcoming hike');
      await tester.tap(find.text('Cancel upcoming hike'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep hike'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('Cancel upcoming hike'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel hike'));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(FinalPreparationReviewPage), findsOneWidget);
      await tester.tap(find.text('Cancel upcoming hike'));
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
    },
  );
  testWidgets('failed cancellation stays open with error and allows retry', (
    tester,
  ) async {
    await openPage(
      tester,
      cancel: () async {
        throw Exception('Connect to the internet and retry.');
      },
    );
    await reveal(tester, 'Cancel upcoming hike');
    await tester.tap(find.text('Cancel upcoming hike'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel hike'));
    await tester.pumpAndSettle();
    expect(find.text('Connect to the internet and retry.'), findsOneWidget);
    expect(find.byType(FinalPreparationReviewPage), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Cancel upcoming hike'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'participants have no cancellation action; preparation saves checked gear',
    (tester) async {
      PlannedHike? saved;
      await openPage(
        tester,
        host: false,
        cancel: () async {},
        save: (plan) async {
          saved = plan;
        },
      );
      expect(find.text('Cancel upcoming hike'), findsNothing);
      expect(find.text('Adapt to this hike'), findsNothing);
      expect(find.text('Charged phone'), findsNothing);
      await reveal(tester, 'Drinking water');
      await tester.tap(find.text('Drinking water'));
      await tester.pumpAndSettle();
      expect(saved!.completedChecklistItems, contains('Drinking water'));
      expect(saved!.checklistCompleted, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'packing card updates immediately and rolls back if saving fails',
    (tester) async {
      final pending = Completer<void>();
      await openPage(tester, save: (_) => pending.future);
      await reveal(tester, 'Drinking water');
      final tile = find.byKey(const ValueKey('gear-item-Drinking water'));
      expect(tester.widget<GearPackingTile>(tile).packed, isFalse);
      await tester.tap(tile);
      await tester.pump();
      expect(tester.widget<GearPackingTile>(tile).packed, isTrue);
      expect(tester.widget<GearPackingTile>(tile).onTap, isNull);
      pending.completeError(Exception('Offline'));
      await tester.pumpAndSettle();
      expect(tester.widget<GearPackingTile>(tile).packed, isFalse);
      expect(tester.widget<GearPackingTile>(tile).onTap, isNotNull);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'start is gated by required items, not every recommendation; safety is a tab',
    (tester) async {
      final hike = fixtures.testHike();
      final plan = PlannedHikeStateResolver.resolve(
        upcomingHike: hike,
        liveTrails: [],
        emergencyContactsSelected: true,
        phoneBatteryLevel: 80,
      );
      final required = plan.gearPlan.requiredItems;
      PlannedHike? reviewed;
      await openPage(
        tester,
        initialPlan: plan.copyWith(
          completedChecklistItems: required.difference({'Drinking water'}),
        ),
        save: (_) async {},
        ready: (value) => reviewed = value,
      );
      FilledButton startButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start hike'),
      );
      expect(startButton().onPressed, isNull);
      expect(find.text('GPS device or app'), findsNothing);
      expect(find.text('Emergency contacts saved'), findsNothing);
      await reveal(tester, 'Drinking water');
      await tester.tap(find.text('Drinking water'));
      await tester.pumpAndSettle();
      expect(startButton().onPressed, isNotNull);
      await tester.scrollUntilVisible(
        find.text('Safety readiness'),
        -150,
        scrollable: find
            .descendant(
              of: find.byType(FinalPreparationReviewPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('Safety readiness'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safety readiness'));
      await tester.pumpAndSettle();
      expect(find.text('Emergency contacts'), findsOneWidget);
      expect(find.text('Drinking water'), findsNothing);
      await tester.tap(find.text('Start hike'));
      await tester.pumpAndSettle();
      expect(reviewed!.requiredGearReady, isTrue);
      expect(reviewed!.checklistCompleted, lessThan(reviewed!.checklistTotal));
      expect(find.byType(FinalPreparationReviewPage), findsNothing);
    },
  );
  testWidgets(
    'new route findings block start until newly required poles are packed',
    (tester) async {
      final hike = fixtures.testHike();
      final plan = PlannedHikeStateResolver.resolve(
        upcomingHike: hike,
        liveTrails: [],
        emergencyContactsSelected: true,
        phoneBatteryLevel: 80,
      );
      final pending = Completer<RouteGearAssessment>();
      await openPage(
        tester,
        initialPlan: plan.copyWith(
          completedChecklistItems: plan.gearPlan.requiredItems,
        ),
        save: (_) async {},
        route: (_) => pending.future,
      );
      FilledButton startButton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start hike'),
      );
      expect(startButton().onPressed, isNull);
      pending.complete(
        RouteGearAssessment(
          routeKey: 'x',
          checkedAt: DateTime.now(),
          status: 'complete',
          rough: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(startButton().onPressed, isNull);
      await reveal(tester, 'Uneven terrain');
      await tester.ensureVisible(find.text('Uneven terrain'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uneven terrain'));
      await tester.pumpAndSettle();
      await reveal(tester, 'Trekking poles');
      await tester.tap(find.text('Trekking poles'));
      await tester.pumpAndSettle();
      expect(startButton().onPressed, isNotNull);
    },
  );
  testWidgets('fresh cold forecast adds blanket requirement before starting', (
    tester,
  ) async {
    final hike = fixtures.testHike();
    final plan = PlannedHikeStateResolver.resolve(
      upcomingHike: hike,
      liveTrails: [],
      emergencyContactsSelected: true,
      phoneBatteryLevel: 80,
    );
    final pending = Completer<TrailWeather>();
    await openPage(
      tester,
      initialPlan: plan.copyWith(
        completedChecklistItems: plan.gearPlan.requiredItems,
      ),
      save: (_) async {},
      weather: () => pending.future,
    );
    FilledButton startButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start hike'),
    );
    expect(startButton().onPressed, isNull);
    final forecast = fixtures.testForecast(hike.departureTime);
    final hourly = forecast.forecastData['hourly'] as Map;
    hourly['temperature_2m'] = List.filled(96, 14);
    hourly['precipitation_probability'] = List.filled(96, 0);
    pending.complete(forecast);
    await tester.pumpAndSettle();
    final checklist = tester.widget<TrailGearChecklist>(
      find.byType(TrailGearChecklist),
    );
    expect(checklist.plan.missingRequiredGear, {'Emergency blanket'});
    expect(startButton().onPressed, isNull);
    await reveal(tester, 'Emergency blanket');
    await tester.tap(find.text('Emergency blanket'));
    await tester.pumpAndSettle();
    expect(startButton().onPressed, isNotNull);
  });
  testWidgets(
    'participant can continue to team readiness only with their required pack',
    (tester) async {
      final hike = fixtures.testHike();
      final plan = PlannedHikeStateResolver.resolve(
        upcomingHike: hike,
        liveTrails: [],
        emergencyContactsSelected: true,
        phoneBatteryLevel: 80,
      );
      await openPage(
        tester,
        host: false,
        joiningTeam: true,
        initialPlan: plan,
        save: (_) async {},
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to team readiness'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await openPage(
        tester,
        host: false,
        joiningTeam: true,
        initialPlan: plan.copyWith(
          completedChecklistItems: plan.gearPlan.requiredItems,
        ),
        save: (_) async {},
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to team readiness'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
