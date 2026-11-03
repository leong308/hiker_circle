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
