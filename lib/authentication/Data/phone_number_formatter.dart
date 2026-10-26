// PhoneNumberFormatter normalizes account phone numbers and WhatsApp chat IDs.
/// Use one phone normalization rule for authentication, stored contact identity and WhatsApp addressing.
class PhoneNumberFormatter {
  /// Normalizes.
  static String normalize(String input) {
    final compact = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (compact.startsWith('+')) {
      return compact;
    }

    final digitsOnly = compact.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('0')) {
      return '+6$digitsOnly';
    }
    if (digitsOnly.startsWith('60')) {
      return '+$digitsOnly';
    }
    return '+60$digitsOnly';
  }

  /// Checks whether valid.
  static bool isValid(String input) {
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalize(input));
  }

  /// Converts to whats app chat id.
  static String toWhatsAppChatId(String normalizedPhoneNumber) {
    final digitsOnly = normalizedPhoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    return '$digitsOnly@c.us';
  }
}
