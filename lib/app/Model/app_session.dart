class AppSession {
  const AppSession({
    required this.phoneNumber,
    required this.signedInAt,
    DateTime? createdAt,
    this.appInstanceId = '',
    this.isAdmin = false,
  }) : createdAt = createdAt ?? signedInAt;

  final String phoneNumber;
  final DateTime signedInAt;
  final DateTime createdAt;
  final String appInstanceId;
  final bool isAdmin;

  AppSession copyWith({
    String? phoneNumber,
    DateTime? signedInAt,
    DateTime? createdAt,
    String? appInstanceId,
    bool? isAdmin,
  }) {
    return AppSession(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      signedInAt: signedInAt ?? this.signedInAt,
      createdAt: createdAt ?? this.createdAt,
      appInstanceId: appInstanceId ?? this.appInstanceId,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}
