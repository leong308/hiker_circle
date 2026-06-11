import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/authentication/Data/phone_number_formatter.dart';
import 'package:hiker_circle/authentication/Model/otp_challenge.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';

void main() {
  group('PhoneNumberFormatter', () {
    test('keeps numbers that already include the country code prefix', () {
      expect(PhoneNumberFormatter.normalize('+60123456789'), '+60123456789');
    });

    test('converts local Malaysian numbers to E.164 format', () {
      expect(PhoneNumberFormatter.normalize('012 345 6789'), '+60123456789');
    });

    test('adds plus sign when the number starts with 60', () {
      expect(PhoneNumberFormatter.normalize('60123456789'), '+60123456789');
    });

    test('creates a WhatsApp private chat id', () {
      expect(
        PhoneNumberFormatter.toWhatsAppChatId('+60123456789'),
        '60123456789@c.us',
      );
    });
  });

  group('OtpChallenge', () {
    test('verifies the generated code before it is hidden', () {
      final challenge = OtpChallenge.generate(phoneNumber: '+60123456789');

      expect(challenge.verify(challenge.code!), isTrue);
      expect(challenge.verify('000000'), isFalse);
    });

    test('keeps verifying after the code is hidden from memory', () {
      final challenge = OtpChallenge.generate(phoneNumber: '+60123456789');
      final hidden = challenge.hideCode();

      expect(hidden.code, isNull);
      expect(hidden.verify(challenge.code!), isTrue);
    });
  });

  group('EmergencyContact', () {
    test('round trips Firestore data', () {
      const contact = EmergencyContact(
        name: 'Aina',
        phoneNumber: '+60123456789',
        relationship: 'Sister',
      );

      final firestoreData = contact.toFirestore();

      expect(firestoreData, {
        'name': 'Aina',
        'phoneNumber': '+60123456789',
        'relationship': 'Sister',
      });
      expect(EmergencyContact.fromFirestore(firestoreData).name, 'Aina');
      expect(
        EmergencyContact.fromFirestore(firestoreData).phoneNumber,
        '+60123456789',
      );
      expect(
        EmergencyContact.fromFirestore(firestoreData).relationship,
        'Sister',
      );
    });
  });
}
