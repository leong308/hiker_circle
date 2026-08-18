import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/hiker_ble_service.dart';
import 'sos_button_pairing_sheet.dart';

class _PairingHeroCard extends StatelessWidget {
  const _PairingHeroCard({
    required this.scheme,
    required this.enabled,
    required this.onAdd,
  });

  final ColorScheme scheme;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.22)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect your SOS button',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'A guided setup will walk you through detection, secure pairing, and physical confirmation.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Detect and add a button'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: scheme.primary,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    this.count,
  });

  final String title;
  final String subtitle;
  final int? count;

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

class PairedSosButtonPage extends StatefulWidget {
  const PairedSosButtonPage({super.key, required this.accountId});

  final String accountId;

  @override
  State<PairedSosButtonPage> createState() => _PairedSosButtonPageState();
}

class _PairedSosButtonPageState extends State<PairedSosButtonPage> {
  final HikerBleService _ble = const HikerBleService();
  List<PairedSosButton> _paired = const [];
  bool _accountReady = false;
  bool _pairingInProgress = false;
  bool _registryNeedsReset = false;
  String? _downloadingLogsFor;
  String? _testingButtonFor;
  Timer? _buttonTestCountdownTimer;
  StreamSubscription<HikerBleEvent>? _buttonTestSubscription;
  Completer<_ButtonTestOutcome>? _buttonTestOutcome;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _ble.setActiveSosAccount(widget.accountId);
      if (!mounted) return;
      _accountReady = true;
      await _loadPaired();
    } on HikerBleException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    }
  }

  @override
  void dispose() {
    _buttonTestCountdownTimer?.cancel();
    final testOutcome = _buttonTestOutcome;
    if (testOutcome != null && !testOutcome.isCompleted) {
      testOutcome.complete(const _ButtonTestOutcome.cancelled());
    }
    unawaited(_buttonTestSubscription?.cancel());
    if (_testingButtonFor != null) {
      unawaited(_cancelButtonTestSilently());
    }
    unawaited(_ble.stopPairedButtonSetupScan());
    super.dispose();
  }

  Future<void> _cancelButtonTestSilently() async {
    try {
      await _ble.cancelPairedSosButtonTest();
    } catch (_) {
      // Native test mode is also bounded by its own 30-second expiry.
    }
  }

  Future<void> _loadPaired() async {
    try {
      final paired = await _ble.listPairedSosButtons();
      if (mounted) {
        setState(() {
          _paired = paired;
          _registryNeedsReset = false;
        });
      }
    } on HikerBleException {
      if (mounted) setState(() => _registryNeedsReset = true);
      rethrow;
    }
  }

  Future<void> _openPairingGuide() async {
    if (!_accountReady || _registryNeedsReset || _pairingInProgress) return;
    setState(() {
      _pairingInProgress = true;
      _message = null;
    });
    final paired = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          SosButtonPairingSheet(ble: _ble, onPaired: _loadPaired),
    );
    if (!mounted) return;
    setState(() {
      _pairingInProgress = false;
      if (paired == true) {
        _message = 'SOS button paired and ready.';
      }
    });
  }

  Future<void> _unpair(PairedSosButton button) async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true) return;
    try {
      final removed = await _ble.unpairSosButton(button.deviceId);
      if (!removed) {
        throw const HikerBleException(
          'The SOS button was not removed. Refresh and try again.',
        );
      }
      await _loadPaired();
    } on HikerBleException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _resetPairingData() async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true || !mounted) return;

    setState(() => _pairingInProgress = true);
    try {
      await _ble.resetPairedSosButtonRegistry();
      await _loadPaired();
      if (!mounted) return;
      setState(() {
        _message =
            'Local pairing data was reset. Put the button in setup mode and pair it again.';
      });
    } on HikerBleException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _pairingInProgress = false);
    }
  }

  Future<void> _downloadLogs(PairedSosButton button) async {
    final ready = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download button event log'),
        content: const Text(
          'Pairing setup and RST are not required.\n\n'
          'After tapping Start, immediately press the external SOS button '
          'five times within 3 seconds. The app will wait for the read-only '
          'log service, then authenticate with the existing pairing secret.\n\n'
          'When all five presses are detected, the firmware suppresses SOS '
          'and opens log download for 30 seconds. Complete all five presses: '
          'an incomplete sequence is handled as a normal SOS press.',
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
    if (ready != true || !mounted) return;

    await _ble.stopPairedButtonSetupScan();
    if (!mounted) return;
    setState(() {
      _downloadingLogsFor = button.deviceId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Now press the external button 5 times within 3 seconds.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
    try {
      final records = await _ble.readPairedSosButtonLog(button.deviceId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${button.displayName} event log'),
          content: SizedBox(
            width: 620,
            child: records.isEmpty
                ? const Text('The button event log is empty.')
                : ListView.separated(
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
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on HikerBleException catch (error) {
      if (mounted) {
        if (error.code == 'paired_button_log_service_missing' ||
            error.code == 'paired_button_log_bluetooth_cache_stale') {
          await _showLogServiceRecoveryDialog(button);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    } finally {
      if (mounted) setState(() => _downloadingLogsFor = null);
    }
  }

  Future<void> _testButtonConnection(PairedSosButton button) async {
    if (_pairingInProgress ||
        _downloadingLogsFor != null ||
        _testingButtonFor != null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.play_circle_outline_rounded),
        title: const Text('Test physical SOS button'),
        content: Text(
          'After the test starts, you have 30 seconds to press '
          '${button.displayName} once. During this test window, an '
          'authenticated press from this button is consumed as a test on this '
          'phone and will not open SOS or notify your emergency contacts.\n\n'
          'Test mode is local to this phone. Current button firmware still '
          'broadcasts the normal radio packet, so nearby HikerCircle phones '
          'may detect it.',
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
        Navigator.of(dialogContext).pop(result);
      }
      await testDialogFuture;
      if (!mounted) return;

      if (result.event != null) {
        await _loadPaired();
        if (!mounted) return;
        final event = result.event!;
        await showDialog<void>(
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
      } else if (result.timedOut) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No authenticated button press was detected within 30 seconds.',
            ),
          ),
        );
      }
    } on HikerBleException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Button test failed. ${error.message}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Button test failed. Refresh the page and try again.',
            ),
          ),
        );
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
        Navigator.of(dialogContext).pop();
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
          'history download by pressing the external button five times within '
          '3 seconds.\n\n'
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

  String _formatUptime(Duration uptime) {
    final hours = uptime.inHours;
    final minutes = uptime.inMinutes.remainder(60);
    final seconds = uptime.inSeconds.remainder(60);
    return '${hours}h ${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Paired SOS button'),
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _PairingHeroCard(
            scheme: scheme,
            enabled:
                _accountReady && !_registryNeedsReset && !_pairingInProgress,
            onAdd: _openPairingGuide,
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
}

class _ButtonTestOutcome {
  const _ButtonTestOutcome.pressed(this.event) : timedOut = false;
  const _ButtonTestOutcome.timeout() : event = null, timedOut = true;
  const _ButtonTestOutcome.cancelled() : event = null, timedOut = false;

  final HikerBlePairedSosButtonTestEvent? event;
  final bool timedOut;
}
