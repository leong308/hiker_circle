/// The agreement presented before a sign-up phone number is submitted.
/// Optional permissions and sharing actions remain separate decisions.
class PrivacyConsentReceipt {
  const PrivacyConsentReceipt({
    required this.acceptedAt,
    required this.languageCode,
    this.noticeId = currentNoticeId,
  });

  static const noticeVersion = '2026-11-04';
  // The revised notice explicitly names overseas processing in the agreement.
  // Historical receipts keep the wording version that was originally accepted.
  static const currentNoticeId = 'signup-v2';
  static const previousNoticeId = 'signup-v1';
  static const legacyNoticeId = 'post-onboarding-v1';
  static const localKey = 'privacy_consent_receipt';
  final DateTime acceptedAt;
  final String languageCode;
  final String noticeId;

  static PrivacyConsentReceipt? fromMap(Object? value) {
    if (value is! Map ||
        value['accepted'] != true ||
        !const [
          currentNoticeId,
          previousNoticeId,
          legacyNoticeId,
        ].contains(value['noticeId']) ||
        value['policyVersion'] != noticeVersion ||
        !const ['en', 'ms'].contains(value['languageCode'])) {
      return null;
    }
    final time = DateTime.tryParse(value['acceptedAtLocal']?.toString() ?? '');
    if (time == null) return null;
    return PrivacyConsentReceipt(
      acceptedAt: time.toUtc(),
      languageCode: value['languageCode'] as String,
      noticeId: value['noticeId'] as String,
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
