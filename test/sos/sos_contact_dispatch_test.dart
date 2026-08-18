import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';

void main() {
  test(
    'terminal uncertain dispatch remains non-retryable after persistence',
    () {
      const dispatch = SosContactDispatch(
        contactName: 'Emergency contact',
        phoneNumber: '+60123456789',
        wasSent: false,
        retryable: false,
        errorMessage: 'Delivery could not be confirmed.',
      );

      final restored = SosContactDispatch.fromFirestore(dispatch.toFirestore());

      expect(restored.wasSent, isFalse);
      expect(restored.retryable, isFalse);
      expect(restored.errorMessage, 'Delivery could not be confirmed.');
    },
  );

  test('legacy failed dispatches remain retryable', () {
    final restored = SosContactDispatch.fromFirestore(const {
      'contactName': 'Emergency contact',
      'phoneNumber': '+60123456789',
      'wasSent': false,
    });

    expect(restored.retryable, isTrue);
  });

  test('provider message id is retained for sent audit entries', () {
    const dispatch = SosContactDispatch(
      contactName: 'Emergency contact',
      phoneNumber: '+60123456789',
      wasSent: true,
      retryable: false,
      providerMessageId: 'provider-message-123',
    );

    final restored = SosContactDispatch.fromFirestore(dispatch.toFirestore());

    expect(restored.wasSent, isTrue);
    expect(restored.providerMessageId, 'provider-message-123');
  });
}
