part of '../sos_page_feature.dart';

/// Represents queued sos request.
class _QueuedSosRequest {
  /// Creates queued sos request.
  const _QueuedSosRequest({
    required this.mode,
    required this.triggeredAt,
    required this.triggerSource,
    required this.presentationId,
  });

  final SosAlertMode mode;
  final DateTime triggeredAt;
  final SosAlertTriggerSource triggerSource;
  final int presentationId;
}

/// Represents whats app note update.
class _WhatsAppNoteUpdate {
  /// Creates whats app note update.
  const _WhatsAppNoteUpdate({required this.mode, required this.note});

  final SosAlertMode mode;
  final String note;
}
