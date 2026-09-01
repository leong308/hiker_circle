import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/privacy_policy_launcher.dart';
import 'package:hiker_circle/core/widgets/privacy_policy_link.dart';
import 'package:hiker_circle/me/Data/me_repository.dart';

void main() {
  testWidgets('authentication screen exposes one Privacy Policy link', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrivacyPolicyLink())),
    );

    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  test('signed-in settings expose one Privacy Policy item', () {
    final items = const MeRepository()
        .loadSections()
        .expand((section) => section.items)
        .where((item) => item.title == 'Privacy Policy');

    expect(items, hasLength(1));
  });

  test('Privacy Policy points to the hosted policy page', () {
    expect(
      privacyPolicyUri.toString(),
      'https://hiker-circle.web.app/privacy-policy',
    );
  });
}
