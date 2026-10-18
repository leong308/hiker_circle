// MfaContinuation, MfaStatus and TotpEnrollment carry pending multi-factor authentication state.
class MfaContinuation {
  const MfaContinuation({
    required this.token,
    required this.phoneNumber,
    required this.methods,
    required this.enrollmentRequired,
    required this.isNewAccount,
    required this.expiresAt,
  });

  final String token;
  final String phoneNumber;
  final List<String> methods;
  final bool enrollmentRequired;
  final bool isNewAccount;
  final DateTime expiresAt;
}

class MfaFactor {
  const MfaFactor({
    required this.id,
    required this.type,
    required this.label,
    this.createdAtLocal,
  });

  final String id;
  final String type;
  final String label;
  final String? createdAtLocal;
}

class MfaStatus {
  const MfaStatus({
    required this.required,
    required this.factorCount,
    required this.methods,
    required this.factors,
    required this.canRemove,
  });

  final bool required;
  final int factorCount;
  final List<String> methods;
  final List<MfaFactor> factors;
  final bool canRemove;
}

class TotpEnrollment {
  const TotpEnrollment({
    required this.challengeId,
    required this.secret,
    required this.otpauthUri,
    required this.expiresAt,
  });

  final String challengeId;
  final String secret;
  final String otpauthUri;
  final DateTime expiresAt;
}
