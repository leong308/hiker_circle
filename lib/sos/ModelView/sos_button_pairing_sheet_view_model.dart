part of '../sos_button_pairing_sheet_feature.dart';

/// Owns the state and non-visual actions of SosButtonPairingSheet.
class _SosButtonPairingSheetStateViewModel extends ChangeNotifier {
  /// Creates sos button pairing sheet state view model.
  _SosButtonPairingSheetStateViewModel({required this.readBle});
  final HikerBleService Function() readBle;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final Map<String, HikerBlePairedButtonSetupEvent> stateDevices = {};

  Timer? stateScanTimer;

  Timer? stateElapsedTimer;

  Timer? stateSetupModeCountdownTimer;

  DateTime? stateSetupModeDeadline;

  _PairingStep stateStep = _PairingStep.prepare;

  HikerBlePairedButtonSetupEvent? stateSelectedDevice;

  int? stateSetupModeRemainingSeconds;

  String? stateError;

  String? stateErrorCode;

  String? stateStatusDetail;

  bool stateOperationActive = false;

  /// Computes anchor setup mode countdown.
  void commandAnchorSetupModeCountdown(HikerBlePairedButtonSetupEvent event) {
    final remainingSeconds = event.setupModeRemainingSeconds;
    if (remainingSeconds == null) return;
    stateSetupModeDeadline = event.receivedAt.add(
      Duration(seconds: remainingSeconds),
    );
    stateSetupModeRemainingSeconds = remainingSeconds;
    stateSetupModeCountdownTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => commandRefreshSetupModeCountdown(),
    );
  }

  /// Computes use setup mode countdown.
  void commandUseSetupModeCountdown(HikerBlePairedButtonSetupEvent event) {
    if (event.setupModeRemainingSeconds == null) {
      commandClearSetupModeCountdown();
      return;
    }
    commandAnchorSetupModeCountdown(event);
  }

  /// Refreshes setup mode countdown.
  void commandRefreshSetupModeCountdown() {
    final deadline = stateSetupModeDeadline;
    if (deadline == null) return;
    final milliseconds = deadline
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    final remainingSeconds = milliseconds <= 0
        ? 0
        : (milliseconds + 999) ~/ 1000;
    if (remainingSeconds == stateSetupModeRemainingSeconds) return;
    if (mounted) {
      _publish(() => stateSetupModeRemainingSeconds = remainingSeconds);
    }
    if (remainingSeconds == 0) {
      stateSetupModeCountdownTimer?.cancel();
      stateSetupModeCountdownTimer = null;
    }
  }

  /// Clears setup mode countdown.
  void commandClearSetupModeCountdown() {
    stateSetupModeCountdownTimer?.cancel();
    stateSetupModeCountdownTimer = null;
    stateSetupModeDeadline = null;
    stateSetupModeRemainingSeconds = null;
  }

  /// Finishes scan.
  Future<void> commandFinishScan() async {
    if (!mounted || stateOperationActive) return;
    await readBle().stopPairedButtonSetupScan();
    if (!mounted) return;
    stateElapsedTimer?.cancel();
    if (stateDevices.isNotEmpty) {
      if (stateStep == _PairingStep.scanning) {
        _publish(() => stateStep = _PairingStep.detected);
      }
      return;
    }
    commandShowFailure(
      'No setup button was detected. Check that Bluetooth is on, keep the button within one metre, then repeat the 8-second hold and two short presses.',
    );
  }

  /// Computes return to prepare.
  Future<void> commandReturnToPrepare() async {
    if (stateOperationActive) return;
    stateScanTimer?.cancel();
    stateElapsedTimer?.cancel();
    commandClearSetupModeCountdown();
    await readBle().stopPairedButtonSetupScan();
    if (!mounted) return;
    _publish(() {
      stateError = null;
      stateErrorCode = null;
      stateSelectedDevice = null;
      stateStep = _PairingStep.prepare;
    });
  }

  /// Opens bluetooth settings.
  Future<void> commandOpenBluetoothSettings() async {
    try {
      await readBle().openBluetoothSettings();
    } on HikerBleException catch (error) {
      if (!mounted) return;
      _publish(() => stateError = error.message);
    }
  }

  /// Shows failure.
  void commandShowFailure(
    String message, {
    bool keepSelection = false,
    String? errorCode,
  }) {
    stateScanTimer?.cancel();
    stateElapsedTimer?.cancel();
    if (!mounted) return;
    _publish(() {
      stateError = message;
      stateErrorCode = errorCode;
      stateStatusDetail = null;
      stateStep = _PairingStep.failure;
      if (!keepSelection) stateSelectedDevice = null;
    });
  }

  /// Returns command progress.
  double get commandProgress => switch (stateStep) {
    _PairingStep.prepare => 0.15,
    _PairingStep.scanning => 0.32,
    _PairingStep.detected => 0.48,
    _PairingStep.naming => 0.62,
    _PairingStep.connecting => 0.78,
    _PairingStep.confirming => 0.9,
    _PairingStep.success => 1,
    _PairingStep.failure => stateSelectedDevice == null ? 0.32 : 0.78,
  };

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final void Function() effectPresentCloseEffect1;

  /// Closes.
  Future<void> commandClose() async {
    if (stateOperationActive) return;
    stateScanTimer?.cancel();
    stateElapsedTimer?.cancel();
    commandClearSetupModeCountdown();
    await readBle().stopPairedButtonSetupScan();
    if (mounted) effectPresentCloseEffect1();
  }
}
