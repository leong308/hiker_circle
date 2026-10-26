part of '../ios_hike_safety_setup_dialog_feature.dart';

/// Keeps the same start attempt suspended while the hiker visits Settings.
/// Only confirmed permission readiness or explicit cancellation resolves it.
Future<bool> showIosHikeSafetySetupDialog({
  required BuildContext context,
  required ActiveHikeLiveStatusService service,
  required NativeHikeSafetyStatus initialStatus,
  required bool fallDetectionEnabled,
}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IosHikeSafetySetupDialog(
        key: const ValueKey('ios-hike-safety-setup'),
        service: service,
        initialStatus: initialStatus,
        fallDetectionEnabled: fallDetectionEnabled,
      ),
    ) ==
    true;

/// Displays the ios hike safety setup dialog.
class _IosHikeSafetySetupDialog extends StatefulWidget {
  /// Creates ios hike safety setup dialog.
  const _IosHikeSafetySetupDialog({
    super.key,
    required this.service,
    required this.initialStatus,
    required this.fallDetectionEnabled,
  });

  final ActiveHikeLiveStatusService service;
  final NativeHikeSafetyStatus initialStatus;
  final bool fallDetectionEnabled;

  /// Creates the presentation state for this widget.
  @override
  State<_IosHikeSafetySetupDialog> createState() =>
      _IosHikeSafetySetupDialogState();
}

/// Manages the ios hike safety setup dialog presentation and lifecycle.
class _IosHikeSafetySetupDialogState extends State<_IosHikeSafetySetupDialog>
    with WidgetsBindingObserver {
  late final _IosHikeSafetySetupDialogStateViewModel _screenModel;

  /// Returns checking.
  bool get _checking => _screenModel.stateChecking;

  /// Updates checking.
  set _checking(bool value) => _screenModel.stateChecking = value;

  /// Returns opening settings.
  bool get _openingSettings => _screenModel.stateOpeningSettings;

  /// Returns finished.
  bool get _finished => _screenModel.stateFinished;

  /// Updates finished.
  set _finished(bool value) => _screenModel.stateFinished = value;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late NativeHikeSafetyStatus _status = widget.initialStatus;

  bool _checkAgain = false;

  /// Returns missing.
  List<String> get _missing => [
    if (!_status.fineLocationGranted || !_status.backgroundLocationGranted)
      'Location: Always',
    if (widget.fallDetectionEnabled && !_status.notificationsAuthorized)
      'Notifications: Allow',
    if (widget.fallDetectionEnabled && !_status.motionGranted)
      'Motion & Fitness: On',
  ];

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _IosHikeSafetySetupDialogStateViewModel(
      readService: () => widget.service,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_finished) {
      unawaited(_refreshStatus());
    }
  }

  /// Finishes.
  void _finish(bool ready) {
    if (_finished || !mounted) return;
    _finished = true;
    HikeStartNavigation.closeOwnedRoute(ModalRoute.of<bool>(context), ready);
  }

  /// Refreshes status.
  Future<void> _refreshStatus() async {
    if (_finished || !mounted) return;
    if (_checking) {
      _checkAgain = true;
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      do {
        _checkAgain = false;
        final next = await widget.service.nativeSafetyStatus().timeout(
          const Duration(seconds: 10),
        );
        if (!mounted || _finished) return;
        // A missing/failed native response cannot clear a known iOS gate.
        if (!next.supported || next.platform != 'ios') {
          throw StateError('iPhone permission status unavailable');
        }
        setState(() => _status = next);
        if (_missing.isEmpty) {
          _finish(true);
          return;
        }
      } while (_checkAgain);
    } catch (_) {
      if (mounted && !_finished) {
        setState(
          () => _error =
              'Unable to verify the updated settings. Check again to continue; your preparation is kept.',
        );
      }
    } finally {
      if (mounted && !_finished) {
        setState(() => _checking = false);
      }
    }
  }

  /// Delegates open settings to the ViewModel.
  Future<void> _openSettings() => _screenModel.commandOpenSettings();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: CupertinoAlertDialog(
      title: const Text('Finish iPhone safety setup'),
      content: Column(
        children: [
          Text(
            'Hike monitoring cannot start until these settings are enabled:\n\n'
            '${_missing.map((item) => '• $item').join('\n')}\n\n'
            'Only the settings listed above are required. Time Sensitive '
            'Notifications and Live Activities are optional enhancements '
            'and will not remove you from a team hike.',
          ),
          if (_checking) ...[
            const SizedBox(height: 12),
            const CupertinoActivityIndicator(),
            const SizedBox(height: 6),
            const Text('Checking updated settings…'),
          ],
          if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => _finish(false),
          child: const Text('Cancel hike start'),
        ),
        if (_error != null)
          CupertinoDialogAction(
            onPressed: _checking ? null : _refreshStatus,
            child: const Text('Check again'),
          ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: _openingSettings || _checking ? null : _openSettings,
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}
