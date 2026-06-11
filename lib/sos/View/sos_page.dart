import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Model/app_session.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/location_snapshot_service.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_device_alert_service.dart';
import '../Model/sos_models.dart';
import '../ModelView/sos_view_model.dart';
import 'emergency_contacts_page.dart';

class SosPage extends StatefulWidget {
  const SosPage({
    super.key,
    required this.session,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  late final SosViewModel viewModel;
  bool _isManualSosPatternActive = false;

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

  Future<void> _triggerAlert(SosAlertMode mode) async {
    final triggeredAt = DateTime.now().toUtc();
    if (mode == SosAlertMode.manual) {
      unawaited(_startManualSosPattern());
    }

    final triggerLocation = await _captureTriggerLocation();
    final result = await viewModel.triggerAlert(
      mode: mode,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
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
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

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
                  ),
                  const SizedBox(height: 16),
                  _MetricsGroup(metrics: viewModel.metrics),
                  const SizedBox(height: 18),
                  _SosAlertStatusCard(
                    isSending: viewModel.isSendingSosAlert,
                    latestResult: viewModel.latestSosAlertResult,
                    errorMessage: viewModel.sosAlertErrorMessage,
                  ),
                  const SizedBox(height: 14),
                  _ManualSosCard(
                    details: viewModel.manualSosDetails,
                    isSending: viewModel.isSendingSosAlert,
                    isAlarmActive: _isManualSosPatternActive,
                    onTrigger: () => unawaited(_handleManualSos()),
                    onStopAlarm: () => unawaited(_stopManualSosPattern()),
                  ),
                  const SizedBox(height: 14),
                  _DuressSosCard(
                    isSending: viewModel.isSendingSosAlert,
                    onLongPress: () => unawaited(_handleDuressSos()),
                  ),
                  const SizedBox(height: 22),
                  for (final section in viewModel.sections) ...[
                    _FeatureSection(section: section),
                    const SizedBox(height: 18),
                  ],
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
  });

  final AppSession session;
  final List<EmergencyContact> emergencyContacts;
  final EmergencyContactsRepository emergencyContactsRepository;
  final ValueChanged<List<EmergencyContact>> onEmergencyContactsChanged;

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

class _ManualSosCard extends StatelessWidget {
  const _ManualSosCard({
    required this.details,
    required this.isSending,
    required this.isAlarmActive,
    required this.onTrigger,
    required this.onStopAlarm,
  });

  final List<SosActionDetail> details;
  final bool isSending;
  final bool isAlarmActive;
  final VoidCallback onTrigger;
  final VoidCallback onStopAlarm;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Glyph(
                  icon: Icons.sos_rounded,
                  color: _SosColors.destructive,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manual SOS',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _SosColors.text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Starts sending emergency details after the cancel window',
                        maxLines: 2,
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
              ],
            ),
            const SizedBox(height: 14),
            _TapSurface(
              onTap: isAlarmActive
                  ? onStopAlarm
                  : isSending
                  ? null
                  : onTrigger,
              child: Container(
                height: 104,
                decoration: BoxDecoration(
                  color: isAlarmActive
                      ? _SosColors.green
                      : isSending
                      ? _SosColors.destructive.withValues(alpha: 0.56)
                      : _SosColors.destructive,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isAlarmActive
                            ? 'Stop Alarm'
                            : isSending
                            ? 'Sending SOS'
                            : 'Emergency SOS',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAlarmActive
                            ? 'Alarm and flashlight pattern active'
                            : isSending
                            ? 'Contacting emergency contacts'
                            : '10 seconds to cancel',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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

class _DuressSosCard extends StatelessWidget {
  const _DuressSosCard({required this.isSending, required this.onLongPress});

  final bool isSending;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onLongPress: isSending ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              const _Glyph(
                icon: Icons.pan_tool_alt_rounded,
                color: _SosColors.duress,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duress SOS',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _SosColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isSending
                          ? 'Sending silent alert to saved emergency contacts'
                          : 'Long press for a silent alert with no flash or alarm',
                      maxLines: 2,
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
              const SizedBox(width: 10),
              const Icon(
                CupertinoIcons.chevron_forward,
                color: _SosColors.chevron,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({required this.section});

  final SosFeatureSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 7),
          child: Text(
            section.title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _SosColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < section.items.length; index++) ...[
                _FeatureCell(item: section.items[index]),
                if (index != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureCell extends StatelessWidget {
  const _FeatureCell({required this.item});

  final SosFeatureItem item;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Glyph(icon: item.icon, color: _SosColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.text,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
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
            const SizedBox(width: 8),
            if (item.trailing case final trailing?)
              _StatusPill(
                label: trailing,
                color: _SosColors.green,
                surface: _SosColors.greenSoft,
              )
            else
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
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
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
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);
  static const Color destructiveSoft = Color(0xFFFFEDEC);
  static const Color duress = Color(0xFF8E4C5A);
}
