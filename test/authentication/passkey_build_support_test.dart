import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/authentication/Data/passkey_build_support.dart';

void main() {
  test('personal-signed iOS builds disable native passkeys', () {
    expect(
      nativePasskeysEnabledForBuild(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
  });

  test('paid-team iOS builds can explicitly enable native passkeys', () {
    expect(
      nativePasskeysEnabledForBuild(
        isWeb: false,
        platform: TargetPlatform.iOS,
        iosNativePasskeysEnabled: true,
      ),
      isTrue,
    );
  });

  test('Android and web passkeys remain enabled', () {
    expect(
      nativePasskeysEnabledForBuild(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      nativePasskeysEnabledForBuild(isWeb: true, platform: TargetPlatform.iOS),
      isTrue,
    );
  });
}
