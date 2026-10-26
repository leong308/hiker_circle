part of '../ios_sos_volume_guard_feature.dart';

/// Require the iOS volume confirmation before continuing the audible SOS setup flow.
Future<bool> ensureIosSosOutputVolumeReady({
  required BuildContext context,
  required SosDeviceAlertService deviceAlertService,
  String title = 'Turn Up iPhone Volume',
  String message =
      'HikerCircle uses iPhone media volume for the SOS alarm. Turn up the volume before continuing.',
  String proceedLabel = 'Continue SOS',
}) async {
  final status = await deviceAlertService.getOutputVolumeStatus();
  if (!status.shouldGateForIos || status.isAudible) {
    if (status.shouldGateForIos) {
      unawaited(deviceAlertService.endOutputVolumeMonitoring());
    }
    return true;
  }
  if (!context.mounted) {
    return false;
  }

  final result = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _IosSosVolumeGuardDialog(
        deviceAlertService: deviceAlertService,
        initialStatus: status,
        title: title,
        message: message,
        proceedLabel: proceedLabel,
      );
    },
  );
  return result == true;
}

/// Displays the ios sos volume guard dialog.
class _IosSosVolumeGuardDialog extends StatefulWidget {
  /// Creates ios sos volume guard dialog.
  const _IosSosVolumeGuardDialog({
    required this.deviceAlertService,
    required this.initialStatus,
    required this.title,
    required this.message,
    required this.proceedLabel,
  });

  final SosDeviceAlertService deviceAlertService;
  final SosOutputVolumeStatus initialStatus;
  final String title;
  final String message;
  final String proceedLabel;

  /// Creates the presentation state for this widget.
  @override
  State<_IosSosVolumeGuardDialog> createState() =>
      _IosSosVolumeGuardDialogState();
}

/// Manages the ios sos volume guard dialog presentation and lifecycle.
class _IosSosVolumeGuardDialogState extends State<_IosSosVolumeGuardDialog>
    with WidgetsBindingObserver {
  late final _IosSosVolumeGuardDialogStateViewModel _screenModel;

  /// Returns status.
  SosOutputVolumeStatus get _status => _screenModel.stateStatus;

  /// Updates status.
  set _status(SosOutputVolumeStatus value) => _screenModel.stateStatus = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  Timer? _pollTimer;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _IosSosVolumeGuardDialogStateViewModel(
      readDeviceAlertService: () => widget.deviceAlertService,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    _status = widget.initialStatus;
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => unawaited(_refreshStatus()),
    );
    unawaited(_prepareVolumeMonitoring());
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    unawaited(widget.deviceAlertService.endOutputVolumeMonitoring());

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatus());
    }
  }

  /// Delegates prepare volume monitoring to the ViewModel.
  Future<void> _prepareVolumeMonitoring() =>
      _screenModel.commandPrepareVolumeMonitoring();

  /// Delegates refresh status to the ViewModel.
  Future<void> _refreshStatus() => _screenModel.commandRefreshStatus();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final currentPercent = _status.outputVolumePercent;
    final requiredPercent = _status.minimumRequiredPercent;
    final canProceed = _status.isAudible;

    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(widget.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              canProceed
                  ? 'Volume detected: $currentPercent%'
                  : 'Volume must be at least $requiredPercent%',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: canProceed
                    ? const Color(0xFF34A853)
                    : const Color(0xFFE11D48),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _status.displayOutputVolume,
              minHeight: 4,
              color: canProceed
                  ? const Color(0xFF34A853)
                  : const Color(0xFFE11D48),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
            Text(
              canProceed
                  ? 'You can continue.'
                  : 'Use the iPhone volume buttons or Control Center, then wait for this check to update.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: canProceed ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.proceedLabel),
        ),
      ],
    );
  }
}
