import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/me/Data/live_location_repository.dart';
import 'package:hiker_circle/me/Data/live_location_sharing_service.dart';
import 'package:hiker_circle/me/Model/live_location_models.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late LocalSessionDatabase database;
  const phone = '+60111111111';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sharing_stop_');
    database = LocalSessionDatabase(
      databasePath: '${directory.path}/session.db',
    );
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });
  test(
    'offline stop survives restart and cannot restore a cloud share',
    () async {
      final repository = _Sharing(database)..failStop = true;
      await expectLater(
        repository.deactivate(phoneNumber: phone, share: null),
        throwsStateError,
      );
      final restarted = _Sharing(database)..failStop = true;
      expect(await restarted.loadForUser(phoneNumber: phone), isNull);
      expect(await restarted.hasPendingStop(phone), isTrue);
      restarted.failStop = false;
      await restarted.retryPendingStop(phone);
      expect(await restarted.hasPendingStop(phone), isFalse);
    },
  );
  test('activation uses canonical server expiry', () async {
    final repository = _Sharing(database);
    final share = await repository.activate(
      phoneNumber: phone,
      location: const SosTriggerLocation(latitude: 3, longitude: 101),
    );
    expect(share.expiresAt.millisecondsSinceEpoch, repository.serverExpiry);
  });
  test(
    'manual stop signals before cloud completion and survives reset',
    () async {
      final repository = _LoadingSharing(database)
        ..stopGate = Completer<void>();
      final service = LiveLocationSharingService(
        repositoryFactory: (_) => repository,
      );
      final load = service.loadExisting(
        phoneNumber: phone,
        firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
      );
      await repository.started.future;
      repository.loaded.complete(null);
      await load;
      final revisions = <int>[];
      service.addListener(() => revisions.add(service.manualStopRevision));
      final stop = service.deactivate();
      expect(service.manualStopRevision, 1);
      expect(revisions.first, 1);
      await repository.stopStarted.future;
      repository.stopGate!.complete();
      await stop;
      await service.deactivate(manual: false);
      expect(service.manualStopRevision, 1);
      service.reset();
      expect(service.manualStopRevision, 1);
      await service.deactivate();
      expect(service.manualStopRevision, 2);
      expect(revisions.last, 2);
      service.dispose();
    },
  );
  test(
    'older stop acknowledgement cannot clear a newer offline stop',
    () async {
      final first = _Sharing(database)..stopGate = Completer<void>();
      final stop = first.deactivate(phoneNumber: phone, share: null);
      await first.stopStarted.future;
      final second = _Sharing(database)..failStop = true;
      await expectLater(
        second.deactivate(phoneNumber: phone, share: null),
        throwsStateError,
      );
      first.stopGate!.complete();
      await stop;
      expect(await second.hasPendingStop(phone), isTrue);
      second.failStop = false;
      await second.retryPendingStop(phone);
      expect(await second.hasPendingStop(phone), isFalse);
    },
  );
  test(
    'stop invalidates a busy load and keeps stale result inactive',
    () async {
      final repository = _LoadingSharing(database);
      final service = LiveLocationSharingService(
        repositoryFactory: (_) => repository,
      );
      final load = service.loadExisting(
        phoneNumber: phone,
        firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
      );
      await repository.started.future;
      await service.deactivate();
      expect(service.isActive, isFalse);
      repository.loaded.complete(
        LiveLocationShare(
          id: 'old',
          shareUrl: 'https://example.test',
          isActive: true,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      await load;
      expect(service.isActive, isFalse);
      expect(service.isBusy, isFalse);
      service.dispose();
    },
  );
}

class _Sharing extends LiveLocationRepository {
  _Sharing(LocalSessionDatabase db)
    : super(localDatabase: db, cloudTimeout: const Duration(milliseconds: 50));
  bool failStop = false;
  Completer<void>? stopGate;
  final stopStarted = Completer<void>();
  final serverExpiry = DateTime.utc(2028, 1, 2).millisecondsSinceEpoch;
  @override
  Future<void> deactivateCloudShare(
    String phoneNumber,
    String? savedShareId,
  ) async {
    if (!stopStarted.isCompleted) stopStarted.complete();
    await stopGate?.future;
    if (failStop) throw StateError('offline');
  }

  @override
  Future<Map<String, dynamic>> activateCloudShare(
    SosTriggerLocation location,
  ) async => {
    'shareId': 'server-id',
    'shareUrl': 'https://example.test/share',
    'expiresAtMillis': serverExpiry,
  };
}

class _LoadingSharing extends _Sharing {
  _LoadingSharing(super.db);
  final started = Completer<void>();
  final loaded = Completer<LiveLocationShare?>();
  @override
  Future<bool> loadAutoShareOnHikeStart({required String phoneNumber}) async =>
      false;
  @override
  Future<LiveLocationShare?> loadForUser({required String phoneNumber}) {
    started.complete();
    return loaded.future;
  }
}
