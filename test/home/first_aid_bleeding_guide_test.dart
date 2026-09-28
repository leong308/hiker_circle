import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/emergency_number_service.dart';
import 'package:hiker_circle/home/View/first_aid_guide_page.dart';

void main() {
  testWidgets('bleeding and falls use focused condition response sheets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: FirstAidGuidePage(
          emergencyLatitude: 5.4141,
          emergencyLongitude: 100.3288,
          emergencyNumberResolver: _MalaysiaEmergencyNumberResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('first-aid-category-Bleeding')));
    await tester.pumpAndSettle();

    expect(find.text('KKM VIDEO REFERENCE'), findsNothing);
    expect(find.textContaining('Select the closest situation'), findsNothing);
    expect(find.byKey(const ValueKey('first-aid-scenario-list')), findsOne);
    expect(find.text('Bleeding wound'), findsOne);
    expect(find.byIcon(Icons.touch_app_rounded), findsWidgets);
    expect(find.byKey(const ValueKey('first-aid-action-count')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('first-aid-scenario-nosebleed')),
      220,
    );
    await tester.tap(
      find.byKey(const ValueKey('first-aid-scenario-nosebleed')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('first-aid-scenario-sheet-nosebleed')),
      findsOne,
    );
    expect(find.text('Nosebleed'), findsWidgets);
    expect(find.text('Pinch continuously for 10–15 minutes'), findsWidgets);
    expect(find.text('ACTION 1 OF 5'), findsOne);
    await tester.tap(find.byKey(const ValueKey('first-aid-action-next')));
    await tester.pumpAndSettle();
    expect(find.text('ACTION 2 OF 5'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('first-aid-reference-nosebleed')),
      260,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('first-aid-scenario-sheet-nosebleed')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const ValueKey('first-aid-reference-nosebleed')),
      findsOne,
    );

    await tester.tap(find.byKey(const ValueKey('first-aid-scenario-close')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('first-aid-category-Falls and Injury')),
    );
    await tester.pumpAndSettle();
    expect(find.text('KKM VIDEO REFERENCE'), findsNothing);
    expect(find.text('Minor fall or bruise'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('first-aid-scenario-head_injury')),
      220,
    );
    await tester.tap(
      find.byKey(const ValueKey('first-aid-scenario-head_injury')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('first-aid-scenario-sheet-head_injury')),
      findsOne,
    );
    expect(find.text('Head injury or concussion'), findsWidgets);
    expect(find.text('Monitor closely; red flags need 999'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('first-aid-reference-head_injury')),
      260,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('first-aid-scenario-sheet-head_injury')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const ValueKey('first-aid-reference-head_injury')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });
}

class _MalaysiaEmergencyNumberResolver implements EmergencyNumberResolver {
  @override
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
    String? fallbackCountryCode,
  }) async {
    return const EmergencyDialTarget(
      number: '999',
      countryCode: 'MY',
      countryName: 'Malaysia',
      isLocationBased: true,
      isFallback: false,
    );
  }
}
