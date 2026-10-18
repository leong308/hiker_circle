// PreparationSharingPage and PreparationBatteryPage edit per-hike sharing and battery choices.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../Model/hike_preparation_sharing.dart';

class PreparationSharingPage extends StatefulWidget {
  const PreparationSharingPage({super.key, required this.initial, this.onSave});
  final HikePreparationSharing initial;
  final Future<void> Function(HikePreparationSharing)? onSave;
  @override
  State<PreparationSharingPage> createState() => _SharingState();
}

class _SharingState extends State<PreparationSharingPage> {
  late bool _enabled = widget.initial.enabled;
  late Duration _interval = widget.initial.interval;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final choice = HikePreparationSharing(
      enabled: _enabled,
      interval: _interval,
    );
    try {
      await widget.onSave?.call(choice);
      if (mounted) Navigator.pop(context, choice);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not save your sharing choices. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: PageHeaderAppBar(title: const Text('Sharing for this hike')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share live location during this hike'),
            subtitle: const Text(
              'Your choice takes effect when the hike starts.',
            ),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 20),
          Text(
            'Cloud upload interval',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your phone records GPS locally every 5 seconds. Choose how often the saved route is uploaded; unsuccessful uploads are retried.',
          ),
          const SizedBox(height: 12),
          for (final interval in HikePreparationSharing.intervals)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                HikePreparationSharing(
                  enabled: _enabled,
                  interval: interval,
                ).intervalLabel,
              ),
              leading: Icon(
                _interval == interval
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              selected: _interval == interval,
              onTap: _saving
                  ? null
                  : () => setState(() => _interval = interval),
            ),
          const SizedBox(height: 8),
          const Text(
            'More frequent uploads can use more battery and mobile data. Turning off live sharing stops the live viewer link; your hike route still syncs at this interval.',
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save and return'),
          ),
        ],
      ),
    ),
  );
}

class PreparationBatteryPage extends StatefulWidget {
  const PreparationBatteryPage({
    super.key,
    required this.loadBattery,
    this.initialLevel,
  });
  final Future<int?> Function() loadBattery;
  final int? initialLevel;
  @override
  State<PreparationBatteryPage> createState() => _BatteryState();
}

class _BatteryState extends State<PreparationBatteryPage>
    with WidgetsBindingObserver {
  late int? _level = widget.initialLevel;
  bool _loading = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    int? level;
    try {
      level = await widget.loadBattery().timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Show unavailable. */
    }
    if (mounted) {
      setState(() {
        _level = level?.clamp(0, 100);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeaderAppBar(title: const Text('Phone battery')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.battery_charging_full_rounded, size: 56),
        const SizedBox(height: 16),
        Text(
          _level == null ? 'Battery level unavailable' : '$_level%',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 24),
        const Text(
          'Charge your phone before leaving and bring a power bank for longer hikes.',
        ),
        const SizedBox(height: 16),
        const Text(
          'You can adjust brightness in your phone controls and review power options in Settings → Battery. Return to this page to see the latest charge.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Battery readings refresh every 30 seconds and when you return to the app.',
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: Text(_loading ? 'Reading battery…' : 'Refresh battery'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Return to preparation'),
        ),
      ],
    ),
  );
}
