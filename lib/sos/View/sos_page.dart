import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Model/app_session.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/location_snapshot_service.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_device_alert_service.dart';
import '../Model/sos_models.dart';
import '../ModelView/sos_view_model.dart';
import 'emergency_contacts_page.dart';
import 'ios_sos_volume_guard.dart';

class SosPage extends StatefulWidget {
  const SosPage({
    super.key,
    required this.session,
    this.manualSosRequestId = 0,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final int manualSosRequestId;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  late final SosViewModel viewModel;
  int _handledManualSosRequestId = 0;
  bool _isManualSosPatternActive = false;
  String _customWhatsAppNote = SosAlertMessageComposer.defaultCustomNote;
  SosLocalAlertFeedback? _localAlertFeedback;

  @override
  void initState() {
    super.initState();
    viewModel = SosViewModel(
      session: widget.session,
      emergencyContactsRepository: EmergencyContactsRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
      sosAlertRepository: SosAlertRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    );
    viewModel.addListener(_refresh);
    unawaited(viewModel.loadEmergencyContacts());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingManualSosRequest();
    });
  }

  @override
  void didUpdateWidget(covariant SosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingManualSosRequest();
    });
  }

  @override
  void dispose() {
    if (_isManualSosPatternActive) {
      unawaited(_deviceAlertService.stopManualSosPattern());
    }
    viewModel.removeListener(_refresh);
    viewModel.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  void _handlePendingManualSosRequest() {
    if (!mounted ||
        widget.manualSosRequestId <= 0 ||
        widget.manualSosRequestId == _handledManualSosRequestId) {
      return;
    }

    _handledManualSosRequestId = widget.manualSosRequestId;
    unawaited(_handleManualSos());
  }

  Future<void> _handleManualSos() async {
    if (viewModel.isSendingSosAlert) {
      return;
    }

    unawaited(HapticFeedback.heavyImpact());
    final shouldSend = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _ManualSosCountdownDialog();
      },
    );

    if (shouldSend != true || !mounted) {
      return;
    }

    await _triggerAlert(SosAlertMode.manual);
  }

  Future<void> _handleDuressSos() async {
    if (viewModel.isSendingSosAlert) {
      return;
    }

    unawaited(HapticFeedback.mediumImpact());
    await _triggerAlert(SosAlertMode.duress);
  }

  void _openTestSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _SosTestSettingsPage(),
      ),
    );
  }

  void _showManualSosDetailsOverlay() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return _ManualSosDetailsOverlay(details: viewModel.manualSosDetails);
      },
    );
  }

  Future<void> _triggerAlert(SosAlertMode mode) async {
    if (mode.usesLoudEmergencyPattern) {
      final volumeReady = await ensureIosSosOutputVolumeReady(
        context: context,
        deviceAlertService: _deviceAlertService,
        message:
            'Manual SOS uses iPhone media volume for the local alarm. Turn it up before continuing.',
      );
      if (!volumeReady || !mounted) {
        return;
      }
      unawaited(_startManualSosPattern());
    }

    final triggeredAt = DateTime.now().toUtc();
    final triggerLocation = await _captureTriggerLocation();
    final result = await viewModel.triggerAlert(
      mode: mode,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customMessageNote: _customWhatsAppNote,
    );
    if (!mounted) {
      return;
    }

    final message = result == null
        ? viewModel.sosAlertErrorMessage ?? 'SOS alert was not sent.'
        : _messageForResult(result);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: result == null || result.alert.failedCount > 0
              ? _SosColors.destructive
              : _SosColors.green,
        ),
      );
  }

  Future<SosTriggerLocation?> _captureTriggerLocation() async {
    try {
      final snapshotService = LocationSnapshotService.instance;
      return snapshotService.latestLocation ?? await snapshotService.refresh();
    } catch (_) {
      return null;
    }
  }

  Future<void> _startManualSosPattern() async {
    try {
      await _deviceAlertService.startManualSosPattern();
      if (!mounted) {
        return;
      }

      setState(() {
        _isManualSosPatternActive = true;
        _localAlertFeedback = SosLocalAlertFeedback.started(
          updatedAt: DateTime.now(),
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _localAlertFeedback = SosLocalAlertFeedback.failed(
          updatedAt: DateTime.now(),
          errorMessage: 'Unable to start phone alarm or flashlight.',
        );
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to start phone alarm or flashlight.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _stopManualSosPattern() async {
    try {
      await _deviceAlertService.stopManualSosPattern();
    } finally {
      if (mounted) {
        setState(() {
          _isManualSosPatternActive = false;
          _localAlertFeedback = SosLocalAlertFeedback.stopped(
            updatedAt: DateTime.now(),
          );
        });
      }
    }
  }

  String _messageForResult(SosAlertResult result) {
    final alert = result.alert;
    if (alert.status == SosAlertStatus.noContacts) {
      return '${alert.mode.label} logged, but no emergency contacts are saved.';
    }
    if (alert.status == SosAlertStatus.sent) {
      return '${alert.mode.label} sent to ${alert.sentCount} contacts.';
    }
    if (alert.status == SosAlertStatus.partial) {
      return '${alert.mode.label} sent to ${alert.sentCount} contacts; ${alert.failedCount} failed.';
    }
    return '${alert.mode.label} could not be sent to your contacts.';
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _SosColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    session: widget.session,
                    emergencyContacts: viewModel.emergencyContacts,
                    emergencyContactsRepository:
                        viewModel.emergencyContactsRepository,
                    onEmergencyContactsChanged:
                        viewModel.replaceEmergencyContacts,
                    onOpenTestSettings: _openTestSettings,
                  ),
                  const SizedBox(height: 16),
                  _NetworkSosStatusCard(
                    isNetworkAvailable:
                        widget.firebaseBootstrapResult.isAvailable,
                    errorMessage: widget.firebaseBootstrapResult.errorMessage,
                  ),
                  const SizedBox(height: 14),
                  _MetricsGroup(metrics: viewModel.metrics),
                  const SizedBox(height: 18),
                  _SosAlertStatusCard(
                    isSending: viewModel.isSendingSosAlert,
                    latestResult: viewModel.latestSosAlertResult,
                    errorMessage: viewModel.sosAlertErrorMessage,
                  ),
                  const SizedBox(height: 14),
                  _EmergencySosControlCard(
                    isSending: viewModel.isSendingSosAlert,
                    isAlarmActive: _isManualSosPatternActive,
                    onTrigger: () => unawaited(_handleManualSos()),
                    onStopAlarm: () => unawaited(_stopManualSosPattern()),
                    onShowDetailsOverlay: _showManualSosDetailsOverlay,
                    onDuressLongPress: () => unawaited(_handleDuressSos()),
                  ),
                  const SizedBox(height: 22),
                  _AlertDeliveryPanel(
                    isNetworkAvailable:
                        widget.firebaseBootstrapResult.isAvailable,
                    session: widget.session,
                    latestResult: viewModel.latestSosAlertResult,
                    customWhatsAppNote: _customWhatsAppNote,
                    localAlertFeedback: _localAlertFeedback,
                    isLocalAlarmActive: _isManualSosPatternActive,
                    onCustomWhatsAppNoteChanged: (note) {
                      setState(() {
                        _customWhatsAppNote = note;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  const _SosReadinessPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.emergencyContacts,
    required this.emergencyContactsRepository,
    required this.onEmergencyContactsChanged,
    required this.onOpenTestSettings,
  });

  final AppSession session;
  final List<EmergencyContact> emergencyContacts;
  final EmergencyContactsRepository emergencyContactsRepository;
  final ValueChanged<List<EmergencyContact>> onEmergencyContactsChanged;
  final VoidCallback onOpenTestSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _SosColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Emergency controls and safety checks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryText,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'Emergency contacts',
            icon: Icons.contacts_rounded,
            onPressed: () => unawaited(_openEmergencyContacts(context)),
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Test settings',
            icon: Icons.science_rounded,
            onPressed: onOpenTestSettings,
          ),
        ],
      ),
    );
  }

  Future<void> _openEmergencyContacts(BuildContext context) async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) {
          return EmergencyContactsPage(
            session: session,
            initialContacts: emergencyContacts,
            repository: emergencyContactsRepository,
          );
        },
      ),
    );

    if (contacts == null || !context.mounted) {
      return;
    }

    onEmergencyContactsChanged(contacts);
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _SosColors.green, size: 19),
        ),
      ),
    );
  }
}

class _ManualSosCountdownDialog extends StatefulWidget {
  const _ManualSosCountdownDialog();

  @override
  State<_ManualSosCountdownDialog> createState() =>
      _ManualSosCountdownDialogState();
}

class _ManualSosCountdownDialogState extends State<_ManualSosCountdownDialog> {
  static const int _totalSeconds = 10;

  Timer? _timer;
  int _secondsRemaining = _totalSeconds;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final nextSecond = _secondsRemaining - 1;
      if (nextSecond <= 0) {
        _completeCountdown();
        return;
      }

      setState(() {
        _secondsRemaining = nextSecond;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _completeCountdown() {
    if (_didComplete || !mounted) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    Navigator.of(context).pop(true);
  }

  void _cancel() {
    if (_didComplete) {
      return;
    }

    _didComplete = true;
    _timer?.cancel();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalSeconds - _secondsRemaining) / _totalSeconds;

    return CupertinoAlertDialog(
      title: const Text('Emergency SOS'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(
              'Sending in $_secondsRemaining seconds',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: _SosColors.destructive,
              backgroundColor: _SosColors.destructiveSoft,
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: _cancel,
          child: const Text('Cancel SOS'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _completeCountdown,
          child: const Text('Send Now'),
        ),
      ],
    );
  }
}

class _NetworkSosStatusCard extends StatelessWidget {
  const _NetworkSosStatusCard({
    required this.isNetworkAvailable,
    required this.errorMessage,
  });

  final bool isNetworkAvailable;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final color = isNetworkAvailable ? _SosColors.green : _SosColors.orange;
    final title = isNetworkAvailable
        ? 'Network SOS available'
        : 'Local SOS mode only';
    final subtitle = isNetworkAvailable
        ? 'Alerts can use cloud logging and WhatsApp delivery when sent.'
        : 'No backend connection right now. The phone alarm, flashlight pattern, and local log remain available.';

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: isNetworkAvailable
                  ? Icons.cloud_done_rounded
                  : Icons.signal_wifi_connected_no_internet_4_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _SosColors.text,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      _StatusPill(
                        label: isNetworkAvailable ? 'Online' : 'Local',
                        color: color,
                        surface: color.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage == null ? subtitle : '$subtitle $errorMessage',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGroup extends StatelessWidget {
  const _MetricsGroup({required this.metrics});

  final List<SosMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              Expanded(child: _MetricCell(metric: metrics[index])),
              if (index != metrics.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final SosMetric metric;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _SosColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _SosColors.secondaryText,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _SosAlertStatusCard extends StatelessWidget {
  const _SosAlertStatusCard({
    required this.isSending,
    required this.latestResult,
    required this.errorMessage,
  });

  final bool isSending;
  final SosAlertResult? latestResult;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final latestAlert = latestResult?.alert;
    final statusColor = latestAlert?.status == SosAlertStatus.failed
        ? _SosColors.destructive
        : _SosColors.green;
    final title = isSending
        ? 'Sending SOS alert'
        : latestAlert == null
        ? 'SOS ready'
        : '${latestAlert.mode.label} ${latestAlert.status.label.toLowerCase()}';
    final subtitle = errorMessage != null
        ? errorMessage!
        : latestAlert == null
        ? 'Emergency alerts will be logged to your profile and sent by WhatsApp.'
        : _subtitleFor(latestAlert);

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Glyph(
                  icon: isSending
                      ? Icons.outbox_rounded
                      : Icons.verified_user_rounded,
                  color: errorMessage != null
                      ? _SosColors.destructive
                      : statusColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _SosColors.text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: errorMessage != null
                              ? _SosColors.destructive
                              : _SosColors.secondaryText,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSending) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  String _subtitleFor(SosAlert alert) {
    if (alert.status == SosAlertStatus.noContacts) {
      return 'Saved to Firebase, but no emergency contacts were available.';
    }
    if (alert.status == SosAlertStatus.sent) {
      return 'Saved to Firebase and sent to ${alert.sentCount} contacts.';
    }
    if (alert.status == SosAlertStatus.partial) {
      return 'Saved to Firebase. Sent to ${alert.sentCount}; ${alert.failedCount} failed.';
    }
    return 'Saved to Firebase, but contact delivery failed.';
  }
}

class _EmergencySosControlCard extends StatelessWidget {
  const _EmergencySosControlCard({
    required this.isSending,
    required this.isAlarmActive,
    required this.onTrigger,
    required this.onStopAlarm,
    required this.onShowDetailsOverlay,
    required this.onDuressLongPress,
  });

  final bool isSending;
  final bool isAlarmActive;
  final VoidCallback onTrigger;
  final VoidCallback onStopAlarm;
  final VoidCallback onShowDetailsOverlay;
  final VoidCallback onDuressLongPress;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manual SOS',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _SosColors.text,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: isAlarmActive
                    ? onStopAlarm
                    : isSending
                    ? null
                    : onTrigger,
                onLongPress: onShowDetailsOverlay,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 188,
                  height: 188,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAlarmActive
                        ? _SosColors.green
                        : isSending
                        ? _SosColors.destructive.withValues(alpha: 0.58)
                        : _SosColors.destructive,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isAlarmActive
                                    ? _SosColors.green
                                    : _SosColors.destructive)
                                .withValues(alpha: 0.26),
                        blurRadius: 26,
                        spreadRadius: 8,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.72),
                      width: 7,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isAlarmActive
                            ? Icons.notifications_off_rounded
                            : Icons.sos_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isAlarmActive
                            ? 'STOP'
                            : isSending
                            ? 'SENDING'
                            : 'HOLD SOS',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAlarmActive
                            ? 'Alarm active'
                            : isSending
                            ? 'Notifying contacts'
                            : 'Tap to start',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tap for the 10-second cancel window. Press and hold the button to view exactly what gets activated.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryText,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            _HiddenDuressIndicator(
              isSending: isSending,
              onLongPress: onDuressLongPress,
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenDuressIndicator extends StatelessWidget {
  const _HiddenDuressIndicator({
    required this.isSending,
    required this.onLongPress,
  });

  final bool isSending;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: _TapSurface(
        onLongPress: isSending ? null : onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _SosColors.duress.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                color: _SosColors.duress,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Silent shortcut: hold this shield',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _SosColors.duress,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSosDetailsOverlay extends StatelessWidget {
  const _ManualSosDetailsOverlay({required this.details});

  final List<SosActionDetail> details;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manual SOS activates',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _SosColors.text,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'These are shown on hold so the main button stays calm and uncluttered.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final detail in details)
                  _DetailChip(icon: detail.icon, label: detail.label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertDeliveryPanel extends StatelessWidget {
  const _AlertDeliveryPanel({
    required this.isNetworkAvailable,
    required this.session,
    required this.latestResult,
    required this.customWhatsAppNote,
    required this.localAlertFeedback,
    required this.isLocalAlarmActive,
    required this.onCustomWhatsAppNoteChanged,
  });

  final bool isNetworkAvailable;
  final AppSession session;
  final SosAlertResult? latestResult;
  final String customWhatsAppNote;
  final SosLocalAlertFeedback? localAlertFeedback;
  final bool isLocalAlarmActive;
  final ValueChanged<String> onCustomWhatsAppNoteChanged;

  @override
  Widget build(BuildContext context) {
    final latestAlert = latestResult?.alert;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(label: 'Alert Delivery'),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.chat_bubble_rounded,
          title: 'WhatsApp notification',
          subtitle: 'Edit the custom note and preview the outgoing payload.',
          trailing: customWhatsAppNote.trim().isEmpty ? 'Default' : 'Custom',
          onTap: () => unawaited(_openWhatsAppMessageEditor(context)),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.cloud_done_rounded,
          title: 'Cloud alert log',
          subtitle: latestAlert == null
              ? 'Cloud log fields are ready for the next SOS.'
              : 'Latest ${latestAlert.mode.label} is logged with audit fields.',
          trailing: isNetworkAvailable ? 'Online' : 'Local only',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'Cloud alert log',
            icon: Icons.cloud_done_rounded,
            description:
                'SOS alerts are saved to the user profile for the in-app latest status and mirrored to a top-level sosAlerts collection for emergency review.',
            rows: _cloudLogRows(),
          ),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.fact_check_rounded,
          title: 'Delivery results',
          subtitle: latestAlert == null
              ? 'Dispatch results appear after an SOS alert is sent.'
              : '${latestAlert.sentCount} sent, ${latestAlert.failedCount} failed.',
          trailing: latestAlert?.status.label ?? 'Ready',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'Delivery results',
            icon: Icons.fact_check_rounded,
            description:
                'Each contact dispatch records the normalized recipient, send state, and any WhatsApp/Green API error returned by the delivery layer.',
            rows: _deliveryResultRows(),
          ),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.phone_android_rounded,
          title: 'Local fallback',
          subtitle: 'Phone alarm, flashlight pattern, and stop feedback.',
          trailing: isLocalAlarmActive ? 'Active' : 'Standby',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'Local SOS feedback',
            icon: Icons.phone_android_rounded,
            description:
                'Local feedback runs even when contact delivery fails. Manual SOS and Fall SOS use the loud pattern; Duress SOS stays silent.',
            rows: _localFeedbackRows(),
          ),
        ),
      ],
    );
  }

  Future<void> _openWhatsAppMessageEditor(BuildContext context) async {
    final latestAlert = latestResult?.alert;
    final nextNote = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) {
          return _WhatsAppMessageDetailPage(
            session: session,
            initialNote: customWhatsAppNote,
            previewMode: latestAlert?.mode ?? SosAlertMode.manual,
            previewTriggeredAt: latestAlert?.triggeredAt ?? DateTime.now(),
            previewLocation: latestAlert?.triggerLocation,
          );
        },
      ),
    );

    if (nextNote != null && context.mounted) {
      onCustomWhatsAppNoteChanged(nextNote);
    }
  }

  List<(String, String)> _cloudLogRows() {
    final latestAlert = latestResult?.alert;
    final userDocumentId = FirebaseUserRepository.documentIdForPhoneNumber(
      session.phoneNumber,
    );
    if (latestAlert == null) {
      return [
        ('Network status', isNetworkAvailable ? 'Ready' : 'Local only'),
        ('User latest path', 'users/$userDocumentId/latest_sos_alert'),
        ('Audit collection', 'sosAlerts/{alertId}'),
        ('Stored fields', 'Mode, timestamp, GPS, message, status, dispatches'),
      ];
    }

    return [
      ('Alert ID', latestAlert.id),
      ('Status', latestAlert.status.label),
      ('Triggered', latestAlert.triggeredAt.toUtc().toIso8601String()),
      ('User latest path', 'users/$userDocumentId/latest_sos_alert'),
      ('Audit path', 'sosAlerts/${latestAlert.id}'),
      (
        'Location',
        latestAlert.triggerLocation?.universalMapLink ?? 'Unavailable',
      ),
    ];
  }

  List<(String, String)> _deliveryResultRows() {
    final latestAlert = latestResult?.alert;
    if (latestAlert == null) {
      return const [
        ('Latest alert', 'No SOS alert sent yet'),
        ('Sent', '0 contacts'),
        ('Failed', '0 contacts'),
      ];
    }

    return [
      ('Alert mode', latestAlert.mode.label),
      ('Overall status', latestAlert.status.label),
      ('Contacts', '${latestAlert.contactCount} selected'),
      ('Sent', '${latestAlert.sentCount} contacts'),
      ('Failed', '${latestAlert.failedCount} contacts'),
      for (final dispatch in latestAlert.dispatches)
        (
          dispatch.contactName,
          dispatch.wasSent
              ? 'Sent to ${dispatch.phoneNumber}'
              : 'Failed: ${dispatch.errorMessage ?? dispatch.phoneNumber}',
        ),
    ];
  }

  List<(String, String)> _localFeedbackRows() {
    final feedback = localAlertFeedback;
    return [
      ('Alarm sound', isLocalAlarmActive ? 'Looping' : 'Standby'),
      (
        'Flashlight pattern',
        isLocalAlarmActive || feedback?.flashlightRequested == true
            ? 'SOS pattern requested'
            : 'Standby',
      ),
      ('Latest command', feedback?.statusLabel ?? 'No local SOS command yet'),
      if (feedback?.errorMessage != null) ('Error', feedback!.errorMessage!),
      (
        'iOS alarm behavior',
        'Uses playback audio at full app volume. iOS does not expose the system Alarm volume channel to third-party apps.',
      ),
    ];
  }

  void _openDeliveryDetail(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
    required List<(String, String)> rows,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AlertDeliveryDetailPage(
          title: title,
          icon: icon,
          description: description,
          rows: rows,
        ),
      ),
    );
  }
}

class _DeliveryActionCard extends StatelessWidget {
  const _DeliveryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              _Glyph(icon: icon, color: _SosColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _SosColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryText,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: trailing,
                color: _SosColors.green,
                surface: _SosColors.greenSoft,
              ),
              const SizedBox(width: 6),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevron,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatsAppMessageDetailPage extends StatefulWidget {
  const _WhatsAppMessageDetailPage({
    required this.session,
    required this.initialNote,
    required this.previewMode,
    required this.previewTriggeredAt,
    required this.previewLocation,
  });

  final AppSession session;
  final String initialNote;
  final SosAlertMode previewMode;
  final DateTime previewTriggeredAt;
  final SosTriggerLocation? previewLocation;

  @override
  State<_WhatsAppMessageDetailPage> createState() =>
      _WhatsAppMessageDetailPageState();
}

class _WhatsAppMessageDetailPageState
    extends State<_WhatsAppMessageDetailPage> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = SosAlertMessageComposer.compose(
      mode: widget.previewMode,
      phoneNumber: widget.session.phoneNumber,
      triggeredAt: widget.previewTriggeredAt,
      triggerLocation: widget.previewLocation,
      customNote: _noteController.text,
    );

    return Scaffold(
      backgroundColor: _SosColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'WhatsApp Message',
                    subtitle: 'Custom SOS notification payload',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Glyph(
                            icon: Icons.chat_bubble_rounded,
                            color: _SosColors.green,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Custom note',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _SosColors.text,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _noteController,
                            minLines: 3,
                            maxLines: 5,
                            maxLength: 240,
                            decoration: const InputDecoration(
                              hintText:
                                  'Tell contacts what to do when they receive your SOS.',
                              alignLabelWithHint: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _noteController.text =
                                          SosAlertMessageComposer
                                              .defaultCustomNote;
                                    });
                                  },
                                  child: const Text('Reset Default'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.of(
                                    context,
                                  ).pop(_noteController.text.trim()),
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('Use Message'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'WhatsApp preview',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _SosColors.text,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            preview,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.text,
                                  height: 1.35,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertDeliveryDetailPage extends StatelessWidget {
  const _AlertDeliveryDetailPage({
    required this.title,
    required this.icon,
    required this.description,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final String description;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: title,
                    subtitle: 'Alert delivery settings',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Glyph(icon: icon, color: _SosColors.green),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _SosColors.text,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.secondaryText,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          for (final row in rows) ...[
                            _StatusRow(label: row.$1, value: row.$2),
                            if (row != rows.last) const _HorizontalSeparator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SosReadinessPanel extends StatelessWidget {
  const _SosReadinessPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionTitle(label: 'Useful Before You Need It'),
        SizedBox(height: 8),
        _InsetGroup(
          child: Column(
            children: [
              _ReadinessRow(
                icon: Icons.volume_up_rounded,
                title: 'Check phone volume',
                subtitle: 'Manual SOS uses alarm sound and flashlight pattern.',
              ),
              _HorizontalSeparator(),
              _ReadinessRow(
                icon: Icons.location_searching_rounded,
                title: 'Keep location permission ready',
                subtitle: 'The map link is only useful when GPS can refresh.',
              ),
              _HorizontalSeparator(),
              _ReadinessRow(
                icon: Icons.battery_charging_full_rounded,
                title: 'Protect battery',
                subtitle: 'Low power mode is better than a dead phone.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(icon: icon, color: _SosColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _SosColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryText,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SosTestSettingsPage extends StatelessWidget {
  const _SosTestSettingsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosDetailHeader(
                    title: 'Test Settings',
                    subtitle: 'Dry-run SOS flows without notifying anyone',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Column(
                      children: [
                        _SosTestRow(
                          icon: Icons.sos_rounded,
                          title: 'Manual SOS test',
                          subtitle:
                              'Preview countdown, alarm copy, and map link.',
                          onTap: () => _showTestResult(
                            context,
                            'Manual SOS dry run completed.',
                          ),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.shield_outlined,
                          title: 'Duress SOS test',
                          subtitle:
                              'Confirm the hidden shield long-press path.',
                          onTap: () => _showTestResult(
                            context,
                            'Duress SOS dry run completed silently.',
                          ),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.health_and_safety_rounded,
                          title: 'Fall and stillness SOS',
                          subtitle:
                              'Simulate fall detection and no-movement timer.',
                          onTap: () => _showTestResult(
                            context,
                            'Fall and stillness simulation passed.',
                          ),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.chat_bubble_rounded,
                          title: 'WhatsApp notification',
                          subtitle: 'Preview a dummy WhatsApp alert payload.',
                          onTap: () => _showTestResult(
                            context,
                            'WhatsApp dummy notification prepared.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Glyph(
                            icon: Icons.info_outline_rounded,
                            color: _SosColors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'These controls are UI-only dry runs. They do not call emergency contacts, WhatsApp, Firebase, alarm, or flashlight services.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _SosColors.secondaryText,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTestResult(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _SosTestRow extends StatelessWidget {
  const _SosTestRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon, color: _SosColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryText,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              color: _SosColors.chevron,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _SosDetailHeader extends StatelessWidget {
  const _SosDetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.chevron_back,
                color: _SosColors.green,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _SosColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _SosColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 11, 0, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryText,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _SosColors.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _SosColors.destructiveSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _SosColors.destructive, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _SosColors.destructive,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.surface,
  });

  final String label;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _TapSurface extends StatelessWidget {
  const _TapSurface({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _SosColors.separator,
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _SosColors.separator,
      ),
    );
  }
}

abstract final class _SosColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color orange = Color(0xFFF59E0B);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);
  static const Color destructiveSoft = Color(0xFFFFEDEC);
  static const Color duress = Color(0xFF8E4C5A);
}
