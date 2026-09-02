import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restored iOS monitoring cannot start Firestore before Flutter', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final publishStart = source.indexOf(
      'private func publishTelemetry(force: Bool = false)',
    );
    final publishEnd = source.indexOf(
      'private func refreshTerminationWatchdog',
      publishStart,
    );
    final publishBlock = source.substring(publishStart, publishEnd);

    expect(publishStart, greaterThanOrEqualTo(0));
    expect(
      publishBlock,
      contains('guard isActive, firebaseTelemetryReady, FirebaseApp.app()'),
    );
    expect(publishBlock, contains('Firestore.firestore()'));
  });

  test('Flutter reconciles and awaits stale native monitoring shutdown', () {
    final source = File(
      'lib/home/View/hiker_home_page.dart',
    ).readAsStringSync();

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
