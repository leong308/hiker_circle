// OnboardingRepository saves first-time profile details and prepares the selected profile photo.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../app/Data/user_module_paths.dart';

import '../../app/Data/conditional_cloud_cache.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../Model/onboarding_profile.dart';

/// Represents onboarding repository exception.
class OnboardingRepositoryException implements Exception {
  /// Creates onboarding repository exception.
  const OnboardingRepositoryException(this.message);

  final String message;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents onboarding repository.
class OnboardingRepository {
  /// Creates onboarding repository.
  OnboardingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalSessionDatabase? localDatabase,
    ConditionalCloudCache? cache,
    String? Function()? currentOwner,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _functions = functions,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _providedCache = cache,
       _currentOwner = currentOwner,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final LocalSessionDatabase _localDatabase;
  final ConditionalCloudCache? _providedCache;
  final String? Function()? _currentOwner;
  late final ConditionalCloudCache _cache =
      _providedCache ??
      ConditionalCloudCache(
        _localDatabase,
        () => _functions ?? FirebaseFunctions.instance,
        currentOwner: _currentOwner,
      );
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  /// Publishes validated downloaded profile changes across repository instances.
  Stream<CacheResourceUpdate> get cachedReadUpdates => _cache.updates;

  /// Returns resolved firestore.
  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Computes user document.
  DocumentReference<Map<String, dynamic>> _userDocument(AppSession session) {
    return userModuleDocument(
      _resolvedFirestore
          .collection('users')
          .doc(
            FirebaseUserRepository.documentIdForPhoneNumber(
              session.phoneNumber,
            ),
          ),
      UserModule.profile,
    );
  }

  /// Loads profile.
  Future<OnboardingProfile> loadProfile(
    AppSession session, {
    bool force = false,
    bool cacheOnly = false,
  }) async {
    try {
      final data = await _cache.read(
        owner: session.phoneNumber,
        type: 'profile',
        id: 'current',
        callable: 'readMobileResource',
        arguments: const {'resourceType': 'profile'},
        freshness: const Duration(minutes: 5),
        online: _firebaseBootstrapResult.isAvailable,
        force: force,
        cacheOnly: cacheOnly,
      );
      final profile = data['profile'];
      if (profile is! Map) {
        throw const OnboardingRepositoryException(
          'Your profile is not available on this device. Connect to the internet and try again.',
        );
      }
      final profileData = Map<String, dynamic>.from(profile);
      return OnboardingProfile.fromFirestore(profileData);
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  /// Save the selected profile fields and optional photo through the authenticated account repository.
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
        'profileSetupCompleted': true,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
        'profileUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));
      await _invalidateProfile(session);
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  /// Mark setup complete only after the required profile values have been saved.
  Future<void> completeOnboarding(AppSession session) async {
    _ensureFirebaseAvailable();
    try {
      final userDocument = _userDocument(session);
      await _resolvedFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userDocument);
        final sosSnapshot = await transaction.get(
          userModuleDocument(userDocument.parent.parent!, UserModule.sos),
        );
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

        final contacts = sosSnapshot.data()?['sos_contacts'];
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
          // Consent is already collected before the sign-up phone request.
          'onboardingVersion': 2,
        }, SetOptions(merge: true));
      });
      await _invalidateProfile(session);
    } on OnboardingRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw OnboardingRepositoryException(_firebaseMessage(error));
    }
  }

  Future<void> _invalidateProfile(AppSession session) async {
    try {
      await _cache.invalidateTypes(
        owner: session.phoneNumber,
        types: const {
          'public_profiles',
          'public_hiker_profile',
          'achievement_leaderboard',
        },
      );
      await _cache.invalidate(
        owner: session.phoneNumber,
        type: 'profile',
        id: 'current',
      );
      await loadProfile(session, force: true);
    } catch (_) {
      // Confirmed profile writes remain valid if their display refresh fails.
    }
  }

  /// Ensures firebase available.
  void _ensureFirebaseAvailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }
    throw OnboardingRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }

  /// Computes firebase message.
  String _firebaseMessage(FirebaseException error) {
    return 'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}';
  }
}
