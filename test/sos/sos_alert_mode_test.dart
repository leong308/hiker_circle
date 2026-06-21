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
}
