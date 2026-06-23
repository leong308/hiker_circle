import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Model/app_session.dart';
import 'firebase_bootstrap.dart';

class FirebaseUserRepositoryException implements Exception {
  const FirebaseUserRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseUserRepository {
  FirebaseUserRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? firebaseFunctions,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _firebaseAuth = firebaseAuth,
       _firebaseFunctions = firebaseFunctions,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _firebaseAuth;
  final FirebaseFunctions? _firebaseFunctions;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  FirebaseAuth get _resolvedFirebaseAuth =>
      _firebaseAuth ?? FirebaseAuth.instance;

  FirebaseFunctions get _resolvedFirebaseFunctions =>
      _firebaseFunctions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  static String documentIdForPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll('/', '_');
  }

  Future<AppSession> registerOrLoadUser(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw FirebaseUserRepositoryException(
        'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
            .trim(),
      );
    }

    try {
      final now = DateTime.now().toUtc();
      final userDocument = _users.doc(
        documentIdForPhoneNumber(session.phoneNumber),
      );

      final registeredSession = await _resolvedFirestore.runTransaction((
        transaction,
      ) async {
        final snapshot = await transaction.get(userDocument);
        final appInstanceId = session.appInstanceId;
        if (!snapshot.exists) {
          transaction.set(userDocument, {
            'phoneNumber': session.phoneNumber,
            'requiresOnboarding': true,
            'profileSetupCompleted': false,
            'onboardingVersion': 1,
            'boundAppInstanceId': appInstanceId,
            'currentAppId': appInstanceId,
            'lastSignedInAppInstanceId': appInstanceId,
            'boundAppInstanceUpdatedAtLocal': now.toIso8601String(),
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtLocal': now.toIso8601String(),
            'lastSignedInAt': FieldValue.serverTimestamp(),
            'lastSignedInAtLocal': now.toIso8601String(),
          });

          return session.copyWith(
            createdAt: now,
            signedInAt: now,
            appInstanceId: appInstanceId,
            username: '',
            requiresOnboarding: true,
            isOnboardingProfileComplete: false,
          );
        }

        final data = snapshot.data();
        final createdAt =
            _dateFromValue(data?['createdAt']) ??
            _dateFromValue(data?['createdAtLocal']) ??
            now;
        final existingAppInstanceId = _stringFrom(data?['boundAppInstanceId']);
        final isRebinding =
            appInstanceId.isNotEmpty &&
            existingAppInstanceId.isNotEmpty &&
            existingAppInstanceId != appInstanceId;
        final requiresOnboarding = _requiresOnboarding(data);
        final isOnboardingProfileComplete = _isProfileSetupComplete(data);

        transaction.set(userDocument, {
          'phoneNumber': session.phoneNumber,
          if (data?['requiresOnboarding'] is! bool)
            'requiresOnboarding': requiresOnboarding,
          if (data?['profileSetupCompleted'] is! bool)
            'profileSetupCompleted': isOnboardingProfileComplete,
          if (data?['onboardingVersion'] == null) 'onboardingVersion': 1,
          'boundAppInstanceId': appInstanceId,
          'currentAppId': appInstanceId,
          'lastSignedInAppInstanceId': appInstanceId,
          'boundAppInstanceUpdatedAt': FieldValue.serverTimestamp(),
          'boundAppInstanceUpdatedAtLocal': now.toIso8601String(),
          if (isRebinding) ...{
            'previousBoundAppInstanceId': existingAppInstanceId,
            'deviceReboundAt': FieldValue.serverTimestamp(),
            'deviceReboundAtLocal': now.toIso8601String(),
            'deviceRebindVerifiedBy': 'whatsapp_otp',
          },
          'lastSignedInAt': FieldValue.serverTimestamp(),
          'lastSignedInAtLocal': now.toIso8601String(),
        }, SetOptions(merge: true));

        return session.copyWith(
          createdAt: createdAt,
          signedInAt: now,
          appInstanceId: appInstanceId,
          isAdmin: _isAdmin(data),
          username: _username(data),
          requiresOnboarding: requiresOnboarding,
          isOnboardingProfileComplete: isOnboardingProfileComplete,
        );
      });
      await authenticateAppSession(registeredSession);
      return registeredSession;
    } on FirebaseException catch (error) {
      throw FirebaseUserRepositoryException(
        'Firebase ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<AppSession> refreshBoundSession(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw FirebaseUserRepositoryException(
        'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
            .trim(),
      );
    }

    try {
      await authenticateAppSession(session);
      final snapshot = await _users
          .doc(documentIdForPhoneNumber(session.phoneNumber))
          .get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return session;
      }

      final boundAppInstanceId = _stringFrom(data['boundAppInstanceId']);
      if (boundAppInstanceId.isNotEmpty &&
          session.appInstanceId.isNotEmpty &&
          boundAppInstanceId != session.appInstanceId) {
        throw const FirebaseUserRepositoryException(
          'This account is now bound to another phone. Request a new WhatsApp code to use it here again.',
        );
      }

      return session.copyWith(
        isAdmin: _isAdmin(data),
        username: _username(data),
        requiresOnboarding: _requiresOnboarding(data),
        isOnboardingProfileComplete: _isProfileSetupComplete(data),
        photoURL: _photoURL(data),
      );
    } on FirebaseUserRepositoryException {
      rethrow;
    } on FirebaseException catch (error) {
      throw FirebaseUserRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
      );
    }
  }

  Future<User> authenticateAppSession(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw FirebaseUserRepositoryException(
        'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
            .trim(),
      );
    }
    if (session.phoneNumber.trim().isEmpty ||
        session.appInstanceId.trim().isEmpty) {
      throw const FirebaseUserRepositoryException(
        'The saved login credentials are incomplete. Sign in again.',
      );
    }

    try {
      final callable = _resolvedFirebaseFunctions.httpsCallable(
        'authenticateAppSession',
      );
      final response = await callable.call(<String, Object?>{
        'phoneNumber': session.phoneNumber,
        'appInstanceId': session.appInstanceId,
      });
      final data = response.data;
      if (data is! Map || data['customToken'] is! String) {
        throw const FirebaseUserRepositoryException(
          'Firebase returned an invalid authentication response.',
        );
      }
      final expectedUserId = documentIdForPhoneNumber(session.phoneNumber);
      final credential = await _resolvedFirebaseAuth.signInWithCustomToken(
        data['customToken'] as String,
      );
      final user = credential.user;
      if (user == null || user.uid != expectedUserId) {
        await _resolvedFirebaseAuth.signOut();
        throw const FirebaseUserRepositoryException(
          'Firebase could not validate this HikerCircle account.',
        );
      }
      return user;
    } on FirebaseUserRepositoryException {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseUserRepositoryException(
        error.message ?? 'Firebase rejected the saved login.',
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseUserRepositoryException(
        error.message ?? 'Firebase authentication failed.',
      );
    }
  }

  Future<void> signOut() async {
    await _resolvedFirebaseAuth.signOut();
  }

  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  bool _isAdmin(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    final role = _stringFrom(data['role']).toLowerCase();
    final roles = data['roles'];
    return data['isAdmin'] == true ||
        role == 'admin' ||
        role == 'super_admin' ||
        (roles is Iterable &&
            roles.any((value) => _stringFrom(value).toLowerCase() == 'admin'));
  }

  bool _requiresOnboarding(Map<String, dynamic>? data) {
    final value = data?['requiresOnboarding'];
    return value is bool ? value : true;
  }

  String _username(Map<String, dynamic>? data) {
    final topLevelUsername = _stringFrom(data?['username']).trim();
    if (topLevelUsername.isNotEmpty) {
      return topLevelUsername;
    }
    final profile = data?['profile'];
    return profile is Map ? _stringFrom(profile['username']).trim() : '';
  }

  String? _photoURL(Map<String, dynamic>? data) {
    final topLevel = _stringFrom(data?['photoURL']).trim();
    if (topLevel.isNotEmpty) {
      return topLevel;
    }
    final profile = data?['profile'];
    if (profile is Map) {
      final fromProfile = _stringFrom(profile['photoURL']).trim();
      if (fromProfile.isNotEmpty) {
        return fromProfile;
      }
    }
    return null;
  }

  bool _isProfileSetupComplete(Map<String, dynamic>? data) {
    if (data?['profileSetupCompleted'] == true) {
      return true;
    }
    final profile = data?['profile'];
    if (profile is! Map) {
      return false;
    }
    return _stringFrom(profile['username']).trim().isNotEmpty &&
        _stringFrom(profile['gender']).trim().isNotEmpty &&
        _stringFrom(profile['hikerExperience']).trim().isNotEmpty &&
        _stringFrom(profile['hikeFrequency']).trim().isNotEmpty &&
        _stringFrom(profile['residentialLocation']).trim().isNotEmpty &&
        profile['residentialLatitude'] is num &&
        profile['residentialLongitude'] is num;
  }

  String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}
