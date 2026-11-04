/// The agreement presented after profile and emergency-contact setup.
/// Optional permissions and sharing actions remain separate decisions.
class PrivacyConsentReceipt {
  const PrivacyConsentReceipt({
    required this.acceptedAt,
    required this.languageCode,
  });

  static const noticeVersion = '2026-11-04';
  static const noticeId = 'post-onboarding-v1';
  static const localKey = 'privacy_consent_receipt';
  final DateTime acceptedAt;
  final String languageCode;

  /// Existing completed accounts are not interrupted by a rollout of the new flow.
  static bool isRequiredForProfile(Map<String, dynamic> profile) {
    final version = profile['onboardingVersion'];
    return version is num &&
        version >= 2 &&
        fromMap(profile['privacyConsent']) == null;
  }

  static PrivacyConsentReceipt? fromMap(Object? value) {
    if (value is! Map ||
        value['accepted'] != true ||
        value['noticeId'] != noticeId ||
        value['policyVersion'] != noticeVersion ||
        !const ['en', 'ms'].contains(value['languageCode'])) {
      return null;
    }
    final time = DateTime.tryParse(value['acceptedAtLocal']?.toString() ?? '');
    if (time == null) return null;
    return PrivacyConsentReceipt(
      acceptedAt: time.toUtc(),
      languageCode: value['languageCode'] as String,
    );
  }

  Map<String, Object?> toMap() => {
    'accepted': true,
    'noticeId': noticeId,
    'policyVersion': noticeVersion,
    'languageCode': languageCode,
    'acceptedAtLocal': acceptedAt.toUtc().toIso8601String(),
  };
}
