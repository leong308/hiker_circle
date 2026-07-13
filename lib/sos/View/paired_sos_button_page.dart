import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/hiker_ble_service.dart';

class _ButtonNameDialog extends StatefulWidget {
  const _ButtonNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_ButtonNameDialog> createState() => _ButtonNameDialogState();
}

class _PairingHeroCard extends StatelessWidget {
  const _PairingHeroCard({required this.scheme});

  final ColorScheme scheme;

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
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sos_rounded, color: Colors.white, size: 24),
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
                  'Pair it once, then keep it ready for a fast Manual SOS.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
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

class _PairingStepsCard extends StatelessWidget {
  const _PairingStepsCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How pairing works',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const _StepRow(
              number: '1',
              text: 'Hold the external button for 8 seconds.',
            ),
            const _StepRow(
              number: '2',
              text: 'Release, then press it twice within 5 seconds.',
            ),
            const _StepRow(
              number: '3',
              text:
                  'After the name prompt, press the external button once to confirm.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SetupScanCard extends StatelessWidget {
  const _SetupScanCard({
    required this.scheme,
    required this.scanning,
    required this.pairingInProgress,
    required this.message,
    required this.onToggleScan,
  });

  final ColorScheme scheme;
  final bool scanning;
  final bool pairingInProgress;
  final String? message;
  final VoidCallback onToggleScan;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_searching_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover a setup button',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        scanning
                            ? 'Listening for buttons in setup mode nearby…'
                            : 'Put the button in setup mode, then scan for it here.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (scanning) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(borderRadius: BorderRadius.circular(8)),
            ],
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.primary),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: pairingInProgress ? null : onToggleScan,
              icon: Icon(
                scanning ? Icons.stop_rounded : Icons.bluetooth_rounded,
              ),
              label: Text(scanning ? 'Stop scan' : 'Scan for button'),
            ),
          ],
        ),
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

class _ButtonNameDialogState extends State<_ButtonNameDialog> {
  late String _name;

  @override
  void initState() {
    super.initState();
    _name = widget.initialName;
  }

  void _submit() {
    Navigator.of(context).pop(_name.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this SOS button'),
      content: TextFormField(
        initialValue: widget.initialName,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onChanged: (value) => _name = value,
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: 'Button name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

class PairedSosButtonPage extends StatefulWidget {
  const PairedSosButtonPage({super.key});

  @override
  State<PairedSosButtonPage> createState() => _PairedSosButtonPageState();
}

class _PairedSosButtonPageState extends State<PairedSosButtonPage> {
  final HikerBleService _ble = const HikerBleService();
  final Map<String, HikerBlePairedButtonSetupEvent> _devices = {};
  StreamSubscription<HikerBleEvent>? _events;
  List<PairedSosButton> _paired = const [];
  bool _scanning = false;
  bool _pairingInProgress = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _events = _ble.events.listen(_handleEvent, onError: (_) {});
    unawaited(_loadPaired());
  }

  @override
  void dispose() {
    unawaited(_ble.stopPairedButtonSetupScan());
    unawaited(_events?.cancel());
    super.dispose();
  }

  void _handleEvent(HikerBleEvent event) {
    if (event is HikerBlePairedButtonSetupEvent && event.address.isNotEmpty) {
      if (mounted) {
        setState(() => _devices[event.address] = event);
      }
      return;
    }
    if (event is HikerBleStatusEvent &&
        event.status.startsWith('paired_button_')) {
      final message = switch (event.status) {
        'paired_button_awaiting_confirmation' =>
          'Press and release the external SOS button once now to confirm ownership.',
        'paired_button_paired' => 'Button paired successfully.',
        'paired_button_pairing_written' =>
          'Pairing data written. Waiting for the button confirmation press.',
        _ => event.message ?? event.status,
      };
      if (mounted) setState(() => _message = message);
    }
  }

  Future<void> _loadPaired() async {
    final paired = await _ble.listPairedSosButtons();
    if (mounted) setState(() => _paired = paired);
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _ble.stopPairedButtonSetupScan();
      if (mounted) setState(() => _scanning = false);
      return;
    }
    setState(() {
      _devices.clear();
      _message = 'Hold the button for 8 seconds, then make two short presses.';
      _scanning = true;
    });
    try {
      await _ble.startPairedButtonSetupScan();
    } on HikerBleException catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _message = error.message;
        });
      }
    }
  }

  Future<void> _pair(HikerBlePairedButtonSetupEvent device) async {
    if (_pairingInProgress) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _ButtonNameDialog(
        initialName: HikerBleService.defaultPairedButtonName,
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    setState(() => _pairingInProgress = true);
    try {
      await _ble.stopPairedButtonSetupScan();
    } on HikerBleException catch (error) {
      if (mounted) {
        setState(() {
          _pairingInProgress = false;
          _message = error.message;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _message = 'Write pairing data, then press the button once to confirm.';
    });
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Confirm button ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pairing data is being written to the button. When prompted, press and release the external SOS button once to confirm ownership. Do not use BOOT or RST.',
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
    // Let the dialog route finish mounting before the GATT callbacks begin.
    await Future<void>.delayed(Duration.zero);
    try {
      await _ble.pairSosButton(address: device.address, displayName: name);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await progressDialog;
      await _loadPaired();
      if (mounted) {
        setState(() => _message = 'Button paired successfully.');
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('SOS button paired'),
            content: Text(
              '$name is now paired to this phone. A valid button press will start this phone’s Manual SOS workflow.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } on HikerBleException catch (error) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await progressDialog;
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _pairingInProgress = false);
    }
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
    await _ble.unpairSosButton(button.deviceId);
    await _loadPaired();
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
          _PairingHeroCard(scheme: scheme),
          const SizedBox(height: 16),
          _PairingStepsCard(scheme: scheme),
          const SizedBox(height: 16),
          _SetupScanCard(
            scheme: scheme,
            scanning: _scanning,
            pairingInProgress: _pairingInProgress,
            message: _message,
            onToggleScan: _toggleScan,
          ),
          if (_devices.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionHeading(
              title: 'Detected nearby',
              subtitle: 'Select the button you want to pair with this phone.',
              count: _devices.length,
            ),
            const SizedBox(height: 8),
            ..._devices.values.map(
              (device) => Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                color: scheme.primaryContainer.withValues(alpha: 0.42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(Icons.bluetooth_rounded),
                  ),
                  title: Text(
                    device.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text('${device.address} · ${device.rssi} dBm'),
                  trailing: FilledButton.tonal(
                    onPressed: _pairingInProgress ? null : () => _pair(device),
                    child: const Text('Pair'),
                  ),
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
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off_rounded),
                    tooltip: 'Unpair',
                    onPressed: _pairingInProgress
                        ? null
                        : () => _unpair(button),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
