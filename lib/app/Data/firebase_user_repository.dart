// FirebaseUserRepository resolves the signed-in account and profile modules before building the
// local AppSession.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Model/app_session.dart';
import 'firebase_bootstrap.dart';
import 'user_module_paths.dart';
import '../../core/models/account_role.dart';
import '../../onboarding/Model/privacy_consent_receipt.dart';

/// Represents firebase user repository exception.
class FirebaseUserRepositoryException implements Exception {
  /// Creates firebase user repository exception.
  const FirebaseUserRepositoryException(
    this.message, {
    this.requiresSignIn = false,
  });

  final String message;
  final bool requiresSignIn;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents firebase user repository.
class FirebaseUserRepository {
  /// Creates firebase user repository.
  FirebaseUserRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? firebaseAuth,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _firebaseAuth = firebaseAuth,
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _firebaseAuth;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  /// Returns resolved firestore.
  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Returns resolved firebase auth.
  FirebaseAuth get _resolvedFirebaseAuth =>
      _firebaseAuth ?? FirebaseAuth.instance;

  /// Returns users.
  CollectionReference<Map<String, dynamic>> get _users {
    return _resolvedFirestore.collection('users');
  }

  /// Computes document id for phone number.
  static String documentIdForPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll('/', '_');
  }

  /// Computes register or load user.
  Future<AppSession> registerOrLoadUser(AppSession session) async {
    // Login activation and device ownership are committed by the server.
    return refreshBoundSession(session);
  }

  /// Watches session state.
  Stream<Map<String, dynamic>> watchSessionState(String phoneNumber) {
    return _resolvedFirestore
        .collection('mobileSessions')
        .doc(documentIdForPhoneNumber(phoneNumber))
        .snapshots(includeMetadataChanges: true)
        .where(
          (event) =>
              !event.metadata.isFromCache && !event.metadata.hasPendingWrites,
        )
        .map((event) => event.data() ?? <String, dynamic>{});
  }

  /// Publishes confirmed account roles independently of mobile-session changes.
  Stream<Map<String, dynamic>> watchAccountState(String phoneNumber) => _users
      .doc(documentIdForPhoneNumber(phoneNumber))
      .snapshots(includeMetadataChanges: true)
      .where(
        (event) =>
            !event.metadata.isFromCache && !event.metadata.hasPendingWrites,
      )
      .map((event) => event.data() ?? <String, dynamic>{});

  /// Refreshes bound session.
  Future<AppSession> refreshBoundSession(AppSession session) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw FirebaseUserRepositoryException(
        'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
            .trim(),
      );
    }

    try {
      await _requireAuthenticatedMfaSession(session);
      final account = _users.doc(documentIdForPhoneNumber(session.phoneNumber));
      final snapshots = await Future.wait([
        account.get(const GetOptions(source: Source.server)),
        userModuleDocument(
          account,
          UserModule.profile,
        ).get(const GetOptions(source: Source.server)),
        userModuleDocument(
          account,
          UserModule.devices,
        ).get(const GetOptions(source: Source.server)),
      ]);
      // A missing/stale downloaded document is not proof of account deletion,
      // disability or device replacement. Only confirmed server data may revoke
      // a restored session or replace its saved profile/onboarding state.
      if (snapshots.any(
        (snapshot) =>
            snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites,
      )) {
        throw const FirebaseUserRepositoryException(
          'Your saved login is available. Connect to verify the latest account state.',
        );
      }
      if (!snapshots[0].exists) {
        throw const FirebaseUserRepositoryException(
          'Your account record is unavailable. Sign in again.',
          requiresSignIn: true,
        );
      }
      final data = <String, dynamic>{
        ...?snapshots[0].data(),
        ...?snapshots[1].data(),
        ...?snapshots[2].data(),
      };

      if (data['accountDisabled'] == true || data['status'] == 'disabled') {
        throw const FirebaseUserRepositoryException(
          'This account is disabled.',
          requiresSignIn: true,
        );
      }
      final boundAppInstanceId = _stringFrom(data['boundAppInstanceId']);
      if (boundAppInstanceId.isNotEmpty &&
          session.appInstanceId.isNotEmpty &&
          boundAppInstanceId != session.appInstanceId) {
        throw const FirebaseUserRepositoryException(
          'This account is now bound to another phone. Request a new WhatsApp code to use it here again.',
          requiresSignIn: true,
        );
      }

      return session.copyWith(
        isAdmin: _isAdmin(data),
        isSuperAdmin: AccountRole.fromAccount(data) == AccountRole.superadmin,
        username: _username(data),
        requiresOnboarding: _requiresOnboarding(data),
        isOnboardingProfileComplete: _isProfileSetupComplete(data),
        requiresPrivacyConsent: PrivacyConsentReceipt.isRequiredForProfile(
          data,
        ),
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

  /// Computes require authenticated mfa session.
  Future<User> _requireAuthenticatedMfaSession(AppSession session) async {
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
        requiresSignIn: true,
      );
    }

    try {
      final expectedUserId = documentIdForPhoneNumber(session.phoneNumber);
      final user = _resolvedFirebaseAuth.currentUser;
      if (user == null || user.uid != expectedUserId) {
        throw const FirebaseUserRepositoryException(
          'Your secure login has expired. Verify WhatsApp and your security method again.',
          requiresSignIn: true,
        );
      }

      // MFA completion already signed Firebase in with a short-lived custom
      // token. Reuse that durable Firebase session instead of calling the
      // retired saved-device token issuer, which would both bypass MFA and
      // reject every legitimate post-MFA login.
      final token = await user.getIdTokenResult();
      if (_resolvedFirebaseAuth.currentUser?.uid != expectedUserId) {
        throw const FirebaseUserRepositoryException(
          'The signed-in account changed while credentials were checked.',
          requiresSignIn: true,
        );
      }
      final claims = token.claims ?? const <String, dynamic>{};
      if (claims['mfa'] != true ||
          (claims['mobileSessionId'] as String? ?? '').isEmpty ||
          claims['phoneNumber'] != session.phoneNumber) {
        // The session owner decides whether this result still applies. A late
        // refresh must never sign out a newer Firebase login here.
        throw const FirebaseUserRepositoryException(
          'This login was not completed with both required verification steps. Sign in again.',
          requiresSignIn: true,
        );
      }
      return user;
    } on FirebaseUserRepositoryException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw FirebaseUserRepositoryException(
        error.message ?? 'Firebase authentication failed.',
        // Unknown/internal/provider errors can be transient while offline.
        // Erase local authentication only for a definitive credential denial.
        requiresSignIn: const {
          'user-disabled',
          'user-not-found',
          'invalid-user-token',
          'user-token-expired',
          'id-token-revoked',
        }.contains(error.code),
      );
    }
  }

  /// Computes sign out.
  Future<void> signOut() async {
    await _resolvedFirebaseAuth.signOut();
  }

  /// Checks whether admin.
  bool _isAdmin(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    return AccountRole.fromAccount(data) != AccountRole.hiker;
  }

  /// Computes requires onboarding.
  bool _requiresOnboarding(Map<String, dynamic>? data) {
    final value = data?['requiresOnboarding'];
    return value is bool ? value : true;
  }

  /// Computes username.
  String _username(Map<String, dynamic>? data) {
    final profile = data?['profile'];
    final canonical = profile is Map
        ? _stringFrom(profile['username']).trim()
        : '';
    if (canonical.isNotEmpty) return canonical;
    return '';
  }

  /// Computes photo url.
  String? _photoURL(Map<String, dynamic>? data) {
    final profile = data?['profile'];
    final value = profile is Map ? _stringFrom(profile['photoURL']).trim() : '';
    return value.isEmpty ? null : value;
  }

  /// Checks whether profile setup complete.
  bool _isProfileSetupComplete(Map<String, dynamic>? data) =>
      data?['profileSetupCompleted'] == true;

  /// Computes string from.
  String _stringFrom(Object? value) {
    return value is String ? value : '';
  }
}
