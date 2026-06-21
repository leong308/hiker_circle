import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/authentication/Data/phone_number_formatter.dart';
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
