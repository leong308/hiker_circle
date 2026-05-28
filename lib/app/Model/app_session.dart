class AppSession {
  const AppSession({
    required this.phoneNumber,
    required this.signedInAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? signedInAt;

  final String phoneNumber;
  final DateTime signedInAt;
  final DateTime createdAt;

  AppSession copyWith({
    String? phoneNumber,
    DateTime? signedInAt,
    DateTime? createdAt,
  }) {
    return AppSession(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      signedInAt: signedInAt ?? this.signedInAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
