part of '../button_debugging_page_feature.dart';

/// Owns the state and non-visual actions of ButtonDebuggingPage.
class _ButtonDebuggingPageStateViewModel extends ChangeNotifier {
  /// Creates button debugging page state view model.
  _ButtonDebuggingPageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final ButtonDebugController stateDebug;

  bool stateLoading = true, stateCommandBusy = false, stateOwnsTest = false;

  List<PairedSosButton> stateButtons = [];

  String? stateDeviceId, stateMessage;

  bool stateShowHistory = false;

  String stateDirection = 'All';

  /// Computes initialize.
  Future<void> commandInitialize() async {
    try {
      await stateDebug.initialize();
      stateButtons = await stateDebug.ble.listPairedSosButtons();
      stateDeviceId = stateButtons.firstOrNull?.deviceId;
    } catch (e) {
      stateMessage = '$e';
    }
    if (mounted) _publish(() => stateLoading = false);
  }

  /// Stops.
  Future<void> commandStop(String reason) async {
    final stopped = stateDebug.stop(reason);
    if (stateOwnsTest) {
      stateOwnsTest = false;
      try {
        await stateDebug.ble.cancelPairedSosButtonTest();
      } catch (_) {
        /* Capture still concludes. */
      }
    }
    await stopped;
  }

  /// Starts.
  Future<void> commandStart() async {
    _publish(() {
      stateShowHistory = false;
      stateDirection = 'All';
      stateMessage = null;
    });
    try {
      await stateDebug.start();
    } catch (e) {
      await commandStop('start_failed');
      if (mounted) _publish(() => stateMessage = '$e');
    }
  }

  /// Computes command.
  Future<void> commandCommand(
    String name,
    Future<String> Function() run,
  ) async {
    _publish(() {
      stateCommandBusy = true;
      stateMessage = null;
    });
    stateDebug.recordAction(
      name,
      'Admin requested $name.',
      status: 'requested',
    );
    try {
      final message = await run();
      stateDebug.recordAction(name, message, status: 'completed');
      if (mounted && stateDebug.recording) {
        _publish(() => stateMessage = message);
      }
    } catch (e) {
      stateDebug.recordAction(name, '$e', status: 'failed');
      if (mounted) _publish(() => stateMessage = '$e');
    } finally {
      if (mounted) _publish(() => stateCommandBusy = false);
    }
  }

  /// Computes arm test.
  Future<void> commandArmTest() => commandCommand('safe_test', () async {
    stateOwnsTest = true;
    await stateDebug.ble.armPairedSosButtonTest(stateDeviceId!);
    return 'Safe test armed. Press the button within 30 seconds. Do not press after the test window expires.';
  });

  /// Computes device log.
  Future<void>
  commandReadDeviceLog() => commandCommand('read_device_log', () async {
    final records = await stateDebug.ble.readPairedSosButtonLog(stateDeviceId!);
    for (final record in records) {
      stateDebug.recordAction(
        'decoded_device_log_record',
        'Reassembled device log: sequence=${record.sequence}, '
            'uptime=${record.uptimeMillis} ms, epoch=${record.epochSeconds}, '
            'event ID=${record.eventId}, type=${record.type} (${record.typeLabel}), '
            'reset reason=${record.resetReason}, detail=${record.detail}. '
            'Decoded summary, not an additional BLE packet.',
      );
    }
    return 'Received ${records.length} device log records.';
  });

  /// Computes session date.
  String commandSessionDate(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '$value';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function(
    List<Map<String, Object?>> entries,
    String text,
    Map<String, Object?> session,
  )
  effectPresentOpenLogEffect1;

  /// Opens log.
  Future<void> commandOpenLog(Map<String, Object?> session) async {
    if (!mounted) return;
    final String text;
    final List<Map<String, Object?>> entries;
    try {
      entries = await stateDebug.database.loadButtonDebugEntries(
        stateDebug.owner,
        session['id'] as String,
      );
      final savedText =
          await stateDebug.database.loadButtonDebugLog(
            stateDebug.owner,
            session['id'] as String,
          ) ??
          'No finalized log available.';
      // Re-render old captures from their original stored bytes as well.
      text = entries.isEmpty
          ? savedText
          : '${savedText.split(RegExp(r'\n#\d+ ')).first.trimRight()}\n\n'
                '${entries.map(ButtonDebugEntry.formatRow).join('\n')}';
    } catch (e) {
      if (mounted) {
        _publish(() => stateMessage = 'Unable to load saved log: $e');
      }
      return;
    }
    if (!mounted) return;
    await effectPresentOpenLogEffect1(entries, text, session);
  }
}
