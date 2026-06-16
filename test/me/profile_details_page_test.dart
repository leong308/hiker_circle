import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/me/View/profile_details_page.dart';
import 'package:hiker_circle/onboarding/Data/onboarding_repository.dart';
import 'package:hiker_circle/onboarding/Model/onboarding_profile.dart';

void main() {
  testWidgets('shows profile details load error with retry action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileDetailsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 6, 15),
          ),
          firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
            'Firebase unavailable for test',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Personal Profile'), findsOneWidget);
    expect(find.text('Unable to load profile'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_rounded), findsNothing);
  });

  testWidgets('shows edit actions without duplicate identity details', (
    tester,
  ) async {
    final session = AppSession(
      phoneNumber: '+60123456789',
      signedInAt: DateTime.utc(2026, 6, 15),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileDetailsPage(
          session: session,
          repository: _FakeOnboardingRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@trailwalker'), findsNothing);
    expect(find.text('Verified and complete'), findsNothing);
    expect(find.text('Experienced hiker'), findsOneWidget);
    expect(find.text('Edit'), findsNWidgets(3));
  });
}

class _FakeOnboardingRepository extends OnboardingRepository {
  _FakeOnboardingRepository();

  @override
  Future<OnboardingProfile> loadProfile(AppSession session) async {
    return const OnboardingProfile(
      username: 'trailwalker',
      gender: 'female',
      hikerExperience: 'experienced',
      hikeFrequency: 'monthly',
      residentialLocation: 'Kuala Lumpur, Malaysia',
      residentialLatitude: 3.139,
      residentialLongitude: 101.6869,
    );
  }

  @override
  Future<void> saveProfile({
    required AppSession session,
    required OnboardingProfile profile,
  }) async {}
}
