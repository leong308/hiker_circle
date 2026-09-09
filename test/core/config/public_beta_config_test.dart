import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/config/google_api_config.dart';

void main() {
  test('beta-only Android identity headers match the distribution certificate', () {
    const enabled = bool.fromEnvironment('HC_PUBLIC_BETA');
    if (enabled) {
      expect(GoogleApiConfig.androidBetaHeaders['X-Android-Package'],
          'com.leongziqi.hikercircle');
      expect(GoogleApiConfig.androidBetaHeaders['X-Android-Cert'],
          '4E84B7B37406768A071559598FFE800C61987B3A');
    } else {
      expect(GoogleApiConfig.androidBetaHeaders, isEmpty);
    }
  });
}
