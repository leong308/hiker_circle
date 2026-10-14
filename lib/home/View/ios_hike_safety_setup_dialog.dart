import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../Data/active_hike_live_status_service.dart';
import 'hike_start_navigation.dart';

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

class _IosHikeSafetySetupDialog extends StatefulWidget {
  const _IosHikeSafetySetupDialog({
    super.key,
    required this.service,
    required this.initialStatus,
    required this.fallDetectionEnabled,
  });

  final ActiveHikeLiveStatusService service;
  final NativeHikeSafetyStatus initialStatus;
  final bool fallDetectionEnabled;

  @override
  State<_IosHikeSafetySetupDialog> createState() =>
      _IosHikeSafetySetupDialogState();
}

class _IosHikeSafetySetupDialogState extends State<_IosHikeSafetySetupDialog>
    with WidgetsBindingObserver {
  late NativeHikeSafetyStatus _status = widget.initialStatus;
  bool _checking = false;
  bool _checkAgain = false;
  bool _openingSettings = false;
  bool _finished = false;
  String? _error;

  List<String> get _missing => [
    if (!_status.fineLocationGranted || !_status.backgroundLocationGranted)
      'Location: Always',
    if (widget.fallDetectionEnabled && !_status.notificationsAuthorized)
      'Notifications: Allow',
    if (widget.fallDetectionEnabled && !_status.motionGranted)
      'Motion & Fitness: On',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_finished) {
      unawaited(_refreshStatus());
    }
  }

  void _finish(bool ready) {
    if (_finished || !mounted) return;
    _finished = true;
    HikeStartNavigation.closeOwnedRoute(ModalRoute.of<bool>(context), ready);
  }

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

  Future<void> _openSettings() async {
    if (_openingSettings || _checking || _finished) return;
    setState(() {
      _openingSettings = true;
      _error = null;
    });
    try {
      await widget.service.openIosSafetySettings().timeout(
        const Duration(seconds: 10),
      );
      // Opening Settings is not permission approval. Leave the dialog and its
      // caller's prepared draft in place until the resume check confirms it.
    } catch (_) {
      if (mounted && !_finished) {
        setState(() => _error = 'Settings could not open. Please try again.');
      }
    } finally {
      if (mounted && !_finished) {
        setState(() => _openingSettings = false);
      }
    }
  }

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
