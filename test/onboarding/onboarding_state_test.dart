import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/onboarding/Model/onboarding_profile.dart';

void main() {
  group('OnboardingProfile', () {
    test('requires every mandatory profile value', () {
      const incompleteProfile = OnboardingProfile(
        username: 'trailwalker',
        gender: 'female',
        hikerExperience: 'new',
      );
      const completeProfile = OnboardingProfile(
        username: 'trailwalker',
        gender: 'female',
        hikerExperience: 'new',
        hikeFrequency: 'monthly',
        residentialLocation: 'Singapore',
        residentialLatitude: 1.3521,
        residentialLongitude: 103.8198,
      );

      expect(incompleteProfile.isComplete, isFalse);
      expect(completeProfile.isComplete, isTrue);
    });

    test('round trips Firestore profile values', () {
      const profile = OnboardingProfile(
        username: 'trailwalker',
        gender: 'prefer_not_to_say',
        hikerExperience: 'experienced',
        hikeFrequency: 'weekly',
        residentialLocation: '  Tampines  ',
        residentialLatitude: 1.3496,
        residentialLongitude: 103.9568,
      );

      final restored = OnboardingProfile.fromFirestore(profile.toFirestore());

      expect(restored.username, 'trailwalker');
      expect(restored.gender, 'prefer_not_to_say');
      expect(restored.hikerExperience, 'experienced');
      expect(restored.hikeFrequency, 'weekly');
      expect(restored.residentialLocation, 'Tampines');
      expect(restored.residentialLatitude, 1.3496);
      expect(restored.residentialLongitude, 103.9568);
      expect(restored.isComplete, isTrue);
    });

    test('copyWith updates editable values and preserves identity', () {
      const profile = OnboardingProfile(
        username: 'trailwalker',
        gender: 'female',
        hikerExperience: 'new',
        hikeFrequency: 'rarely',
        residentialLocation: 'Kuala Lumpur, Malaysia',
        residentialLatitude: 3.139,
        residentialLongitude: 101.6869,
      );

      final updated = profile.copyWith(
        hikerExperience: 'experienced',
        hikeFrequency: 'weekly',
      );

      expect(updated.username, profile.username);
      expect(updated.gender, profile.gender);
      expect(updated.hikerExperience, 'experienced');
      expect(updated.hikeFrequency, 'weekly');
      expect(updated.residentialLocation, profile.residentialLocation);
    });
  });

  test('AppSession copyWith preserves and updates onboarding state', () {
    final signedInAt = DateTime.utc(2026, 6, 15);
    final session = AppSession(
      phoneNumber: '+60123456789',
      signedInAt: signedInAt,
      username: 'trailwalker',
      requiresOnboarding: true,
      isOnboardingProfileComplete: true,
    );

    final completed = session.copyWith(requiresOnboarding: false);

    expect(completed.requiresOnboarding, isFalse);
    expect(completed.isOnboardingProfileComplete, isTrue);
    expect(completed.username, 'trailwalker');
    expect(completed.phoneNumber, session.phoneNumber);
  });
}
