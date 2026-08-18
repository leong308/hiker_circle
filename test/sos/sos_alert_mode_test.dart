import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';

void main() {
  test(
    'prolonged stillness SOS keeps its own persisted identity and reason',
    () {
      expect(
        SosAlertMode.prolongedStillness.firestoreValue,
        'prolonged_stillness',
      );
      expect(
        SosAlertMessageComposer.reasonFor(SosAlertMode.prolongedStillness),
        contains('selected safe rest time'),
      );
    },
  );

  test('duress SOS never instructs an emergency contact to call', () {
    final message = SosAlertMessageComposer.compose(
      mode: SosAlertMode.duress,
      phoneNumber: '+60123456789',
      triggeredAt: DateTime.utc(2026, 8, 4),
      triggerLocation: null,
    );

    expect(message, contains('Do not call'));
    expect(message.toLowerCase(), isNot(contains('call me')));
    expect(message.toLowerCase(), isNot(contains('call the hiker')));
  });
}
