import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Model/app_session.dart';
import '../Model/onboarding_profile.dart';

class OnboardingRepositoryException implements Exception {
  const OnboardingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OnboardingRepository {
  const OnboardingRepository({
    FirebaseFirestore? firestore,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDocument(AppSession session) {
    return _resolvedFirestore
        .collection('users')
        .doc(
          FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber),
        );
  }

  Future<OnboardingProfile> loadProfile(AppSession session) async {
    _ensureFirebaseAvailable();
    try {
      final snapshot = await _userDocument(session).get();
      final profile = snapshot.data()?['profile'];
      final profileData = profile is Map
          ? Map<String, dynamic>.from(profile)
          : <String, dynamic>{};
      profileData['photoURL'] ??= snapshot.data()?['photoURL'];
      return OnboardingProfile.fromFirestore(profileData);
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  Future<void> saveProfile({
    required AppSession session,
    required OnboardingProfile profile,
  }) async {
    if (!profile.isComplete) {
      throw const OnboardingRepositoryException(
        'Complete every profile field before continuing.',
      );
    }
    _ensureFirebaseAvailable();
    try {
      final now = DateTime.now().toUtc();
      await _userDocument(session).set({
        'profile': profile.toFirestore(),
        'username': profile.username.trim(),
        'profileSetupCompleted': true,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
        'profileUpdatedAtLocal': now.toIso8601String(),
        if (profile.photoURL != null) 'photoURL': profile.photoURL,
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  Future<void> completeOnboarding(AppSession session) async {
    _ensureFirebaseAvailable();
    try {
      final userDocument = _userDocument(session);
      await _resolvedFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocument);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          throw const OnboardingRepositoryException(
            'Your account record could not be found. Sign in again.',
          );
        }
        if (data['requiresOnboarding'] == false) {
          return;
        }

        final profile = data['profile'];
        final parsedProfile = OnboardingProfile.fromFirestore(
          profile is Map ? Map<String, dynamic>.from(profile) : null,
        );
        if (!parsedProfile.isComplete ||
            data['profileSetupCompleted'] != true) {
          throw const OnboardingRepositoryException(
            'Complete your profile before adding emergency contacts.',
          );
        }

        final contacts = data['sos_contacts'];
        if (contacts is! Iterable || contacts.isEmpty) {
          throw const OnboardingRepositoryException(
            'Add at least one emergency contact before continuing.',
          );
        }

        final now = DateTime.now().toUtc();
        transaction.set(userDocument, {
          'requiresOnboarding': false,
          'onboardingCompletedAt': FieldValue.serverTimestamp(),
          'onboardingCompletedAtLocal': now.toIso8601String(),
          'onboardingVersion': 1,
        }, SetOptions(merge: true));
      });
    } on OnboardingRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  void _ensureFirebaseAvailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }
    throw OnboardingRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }

  String _firebaseMessage(FirebaseException error) {
    return 'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}';
  }
}
