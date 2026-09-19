import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_preparation_sharing.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/Model/route_gear_assessment.dart';
import 'package:hiker_circle/home/View/final_preparation_review_page.dart';
import 'package:hiker_circle/home/View/preparation_conditions.dart';
import 'package:hiker_circle/home/View/preparation_safety_details_page.dart';
import 'package:hiker_circle/home/View/hiking_forecast_sheet.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'final_preparation_review_page_test.dart' as guide;
import 'next_hike_briefing_test.dart' as fixtures;

Future<void> toStep(WidgetTester tester, String step) async {
  await guide.tap(tester, 'Skip extras');
  for (final id in ['contacts', 'battery', 'sharing', 'conditions']) {
    if (id == step) return;
    await guide.tap(tester, 'Continue');
  }
}

Future<void> revealAndTap(WidgetTester tester, String text) async {
  await guide.reveal(tester, text);
  await guide.tap(tester, text);
  await tester.pumpAndSettle();
}

void main() {
  const contactA = EmergencyContact(
    name: 'Alex',
    phoneNumber: '+60111111111',
    relationship: 'Sibling',
  );
  const contactB = EmergencyContact(
    name: 'Jamie',
    phoneNumber: '+60222222222',
    relationship: 'Friend',
  );
  const contactC = EmergencyContact(
    name: 'Taylor',
    phoneNumber: '+60333333333',
    relationship: 'Partner',
  );

  testWidgets(
    'contact editor returns to the same question with all updated contacts and packed gear intact',
    (tester) async {
      var contacts = [contactA, contactB];
      final plan = guide.testPlan(packed: true);
      PlannedHike? reviewed;
      await guide.openPage(
        tester,
        initialPlan: plan,
        contacts: contacts,
        save: (_) async {},
        loadContacts: () async => contacts,
        ready: (value) => reviewed = value,
        editContacts: () async {
          final context = tester.element(
            find.byType(FinalPreparationReviewPage),
          );
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Edit emergency contacts')),
                body: TextButton(
                  onPressed: () {
                    contacts = [contactB, contactC];
                    Navigator.pop(context);
                  },
                  child: const Text('Save contacts'),
                ),
              ),
            ),
          );
        },
      );
      await toStep(tester, 'contacts');
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Jamie'), findsOneWidget);
      expect(find.text('+60111111111'), findsOneWidget);
      final state = tester.state(find.byType(FinalPreparationReviewPage));
      await revealAndTap(tester, 'Modify contacts');
      expect(
        find.byType(FinalPreparationReviewPage, skipOffstage: false),
        findsOneWidget,
      );
      await guide.tap(tester, 'Save contacts');
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(FinalPreparationReviewPage)),
        same(state),
      );
      expect(find.text('Who can help if you need it?'), findsOneWidget);
      expect(find.text('Taylor'), findsOneWidget);
      expect(find.text('Jamie'), findsOneWidget);
      expect(find.text('Alex'), findsNothing);
      await guide.finishGuide(tester);
      await guide.tap(tester, 'Start hike');
      await tester.pumpAndSettle();
      expect(reviewed!.completedChecklistItems, plan.completedChecklistItems);
      expect(reviewed!.emergencyContactsSelected, isTrue);
    },
  );

  testWidgets(
    'contacts removed in an editor are refreshed even when system Back returns no result',
    (tester) async {
      var contacts = [contactA];
      await guide.openPage(
        tester,
        initialPlan: guide.testPlan(packed: true),
        contacts: contacts,
        save: (_) async {},
        loadContacts: () async => contacts,
        editContacts: () async {
          final context = tester.element(
            find.byType(FinalPreparationReviewPage),
          );
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Contact editor')),
            ),
          );
        },
      );
      await toStep(tester, 'contacts');
      await revealAndTap(tester, 'Modify contacts');
      contacts = [];
      Navigator.of(tester.element(find.text('Contact editor'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('No emergency contacts saved.'), findsOneWidget);
      expect(find.text('Alex'), findsNothing);
      expect(find.text('Who can help if you need it?'), findsOneWidget);
    },
  );

  testWidgets(
    'battery details return to the battery question with a fresh reading',
    (tester) async {
      var level = 42;
      await guide.openPage(
        tester,
        initialPlan: guide.testPlan(packed: true),
        save: (_) async {},
        battery: () async => level,
      );
      await toStep(tester, 'battery');
      expect(find.text('Phone battery · 42%'), findsOneWidget);
      await revealAndTap(tester, 'Battery details');
      expect(find.byType(PreparationBatteryPage), findsOneWidget);
      level = 76;
      await tester.ensureVisible(find.text('Return to preparation'));
      await guide.tap(tester, 'Return to preparation');
      await tester.pumpAndSettle();
      expect(find.text('Is your phone ready for the trail?'), findsOneWidget);
      expect(find.text('Phone battery · 76%'), findsOneWidget);
      level = 79;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Phone battery · 79%'), findsOneWidget);
    },
  );

  testWidgets(
    'sharing changes save before returning and reach the hike draft',
    (tester) async {
      HikePreparationSharing? saved;
      PlannedHike? reviewed;
      final plan = guide.testPlan(packed: true);
      await guide.openPage(
        tester,
        initialPlan: plan,
        save: (_) async {},
        saveSharing: (choice) async => saved = choice,
        ready: (value) => reviewed = value,
      );
      await toStep(tester, 'sharing');
      await revealAndTap(tester, 'Modify sharing');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Every 1 minute'));
      await guide.tap(tester, 'Every 1 minute');
      await tester.ensureVisible(find.text('Save and return'));
      await tester.pumpAndSettle();
      await guide.tap(tester, 'Save and return');
      await tester.pumpAndSettle();
      expect(saved!.enabled, isTrue);
      expect(saved!.interval, const Duration(minutes: 1));
      expect(find.text('How will you share your location?'), findsOneWidget);
      expect(
        find.text('Live location sharing is on for this hike.'),
        findsOneWidget,
      );
      expect(find.text('Cloud upload · Every 1 minute'), findsOneWidget);
      await guide.finishGuide(tester);
      await guide.tap(tester, 'Start hike');
      await tester.pumpAndSettle();
      final draft = reviewed!.applyToDraft(
        HikeSessionDraft.fromTrail(plan.trail),
      );
      expect(draft.shareLiveLocation, isTrue);
      expect(draft.locationRecordingInterval, const Duration(minutes: 1));
      expect(draft.completedChecklistItems, plan.completedChecklistItems);
    },
  );

  testWidgets(
    'failed sharing save stays in editor and Back discards only unsaved sharing changes',
    (tester) async {
      await guide.openPage(
        tester,
        initialPlan: guide.testPlan(packed: true),
        save: (_) async {},
        saveSharing: (_) async => throw Exception('Disk unavailable'),
      );
      await toStep(tester, 'sharing');
      await revealAndTap(tester, 'Modify sharing');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save and return'));
      await tester.pumpAndSettle();
      await guide.tap(tester, 'Save and return');
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save your sharing choices. Please try again.'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(PreparationSharingPage))).pop();
      await tester.pumpAndSettle();
      expect(
        find.text('Live location sharing is off for this hike.'),
        findsOneWidget,
      );
      expect(find.text('How will you share your location?'), findsOneWidget);
    },
  );

  testWidgets(
    'restored per-hike sharing wins over defaults without replacing newly packed gear',
    (tester) async {
      final restored = Completer<HikePreparationSharing?>();
      PlannedHike? reviewed;
      await guide.openPage(
        tester,
        initialPlan: guide.testPlan(),
        save: (_) async {},
        loadSharing: () => restored.future,
        ready: (value) => reviewed = value,
      );
      await guide.tap(tester, 'Yes, packed');
      restored.complete(
        const HikePreparationSharing(
          enabled: true,
          interval: Duration(seconds: 15),
        ),
      );
      await tester.pumpAndSettle();
      await guide.finishGuide(tester);
      await guide.tap(tester, 'Start hike');
      await tester.pumpAndSettle();
      expect(reviewed!.liveLocationConfigured, isTrue);
      expect(reviewed!.locationRecordingInterval, const Duration(seconds: 15));
      expect(reviewed!.completedChecklistItems, contains('Drinking water'));
    },
  );

  testWidgets(
    'conditions show current readings, scheduled forecast and terrain; full forecast returns to same step',
    (tester) async {
      var plan = guide.testPlan(packed: true);
      final forecast = fixtures.testForecast(plan.plannedStartTime);
      forecast.forecastData['current'] = {
        'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'temperature_2m': 29.5,
        'apparent_temperature': 32.0,
        'wind_speed_10m': 8.5,
        'precipitation': 0.2,
        'relative_humidity_2m': 72,
        'weather_code': 3,
      };
      plan = plan.copyWith(
        trail: plan.trail.copyWith(weather: forecast),
        gearAssessment: RouteGearAssessment(
          routeKey: 'route',
          checkedAt: DateTime.now(),
          status: 'complete',
          rough: true,
        ),
      );
      plan = plan.copyWith(
        completedChecklistItems: plan.gearPlan.requiredItems,
      );
      await guide.openPage(tester, initialPlan: plan, save: (_) async {});
      await toStep(tester, 'conditions');
      expect(find.text('Current conditions at the trail'), findsOneWidget);
      expect(find.text('29.5°C'), findsOneWidget);
      expect(find.text('8.5 km/h'), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('• Uneven ground'), findsOneWidget);
      await guide.reveal(tester, 'View full forecast');
      await guide.tap(tester, 'View full forecast');
      expect(find.byType(HikingForecastSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(HikingForecastSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Have you checked the conditions?'), findsOneWidget);
      expect(find.byType(PreparationConditions), findsOneWidget);
    },
  );

  testWidgets(
    'missing current and scheduled weather is shown as unavailable rather than invented zeros',
    (tester) async {
      final now = DateTime.utc(2026, 9, 18, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreparationConditions(
                weather: TrailWeather(
                  summary: '',
                  temperatureRange: '',
                  rainProbability: 0,
                  cachedAt: now,
                  forecastData: {
                    'current': {
                      'time': double.infinity,
                      'temperature_2m': double.nan,
                    },
                  },
                ),
                departure: now,
                returning: now.add(const Duration(hours: 2)),
                now: now,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Current conditions are unavailable. Refresh or check local conditions.',
        ),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsNWidgets(2));
      expect(find.text('0%'), findsNothing);
      expect(find.text('0.0°C'), findsNothing);
    },
  );

  test('sharing preferences reject malformed or unsupported intervals', () {
    expect(
      HikePreparationSharing.fromJson({
        'enabled': true,
        'seconds': 60,
      })!.interval,
      const Duration(minutes: 1),
    );
    expect(
      HikePreparationSharing.fromJson({'enabled': 'true', 'seconds': 60}),
      isNull,
    );
    expect(
      HikePreparationSharing.fromJson({'enabled': true, 'seconds': -1}),
      isNull,
    );
    expect(
      HikePreparationSharing.fromJson({'enabled': true, 'seconds': 300}),
      isNull,
    );
  });
  testWidgets(
    'a failed sharing restore is explained and must be reviewed before start',
    (tester) async {
      await guide.openPage(
        tester,
        initialPlan: guide.testPlan(packed: true),
        save: (_) async {},
        loadSharing: () async => throw Exception('Storage unavailable'),
        saveSharing: (_) async {},
      );
      await guide.finishGuide(tester);
      expect(find.text('Start hike'), findsNothing);
      await guide.tap(tester, 'Review sharing choices');
      expect(find.text('How will you share your location?'), findsOneWidget);
      await revealAndTap(tester, 'Modify sharing');
      await tester.ensureVisible(find.text('Save and return'));
      await tester.pumpAndSettle();
      await guide.tap(tester, 'Save and return');
      await tester.pumpAndSettle();
      await guide.finishGuide(tester);
      expect(find.text('Start hike'), findsOneWidget);
      expect(guide.continueButton(tester).onPressed, isNotNull);
    },
  );
}
