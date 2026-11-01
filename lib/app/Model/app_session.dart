// AppSession is the local account/profile snapshot used by the UI; Firebase credentials and mobile
// session claims remain separate.
import 'dart:typed_data';

/// Represents app session.
class AppSession {
  /// Creates app session.
  const AppSession({
    required this.phoneNumber,
    required this.signedInAt,
    DateTime? createdAt,
    this.appInstanceId = '',
    bool isAdmin = false,
    this.isSuperAdmin = false,
    this.username = '',
    this.requiresOnboarding = false,
    this.isOnboardingProfileComplete = false,
    this.photoURL,
    this.photoBytes,
  }) : createdAt = createdAt ?? signedInAt,
       isAdmin = isAdmin || isSuperAdmin;

  final String phoneNumber;
  final DateTime signedInAt;
  final DateTime createdAt;
  final String appInstanceId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final String username;
  final bool requiresOnboarding;
  final bool isOnboardingProfileComplete;
  final String? photoURL;
  final Uint8List? photoBytes;

  /// Returns a copy with the supplied fields changed.
  AppSession copyWith({
    String? phoneNumber,
    DateTime? signedInAt,
    DateTime? createdAt,
    String? appInstanceId,
    bool? isAdmin,
    bool? isSuperAdmin,
    String? username,
    bool? requiresOnboarding,
    bool? isOnboardingProfileComplete,
    String? photoURL,
    Uint8List? photoBytes,
  }) {
    return AppSession(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      signedInAt: signedInAt ?? this.signedInAt,
      createdAt: createdAt ?? this.createdAt,
      appInstanceId: appInstanceId ?? this.appInstanceId,
      isAdmin: isAdmin ?? this.isAdmin,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      username: username ?? this.username,
      requiresOnboarding: requiresOnboarding ?? this.requiresOnboarding,
      isOnboardingProfileComplete:
          isOnboardingProfileComplete ?? this.isOnboardingProfileComplete,
      photoURL: photoURL ?? this.photoURL,
      photoBytes: photoBytes ?? this.photoBytes,
    );
  }
}
