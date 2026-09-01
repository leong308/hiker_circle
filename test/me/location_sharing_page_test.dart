import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/me/Data/live_location_sharing_service.dart';
import 'package:hiker_circle/me/View/location_sharing_page.dart';

void main() {
  tearDown(LiveLocationSharingService.instance.reset);

  testWidgets('shows the automatic hike-start contact sharing preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LocationSharingPage(
          phoneNumber: '+60123456789',
          firebaseBootstrapResult: FirebaseBootstrapResult.unavailable('test'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Share automatically when a hike starts'), findsOneWidget);
    expect(
      find.textContaining('sends it to every saved SOS contact'),
      findsOneWidget,
    );
    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
