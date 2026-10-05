import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restored iOS monitoring buffers fixes before cloud readiness', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final publishStart = source.indexOf(
      'private func publishTelemetry(force: Bool = false)',
    );
    expect(publishStart, greaterThanOrEqualTo(0));
    final publishEnd = source.indexOf(
      'private func uploadNextLocationBatch',
      publishStart,
    );
    expect(publishEnd, greaterThan(publishStart));
    final publishBlock = source.substring(publishStart, publishEnd);

    final localAppend = publishBlock.indexOf(
      'NativeLocationSampleBuffer.shared.append',
    );
    final cloudReadinessGuard = publishBlock.indexOf(
      'guard firebaseTelemetryReady, FirebaseApp.app() != nil',
    );
    final cloudUpload = publishBlock.indexOf(
      'uploadNextLocationBatch(sessions: sessions, owner: ownerUid)',
    );
    expect(localAppend, greaterThanOrEqualTo(0));
    expect(cloudReadinessGuard, greaterThan(localAppend));
    expect(cloudUpload, greaterThan(cloudReadinessGuard));
    expect(publishBlock, contains('isFreshLocation(location)'));
    expect(publishBlock, contains('Self.locationSampleInterval'));
    expect(
      publishBlock,
      contains('sampledAt: Int64(now.timeIntervalSince1970 * 1000)'),
    );
    expect(
      publishBlock,
      contains(
        'now.timeIntervalSince(lastLocationUploadAt) >= locationUploadInterval',
      ),
    );
    expect(publishBlock, contains('Auth.auth().currentUser?.uid == ownerUid'));
    expect(
      publishBlock,
      contains('UIApplication.shared.applicationState != .active'),
    );
    expect(publishBlock, isNot(contains('Firestore.firestore()')));
  });

  test('native cloud batches acknowledge only server-confirmed samples', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final uploadStart = source.indexOf('private func uploadNextLocationBatch');
    expect(uploadStart, greaterThanOrEqualTo(0));
    final uploadEnd = source.indexOf(
      'private func refreshTerminationWatchdog',
      uploadStart,
    );
    expect(uploadEnd, greaterThan(uploadStart));
    final uploadBlock = source.substring(uploadStart, uploadEnd);

    expect(uploadBlock, contains('Auth.auth().currentUser?.uid == owner'));
    expect(uploadBlock, contains('httpsCallable("recordHikeLocationBatch")'));
    expect(
      uploadBlock,
      contains('"fixCapturedAtMillis": sample["capturedAtMillis"]'),
    );
    expect(uploadBlock, contains('payload["committedRecordedAtMillis"]'));
    expect(uploadBlock, contains('acknowledged.contains(sampledAt)'));
    expect(uploadBlock, contains('sampleIds: ids, cloud: true'));
    expect(uploadBlock, isNot(contains('Firestore.firestore()')));
  });

  test('Flutter reconciles and awaits stale native monitoring shutdown', () {
    final source = File(
      'lib/home/View/hiker_home_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(
      source,
      contains(
        'if (restoredHike == null) {\n'
        '        // Native iOS/Android monitoring persists independently',
      ),
    );
    expect(source, contains('await _activeHikeLiveStatusService.stop();'));
    expect(
      source,
      contains('_syncActiveHikeServices(null, stopNativeLiveStatus: false);'),
    );
  });
}
