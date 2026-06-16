import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/onboarding/Model/onboarding_profile.dart';
import 'package:hiker_circle/onboarding/View/onboarding_profile_page.dart';

void main() {
  testWidgets('clears username error after valid input', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingProfilePage(
          initialProfile: const OnboardingProfile(),
          onSubmit: (_) async {},
        ),
      ),
    );

    final continueButton = find.text('Continue to emergency contacts');
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pump();

    expect(
      find.text('Username must contain at least 3 characters.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), 'trailwalker');
    await tester.pump();

    expect(
      find.text('Username must contain at least 3 characters.'),
      findsNothing,
    );
  });
}
