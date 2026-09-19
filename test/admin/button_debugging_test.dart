import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/Data/button_debug_controller.dart';
import 'package:hiker_circle/admin/Model/button_debug_entry.dart';
import 'package:hiker_circle/admin/View/button_debugging_page.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/services/hiker_ble_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Ble extends HikerBleService {
  final source = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final captureCalls = <bool>[];
  Completer<void>? startGate;
  @override
  Stream<Map<Object?, Object?>> get buttonDebugEvents => source.stream;
  @override
  Future<void> setButtonDebugCapture(bool enabled) async {
    captureCalls.add(enabled);
    if (enabled) await startGate?.future;
  }

  @override
  Future<List<PairedSosButton>> listPairedSosButtons() async => [];
  void receive([int seconds = 20]) => source.add({
    'direction': 'RX',
    'operation': 'advertisement',
    'deviceId': 'test-device',
    'characteristic': 'manufacturer:0x02E5',
    'bytes': Uint8List.fromList([0x48, 0x43, 1, 6, 1, seconds]),
  });
}

class _Controller extends ButtonDebugController {
  _Controller({
    required super.owner,
    required super.database,
    required super.ble,
    required super.logDirectory,
  });
  final initialized = Completer<void>();
  Future<void>? lastStart, lastStop;
  @override
  Future<void> initialize() async {
    await super.initialize();
    if (!initialized.isCompleted) initialized.complete();
  }

  @override
  Future<void> start() => lastStart = super.start();
  @override
  Future<void> stop([String reason = 'manual_stop']) =>
      lastStop = super.stop(reason);
}

// Widget tests keep SQLite I/O out of Flutter's fake-async clock. Real SQLite
// and filesystem behavior is exercised independently by the tests above.
class _MemoryDb extends LocalSessionDatabase {
  final sessionRows = <Map<String, Object?>>[];
  final entries = <Map<String, Object?>>[];
  @override
  Future<void> createButtonDebugSession(
    String id,
    String owner,
    DateTime start,
  ) async {
    sessionRows.add({
      'id': id,
      'owner_phone_number': owner,
      'started_at': start.toIso8601String(),
      'status': 'recording',
    });
  }

  @override
  Future<void> appendButtonDebugEntry(
    String owner,
    Map<String, Object?> entry,
  ) async {
    entries.add(entry);
  }

  @override
  Future<List<Map<String, Object?>>> loadButtonDebugSessions(
    String owner,
  ) async => sessionRows;
  @override
  Future<List<Map<String, Object?>>> loadButtonDebugEntries(
    String owner,
    String id,
  ) async => entries.where((e) => e['session_id'] == id).toList();
  @override
  Future<String?> loadButtonDebugLog(String owner, String id) async =>
      sessionRows.firstWhere((s) => s['id'] == id)['log_text'] as String?;

  @override
  Future<void> concludeButtonDebugSession({
    required String owner,
    required String id,
    required DateTime endedAt,
    required String reason,
    required String logText,
    String? filePath,
  }) async {
    sessionRows.firstWhere((s) => s['id'] == id).addAll({
      'status': 'concluded',
      'ended_at': endedAt.toIso8601String(),
      'end_reason': reason,
      'log_text': logText,
      'file_path': filePath,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late LocalSessionDatabase db;
  late _Ble ble;
  late _Controller controller;
  group('local recording', () {
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('button_debug_test_');
      db = LocalSessionDatabase(databasePath: '${temp.path}/session.db');
      ble = _Ble();
      controller = _Controller(
        owner: 'admin-A',
        database: db,
        ble: ble,
        logDirectory: () async => temp,
      );
    });
    tearDown(() async {
      await controller.stop();
      controller.dispose();
      await ble.source.close();
      await db.close();
      await temp.delete(recursive: true);
    });

    test(
      'manual start, ordered raw bytes, stop excludes late traffic, file survives reopen',
      () async {
        await controller.initialize();
        ble.receive();
        expect(controller.entryCount, 0);
        expect(ble.captureCalls, isEmpty);
        await controller.start();
        ble.receive(20);
        ble.receive(19);
        final stop = controller.stop('page_left');
        ble.receive(18);
        await stop;
        expect(ble.captureCalls, [true, false]);
        final session = controller.sessions.single;
        expect(session['end_reason'], 'page_left');
        final entries = await db.loadButtonDebugEntries(
          'admin-A',
          session['id'] as String,
        );
        expect(entries.map((r) => r['sequence']), [1, 2]);
        expect(
          entries.first['payload'],
          Uint8List.fromList([72, 67, 1, 6, 1, 20]),
        );
        expect(
          entries.first['interpretation'],
          contains('remaining=20 seconds'),
        );
        expect(
          await File(session['file_path'] as String).readAsString(),
          await db.loadButtonDebugLog('admin-A', session['id'] as String),
        );
        expect(
          await db.loadButtonDebugLog('admin-A', session['id'] as String),
          contains('48 43 01 06 01 14'),
        );
        expect(
          await db.loadButtonDebugLog('admin-B', session['id'] as String),
          isNull,
        );
        expect(await db.loadButtonDebugSessions('admin-B'), isEmpty);
        expect(
          await db.loadButtonDebugEntries('admin-B', session['id'] as String),
          isEmpty,
        );
        await expectLater(
          db.appendButtonDebugEntry('admin-B', entries.first),
          throwsStateError,
        );
        await expectLater(
          db.appendButtonDebugEntry('admin-A', entries.first),
          throwsStateError,
        );
        await db.close();
        db = LocalSessionDatabase(databasePath: '${temp.path}/session.db');
        expect(
          (await db.loadButtonDebugSessions('admin-A')).single['status'],
          'concluded',
        );
      },
    );

    test(
      'stop while native start is pending disables capture and saves once',
      () async {
        ble.startGate = Completer<void>();
        final starting = controller.start();
        // Wait until native enable is actually pending (not a guessed duration).
        while (ble.captureCalls.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        final stopping = controller.stop('page_left');
        expect(controller.recording, false);
        ble.receive();
        ble.startGate!.complete();
        await starting;
        await stopping;
        await controller.stop('duplicate_stop');
        expect(ble.captureCalls, [true, false]);
        expect(controller.sessions.single['end_reason'], 'page_left');
        expect(controller.entryCount, 0);
      },
    );

    test('all entries persisted even when live display exceeds 300', () async {
      await controller.start();
      for (var i = 0; i < 325; i++) {
        ble.receive(i % 255);
      }
      await controller.stop();
      expect(controller.liveEntries.length, 300);
      expect(
        (await db.loadButtonDebugEntries(
          'admin-A',
          controller.sessions.single['id'] as String,
        )).length,
        325,
      );
    });

    test(
      'interrupted session recovers from SQLite without BLE or internet',
      () async {
        await db.createButtonDebugSession(
          'interrupted',
          'admin-A',
          DateTime.utc(2026),
        );
        await db.appendButtonDebugEntry(
          'admin-A',
          ButtonDebugEntry.fromEvent({
            'bytes': [72, 67, 1, 6, 1, 9],
            'direction': 'RX',
          }).toRow('interrupted', 1),
        );
        await controller.initialize();
        expect(controller.sessions.single['status'], 'concluded');
        expect(
          controller.sessions.single['end_reason'],
          startsWith('interrupted'),
        );
        expect(
          await db.loadButtonDebugLog('admin-A', 'interrupted'),
          contains('remaining=9 seconds'),
        );
        expect(ble.captureCalls, isEmpty);
      },
    );

    test(
      'v26 upgrade preserves existing data and creates debugging tables',
      () async {
        sqfliteFfiInit();
        final old = await databaseFactoryFfi.openDatabase(
          '${temp.path}/legacy.db',
          options: OpenDatabaseOptions(
            version: 26,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE sentinel (value TEXT)');
              await db.insert('sentinel', {'value': 'keep me'});
            },
          ),
        );
        await old.close();
        final upgraded = LocalSessionDatabase(
          databasePath: '${temp.path}/legacy.db',
        );
        await upgraded.createButtonDebugSession(
          'upgraded',
          'admin-A',
          DateTime.utc(2026),
        );
        expect(
          (await upgraded.loadButtonDebugSessions('admin-A')).single['id'],
          'upgraded',
        );
        await upgraded.close();
        final verified = await databaseFactoryFfi.openDatabase(
          '${temp.path}/legacy.db',
        );
        expect((await verified.query('sentinel')).single['value'], 'keep me');
        expect(await verified.getVersion(), 28);
        await verified.close();
      },
    );

    test(
      'decoder retains malformed/unknown payloads and decodes big endian values',
      () {
        for (var len = 0; len < 45; len++) {
          for (var type = 0; type < 22; type++) {
            final bytes = Uint8List(len);
            if (len >= 4) bytes.setAll(0, [72, 67, 1, type]);
            expect(() => decodeButtonPayload(bytes, ''), returnsNormally);
          }
        }
        final test = Uint8List.fromList([
          72,
          67,
          1,
          19,
          1,
          2,
          3,
          4,
          5,
          6,
          0,
          0,
          1,
          2,
          ...List.filled(8, 0),
        ]);
        expect(decodeButtonPayload(test, ''), contains('next event ID=258'));
        expect(
          decodeButtonPayload(Uint8List.fromList([72, 67, 9, 19]), ''),
          contains('Unsupported'),
        );
      },
    );
  });

  testWidgets(
    'admin page starts manually, back concludes, and stays usable at small size',
    (tester) async {
      ble = _Ble();
      controller = _Controller(
        owner: 'admin-A',
        database: _MemoryDb(),
        ble: ble,
        logDirectory: () async =>
            throw FileSystemException('Test export failure'),
      );
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = AppSession(
        phoneNumber: 'admin-A',
        signedInAt: DateTime.utc(2026),
        isAdmin: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ButtonDebuggingPage(
                      session: session,
                      controller: controller,
                    ),
                  ),
                ),
                child: const Text('Open debugger'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open debugger'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(ble.captureCalls, isEmpty);
      await tester.tap(find.text('Start debug session'));
      await tester.pumpAndSettle();
      ble.receive();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('RAW HEX'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('RAW HEX'), findsOneWidget);
      expect(find.text('20 seconds'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      for (var i = 0; i < 20 && controller.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        controller.busy,
        false,
        reason:
            'calls=${ble.captureCalls}, sessions=${controller.sessions}, error=${controller.error}',
      );
      expect(find.text('Open debugger'), findsOneWidget);
      expect(controller.sessions.single['end_reason'], 'page_left');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'popups, covering routes and lifecycle changes keep capturing until disposal',
    (tester) async {
      final ble = _Ble();
      final memory = _MemoryDb();
      final recorder = _Controller(
        owner: 'admin-A',
        database: memory,
        ble: ble,
        logDirectory: () async =>
            throw FileSystemException('Test export failure'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ButtonDebuggingPage(
            session: AppSession(
              phoneNumber: 'admin-A',
              signedInAt: DateTime.utc(2026),
              isAdmin: true,
            ),
            controller: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start debug session'));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(ButtonDebuggingPage));
      final navigator = Navigator.of(context);
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Button popup')),
        ),
      );
      await tester.pumpAndSettle();
      ble.receive(20);
      await tester.pump();
      expect(recorder.recording, true);
      expect(recorder.entryCount, 1);
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => const Text('Button sheet'),
        ),
      );
      await tester.pumpAndSettle();
      ble.receive(19);
      await tester.pump();
      expect(recorder.recording, true);
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ble.receive(18);
      await tester.pump();
      expect(recorder.recording, true);
      navigator.pop();
      await tester.pumpAndSettle();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        ble.receive(17);
        await tester.pump();
        expect(recorder.recording, true);
      }
      expect(recorder.entryCount, 9);
      expect(ble.captureCalls, [true]);
      expect(memory.sessionRows.single['status'], 'recording');
      await tester.pumpWidget(const SizedBox());
      // Disposing closes capture synchronously; late packets must be excluded.
      expect(recorder.recording, false);
      ble.receive(16);
      for (var i = 0; i < 20 && recorder.busy; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(ble.captureCalls, [true, false]);
      expect(memory.entries.length, 9);
      expect(memory.sessionRows.single['status'], 'concluded');
      expect(memory.sessionRows.single['end_reason'], 'page_left');
      expect(tester.takeException(), isNull);
      await ble.source.close();
    },
  );

  testWidgets('direction filters and history keep the same capture running', (
    tester,
  ) async {
    final ble = _Ble();
    final recorder = _Controller(
      owner: 'admin-A',
      database: _MemoryDb(),
      ble: ble,
      logDirectory: () async =>
          throw FileSystemException('Test export failure'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ButtonDebuggingPage(
          session: AppSession(
            phoneNumber: 'admin-A',
            signedInAt: DateTime.utc(2026),
            isAdmin: true,
          ),
          controller: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start debug session'));
    await tester.pumpAndSettle();
    ble.receive();
    ble.source.add({
      'bytes': [1, 2],
      'direction': 'TX',
      'operation': 'write_request',
    });
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('debug-filter-TX')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debug-filter-TX')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Write request'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Advertisement'), findsNothing);
    expect(recorder.entryCount, 2);
    await tester.ensureVisible(find.text('Saved sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved sessions'));
    await tester.pumpAndSettle();
    ble.receive(12);
    await tester.pump();
    expect(recorder.recording, true);
    expect(recorder.entryCount, 3);
    expect(ble.captureCalls, [true]);
    await tester.tap(find.text('Stop and save session'));
    for (var i = 0; i < 20 && recorder.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();
    }
    expect(recorder.recording, false);
    expect(recorder.sessions.single['status'], 'concluded');
    expect(ble.captureCalls, [true, false]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await ble.source.close();
  });

  testWidgets(
    'debug workspace controls fit narrow screens with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ble = _Ble();
      final recorder = _Controller(
        owner: 'admin-A',
        database: _MemoryDb(),
        ble: ble,
        logDirectory: () async => throw FileSystemException('unused'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: ButtonDebuggingPage(
              session: AppSession(
                phoneNumber: 'admin-A',
                signedInAt: DateTime.utc(2026),
                isAdmin: true,
              ),
              controller: recorder,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Device commands'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device commands'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Start debug session').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Saved sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved sessions'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(ble.captureCalls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await ble.source.close();
    },
  );

  testWidgets('non-admin cannot start debugging', (tester) async {
    final ble = _Ble();
    final recorder = _Controller(
      owner: 'ordinary',
      database: _MemoryDb(),
      ble: ble,
      logDirectory: () async => throw FileSystemException('unused'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ButtonDebuggingPage(
          session: AppSession(
            phoneNumber: 'ordinary',
            signedInAt: DateTime.utc(2026),
          ),
          controller: recorder,
        ),
      ),
    );
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Start debug session'), findsNothing);
    expect(ble.captureCalls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('saved sessions show the same decoded HEX table', (tester) async {
    final memory = _MemoryDb();
    await memory.createButtonDebugSession(
      'saved',
      'admin-A',
      DateTime.utc(2026),
    );
    await memory.appendButtonDebugEntry(
      'admin-A',
      ButtonDebugEntry.fromEvent({
        'bytes': [72, 67, 1, 6, 1, 20],
        'direction': 'RX',
      }).toRow('saved', 1),
    );
    await memory.concludeButtonDebugSession(
      owner: 'admin-A',
      id: 'saved',
      endedAt: DateTime.utc(2026),
      reason: 'manual_stop',
      logText: 'Legacy saved log',
    );
    final recorder = _Controller(
      owner: 'admin-A',
      database: memory,
      ble: _Ble(),
      logDirectory: () async => throw FileSystemException('unused'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ButtonDebuggingPage(
          session: AppSession(
            phoneNumber: 'admin-A',
            signedInAt: DateTime.utc(2026),
            isAdmin: true,
          ),
          controller: recorder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Saved sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved sessions'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('debug-session-saved')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('debug-session-saved')));
    await tester.pumpAndSettle();
    expect(find.text('Button debug log'), findsOneWidget);
    expect(find.text('48 43 01 06 01 14'), findsOneWidget);
    expect(find.text('20 seconds'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byTooltip('Save log file'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
