// maskPhoneNumber creates a display-safe phone label without changing the underlying account
// identifier.
String maskPhoneNumber(String phone) {
  final value = phone.trim();
  if (value.length < 7) return '****';
  return '${value.substring(0, 3)}****${value.substring(value.length - 3)}';
}

String privateChatLabel(String value) =>
    RegExp(r'^\+?[0-9][0-9\s()-]{6,}$').hasMatch(value.trim())
    ? maskPhoneNumber(value)
    : value;
