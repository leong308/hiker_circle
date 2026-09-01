import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy policy contains worldwide disclosures and relevant footer', () {
    final policy = File('web/privacy-policy.html').readAsStringSync();

    expect(policy, isNot(contains('Senzo')));
    expect(policy, contains('Scope and controller'));
    expect(policy, contains('Regional disclosures'));
    expect(policy, contains('European Economic Area'));
    expect(policy, contains('California'));
    expect(policy, contains('Brazil'));
    expect(policy, contains('Automated processing'));
    expect(policy, contains('does not sell your personal information'));
    expect(policy, contains('Privacy contact'));
  });

  test('every hosted page uses the cache-busted transparent favicon', () {
    for (final path in [
      'web/index.html',
      'web/live-location.html',
      'web/privacy-policy.html',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('href="/favicon.png?v=hc-2"'),
        reason: path,
      );
    }

    final hostingPreparation = File(
      'scripts/prepare_firebase_hosting.js',
    ).readAsStringSync();
    expect(
      hostingPreparation,
      contains('HikerCircle-Loader-Transparent.png'),
    );
  });
}
