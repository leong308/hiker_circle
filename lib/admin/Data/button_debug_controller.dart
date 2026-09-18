import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/Data/local_session_database.dart';
import '../../core/services/hiker_ble_service.dart';
import '../Model/button_debug_entry.dart';

class ButtonDebugController extends ChangeNotifier {
  ButtonDebugController({
    required this.owner,
    required this.database,
    this.ble = const HikerBleService(),
    Future<Directory> Function()? logDirectory,
  }) : _logDirectory = logDirectory ?? getApplicationDocumentsDirectory;

  final String owner;
  final LocalSessionDatabase database;
  final HikerBleService ble;
  final Future<Directory> Function() _logDirectory;
  final List<Map<String, Object?>> liveEntries = [];
  List<Map<String, Object?>> sessions = [];
  StreamSubscription<Map<Object?, Object?>>? _subscription;
  Future<void> _writes = Future.value();
  Future<void>? _starting, _stopping;
  String? _id;
  bool recording = false, busy = false, _accepting = false;
  bool _stopRequested = false, _disposed = false;
  bool _captureRequested = false;
  int entryCount = 0;
  String? error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    // An OS kill cannot run dispose. Preserve and conclude its committed rows.
    for (final session in await database.loadButtonDebugSessions(owner)) {
      if (session['status'] == 'recording') {
        await _conclude(
          session,
          'interrupted: app terminated before normal stop',
        );
      }
    }
    await refreshHistory();
  }

  Future<void> refreshHistory() async {
    sessions = await database.loadButtonDebugSessions(owner);
    _notify();
  }

  Future<void> start() {
    if (busy || recording || _disposed) return Future.value();
    _stopRequested = false;
    _stopping = null;
    error = null;
    busy = true;
    _notify();
    return _starting = _begin();
  }

  Future<void> _begin() async {
    try {
      final now = DateTime.now().toUtc();
      final id =
          '${now.microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';
      await database.createButtonDebugSession(id, owner, now);
      _id = id;
      entryCount = 0;
      liveEntries.clear();
      if (_stopRequested) return;
      _subscription = ble.buttonDebugEvents.listen(
        _record,
        onError: (Object e) {
          error = 'BLE capture failed: $e';
          unawaited(stop('capture_error'));
        },
      );
      _accepting = true;
      _captureRequested = true;
      await ble.setButtonDebugCapture(true);
      recording = !_stopRequested;
    } finally {
      busy = _stopRequested;
      _notify();
    }
  }

  void _record(Map<Object?, Object?> raw) {
    if (!_accepting || _id == null) return;
    final entry = ButtonDebugEntry.fromEvent(raw);
    final row = entry.toRow(_id!, ++entryCount);
    liveEntries.add(row);
    // UI memory is bounded; EVERY entry is still retained in SQLite.
    if (liveEntries.length > 300) liveEntries.removeAt(0);
    _writes = _writes
        .then((_) => database.appendButtonDebugEntry(owner, row))
        .catchError((Object e) {
          error = 'Local recording failed; session stopped: $e';
          unawaited(stop('storage_error'));
        });
    _notify();
  }

  void recordAction(String operation, String message, {String status = ''}) =>
      _record({
        'direction': 'LOCAL',
        'operation': operation,
        'message': message,
        'status': status,
      });

  Future<void> stop([String reason = 'manual_stop']) {
    // Close the gate synchronously, including while start is awaiting native ACK.
    _stopRequested = true;
    _accepting = false;
    recording = false;
    return _stopping ??= _finish(reason);
  }

  Future<void> _finish(String reason) async {
    final stoppedAt = DateTime.now().toUtc();
    busy = true;
    _notify();
    try {
      try {
        await _starting;
      } catch (e) {
        error = 'Unable to start capture: $e';
      }
      if (_captureRequested) {
        try {
          await ble.setButtonDebugCapture(false);
        } catch (e) {
          error = 'Unable to disable native capture: $e';
        }
        _captureRequested = false;
      }
      await _subscription?.cancel();
      _subscription = null;
      await _writes;
      final id = _id;
      if (id != null) {
        final rows = await database.loadButtonDebugSessions(owner);
        await _conclude(
          rows.firstWhere((s) => s['id'] == id),
          reason,
          stoppedAt,
        );
        _id = null;
      }
      await refreshHistory();
    } catch (e) {
      error =
          'Could not finalize log: $e. Committed entries remain in SQLite for recovery.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _conclude(
    Map<String, Object?> session,
    String reason, [
    DateTime? stoppedAt,
  ]) async {
    final id = session['id'] as String;
    final endedAt = stoppedAt ?? DateTime.now().toUtc();
    final rows = await database.loadButtonDebugEntries(owner, id);
    final log =
        'HikerCircle Button Debugging\nSession: $id\n'
        'Started UTC: ${session['started_at']}\nEnded UTC: ${endedAt.toIso8601String()}\n'
        'Conclusion: $reason\nRecorded entries: ${rows.length}\n'
        '${error == null ? '' : 'Recording warning: $error\n'}'
        'Scope: app-visible BLE payloads/control callbacks; not radio frames. '
        'TX attempts are not delivery proof; check write_complete status. '
        'Pairing key bytes are redacted. Logs may contain identifiers and locations.\n\n'
        '${rows.map(ButtonDebugEntry.formatRow).join('\n')}';
    // Commit a recoverable log before filesystem export (no network dependency).
    await database.concludeButtonDebugSession(
      owner: owner,
      id: id,
      endedAt: endedAt,
      reason: reason,
      logText: log,
    );
    try {
      final root = await _logDirectory();
      final directory = await Directory(
        '${root.path}/button_debug_logs',
      ).create(recursive: true);
      final file = await File(
        '${directory.path}/button_debug_$id.log',
      ).writeAsString(log, flush: true);
      await database.concludeButtonDebugSession(
        owner: owner,
        id: id,
        endedAt: endedAt,
        reason: reason,
        logText: log,
        filePath: file.path,
      );
    } catch (e) {
      error =
          'Log saved in SQLite, but file creation failed: $e. Use Save log to export it again.';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop('page_disposed'));
    super.dispose();
  }
}
