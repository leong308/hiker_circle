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
  }) : createdAt = createdAt ?? signedInAt;

  final String phoneNumber;
  final DateTime signedInAt;
  final DateTime createdAt;
  final String appInstanceId;
  final bool isAdmin;
  final String username;
  final bool requiresOnboarding;
  final bool isOnboardingProfileComplete;

  AppSession copyWith({
    String? phoneNumber,
    DateTime? signedInAt,
    DateTime? createdAt,
    String? appInstanceId,
    bool? isAdmin,
    String? username,
    bool? requiresOnboarding,
    bool? isOnboardingProfileComplete,
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
    );
  }
}
