// AppSession is the local account/profile snapshot used by the UI; Firebase credentials and mobile
// session claims remain separate.
import 'dart:typed_data';

class AppSession {
  const AppSession({
    required this.phoneNumber,
    required this.signedInAt,
    DateTime? createdAt,
    this.appInstanceId = '',
    this.isAdmin = false,
    this.username = '',
    this.requiresOnboarding = false,
    this.isOnboardingProfileComplete = false,
    this.photoURL,
    this.photoBytes,
  }) : createdAt = createdAt ?? signedInAt;

  final String phoneNumber;
  final DateTime signedInAt;
  final DateTime createdAt;
  final String appInstanceId;
  final bool isAdmin;
  final String username;
  final bool requiresOnboarding;
  final bool isOnboardingProfileComplete;
  final String? photoURL;
  final Uint8List? photoBytes;

  AppSession copyWith({
    String? phoneNumber,
    DateTime? signedInAt,
    DateTime? createdAt,
    String? appInstanceId,
    bool? isAdmin,
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
      username: username ?? this.username,
      requiresOnboarding: requiresOnboarding ?? this.requiresOnboarding,
      isOnboardingProfileComplete:
          isOnboardingProfileComplete ?? this.isOnboardingProfileComplete,
      photoURL: photoURL ?? this.photoURL,
      photoBytes: photoBytes ?? this.photoBytes,
    );
  }
}
