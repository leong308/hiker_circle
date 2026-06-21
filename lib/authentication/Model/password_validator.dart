class PasswordValidator {
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-~`+=\[\]\\;/]');
  static final RegExp _digitOnly = RegExp(r'^\d+$');

  static const _keyboardPatterns = [
    'qwerty', 'wertyu', 'ertyui', 'rtyuio', 'tyuiop',
    'asdfgh', 'sdfghj', 'dfghjk', 'fghjkl',
    'zxcvbn', 'xcvbnm',
    'qwertz', 'yxcvbn',
    '1qaz', '2wsx', '3edc', '4rfv', '5tgb', '6yhn', '7ujm', '8ik,', '9ol.',
    'qscwdv', 'ijnuhb',
    'qazwsx', 'wsxedc', 'edcrfv', 'rfvtgb',
    'zaq1', 'xsw2', 'cde3',
  ];

  static const _commonPasswords = {
    'password', 'password123', '12345678', '123456789', '1234567890',
    'qwerty123', 'abc123', 'letmein', 'welcome', 'monkey',
    'dragon', 'master', '123123', 'iloveyou', 'sunshine',
    'princess', 'football', 'shadow', 'trustno1', 'superman',
    'password1', 'admin123', 'qwertyuiop', 'asdfghjkl',
    'zxcvbnm', 'passw0rd', 'p@ssword', 'p@ssw0rd',
    'changeme', 'passwd', 'pass123', 'temp123', 'test123',
    'guest123', 'hello123', 'admin', 'root', 'toor',
  };

  static const _genericTerms = {
    'london', 'paris', 'newyork', 'tokyo', 'berlin',
    'madrid', 'rome', 'moscow', 'dubai', 'singapore',
    'kualalumpur', 'seoul', 'bangkok', 'sydney', 'mumbai',
    'beijing', 'hongkong', 'barcelona', 'prague', 'vienna',
    'dublin', 'amsterdam', 'stockholm', 'helsinki', 'oslo',
    'hiker', 'circle', 'hikercircle', 'hiking', 'travel',
    'adventure', 'nature', 'outdoor', 'mountain', 'forest',
    'river', 'ocean', 'summer', 'winter', 'spring', 'autumn',
    'happy', 'smile', 'hello', 'world', 'love', 'life',
    'home', 'work', 'school', 'user', 'guest',
    'test', 'demo', 'sample', 'default',
    'football', 'soccer', 'baseball', 'basketball', 'tennis',
    'golf', 'swimming', 'running', 'cycling', 'yoga',
    'chocolate', 'coffee', 'tea', 'water', 'fire',
    'earth', 'wind', 'star', 'moon', 'sun',
    'dragon', 'tiger', 'eagle', 'lion', 'bear',
    'wolf', 'shark', 'whale', 'snake', 'horse',
    'kuala', 'lumpur', 'penang', 'johor', 'sabah',
    'sarawak', 'melaka', 'perak', 'kedah', 'kelantan',
    'terengganu', 'pahang', 'negeri', 'sembilan',
    'perlis', 'putrajaya', 'labuan', 'malaysia',
  };

  static ValidationResult validate(String password) {
    if (password.length < 8) {
      return ValidationResult(
        false,
        'Password must be at least 8 characters long.',
      );
    }

    if (!_hasUppercase.hasMatch(password)) {
      return ValidationResult(
        false,
        'Password must contain at least one uppercase letter.',
      );
    }

    if (!_hasLowercase.hasMatch(password)) {
      return ValidationResult(
        false,
        'Password must contain at least one lowercase letter.',
      );
    }

    if (!_hasDigit.hasMatch(password)) {
      return ValidationResult(
        false,
        'Password must contain at least one digit.',
      );
    }

    if (!_hasSpecial.hasMatch(password)) {
      return ValidationResult(
        false,
        'Password must contain at least one special character.',
      );
    }

    final lowercase = password.toLowerCase();

    if (_hasSequentialPattern(password)) {
      return ValidationResult(
        false,
        'Password contains sequential numbers (e.g., 123456). Avoid simple sequences.',
      );
    }

    if (_hasRepeatedPattern(password)) {
      return ValidationResult(
        false,
        'Password contains too many repeated characters (e.g., aaaa, 1111).',
      );
    }

    for (final pattern in _keyboardPatterns) {
      if (lowercase.contains(pattern)) {
        return ValidationResult(
          false,
          'Password contains a keyboard pattern (e.g., qwerty, asdfgh).',
        );
      }
    }

    if (_commonPasswords.contains(lowercase)) {
      return ValidationResult(
        false,
        'This password is too common. Choose a more unique password.',
      );
    }

    for (final term in _genericTerms) {
      if (lowercase.contains(term)) {
        return ValidationResult(
          false,
          'Password contains a common term or dictionary word. Avoid using easily guessable words.',
        );
      }
    }

    return ValidationResult(true, null);
  }

  static bool _hasSequentialPattern(String password) {
    for (int i = 0; i < password.length - 2; i++) {
      final a = password.codeUnitAt(i);
      final b = password.codeUnitAt(i + 1);
      final c = password.codeUnitAt(i + 2);
      final forward = a + 1 == b && b + 1 == c;
      final backward = a - 1 == b && b - 1 == c;
      if (forward || backward) {
        final triple = password.substring(i, i + 3);
        if (_digitOnly.hasMatch(triple)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasRepeatedPattern(String password) {
    for (int i = 0; i < password.length - 3; i++) {
      final c1 = password[i];
      final c2 = password[i + 1];
      final c3 = password[i + 2];
      final c4 = password[i + 3];
      if (c1 == c2 && c2 == c3 && c3 == c4) {
        return true;
      }
    }
    return false;
  }
}

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult(this.isValid, this.errorMessage);
}
