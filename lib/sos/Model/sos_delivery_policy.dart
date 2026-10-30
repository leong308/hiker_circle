import 'sos_models.dart';

/// Combines recipient-specific server receipts with locally durable SOS submissions.
abstract final class SosDeliveryPolicy {
  /// Matches by phone identity, so reordering contacts never changes the retry target.
  static String key(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  /// Retains receipt revisions and distinguishes a deadline from a definitive failed delivery.
  static SosContactDispatch contact(
    Map<String, dynamic> receipt, {
    DateTime? now,
  }) {
    final deadline =
        (receipt['confirmationDeadlineMillis'] as num?)?.toInt() ?? 0;
    var state = receipt['status'] as String? ?? 'sending';
    if (state == 'sending' &&
        deadline > 0 &&
        (now ?? DateTime.now()).millisecondsSinceEpoch >= deadline) {
      state = 'unconfirmed';
    }
    return SosContactDispatch(
      contactName: receipt['contactName'] as String? ?? 'Contact',
      phoneNumber: receipt['phoneNumber'] as String? ?? '',
      wasSent: state == 'confirmed',
      confirmationStatus: state,
      contactIndex: (receipt['contactIndex'] as num?)?.toInt() ?? 0,
      updatedAtMillis: (receipt['updatedAtMillis'] as num?)?.toInt() ?? 0,
      nextRetryAtMillis: (receipt['nextRetryAtMillis'] as num?)?.toInt() ?? 0,
      retryable: state == 'failed' && receipt['retryable'] == true,
      providerMessageId: receipt['providerMessageId'] as String?,
      errorMessage: state == 'unconfirmed'
          ? 'No confirmation within 15 seconds. Still checking.'
          : receipt['errorMessage'] as String?,
    );
  }

  /// A retry can target only a failed recipient; unknown or already-confirmed attempts are excluded.
  static bool canRetry(SosContactDispatch dispatch) =>
      !dispatch.wasSent &&
      !dispatch.isUnconfirmed &&
      !dispatch.isConfirming &&
      dispatch.retryable;

  /// Derives a whole-alert label from explicit contact outcomes, preserving mixed results.
  static SosAlertStatus status(int count, List<SosContactDispatch> contacts) {
    if (count == 0) return SosAlertStatus.noContacts;
    final sent = contacts.where((p) => p.wasSent).length;
    if (sent == count) return SosAlertStatus.sent;
    if (sent > 0) return SosAlertStatus.partial;
    if (contacts.any((p) => p.isUnconfirmed)) return SosAlertStatus.unconfirmed;
    if (contacts.any((p) => p.isConfirming) || contacts.length < count) {
      return SosAlertStatus.queued;
    }
    return SosAlertStatus.failed;
  }

  /// Server receipts override stale local results without changing the original contact universe.
  static SosAlert merge(
    SosAlert alert,
    Iterable<Map<String, dynamic>> receipts, {
    DateTime? now,
  }) {
    final byPhone = {for (final p in alert.dispatches) key(p.phoneNumber): p};
    for (final raw in receipts) {
      final p = contact(raw, now: now),
          before = byPhone[key(raw['phoneNumber'] as String? ?? '')];
      if (before == null || p.updatedAtMillis >= before.updatedAtMillis) {
        byPhone[key(p.phoneNumber)] = p;
      }
    }
    final list = byPhone.values.toList()
      ..sort((a, b) => a.contactIndex.compareTo(b.contactIndex));
    return SosAlert(
      id: alert.id,
      mode: alert.mode,
      status: status(alert.contactCount, list),
      triggeredAt: alert.triggeredAt,
      triggeredByPhoneNumber: alert.triggeredByPhoneNumber,
      contactCount: alert.contactCount,
      sentCount: list.where((p) => p.wasSent).length,
      failedCount: list
          .where((p) => !p.wasSent && !p.isUnconfirmed && !p.isConfirming)
          .length,
      dispatches: list,
      message: alert.message,
      triggerLocation: alert.triggerLocation,
      triggerSource: alert.triggerSource,
      shirtColor: alert.shirtColor,
    );
  }
}
