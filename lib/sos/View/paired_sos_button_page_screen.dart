part of '../paired_sos_button_page_feature.dart';

/// Displays the section heading.
class _SectionHeading extends StatelessWidget {
  /// Creates section heading.
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.count,
  });

  final String title;
  final String subtitle;
  final int? count;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (count != null)
          Chip(label: Text('$count'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

/// Present paired-button readiness and the outcome of an explicitly armed test.
class PairedSosButtonPage extends StatefulWidget {
  /// Creates paired sos button page.
  const PairedSosButtonPage({super.key, required this.accountId});

  final String accountId;

  /// Creates the presentation state for this widget.
  @override
  State<PairedSosButtonPage> createState() => _PairedSosButtonPageState();
}

/// Manages the paired sos button page presentation and lifecycle.
class _PairedSosButtonPageState extends State<PairedSosButtonPage> {
  /// Returns pairing in progress.
  bool get _pairingInProgress => _screenModel.statePairingInProgress;

  /// Returns downloading logs for.
  String? get _downloadingLogsFor => _screenModel.stateDownloadingLogsFor;

  late final _PairedSosButtonPageStateViewModel _screenModel;

  /// Returns ble.
  HikerBleService get _ble => _screenModel.stateBle;

  /// Returns paired.
  List<PairedSosButton> get _paired => _screenModel.statePaired;

  /// Returns account ready.
  bool get _accountReady => _screenModel.stateAccountReady;

  /// Returns registry needs reset.
  bool get _registryNeedsReset => _screenModel.stateRegistryNeedsReset;

  /// Returns message.
  String? get _message => _screenModel.stateMessage;

  /// Updates message.
  set _message(String? value) => _screenModel.stateMessage = value;

  /// Returns readiness.
  SosButtonReadiness? get _readiness => _screenModel.stateReadiness;

  /// Returns readiness loading.
  bool get _readinessLoading => _screenModel.stateReadinessLoading;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  String? _testingButtonFor;
  Timer? _buttonTestCountdownTimer;
  StreamSubscription<HikerBleEvent>? _buttonTestSubscription;
  Completer<_ButtonTestOutcome>? _buttonTestOutcome;

  Timer? _readinessTimer;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _PairedSosButtonPageStateViewModel(
      readAccountId: () => widget.accountId,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentDownloadLogsEffect1 = _presentDownloadLogsEffect1;
    _screenModel.effectPresentOpenPairingGuideEffect1 =
        _presentOpenPairingGuideEffect1;
    _screenModel.effectPresentDownloadLogsEffect2 = _presentDownloadLogsEffect2;
    _screenModel.effectPresentUnpairEffect1 = _presentUnpairEffect1;
    _screenModel.effectPresentDownloadLogsEffect3 = _presentDownloadLogsEffect3;
    _screenModel.effectPresentResetPairingDataEffect1 =
        _presentResetPairingDataEffect1;
    _screenModel.effectPresentUnpairEffect2 = _presentUnpairEffect2;
    _screenModel.effectShowLogServiceRecoveryDialog =
        _showLogServiceRecoveryDialog;

    unawaited(_initialize());
    _readinessTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_refreshReadiness());
    });
  }

  /// Delegates initialize to the ViewModel.
  Future<void> _initialize() => _screenModel.commandInitialize();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _buttonTestCountdownTimer?.cancel();
    _readinessTimer?.cancel();
    final testOutcome = _buttonTestOutcome;
    if (testOutcome != null && !testOutcome.isCompleted) {
      testOutcome.complete(const _ButtonTestOutcome.cancelled());
    }
    unawaited(_buttonTestSubscription?.cancel());
    if (_testingButtonFor != null) {
      unawaited(_cancelButtonTestSilently());
    }
    unawaited(_ble.stopPairedButtonSetupScan());

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates cancel button test silently to the ViewModel.
  Future<void> _cancelButtonTestSilently() =>
      _screenModel.commandCancelButtonTestSilently();

  /// Delegates load paired to the ViewModel.
  Future<void> _loadPaired() => _screenModel.commandLoadPaired();

  /// Delegates refresh readiness to the ViewModel.
  Future<void> _refreshReadiness() => _screenModel.commandRefreshReadiness();

  /// Delegates restart monitor to the ViewModel.
  Future<void> _restartMonitor() => _screenModel.commandRestartMonitor();

  /// Delegates set lost warning to the ViewModel.
  Future<void> _setLostWarning(bool enabled, {Duration? threshold}) =>
      _screenModel.commandSetLostWarning(enabled, threshold: threshold);

  /// Delegates open pairing guide to the ViewModel.
  Future<void> _openPairingGuide() => _screenModel.commandOpenPairingGuide();

  /// Delegates unpair to the ViewModel.
  Future<void> _unpair(PairedSosButton button) =>
      _screenModel.commandUnpair(button);

  /// Delegates reset pairing data to the ViewModel.
  Future<void> _resetPairingData() => _screenModel.commandResetPairingData();

  /// Delegates download logs to the ViewModel.
  Future<void> _downloadLogs(PairedSosButton button) =>
      _screenModel.commandDownloadLogs(button);

  /// Computes test button connection.
  Future<void> _testButtonConnection(PairedSosButton button) async {
    if (_pairingInProgress ||
        _downloadingLogsFor != null ||
        _testingButtonFor != null) {
      return;
    }
    final confirmed = await _presentTestButtonConnectionEffect1(button);
    if (confirmed != true || !mounted) return;

    const testDuration = Duration(seconds: 30);
    final outcome = Completer<_ButtonTestOutcome>();
    _buttonTestOutcome = outcome;
    final dialogReady = Completer<BuildContext>();
    final countdown = ValueNotifier<int>(testDuration.inSeconds);
    BuildContext? testDialogContext;
    Future<_ButtonTestOutcome?>? testDialogFuture;
    try {
      await _ble.setActiveSosAccount(widget.accountId);
      await _buttonTestSubscription?.cancel();
      _buttonTestSubscription = _ble.events.listen((event) {
        if (event is HikerBlePairedSosButtonTestEvent &&
            event.deviceId.toUpperCase() == button.deviceId.toUpperCase() &&
            !outcome.isCompleted) {
          outcome.complete(_ButtonTestOutcome.pressed(event));
        }
      });
      await _ble.armPairedSosButtonTest(
        button.deviceId,
        duration: testDuration,
      );
      if (!mounted) return;
      setState(() {
        _testingButtonFor = button.deviceId;
        _message = null;
      });

      final startedAt = DateTime.now();
      _buttonTestCountdownTimer?.cancel();
      _buttonTestCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
        _,
      ) {
        final elapsed = DateTime.now().difference(startedAt).inSeconds;
        final remaining = testDuration.inSeconds - elapsed;
        countdown.value = remaining.clamp(0, testDuration.inSeconds);
        if (remaining <= 0 && !outcome.isCompleted) {
          outcome.complete(const _ButtonTestOutcome.timeout());
        }
      });

      testDialogFuture = showDialog<_ButtonTestOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          testDialogContext = dialogContext;
          if (!dialogReady.isCompleted) {
            dialogReady.complete(dialogContext);
          }
          return PopScope(
            canPop: false,
            child: AlertDialog(
              icon: const Icon(Icons.sensors_rounded),
              title: const Text('Test mode active'),
              content: ValueListenableBuilder<int>(
                valueListenable: countdown,
                builder: (context, seconds, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$seconds',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Press ${button.displayName} once now.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: seconds / testDuration.inSeconds,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SOS dispatch is disabled for this paired button on '
                      'this phone until the test ends.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (!outcome.isCompleted) {
                      outcome.complete(const _ButtonTestOutcome.cancelled());
                    }
                  },
                  child: const Text('Cancel test'),
                ),
              ],
            ),
          );
        },
      );
      unawaited(testDialogFuture);

      final result = await outcome.future;
      final dialogContext = await dialogReady.future;
      if (dialogContext.mounted) {
        _presentTestButtonConnectionEffect2(dialogContext, result);
      }
      await testDialogFuture;
      if (!mounted) return;

      if (result.event != null) {
        await _loadPaired();
        if (!mounted) return;
        final event = result.event!;
        await _presentTestButtonConnectionEffect3(button, event);
      } else if (result.timedOut) {
        _presentTestButtonConnectionEffect4();
      }
    } on HikerBleException catch (error) {
      if (mounted) {
        _presentTestButtonConnectionEffect5(error);
      }
    } catch (_) {
      if (mounted) {
        _presentTestButtonConnectionEffect6();
      }
    } finally {
      _buttonTestCountdownTimer?.cancel();
      _buttonTestCountdownTimer = null;
      await _buttonTestSubscription?.cancel();
      _buttonTestSubscription = null;
      try {
        await _ble.cancelPairedSosButtonTest();
      } catch (_) {
        // Native test mode also expires after 30 seconds.
      }
      final dialogContext = testDialogContext;
      if (dialogContext != null && dialogContext.mounted) {
        _presentTestButtonConnectionEffect7(dialogContext);
      }
      final dialogFuture = testDialogFuture;
      if (dialogFuture != null) {
        await dialogFuture;
      }
      countdown.dispose();
      if (identical(_buttonTestOutcome, outcome)) {
        _buttonTestOutcome = null;
      }
      if (mounted) setState(() => _testingButtonFor = null);
    }
  }

  /// Shows log service recovery dialog.
  Future<void> _showLogServiceRecoveryDialog(PairedSosButton button) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.bluetooth_searching_rounded),
        title: const Text('Button log service unavailable'),
        content: Text(
          '${button.displayName} connected, but Android returned an incomplete '
          'cached Bluetooth service list. The app already tried refreshing it '
          'automatically.\n\n'
          'In Android Bluetooth settings, forget “HikerCircle Setup”. Then '
          'return here, enter button setup mode, pair it again, and retry the '
          'history download while the button remains powered nearby.\n\n'
          'The installed ESP32 firmware already includes the authenticated log '
          'service. Pairing and live SOS alerts are unaffected.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Delegates format uptime to the ViewModel.
  String _formatUptime(Duration uptime) =>
      _screenModel.commandFormatUptime(uptime);

  /// Delegates format log record to the ViewModel.
  String _formatLogRecord(HikerBleButtonLogRecord record) =>
      _screenModel.commandFormatLogRecord(record);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: PageHeaderAppBar(title: const Text('Paired SOS button')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PairingHeroCard(
            scheme: scheme,
            enabled:
                _accountReady && !_registryNeedsReset && !_pairingInProgress,
            onAdd: _openPairingGuide,
          ),
          const SizedBox(height: 12),
          _ReadinessCard(
            readiness: _readiness,
            loading: _readinessLoading,
            onRefresh: () => unawaited(_refreshReadiness()),
            onRestartMonitor: () => unawaited(_restartMonitor()),
            onOpenBluetooth: () => unawaited(_ble.openBluetoothSettings()),
            onOpenBatterySettings: () =>
                unawaited(_ble.openBatteryOptimizationSettings()),
            onLostWarningChanged: (enabled) =>
                unawaited(_setLostWarning(enabled)),
            onLostThresholdChanged: (threshold) =>
                unawaited(_setLostWarning(true, threshold: threshold)),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_message!)),
                  ],
                ),
              ),
            ),
          ],
          if (_registryNeedsReset) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pairing data needs recovery',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The encrypted button registry cannot be read on this device. Reset only the local pairing data, then pair the physical button again.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _pairingInProgress ? null : _resetPairingData,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reset pairing data'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionHeading(
            title: 'Your paired buttons',
            subtitle:
                'Only this phone can trigger Manual SOS from these buttons.',
            count: _paired.isEmpty ? null : _paired.length,
          ),
          const SizedBox(height: 8),
          if (_paired.isEmpty)
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.sos_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No buttons paired yet. Start a scan when your button is ready.',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._paired.map(
              (button) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    child: const Icon(Icons.sos_rounded),
                  ),
                  title: Text(
                    button.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'ID ${button.deviceId}\n'
                    'Last seen: ${button.lastSeenAt?.toLocal() ?? 'Not seen yet'}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_testingButtonFor == button.deviceId)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: HikerCircleMinorLoadingIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          tooltip: 'Test SOS button',
                          onPressed:
                              _pairingInProgress ||
                                  _downloadingLogsFor != null ||
                                  _testingButtonFor != null
                              ? null
                              : () => _testButtonConnection(button),
                        ),
                      if (_downloadingLogsFor == button.deviceId)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: HikerCircleMinorLoadingIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.history_rounded),
                          tooltip: 'Download event log',
                          onPressed:
                              _pairingInProgress ||
                                  _downloadingLogsFor != null ||
                                  _testingButtonFor != null
                              ? null
                              : () => _downloadLogs(button),
                        ),
                      IconButton(
                        icon: const Icon(Icons.link_off_rounded),
                        tooltip: 'Unpair',
                        onPressed:
                            _pairingInProgress ||
                                _downloadingLogsFor != null ||
                                _testingButtonFor != null
                            ? null
                            : () => _unpair(button),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Presents the open pairing guide effect1 UI.
  Future<bool?> _presentOpenPairingGuideEffect1() => showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        SosButtonPairingSheet(ble: _ble, onPaired: _loadPaired),
  );

  /// Presents the unpair effect1 UI.
  Future<bool?> _presentUnpairEffect1(PairedSosButton button) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unpair SOS button?'),
          content: Text('Remove ${button.displayName} from this phone?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unpair'),
            ),
          ],
        ),
      );

  /// Presents the unpair effect2 UI.
  void _presentUnpairEffect2(HikerBleException error) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.message)));

  /// Presents the reset pairing data effect1 UI.
  Future<bool?> _presentResetPairingDataEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset local pairing data?'),
      content: const Text(
        'This clears unreadable SOS button secrets from this phone. The '
        'physical button will no longer trigger SOS here until it is put '
        'back into setup or factory-reset mode and paired again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );

  /// Presents the download logs effect1 UI.
  Future<bool?> _presentDownloadLogsEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Download button event log'),
      content: const Text(
        'Keep the paired SOS button powered and nearby, then tap Start. '
        'The app connects to its read-only maintenance service and '
        'authenticates with the existing pairing secret.\n\n'
        'Do not press the physical button for log download. One short '
        'physical press always has priority and immediately starts SOS.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Start'),
        ),
      ],
    ),
  );

  /// Presents the download logs effect2 UI.
  Future<void> _presentDownloadLogsEffect2(
    PairedSosButton button,
    List<HikerBleButtonLogRecord> records,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${button.displayName} event log'),
      content: SizedBox(
        width: 620,
        child: records.isEmpty
            ? const Text('The button event log is empty.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${records.length} retained events · '
                    '${records.where((value) => value.type == 3).length} SOS · '
                    '${records.where((value) => value.type == 16 || value.type == 17).length} warnings',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final absoluteTime = record.epochTime?.toLocal();
                        final details = <String>[
                          if (absoluteTime != null)
                            absoluteTime.toString()
                          else
                            'Uptime ${_formatUptime(record.uptime)}',
                          if (record.eventId != 0) 'Event ID ${record.eventId}',
                          if (record.resetReason != 0)
                            'Reset reason ${record.resetReason}',
                          if (record.detail != 0) 'Detail ${record.detail}',
                        ];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            child: Text(record.sequence.toString()),
                          ),
                          title: Text(
                            record.typeLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(details.join(' · ')),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (records.isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              final text = records.map(_formatLogRecord).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Event log copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Copy log'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  /// Presents the download logs effect3 UI.
  void _presentDownloadLogsEffect3(HikerBleException error) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));

  /// Presents the test button connection effect1 UI.
  Future<bool?> _presentTestButtonConnectionEffect1(
    PairedSosButton button,
  ) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.play_circle_outline_rounded),
      title: const Text('Test physical SOS button'),
      content: Text(
        'After the test starts, you have 30 seconds to press '
        '${button.displayName} once. During this test window, an '
        'authenticated press from this button is consumed as a test on this '
        'phone and will not open SOS or notify your emergency contacts.\n\n'
        'The app first sends an authenticated test-arm request to the button. '
        'The next press uses the protocol’s test mode, so other HikerCircle '
        'phones ignore it and no nearby incident is forwarded.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Enter test mode'),
        ),
      ],
    ),
  );

  /// Presents the test button connection effect2 UI.
  void _presentTestButtonConnectionEffect2(
    BuildContext dialogContext,
    _ButtonTestOutcome result,
  ) => Navigator.of(dialogContext).pop(result);

  /// Presents the test button connection effect3 UI.
  Future<void> _presentTestButtonConnectionEffect3(
    PairedSosButton button,
    HikerBlePairedSosButtonTestEvent event,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.check_circle_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Button press detected'),
      content: Text(
        '${button.displayName} responded successfully. The press was '
        'handled only as a test and no SOS was triggered.'
        '${event.rssi == null ? '' : '\n\nSignal: ${event.rssi} dBm'}',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  /// Presents the test button connection effect4 UI.
  void _presentTestButtonConnectionEffect4() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No authenticated button press was detected within 30 seconds.',
          ),
        ),
      );

  /// Presents the test button connection effect5 UI.
  void _presentTestButtonConnectionEffect5(HikerBleException error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Button test failed. ${error.message}')),
      );

  /// Presents the test button connection effect6 UI.
  void _presentTestButtonConnectionEffect6() =>
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Button test failed. Refresh the page and try again.'),
        ),
      );

  /// Presents the test button connection effect7 UI.
  void _presentTestButtonConnectionEffect7(BuildContext dialogContext) =>
      Navigator.of(dialogContext).pop();
}
