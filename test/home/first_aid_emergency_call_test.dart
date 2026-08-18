import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/emergency_number_service.dart';
import 'package:hiker_circle/home/View/first_aid_guide_page.dart';

void main() {
  testWidgets('shows the regional emergency call action below search', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FirstAidGuidePage(
          emergencyLatitude: 5.4141,
          emergencyLongitude: 100.3288,
          emergencyNumberResolver: _FakeEmergencyNumberResolver(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Call emergency services'), findsOneWidget);
    expect(find.text('Malaysia ambulance service • 999'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Call 999'), findsOneWidget);
  });
}

class _FakeEmergencyNumberResolver implements EmergencyNumberResolver {
  @override
  Future<EmergencyDialTarget> resolve({
    double? latitude,
    double? longitude,
    String? fallbackCountryCode,
  }) async {
    expect(latitude, 5.4141);
    expect(longitude, 100.3288);
    return const EmergencyDialTarget(
      number: '999',
      countryCode: 'MY',
      countryName: 'Malaysia',
      isLocationBased: true,
      isFallback: false,
    );
  }
}
