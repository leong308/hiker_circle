part of '../paired_sos_button_page_feature.dart';

/// Represents button test outcome.
class _ButtonTestOutcome {
  /// Creates button test outcome using pressed.
  const _ButtonTestOutcome.pressed(this.event) : timedOut = false;

  /// Creates button test outcome using timeout.
  const _ButtonTestOutcome.timeout() : event = null, timedOut = true;

  /// Creates button test outcome using cancelled.
  const _ButtonTestOutcome.cancelled() : event = null, timedOut = false;

  final HikerBlePairedSosButtonTestEvent? event;
  final bool timedOut;
}
