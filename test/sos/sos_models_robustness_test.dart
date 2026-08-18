import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';

void main() {
  group('SOS model robustness', () {
    test('invalid platform coordinates and timestamps do not throw', () {
      final location = SosTriggerLocation.fromPlatform({
        'latitude': double.nan,
        'longitude': double.infinity,
        'accuracyMeters': double.negativeInfinity,
        'capturedAtMillis': double.maxFinite,
      });

      expect(location.hasValidPosition, isFalse);
      expect(location.accuracyMeters, isNull);
      expect(location.capturedAt, isNull);
    });

    test('invalid Firestore alert location is treated as unavailable', () {
      final alert = SosAlert.fromFirestore({
        'id': 'bad-location',
        'mode': 'manual',
        'status': 'sent',
        'triggeredAtLocal': '2026-08-04T10:00:00Z',
        'contactCount': double.nan,
        'triggerLocation': {
          'latitude': 1000,
          'longitude': 2000,
          'accuracyMeters': double.infinity,
        },
      });

      expect(alert.triggerLocation, isNull);
      expect(alert.contactCount, 0);
    });

    test('message composer omits malformed location and accuracy', () {
      final message = SosAlertMessageComposer.compose(
        mode: SosAlertMode.manual,
        phoneNumber: '+60123456789',
        triggeredAt: DateTime.utc(2026, 8, 4),
        triggerLocation: SosTriggerLocation(
          latitude: double.nan,
          longitude: 101.0,
          accuracyMeters: double.infinity,
        ),
      );

      expect(message, contains('Location unavailable'));
      expect(message, isNot(contains('Estimated accuracy:')));
      expect(message, isNot(contains('Type:')));
    });

    test('message uses selected timezone and emergency-button reason', () {
      final message = SosAlertMessageComposer.compose(
        mode: SosAlertMode.manual,
        phoneNumber: '+60123456789',
        triggeredAt: DateTime.parse('2026-08-18T13:50:34.313Z'),
        triggerLocation: null,
        triggerSource: SosAlertTriggerSource.emergencyButton,
        preferredTimeZone: 'Asia/Singapore',
      );

      expect(
        message,
        contains('18 Aug 2026, 9:50:34 PM (GMT+8 · Asia/Singapore)'),
      );
      expect(
        message,
        contains('User triggered SOS through an emergency button.'),
      );
      expect(message, isNot(contains('13:50:34.313Z')));
    });

    test('non-finite native output volume becomes unavailable', () {
      final status = SosOutputVolumeStatus.fromPlatform({
        'platform': 'ios',
        'isIos': true,
        'canMeasureOutputVolume': true,
        'outputVolume': double.nan,
      }, defaultMinimumRequiredVolume: 0.5);

      expect(status.canMeasureOutputVolume, isFalse);
      expect(status.outputVolume, isNull);
      expect(status.isAudible, isTrue);
    });
  });
}
