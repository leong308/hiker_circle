import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/firebase_user_repository.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/View/first_aid_guide_page.dart';
import '../../home/View/gear_checklist_page.dart';
import '../../me/View/location_sharing_page.dart';
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
    this.immediateSosRequestId = 0,
    this.immediateSosMode,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final int manualSosRequestId;
  final int immediateSosRequestId;
  final SosAlertMode? immediateSosMode;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  late final SosViewModel viewModel;
  int _handledManualSosRequestId = 0;
  int _handledImmediateSosRequestId = 0;
  bool _isManualSosPatternActive = false;
  Map<SosAlertMode, String> _customWhatsAppNotes = _defaultWhatsAppNotes();
  List<Map<String, dynamic>> _adminSosSystemLogs = const [];
  bool _isLoadingAdminSosSystemLogs = false;
  String? _adminSosSystemLogsError;

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
    unawaited(_loadCustomWhatsAppNotes());
    unawaited(viewModel.loadCloudAlertLogs());
    if (widget.session.isAdmin) {
      unawaited(_loadAdminSosSystemLogs());
    }
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

  static Map<SosAlertMode, String> _defaultWhatsAppNotes() {
    return const {
      SosAlertMode.manual: SosAlertMessageComposer.defaultCustomNote,
      SosAlertMode.duress:
          'I may be under pressure and cannot speak safely. Please watch my live location, avoid calling if it may increase risk, and contact local emergency services if I stop responding.',
      SosAlertMode.medical:
          'I need medical help during my hike. Please call me, use the map link, and share this alert with medical responders if I do not answer.',
    };
  }

  Future<void> _loadCustomWhatsAppNotes() async {
    await viewModel.loadCustomWhatsAppNotes();
    if (!mounted) {
      return;
    }
    setState(() {
      _customWhatsAppNotes = {
        ..._defaultWhatsAppNotes(),
        ...viewModel.customWhatsAppNotes,
      };
    });
  }

  String _customWhatsAppNoteFor(SosAlertMode mode) {
    return _customWhatsAppNotes[mode] ??
        SosAlertMessageComposer.defaultCustomNote;
  }

  Future<void> _loadAdminSosSystemLogs() async {
    if (_isLoadingAdminSosSystemLogs) {
      return;
    }
    setState(() {
      _isLoadingAdminSosSystemLogs = true;
      _adminSosSystemLogsError = null;
    });

    try {
      final logs = await HikerCircleFirebaseRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ).loadAdminSosAlerts(session: widget.session);
      if (!mounted) {
        return;
      }
      setState(() {
        _adminSosSystemLogs = logs;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          _adminSosSystemLogsError = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _adminSosSystemLogsError = 'Unable to load SOS system logs.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAdminSosSystemLogs = false;
        });
      }
    }
  }

  void _handlePendingManualSosRequest() {
    final immediateMode = widget.immediateSosMode;
    if (mounted &&
        immediateMode != null &&
        widget.immediateSosRequestId > 0 &&
        widget.immediateSosRequestId != _handledImmediateSosRequestId) {
      _handledImmediateSosRequestId = widget.immediateSosRequestId;
      unawaited(_handleImmediateSos(immediateMode));
      return;
    }

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

  Future<void> _handleImmediateSos(SosAlertMode mode) async {
    if (viewModel.isSendingSosAlert) {
      return;
    }

    unawaited(
      mode == SosAlertMode.duress
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.heavyImpact(),
    );
    await _triggerAlert(mode);
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
        builder: (context) => _SosTestSettingsPage(
          onSendWhatsAppTest: viewModel.sendWhatsAppTestMessage,
        ),
      ),
    );
  }

  void _showManualSosDetailsOverlay() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: _SosColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return _ManualSosDetailsOverlay(details: viewModel.manualSosDetails);
      },
    );
  }

  Future<void> _openFirstAidGuide() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const FirstAidGuidePage(),
      ),
    );

    if (result == 'sos' && mounted) {
      unawaited(_handleManualSos());
    }
  }

  void _openGearChecklist() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const GearChecklistPage()),
    );
  }

  void _openSafetyToolDetail({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<(String, String)> rows,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SosSafetyToolDetailPage(
          icon: icon,
          title: title,
          subtitle: subtitle,
          rows: rows,
        ),
      ),
    );
  }

  void _openLiveLocationPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LocationSharingPage(
          phoneNumber: widget.session.phoneNumber,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
  }

  Future<void> _triggerAlert(SosAlertMode mode) async {
    if (mode.usesLoudEmergencyPattern) {
      final volumeReady = await ensureIosSosOutputVolumeReady(
        context: context,
        deviceAlertService: _deviceAlertService,
        message:
            '${mode.label} uses iPhone media volume for the local alarm. Turn it up before continuing.',
      );
      if (!volumeReady || !mounted) {
        return;
      }
      unawaited(_startManualSosPattern(mode));
    }

    final triggeredAt = DateTime.now().toUtc();
    final triggerLocation = await _captureTriggerLocation();
    final result = await viewModel.triggerAlert(
      mode: mode,
      triggeredAt: triggeredAt,
      triggerLocation: triggerLocation,
      customMessageNote: _customWhatsAppNoteFor(mode),
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
              ? _SosColors.destructiveFor(context)
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

  Future<void> _startManualSosPattern(SosAlertMode mode) async {
    try {
      await _deviceAlertService.startSosPatternForMode(mode);
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

      setState(() {
        _isManualSosPatternActive = false;
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
      color: _SosColors.backgroundFor(context),
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
                  _MetricsGroup(
                    metrics: viewModel.metrics,
                    onLiveTap: _openLiveLocationPage,
                  ),
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
                  const SizedBox(height: 18),
                  const _SectionTitle(label: 'Safety Tools'),
                  const SizedBox(height: 8),
                  _SosSafetyToolsGrid(
                    onOpenFirstAid: () => unawaited(_openFirstAidGuide()),
                    onOpenGearChecklist: () => _openGearChecklist(),
                  ),
                  const SizedBox(height: 22),
                  if (widget.session.isAdmin)
                    _AdminSosSystemLogsPanel(
                      logs: _adminSosSystemLogs,
                      isLoading: _isLoadingAdminSosSystemLogs,
                      errorMessage: _adminSosSystemLogsError,
                      onRefresh: () => unawaited(_loadAdminSosSystemLogs()),
                    )
                  else
                    _SosTriggerLogPanel(
                      isNetworkAvailable:
                          widget.firebaseBootstrapResult.isAvailable,
                      session: widget.session,
                      latestResult: viewModel.latestSosAlertResult,
                      customWhatsAppNotes: _customWhatsAppNotes,
                      cloudAlertLogs: viewModel.cloudAlertLogs,
                      onCustomWhatsAppNoteChanged: (mode, note) {
                        setState(() {
                          _customWhatsAppNotes = {
                            ..._customWhatsAppNotes,
                            mode: note,
                          };
                        });
                        unawaited(
                          viewModel
                              .saveCustomWhatsAppNote(mode: mode, note: note)
                              .catchError((_) {}),
                        );
                      },
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
                    color: _SosColors.textFor(context),
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
                    color: _SosColors.secondaryTextFor(context),
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
          decoration: BoxDecoration(
            color: _SosColors.surfaceFor(context),
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
              color: _SosColors.destructiveFor(context),
              backgroundColor: _SosColors.destructiveSoftFor(context),
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
        : 'Cloud SOS unavailable';
    final subtitle = isNetworkAvailable
        ? 'Alerts can use cloud logging and WhatsApp delivery when sent.'
        : 'No backend connection right now. WhatsApp dispatch and Firebase cloud logging may fail until connection is restored.';

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
                                color: _SosColors.textFor(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                      _StatusPill(
                        label: isNetworkAvailable ? 'Online' : 'Offline',
                        color: color,
                        surface: color.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    errorMessage == null ? subtitle : '$subtitle $errorMessage',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
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
  const _MetricsGroup({required this.metrics, required this.onLiveTap});

  final List<SosMetric> metrics;
  final VoidCallback onLiveTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              Expanded(
                child: _MetricCell(
                  metric: metrics[index],
                  onTap: metrics[index].label == 'Live' ? onLiveTap : null,
                ),
              ),
              if (index != metrics.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, this.onTap});

  final SosMetric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _SosColors.textFor(context),
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
              color: onTap == null
                  ? _SosColors.secondaryTextFor(context)
                  : _SosColors.green,
              fontWeight: onTap == null ? FontWeight.w400 : FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
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
        ? _SosColors.destructiveFor(context)
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
                      ? _SosColors.destructiveFor(context)
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
                              color: _SosColors.textFor(context),
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
                              ? _SosColors.destructiveFor(context)
                              : _SosColors.secondaryTextFor(context),
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

class _AdminSosSystemLogsPanel extends StatelessWidget {
  const _AdminSosSystemLogsPanel({
    required this.logs,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> logs;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final subtitle = errorMessage != null
        ? 'Unable to load logs. Tap to inspect the status.'
        : logs.isEmpty
        ? 'No SOS system logs found yet.'
        : '${logs.length} log${logs.length == 1 ? '' : 's'} available. Tap to view all.';

    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSosSystemLogsSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                _Glyph(
                  icon: Icons.receipt_long_rounded,
                  color: errorMessage == null
                      ? _SosColors.green
                      : _SosColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS System Logs',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _SosColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh SOS system logs',
                  onPressed: isLoading ? null : onRefresh,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSosSystemLogsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _SosColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.36,
            maxChildSize: 0.92,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionTitle(label: 'SOS System Logs'),
                      ),
                      IconButton(
                        tooltip: 'Refresh SOS system logs',
                        onPressed: isLoading ? null : onRefresh,
                        icon: isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Column(
                      children: [
                        if (errorMessage != null)
                          _SosSystemLogEmptyState(
                            icon: Icons.cloud_off_rounded,
                            message: errorMessage!,
                          )
                        else if (logs.isEmpty)
                          const _SosSystemLogEmptyState(
                            icon: Icons.fact_check_rounded,
                            message: 'No SOS system logs found yet.',
                          )
                        else
                          for (var index = 0; index < logs.length; index++) ...[
                            _SosSystemLogRow(log: logs[index]),
                            if (index != logs.length - 1)
                              const _HorizontalSeparator(),
                          ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SosSystemLogRow extends StatelessWidget {
  const _SosSystemLogRow({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final status = _sosLogString(log['status'], fallback: 'unknown');
    final mode = _sosLogString(log['mode'], fallback: 'sos');
    final sent = _sosLogInt(log['sentCount']);
    final failed = _sosLogInt(log['failedCount']);
    final contactCount = _sosLogInt(log['contactCount']);
    final color = failed > 0 || status == 'failed'
        ? _SosColors.orange
        : _SosColors.green;

    return InkWell(
      onTap: () => _showSosSystemLogDetails(context, log),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: failed > 0 || status == 'failed'
                  ? Icons.warning_amber_rounded
                  : Icons.verified_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${mode.toUpperCase()} - ${status.toUpperCase()}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _sosLogDateLabel(log['triggeredAtLocal']),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: '$sent sent',
                        color: _SosColors.green,
                        surface: _SosColors.greenSoftFor(context),
                      ),
                      _StatusPill(
                        label: '$failed failed',
                        color: failed > 0
                            ? _SosColors.orange
                            : _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                      _StatusPill(
                        label: '$contactCount contacts',
                        color: _SosColors.secondaryTextFor(context),
                        surface: _SosColors.surfaceFor(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _SosSystemLogEmptyState extends StatelessWidget {
  const _SosSystemLogEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Glyph(icon: icon, color: _SosColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _SosColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showSosSystemLogDetails(BuildContext context, Map<String, dynamic> log) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: _SosColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return _SosSystemLogDetailSheet(log: log);
    },
  );
}

class _SosSystemLogDetailSheet extends StatelessWidget {
  const _SosSystemLogDetailSheet({required this.log});

  final Map<String, dynamic> log;

  @override
  Widget build(BuildContext context) {
    final location = _sosLogLocationSummary(log['triggerLocation']);
    final dispatches = log['dispatches'];
    final dispatchCount = dispatches is Iterable ? dispatches.length : 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          6,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.sos_rounded, color: _SosColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS System Log',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _SosColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        _sosLogDateLabel(log['triggeredAtLocal']),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _SosColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InsetGroup(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _StatusRow(
                      label: 'Alert ID',
                      value: _sosLogString(log['alertId'], fallback: '-'),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Type',
                      value: _sosLogString(log['mode'], fallback: 'SOS'),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Status',
                      value: _sosLogString(log['status'], fallback: 'unknown'),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Hiker',
                      value: _sosLogString(
                        log['phoneNumber'],
                        fallback: _sosLogString(
                          log['triggeredByPhoneNumber'],
                          fallback: '-',
                        ),
                      ),
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(label: 'Location', value: location),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Contacts',
                      value:
                          '${_sosLogInt(log['sentCount'])}/${_sosLogInt(log['contactCount'])} sent, ${_sosLogInt(log['failedCount'])} failed',
                    ),
                    const _HorizontalSeparator(),
                    _StatusRow(
                      label: 'Dispatch records',
                      value: '$dispatchCount',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
            ),
          ],
        ),
      ),
    );
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
                color: _SosColors.textFor(context),
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
                        ? _SosColors.destructiveFor(
                            context,
                          ).withValues(alpha: 0.58)
                        : _SosColors.destructiveFor(context),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isAlarmActive
                                    ? _SosColors.green
                                    : _SosColors.destructiveFor(context))
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
            _HiddenDuressIndicator(
              isSending: isSending,
              onLongPress: onDuressLongPress,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap for the 10-second cancel window. Press and hold the button to view exactly what gets activated.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryTextFor(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _SosColors.duress.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _SosColors.duress.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _SosColors.duress.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: _SosColors.duress,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duress SOS',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _SosColors.duress,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Long press to send a silent emergency alert',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _SosColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.touch_app_rounded,
                color: isSending
                    ? _SosColors.secondaryTextFor(context)
                    : _SosColors.duress,
                size: 18,
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
                color: _SosColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'These are shown on hold so the main button stays calm and uncluttered.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.secondaryTextFor(context),
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

class _SosSafetyToolsGrid extends StatelessWidget {
  const _SosSafetyToolsGrid({
    required this.onOpenFirstAid,
    required this.onOpenGearChecklist,
  });

  final VoidCallback onOpenFirstAid;
  final VoidCallback onOpenGearChecklist;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.62,
      children: [
        _SosSafetyToolTile(
          icon: Icons.medical_services_rounded,
          title: 'First-Aid Guide',
          subtitle: 'Offline steps',
          onTap: onOpenFirstAid,
        ),
        _SosSafetyToolTile(
          icon: Icons.checklist_rounded,
          title: 'Gear Checklist',
          subtitle: 'Pre-hike essentials',
          onTap: onOpenGearChecklist,
        ),
      ],
    );
  }
}

class _SosSafetyToolTile extends StatelessWidget {
  const _SosSafetyToolTile({
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
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Glyph(icon: icon, color: _SosColors.green),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _SosColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SosSafetyToolDetailPage extends StatelessWidget {
  const _SosSafetyToolDetailPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SosSafetyToolHeader(
                    title: title,
                    subtitle: 'Safety tool',
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
                            subtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          for (var index = 0; index < rows.length; index++) ...[
                            _StatusRow(
                              label: rows[index].$1,
                              value: rows[index].$2,
                            ),
                            if (index != rows.length - 1)
                              const _HorizontalSeparator(),
                          ],
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

class _SosSafetyToolHeader extends StatelessWidget {
  const _SosSafetyToolHeader({
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
        CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(36),
          onPressed: onBack,
          child: Icon(
            CupertinoIcons.chevron_back,
            color: _SosColors.textFor(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _SosColors.textFor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _SosColors.secondaryTextFor(context),
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

class _SosTriggerLogPanel extends StatelessWidget {
  const _SosTriggerLogPanel({
    required this.isNetworkAvailable,
    required this.session,
    required this.latestResult,
    required this.customWhatsAppNotes,
    required this.cloudAlertLogs,
    required this.onCustomWhatsAppNoteChanged,
  });

  final bool isNetworkAvailable;
  final AppSession session;
  final SosAlertResult? latestResult;
  final Map<SosAlertMode, String> customWhatsAppNotes;
  final List<SosAlert> cloudAlertLogs;
  final void Function(SosAlertMode mode, String note)
  onCustomWhatsAppNoteChanged;

  @override
  Widget build(BuildContext context) {
    final latestAlert = latestResult?.alert;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(label: 'SOS Trigger Log'),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.chat_bubble_rounded,
          title: 'WhatsApp notification',
          subtitle: 'Edit Manual, Duress, and Medical SOS notes.',
          trailing: 'Edit',
          onTap: () => unawaited(_openWhatsAppMessageEditor(context)),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.cloud_done_rounded,
          title: 'Cloud alert log',
          subtitle: latestAlert == null
              ? 'Cloud logs load from Firebase when alerts exist.'
              : 'Latest ${latestAlert.mode.label} is logged with audit fields.',
          trailing: isNetworkAvailable ? '${cloudAlertLogs.length}' : 'Offline',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'Cloud alert log',
            icon: Icons.cloud_done_rounded,
            description:
                'SOS alerts are read from the top-level sosAlerts Firebase collection and mirrored to the user profile latest alert.',
            rows: _cloudLogRows(),
          ),
        ),
        const SizedBox(height: 8),
        _DeliveryActionCard(
          icon: Icons.fact_check_rounded,
          title: 'SOS trigger log',
          subtitle: latestAlert == null
              ? 'Trigger results appear after an SOS alert is sent.'
              : '${latestAlert.sentCount} sent, ${latestAlert.failedCount} failed.',
          trailing: latestAlert?.status.label ?? 'Ready',
          onTap: () => _openDeliveryDetail(
            context,
            title: 'SOS trigger log',
            icon: Icons.fact_check_rounded,
            description:
                'Each contact dispatch records the normalized recipient, send state, and any WhatsApp/Green API error returned by the delivery layer.',
            rows: _deliveryResultRows(),
          ),
        ),
      ],
    );
  }

  Future<void> _openWhatsAppMessageEditor(BuildContext context) async {
    final latestAlert = latestResult?.alert;
    final update = await Navigator.of(context).push<_WhatsAppNoteUpdate>(
      MaterialPageRoute<_WhatsAppNoteUpdate>(
        builder: (context) {
          return _WhatsAppMessageDetailPage(
            session: session,
            initialNotes: customWhatsAppNotes,
            previewMode: latestAlert?.mode ?? SosAlertMode.manual,
            previewTriggeredAt: latestAlert?.triggeredAt ?? DateTime.now(),
            previewLocation: latestAlert?.triggerLocation,
          );
        },
      ),
    );

    if (update != null && context.mounted) {
      onCustomWhatsAppNoteChanged(update.mode, update.note);
    }
  }

  List<(String, String)> _cloudLogRows() {
    final latestAlert = latestResult?.alert;
    final userDocumentId = FirebaseUserRepository.documentIdForPhoneNumber(
      session.phoneNumber,
    );
    if (latestAlert == null) {
      return [
        ('Network status', isNetworkAvailable ? 'Ready' : 'Offline'),
        ('User latest path', 'users/$userDocumentId/latest_sos_alert'),
        ('Audit collection', 'sosAlerts/{alertId}'),
        ('Loaded cloud logs', '${cloudAlertLogs.length}'),
        for (final alert in cloudAlertLogs.take(8))
          (
            '${alert.mode.label} ${_shortTime(alert.triggeredAt)}',
            alert.status.label,
          ),
        ('Stored fields', 'Mode, timestamp, GPS, message, status, dispatches'),
      ];
    }

    return [
      if (cloudAlertLogs.isNotEmpty)
        ('Loaded cloud logs', '${cloudAlertLogs.length}'),
      for (final alert in cloudAlertLogs.take(8))
        (
          '${alert.mode.label} ${_shortTime(alert.triggeredAt)}',
          alert.status.label,
        ),
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

  String _shortTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
                        color: _SosColors.textFor(context),
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
                        color: _SosColors.secondaryTextFor(context),
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
                surface: _SosColors.greenSoftFor(context),
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

class _WhatsAppNoteUpdate {
  const _WhatsAppNoteUpdate({required this.mode, required this.note});

  final SosAlertMode mode;
  final String note;
}

class _WhatsAppMessageDetailPage extends StatefulWidget {
  const _WhatsAppMessageDetailPage({
    required this.session,
    required this.initialNotes,
    required this.previewMode,
    required this.previewTriggeredAt,
    required this.previewLocation,
  });

  final AppSession session;
  final Map<SosAlertMode, String> initialNotes;
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
  late SosAlertMode _selectedMode;
  late Map<SosAlertMode, String> _notes;

  @override
  void initState() {
    super.initState();
    _notes = {..._SosPageState._defaultWhatsAppNotes(), ...widget.initialNotes};
    _selectedMode = _editableModeFor(widget.previewMode);
    _noteController = TextEditingController(text: _noteFor(_selectedMode));
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = SosAlertMessageComposer.compose(
      mode: _selectedMode,
      phoneNumber: widget.session.phoneNumber,
      triggeredAt: widget.previewTriggeredAt,
      triggerLocation: widget.previewLocation,
      customNote: _noteController.text,
    );

    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
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
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoSlidingSegmentedControl<SosAlertMode>(
                            groupValue: _selectedMode,
                            children: const {
                              SosAlertMode.manual: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Manual'),
                              ),
                              SosAlertMode.duress: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Duress'),
                              ),
                              SosAlertMode.medical: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Medical'),
                              ),
                            },
                            onValueChanged: (mode) {
                              if (mode == null) {
                                return;
                              }
                              _saveCurrentNote();
                              setState(() {
                                _selectedMode = mode;
                                _noteController.text = _noteFor(mode);
                              });
                            },
                          ),
                          const SizedBox(height: 12),
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
                                          _SosPageState._defaultWhatsAppNotes()[_selectedMode]!;
                                    });
                                  },
                                  child: const Text('Reset Default'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    _saveCurrentNote();
                                    Navigator.of(context).pop(
                                      _WhatsAppNoteUpdate(
                                        mode: _selectedMode,
                                        note:
                                            _notes[_selectedMode]?.trim() ?? '',
                                      ),
                                    );
                                  },
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
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            preview,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.textFor(context),
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

  SosAlertMode _editableModeFor(SosAlertMode mode) {
    if (mode == SosAlertMode.duress ||
        mode == SosAlertMode.medical ||
        mode == SosAlertMode.manual) {
      return mode;
    }
    return SosAlertMode.manual;
  }

  String _noteFor(SosAlertMode mode) {
    return _notes[mode] ?? SosAlertMessageComposer.defaultCustomNote;
  }

  void _saveCurrentNote() {
    _notes = {..._notes, _selectedMode: _noteController.text.trim()};
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
      backgroundColor: _SosColors.backgroundFor(context),
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
                                  color: _SosColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _SosColors.secondaryTextFor(context),
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

class _SosTestSettingsPage extends StatefulWidget {
  const _SosTestSettingsPage({required this.onSendWhatsAppTest});

  final Future<List<SosContactDispatch>> Function() onSendWhatsAppTest;

  @override
  State<_SosTestSettingsPage> createState() => _SosTestSettingsPageState();
}

class _SosTestSettingsPageState extends State<_SosTestSettingsPage> {
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  Timer? _testStopTimer;
  bool _isFlashlightActive = false;
  bool _isEmergencySirenActive = false;
  bool _isMedicalSirenActive = false;
  bool _isAccelerometerTestActive = false;
  bool _isGyroscopeTestActive = false;
  double _accelerometerTestProgress = 0;
  double _gyroscopeTestProgress = 0;
  String _accelerometerTestStatus =
      'Tap Start, hold the phone securely, then do one quick downward shake.';
  String _gyroscopeTestStatus =
      'Tap Start, then rotate your wrist left-right and tilt forward-back.';

  @override
  void initState() {
    super.initState();
    _accelerometerSubscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (event) {
            if (!mounted) {
              return;
            }
            _handleAccelerometerTestEvent(event);
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _accelerometerTestStatus = 'Accelerometer unavailable.';
              });
            }
          },
        );
    _gyroscopeSubscription =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 200),
        ).listen(
          (event) {
            if (!mounted) {
              return;
            }
            _handleGyroscopeTestEvent(event);
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _gyroscopeTestStatus = 'Gyroscope unavailable.';
              });
            }
          },
        );
  }

  @override
  void dispose() {
    _testStopTimer?.cancel();
    unawaited(_accelerometerSubscription?.cancel());
    unawaited(_gyroscopeSubscription?.cancel());
    unawaited(_deviceAlertService.stopFlashlightPattern());
    unawaited(_deviceAlertService.stopManualSosPattern());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SosColors.backgroundFor(context),
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
                    subtitle: 'Run device, message, and sensor checks',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Column(
                      children: [
                        _SosTestRow(
                          icon: Icons.chat_bubble_rounded,
                          title: 'WhatsApp test message',
                          subtitle:
                              'Send a non-emergency cloud messaging test to your emergency contacts.',
                          onTap: () => unawaited(_sendWhatsAppTestMessage()),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.flash_on_rounded,
                          title: 'SOS flashlight pattern',
                          subtitle: _isFlashlightActive
                              ? 'Tap to stop the active SOS flash pattern.'
                              : 'Short-short-short, long-long-long, short-short-short.',
                          onTap: () => unawaited(_toggleFlashlightTest()),
                        ),
                        if (_isFlashlightActive) ...[
                          const SizedBox(height: 4),
                          _FlashPatternPreview(active: true),
                        ],
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.sos_rounded,
                          title: 'Emergency siren test',
                          subtitle: _isEmergencySirenActive
                              ? 'Tap to stop the emergency siren.'
                              : 'Play the emergency siren only. No flashlight.',
                          onTap: () =>
                              unawaited(_toggleSirenTest(SosAlertMode.manual)),
                        ),
                        const _HorizontalSeparator(),
                        _SosTestRow(
                          icon: Icons.health_and_safety_rounded,
                          title: 'Medical siren test',
                          subtitle: _isMedicalSirenActive
                              ? 'Tap to stop the medical siren.'
                              : 'Play the medical siren only. No flashlight.',
                          onTap: () =>
                              unawaited(_toggleSirenTest(SosAlertMode.medical)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SensorTestCard(
                            icon: Icons.sensors_rounded,
                            title: 'Accelerometer free-fall mimic',
                            instruction:
                                'Quickly shake downward once while holding the phone securely.',
                            progress: _accelerometerTestProgress,
                            status: _accelerometerTestStatus,
                            isActive: _isAccelerometerTestActive,
                            onStart: _startAccelerometerTest,
                          ),
                          const _HorizontalSeparator(),
                          _SensorTestCard(
                            icon: Icons.threesixty_rounded,
                            title: 'Gyroscope rotation test',
                            instruction:
                                'Rotate your wrist in a figure-eight or left-right tilt.',
                            progress: _gyroscopeTestProgress,
                            status: _gyroscopeTestStatus,
                            isActive: _isGyroscopeTestActive,
                            onStart: _startGyroscopeTest,
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

  Future<void> _sendWhatsAppTestMessage() async {
    try {
      final dispatches = await widget.onSendWhatsAppTest();
      final sent = dispatches.where((dispatch) => dispatch.wasSent).length;
      _showTestResult(
        'WhatsApp cloud test sent to $sent/${dispatches.length} contacts.',
      );
    } catch (_) {
      _showTestResult('Unable to send WhatsApp cloud test right now.');
    }
  }

  Future<void> _toggleFlashlightTest() async {
    if (_isFlashlightActive) {
      await _deviceAlertService.stopFlashlightPattern();
      if (mounted) {
        setState(() {
          _isFlashlightActive = false;
        });
      }
      return;
    }

    await _stopAllTests();
    await _deviceAlertService.startFlashlightPattern();
    if (!mounted) {
      return;
    }
    setState(() {
      _isFlashlightActive = true;
    });
    _scheduleAutoStop();
    _showTestResult('SOS flashlight pattern started.');
  }

  Future<void> _toggleSirenTest(SosAlertMode mode) async {
    final isActive = mode == SosAlertMode.medical
        ? _isMedicalSirenActive
        : _isEmergencySirenActive;
    if (isActive) {
      await _stopAllTests();
      return;
    }

    await _stopAllTests();
    await _deviceAlertService.stopFlashlightPattern();
    await _deviceAlertService.startSirenOnlyForMode(mode);
    if (!mounted) {
      return;
    }
    setState(() {
      _isEmergencySirenActive = mode != SosAlertMode.medical;
      _isMedicalSirenActive = mode == SosAlertMode.medical;
    });
    _scheduleAutoStop();
    _showTestResult(
      mode == SosAlertMode.medical
          ? 'Medical siren test started.'
          : 'Emergency siren test started.',
    );
  }

  Future<void> _stopAllTests() async {
    _testStopTimer?.cancel();
    try {
      await _deviceAlertService.stopFlashlightPattern();
      await _deviceAlertService.stopManualSosPattern();
    } finally {
      if (mounted) {
        setState(() {
          _isFlashlightActive = false;
          _isEmergencySirenActive = false;
          _isMedicalSirenActive = false;
        });
      }
    }
  }

  void _scheduleAutoStop() {
    _testStopTimer?.cancel();
    _testStopTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_stopAllTests());
    });
  }

  void _showTestResult(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _startAccelerometerTest() {
    setState(() {
      _isAccelerometerTestActive = true;
      _accelerometerTestProgress = 0;
      _accelerometerTestStatus =
          'Ready. Do one quick downward shake while gripping the phone.';
    });
  }

  void _startGyroscopeTest() {
    setState(() {
      _isGyroscopeTestActive = true;
      _gyroscopeTestProgress = 0;
      _gyroscopeTestStatus =
          'Ready. Rotate and tilt the phone for a few seconds.';
    });
  }

  void _handleAccelerometerTestEvent(AccelerometerEvent event) {
    if (!_isAccelerometerTestActive || !mounted) {
      return;
    }
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final detected = magnitude < 4 || event.z < -8 || event.y < -8;
    if (!detected) {
      return;
    }
    setState(() {
      _accelerometerTestProgress = (_accelerometerTestProgress + 0.34)
          .clamp(0, 1)
          .toDouble();
      _accelerometerTestStatus = _accelerometerTestProgress >= 1
          ? 'Passed. Accelerometer detected the fast downward motion.'
          : 'Motion detected. Repeat once more to confirm.';
      if (_accelerometerTestProgress >= 1) {
        _isAccelerometerTestActive = false;
      }
    });
  }

  void _handleGyroscopeTestEvent(GyroscopeEvent event) {
    if (!_isGyroscopeTestActive || !mounted) {
      return;
    }
    final angularMotion = event.x.abs() + event.y.abs() + event.z.abs();
    if (angularMotion < 1.4) {
      return;
    }
    setState(() {
      _gyroscopeTestProgress = (_gyroscopeTestProgress + 0.18)
          .clamp(0, 1)
          .toDouble();
      _gyroscopeTestStatus = _gyroscopeTestProgress >= 1
          ? 'Passed. Gyroscope detected rotation on the phone.'
          : 'Rotation detected. Keep rotating briefly.';
      if (_gyroscopeTestProgress >= 1) {
        _isGyroscopeTestActive = false;
      }
    });
  }
}

class _FlashPatternPreview extends StatefulWidget {
  const _FlashPatternPreview({required this.active});

  final bool active;

  @override
  State<_FlashPatternPreview> createState() => _FlashPatternPreviewState();
}

class _FlashPatternPreviewState extends State<_FlashPatternPreview> {
  Timer? _timer;
  bool _isOn = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _FlashPatternPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.active) {
      setState(() {
        _isOn = false;
      });
      return;
    }

    _timer = Timer.periodic(const Duration(milliseconds: 260), (_) {
      if (mounted) {
        setState(() {
          _isOn = !_isOn;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isOn
            ? _SosColors.destructiveSoftFor(context)
            : _SosColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            color: _isOn
                ? _SosColors.destructiveFor(context)
                : _SosColors.green,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.active
                  ? 'SOS flash meaning: 3 short, 3 long, 3 short. Auto-stops after 8 seconds.'
                  : 'Flashlight preview is idle.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _SosColors.textFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorTestCard extends StatelessWidget {
  const _SensorTestCard({
    required this.icon,
    required this.title,
    required this.instruction,
    required this.progress,
    required this.status,
    required this.isActive,
    required this.onStart,
  });

  final IconData icon;
  final String title;
  final String instruction;
  final double progress;
  final String status;
  final bool isActive;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _SosColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  instruction,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    color: _SosColors.green,
                    backgroundColor: _SosColors.greenSoftFor(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _SosColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: isActive ? null : onStart,
            child: Text(progress >= 1 ? 'Retest' : 'Start'),
          ),
        ],
      ),
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
                      color: _SosColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _SosColors.secondaryTextFor(context),
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
              decoration: BoxDecoration(
                color: _SosColors.surfaceFor(context),
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
                  color: _SosColors.textFor(context),
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
                  color: _SosColors.secondaryTextFor(context),
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
                color: _SosColors.textFor(context),
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
                color: _SosColors.secondaryTextFor(context),
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
          color: _SosColors.secondaryTextFor(context),
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
        color: _SosColors.destructiveSoftFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _SosColors.destructiveFor(context), size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _SosColors.destructiveFor(context),
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
          color: _SosColors.surfaceFor(context),
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
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _SosColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _SosColors.separatorFor(context),
      ),
    );
  }
}

String _sosLogString(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

int _sosLogInt(Object? value) {
  return value is num ? value.toInt() : 0;
}

String _sosLogDateLabel(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    return 'Time unavailable';
  }
  final local = parsed.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

String _sosLogLocationSummary(Object? value) {
  if (value is! Map || value.isEmpty) {
    return 'Unavailable';
  }
  final latitude = value['latitude'];
  final longitude = value['longitude'];
  final accuracy = value['accuracyMeters'];
  if (latitude is! num || longitude is! num) {
    return 'Captured';
  }
  final coordinate =
      '${latitude.toDouble().toStringAsFixed(5)}, ${longitude.toDouble().toStringAsFixed(5)}';
  if (accuracy is num) {
    return '$coordinate (+/- ${accuracy.round()} m)';
  }
  return coordinate;
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

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color destructiveSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF3C1B1B) : destructiveSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
