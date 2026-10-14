import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/emergency_number_service.dart';
import 'package:hiker_circle/home/View/first_aid_guide_page.dart';
import 'package:hiker_circle/home/View/gear_checklist_page.dart';

void main() {
  testWidgets('first-aid page follows dark theme surfaces and text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: _darkTheme(),
        home: FirstAidGuidePage(
          emergencyLatitude: 5.4141,
          emergencyLongitude: 100.3288,
          emergencyNumberResolver: _ThemeTestEmergencyNumberResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      const Color(0xFF0C120F),
    );
    expect(
      tester.widget<Text>(find.text('First-Aid Guide')).style?.color,
      Theme.of(
        tester.element(find.byType(FirstAidGuidePage)),
      ).colorScheme.onSurface,
    );
    expect(
      Theme.of(tester.element(find.byType(FirstAidGuidePage))).brightness,
      Brightness.dark,
    );
    expect(_decoratedColors(tester), contains(const Color(0xFF141C17)));
  });

  testWidgets('first-aid page keeps its light palette in light mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: FirstAidGuidePage(
          emergencyLatitude: 5.4141,
          emergencyLongitude: 100.3288,
          emergencyNumberResolver: _ThemeTestEmergencyNumberResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      const Color(0xFFF2F2F7),
    );
    expect(
      tester.widget<Text>(find.text('First-Aid Guide')).style?.color,
      Theme.of(
        tester.element(find.byType(FirstAidGuidePage)),
      ).colorScheme.onSurface,
    );
    expect(_decoratedColors(tester), contains(Colors.white));
  });

  testWidgets('gear checklist no longer forces a light page in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: _darkTheme(),
        home: const GearChecklistPage(),
      ),
    );
    await tester.pump();

    final scheme = Theme.of(
      tester.element(find.byType(GearChecklistPage)),
    ).colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      scheme.surfaceContainerLow,
    );
    expect(
      tester.widget<Text>(find.text('Gear checklist')).style?.color,
      scheme.onSurface,
    );
    expect(_decoratedColors(tester), contains(scheme.surface));
  });
}

ThemeData _darkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0C120F),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF34A853),
      brightness: Brightness.dark,
      surface: const Color(0xFF141C17),
      primaryContainer: const Color(0xFF183625),
      surfaceContainerHighest: const Color(0xFF1B261F),
    ),
  );
}

List<Color?> _decoratedColors(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.color)
      .toList();
}

class _ThemeTestEmergencyNumberResolver implements EmergencyNumberResolver {
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
