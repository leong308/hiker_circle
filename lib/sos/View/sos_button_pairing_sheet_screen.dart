// ignore_for_file: sort_child_properties_last
part of '../sos_button_pairing_sheet_feature.dart';

/// Defines the pairing step choices.
enum _PairingStep {
  prepare,
  scanning,
  detected,
  naming,
  connecting,
  confirming,
  success,
  failure,
}

/// Advance from BLE discovery to a confirmed candidate before persisting the paired button.
class SosButtonPairingSheet extends StatefulWidget {
  /// Creates sos button pairing sheet.
  const SosButtonPairingSheet({
    super.key,
    required this.ble,
    required this.onPaired,
  });

  final HikerBleService ble;
  final Future<void> Function() onPaired;

  /// Creates the presentation state for this widget.
  @override
  State<SosButtonPairingSheet> createState() => _SosButtonPairingSheetState();
}

/// Manages the sos button pairing sheet presentation and lifecycle.
class _SosButtonPairingSheetState extends State<SosButtonPairingSheet>
    with SingleTickerProviderStateMixin {
  late final _SosButtonPairingSheetStateViewModel _screenModel;

  /// Returns devices.
  Map<String, HikerBlePairedButtonSetupEvent> get _devices =>
      _screenModel.stateDevices;

  /// Returns scan timer.
  Timer? get _scanTimer => _screenModel.stateScanTimer;

  /// Updates scan timer.
  set _scanTimer(Timer? value) => _screenModel.stateScanTimer = value;

  /// Returns elapsed timer.
  Timer? get _elapsedTimer => _screenModel.stateElapsedTimer;

  /// Updates elapsed timer.
  set _elapsedTimer(Timer? value) => _screenModel.stateElapsedTimer = value;

  /// Returns setup mode countdown timer.
  Timer? get _setupModeCountdownTimer =>
      _screenModel.stateSetupModeCountdownTimer;

  /// Returns step.
  _PairingStep get _step => _screenModel.stateStep;

  /// Updates step.
  set _step(_PairingStep value) => _screenModel.stateStep = value;

  /// Returns selected device.
  HikerBlePairedButtonSetupEvent? get _selectedDevice =>
      _screenModel.stateSelectedDevice;

  /// Updates selected device.
  set _selectedDevice(HikerBlePairedButtonSetupEvent? value) =>
      _screenModel.stateSelectedDevice = value;

  /// Returns setup mode remaining seconds.
  int? get _setupModeRemainingSeconds =>
      _screenModel.stateSetupModeRemainingSeconds;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Returns error code.
  String? get _errorCode => _screenModel.stateErrorCode;

  /// Updates error code.
  set _errorCode(String? value) => _screenModel.stateErrorCode = value;

  /// Returns status detail.
  String? get _statusDetail => _screenModel.stateStatusDetail;

  /// Updates status detail.
  set _statusDetail(String? value) => _screenModel.stateStatusDetail = value;

  /// Returns operation active.
  bool get _operationActive => _screenModel.stateOperationActive;

  /// Updates operation active.
  set _operationActive(bool value) => _screenModel.stateOperationActive = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const Duration _scanWindow = Duration(seconds: 30);

  final TextEditingController _nameController = TextEditingController(
    text: HikerBleService.defaultPairedButtonName,
  );
  late final AnimationController _pulseController;
  StreamSubscription<HikerBleEvent>? _events;

  int _scanSeconds = 0;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SosButtonPairingSheetStateViewModel(
      readBle: () => widget.ble,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentCloseEffect1 = _presentCloseEffect1;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.88,
      upperBound: 1.08,
    )..repeat(reverse: true);
    _events = widget.ble.events.listen(
      _handleBleEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _operationActive) return;
        _showFailure('Bluetooth event monitoring stopped. Please try again.');
      },
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _scanTimer?.cancel();
    _elapsedTimer?.cancel();
    _setupModeCountdownTimer?.cancel();
    unawaited(widget.ble.stopPairedButtonSetupScan());
    unawaited(_events?.cancel());
    _nameController.dispose();
    _pulseController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Handles ble event.
  void _handleBleEvent(HikerBleEvent event) {
    if (!mounted) return;
    if (event is HikerBlePairedButtonSetupEvent && event.address.isNotEmpty) {
      final wasEmpty = _devices.isEmpty;
      final selectedAddress = _selectedDevice?.address;
      final strongestRssi = _devices.values.fold<int>(
        -1000,
        (strongest, device) =>
            device.rssi > strongest ? device.rssi : strongest,
      );
      if (selectedAddress == event.address ||
          (selectedAddress == null && event.rssi >= strongestRssi)) {
        _useSetupModeCountdown(event);
      }
      setState(() {
        _devices[event.address] = event;
        if (_step == _PairingStep.scanning) {
          _step = _PairingStep.detected;
        }
      });
      if (wasEmpty) {
        unawaited(HapticFeedback.mediumImpact());
      }
      return;
    }
    if (event is! HikerBleStatusEvent ||
        !event.status.startsWith('paired_button_')) {
      return;
    }
    switch (event.status) {
      case 'paired_button_pairing_connecting':
        setState(() {
          _step = _PairingStep.connecting;
          _statusDetail =
              'Keep the SOS button close to this phone. Approve the Bluetooth pairing request if Android shows one.';
        });
      case 'paired_button_secure_bond_pending':
        setState(() {
          _step = _PairingStep.connecting;
          _statusDetail =
              event.message ??
              'Approve Android Bluetooth pairing if requested. Setup will continue automatically.';
        });
      case 'paired_button_secure_bond_reused':
      case 'paired_button_secure_bond_approved':
        setState(() {
          _step = _PairingStep.connecting;
          _statusDetail =
              event.message ??
              'Android Bluetooth pairing is approved. Continuing automatically.';
        });
      case 'paired_button_refreshing_gatt_cache':
        setState(() {
          _step = _PairingStep.connecting;
          _statusDetail =
              event.message ??
              'Refreshing Android Bluetooth details and reconnecting automatically.';
        });
      case 'paired_button_ready':
      case 'paired_button_pairing_written':
      case 'paired_button_awaiting_confirmation':
        setState(() {
          _step = _PairingStep.confirming;
          _statusDetail =
              'Press and release the main external SOS button once now. Do not press BOOT or RST.';
        });
        unawaited(HapticFeedback.selectionClick());
      case 'paired_button_setup_scan_failed':
        if (!_operationActive) {
          _showFailure(
            event.message ?? 'Bluetooth could not scan for the SOS button.',
          );
        }
      default:
        if (event.message?.trim().isNotEmpty == true && _operationActive) {
          setState(() => _statusDetail = event.message!.trim());
        }
    }
  }

  /// Delegates use setup mode countdown to the ViewModel.
  void _useSetupModeCountdown(HikerBlePairedButtonSetupEvent event) =>
      _screenModel.commandUseSetupModeCountdown(event);

  /// Delegates clear setup mode countdown to the ViewModel.
  void _clearSetupModeCountdown() =>
      _screenModel.commandClearSetupModeCountdown();

  /// Starts scan.
  Future<void> _startScan() async {
    if (_operationActive) return;
    _scanTimer?.cancel();
    _elapsedTimer?.cancel();
    _clearSetupModeCountdown();
    setState(() {
      _devices.clear();
      _selectedDevice = null;
      _scanSeconds = 0;
      _error = null;
      _errorCode = null;
      _statusDetail = null;
      _step = _PairingStep.scanning;
    });
    try {
      await widget.ble.startPairedButtonSetupScan();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted &&
            (_step == _PairingStep.scanning ||
                _step == _PairingStep.detected)) {
          setState(() => _scanSeconds += 1);
        }
      });
      _scanTimer = Timer(_scanWindow, _finishScan);
    } on HikerBleException catch (error) {
      _showFailure(error.message);
    }
  }

  /// Delegates finish scan to the ViewModel.
  Future<void> _finishScan() => _screenModel.commandFinishScan();

  /// Delegates return to prepare to the ViewModel.
  Future<void> _returnToPrepare() => _screenModel.commandReturnToPrepare();

  /// Selects device.
  Future<void> _selectDevice(HikerBlePairedButtonSetupEvent device) async {
    if (_operationActive) return;
    _scanTimer?.cancel();
    _elapsedTimer?.cancel();
    _useSetupModeCountdown(device);
    await widget.ble.stopPairedButtonSetupScan();
    if (!mounted) return;
    final advertisedName = device.displayName.trim();
    final isSetupAdvertisement =
        advertisedName.toLowerCase() == 'hikercircle setup';
    _nameController.text = advertisedName.isEmpty || isSetupAdvertisement
        ? HikerBleService.defaultPairedButtonName
        : advertisedName;
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );
    setState(() {
      _selectedDevice = device;
      _step = _PairingStep.naming;
      _error = null;
      _errorCode = null;
    });
  }

  /// Computes pair selected device.
  Future<void> _pairSelectedDevice() async {
    final device = _selectedDevice;
    final name = _nameController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (device == null) {
      _showFailure('The detected button is no longer selected. Scan again.');
      return;
    }
    if (_setupModeRemainingSeconds == 0) {
      _showFailure(
        'The button setup-mode countdown ended. Start setup mode again before pairing.',
      );
      return;
    }
    if (name.isEmpty || name.length > 40) {
      setState(() {
        _error = 'Enter a button name between 1 and 40 characters.';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _operationActive = true;
      _error = null;
      _errorCode = null;
      _step = _PairingStep.connecting;
      _statusDetail =
          'Keep the button close and approve any secure Bluetooth pairing prompt.';
    });
    try {
      await widget.ble.pairSosButton(
        address: device.address,
        displayName: name,
      );
      await widget.onPaired();
      if (!mounted) return;
      await HapticFeedback.heavyImpact();
      setState(() {
        _operationActive = false;
        _step = _PairingStep.success;
        _statusDetail = null;
      });
      _clearSetupModeCountdown();
    } on HikerBleException catch (error) {
      if (!mounted) return;
      setState(() => _operationActive = false);
      final needsFreshStart =
          HikerBleService.isTerminalPairingCompatibilityError(error.code);
      _showFailure(
        error.message,
        keepSelection: !needsFreshStart,
        errorCode: error.code,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _operationActive = false);
      _showFailure(
        'The button may be paired, but HikerCircle could not refresh the local list. Close this guide and reopen the page to verify it.',
        keepSelection: true,
      );
    }
  }

  /// Delegates open bluetooth settings to the ViewModel.
  Future<void> _openBluetoothSettings() =>
      _screenModel.commandOpenBluetoothSettings();

  /// Delegates show failure to the ViewModel.
  void _showFailure(
    String message, {
    bool keepSelection = false,
    String? errorCode,
  }) => _screenModel.commandShowFailure(
    message,
    keepSelection: keepSelection,
    errorCode: errorCode,
  );

  /// Delegates close to the ViewModel.
  Future<void> _close() => _screenModel.commandClose();

  /// Returns progress.
  double get _progress => _screenModel.commandProgress;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return PopScope(
      canPop: !_operationActive,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: 0.94,
          child: Material(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _PairingSheetHeader(
                  progress: _progress,
                  canClose: !_operationActive,
                  onClose: _close,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _buildStep(scheme),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds step.
  Widget _buildStep(ColorScheme scheme) {
    return switch (_step) {
      _PairingStep.prepare => _GuideStep(
        key: const ValueKey('prepare'),
        icon: Icons.touch_app_rounded,
        title: 'Put the button in setup mode',
        subtitle:
            'Keep this screen open and the SOS button within one metre of your phone.',
        child: const Column(
          children: [
            _InstructionTile(
              number: 1,
              title: 'Press and hold',
              detail:
                  'Hold the main external SOS button. The blue LED blinks slowly.',
            ),
            _InstructionTile(
              number: 2,
              title: 'Release it',
              detail:
                  'Release when the blue LED becomes solid at 8 seconds. It will flash twice.',
            ),
            _InstructionTile(
              number: 3,
              title: 'Press twice',
              detail:
                  'Make two presses within 8 seconds. Setup mode repeats two flashes, then one short flash.',
            ),
          ],
        ),
        primaryLabel: 'My button is ready',
        primaryIcon: Icons.bluetooth_searching_rounded,
        onPrimary: _startScan,
        secondaryLabel: 'Cancel',
        onSecondary: _close,
      ),
      _PairingStep.scanning => _GuideStep(
        key: const ValueKey('scanning'),
        icon: Icons.bluetooth_searching_rounded,
        hero: SizedBox.square(
          dimension: 132,
          child: Lottie.asset(
            'assets/animations/bluetooth_search.json',
            repeat: true,
            fit: BoxFit.contain,
          ),
        ),
        title: 'Searching nearby…',
        subtitle:
            'Listening for a HikerCircle SOS button in setup mode. Usually this takes only a few seconds.',
        child: _SearchingPanel(
          elapsedSeconds: _scanSeconds,
          scanWindowSeconds: _scanWindow.inSeconds,
        ),
        primaryLabel: 'Stop and try again',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: _returnToPrepare,
        secondaryLabel: 'Cancel',
        onSecondary: _close,
      ),
      _PairingStep.detected => _GuideStep(
        key: ValueKey('detected-${_devices.length}'),
        icon: Icons.bluetooth_connected_rounded,
        title: _devices.length == 1
            ? 'SOS button detected'
            : '${_devices.length} SOS buttons detected',
        subtitle:
            'Choose the button closest to this phone. Signal strength helps identify it.',
        child: Column(
          children: [
            _SetupModeCountdownCard(
              remainingSeconds: _setupModeRemainingSeconds,
            ),
            const SizedBox(height: 12),
            _DetectedDevices(
              devices: _devices.values.toList()
                ..sort((a, b) => b.rssi.compareTo(a.rssi)),
              onSelected: _selectDevice,
            ),
          ],
        ),
        primaryLabel: 'Scan again',
        primaryIcon: Icons.refresh_rounded,
        onPrimary: _startScan,
        secondaryLabel: 'Cancel',
        onSecondary: _close,
      ),
      _PairingStep.naming => _GuideStep(
        key: const ValueKey('naming'),
        icon: Icons.edit_rounded,
        title: 'Name your SOS button',
        subtitle:
            'Use a recognisable name so you can identify this button later.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SetupModeCountdownCard(
              remainingSeconds: _setupModeRemainingSeconds,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _pairSelectedDevice(),
              decoration: InputDecoration(
                labelText: 'Button name',
                hintText: 'Example: Backpack SOS',
                prefixIcon: const Icon(Icons.sos_rounded),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _InfoBanner(
              icon: Icons.touch_app_rounded,
              text:
                  'Next, Android may ask you to approve secure Bluetooth pairing. Then press the physical SOS button once to confirm ownership.',
              color: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
            ),
          ],
        ),
        primaryLabel: 'Continue to secure pairing',
        primaryIcon: Icons.lock_rounded,
        onPrimary: _pairSelectedDevice,
        secondaryLabel: 'Choose another button',
        onSecondary: () => setState(() => _step = _PairingStep.detected),
      ),
      _PairingStep.connecting => _GuideStep(
        key: const ValueKey('connecting'),
        icon: Icons.lock_rounded,
        animatedIcon: _pulseController,
        title: 'Creating a secure connection',
        subtitle: _statusDetail ?? 'Keep the button close to this phone.',
        child: Column(
          children: [
            _SetupModeCountdownCard(
              remainingSeconds: _setupModeRemainingSeconds,
            ),
            const SizedBox(height: 14),
            const _PairingActivityPanel(
              headline: 'Waiting for Bluetooth',
              detail:
                  'If Android displays a pairing request, approve it. HikerCircle never displays or exports the button secret.',
            ),
          ],
        ),
      ),
      _PairingStep.confirming => _GuideStep(
        key: const ValueKey('confirming'),
        icon: Icons.touch_app_rounded,
        animatedIcon: _pulseController,
        title: 'Press the SOS button once now',
        subtitle:
            _statusDetail ??
            'This physical press proves that the button is in your hands.',
        child: Column(
          children: [
            _SetupModeCountdownCard(
              remainingSeconds: _setupModeRemainingSeconds,
            ),
            const SizedBox(height: 14),
            const _PairingActivityPanel(
              headline: 'Waiting for your confirmation press',
              detail:
                  'Press and release the main external SOS button once. Do not hold it, and do not press BOOT or RST.',
              emphasize: true,
            ),
          ],
        ),
      ),
      _PairingStep.success => _GuideStep(
        key: const ValueKey('success'),
        icon: Icons.check_circle_rounded,
        title: 'Your SOS button is ready',
        subtitle:
            '${_nameController.text.trim()} is securely paired to this phone.',
        child: _InfoBanner(
          icon: Icons.verified_user_rounded,
          text:
              'A valid press from this button can now start this phone’s Manual SOS workflow. Keep Bluetooth enabled for background detection.',
          color: scheme.tertiaryContainer,
          foregroundColor: scheme.onTertiaryContainer,
        ),
        primaryLabel: 'Done',
        primaryIcon: Icons.check_rounded,
        onPrimary: _close,
      ),
      _PairingStep.failure => _GuideStep(
        key: ValueKey('failure-$_error'),
        icon: Icons.error_outline_rounded,
        title: 'Pairing needs attention',
        subtitle: _error ?? 'The SOS button could not be paired.',
        child: _InfoBanner(
          icon: Icons.lightbulb_outline_rounded,
          text: HikerBleService.isTerminalPairingCompatibilityError(_errorCode)
              ? 'HikerCircle already refreshed Android’s cached button details once. Open Bluetooth settings, forget “HikerCircle Setup”, return here, and start setup mode again. Repeated retrying cannot restore a characteristic that Android or the firmware does not expose.'
              : _selectedDevice == null
              ? 'Check Bluetooth permissions, move the button closer, and repeat setup mode before trying again.'
              : 'Keep the button close. If Android started Bluetooth pairing, approve the system prompt, then retry this step.',
          color: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
        ),
        primaryLabel:
            HikerBleService.isTerminalPairingCompatibilityError(_errorCode)
            ? 'Open Bluetooth settings'
            : _selectedDevice == null
            ? 'Try scanning again'
            : 'Retry pairing',
        primaryIcon:
            HikerBleService.isTerminalPairingCompatibilityError(_errorCode)
            ? Icons.settings_bluetooth_rounded
            : Icons.refresh_rounded,
        onPrimary:
            HikerBleService.isTerminalPairingCompatibilityError(_errorCode)
            ? _openBluetoothSettings
            : _selectedDevice == null
            ? _startScan
            : _pairSelectedDevice,
        secondaryLabel: 'Back to instructions',
        onSecondary: _returnToPrepare,
      ),
    };
  }

  /// Presents the close effect1 UI.
  void _presentCloseEffect1() =>
      Navigator.of(context).pop(_step == _PairingStep.success);
}

/// Displays the pairing sheet header.
class _PairingSheetHeader extends StatelessWidget {
  /// Creates pairing sheet header.
  const _PairingSheetHeader({
    required this.progress,
    required this.canClose,
    required this.onClose,
  });

  final double progress;
  final bool canClose;
  final VoidCallback onClose;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add SOS button',
                  style: PageHeaderStyle.title(context, scheme.onSurface),
                ),
              ),
              PageHeaderAction(
                tooltip: canClose
                    ? 'Close pairing guide'
                    : 'Pairing in progress',
                onPressed: canClose ? onClose : null,
                icon: Icons.close_rounded,
                color: scheme.primary,
                surface: scheme.surface,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 350),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the guide step.
class _GuideStep extends StatelessWidget {
  /// Creates guide step.
  const _GuideStep({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.animatedIcon,
    this.hero,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Animation<double>? animatedIcon;
  final Widget? hero;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconWidget = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 38, color: scheme.onPrimaryContainer),
    );
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            child:
                hero ??
                (animatedIcon == null
                    ? iconWidget
                    : ScaleTransition(scale: animatedIcon!, child: iconWidget)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          child,
          if (primaryLabel != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: Icon(primaryIcon ?? Icons.arrow_forward_rounded),
              label: Text(primaryLabel!),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Displays the detected devices.
class _DetectedDevices extends StatelessWidget {
  /// Creates detected devices.
  const _DetectedDevices({required this.devices, required this.onSelected});

  final List<HikerBlePairedButtonSetupEvent> devices;
  final ValueChanged<HikerBlePairedButtonSetupEvent> onSelected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: devices
          .map((device) {
            final signalLabel = switch (device.rssi) {
              >= -55 => 'Very close',
              >= -70 => 'Nearby',
              _ => 'Weak signal',
            };
            final addressSuffix = device.address.length <= 5
                ? device.address
                : device.address.substring(device.address.length - 5);
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelected(device),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: const Icon(Icons.sos_rounded),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text('$signalLabel • Device …$addressSuffix'),
                            if (device.setupModeRemainingSeconds != null)
                              Text(
                                'Setup mode • ${_formatSetupCountdown(device.setupModeRemainingSeconds!)} remaining',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

/// Formats setup countdown.
String _formatSetupCountdown(int totalSeconds) {
  final boundedSeconds = totalSeconds.clamp(0, 255);
  final minutes = boundedSeconds ~/ 60;
  final seconds = boundedSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
