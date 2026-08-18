import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_app_check_guard.dart';
import '../../app/Model/app_session.dart';
import '../Data/phone_number_formatter.dart';
import '../Model/auth_status.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? firebaseFunctions,
    FirebaseAppCheckGuard? appCheckGuard,
    Future<void> Function(AppSession session)? onAutomaticallyVerified,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firebaseFunctions = firebaseFunctions ?? FirebaseFunctions.instance,
       _appCheckGuard = appCheckGuard ?? FirebaseAppCheckGuard(),
       _onAutomaticallyVerified = onAutomaticallyVerified;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _firebaseFunctions;
  final FirebaseAppCheckGuard _appCheckGuard;
  final Future<void> Function(AppSession session)? _onAutomaticallyVerified;

  AuthMode _authMode = AuthMode.signUp;
  AuthStatus _status = AuthStatus.enteringPhone;
  String? _greenApiChallengeId;
  String? _message;
  String? _error;
  bool _isDisposed = false;

  AuthMode get authMode => _authMode;
  AuthStatus get status => _status;
  String? get message => _message;
  String? get error => _error;
  bool get isSendingCode => _status == AuthStatus.sendingCode;
  bool get isVerifyingCode => _status == AuthStatus.verifyingCode;
  bool get hasCodeBeenSent => _greenApiChallengeId != null;
  bool get isBusy =>
      _status == AuthStatus.sendingCode ||
      _status == AuthStatus.verifyingCode ||
      _status == AuthStatus.loggingIn;
  bool get isLoggingIn => _status == AuthStatus.loggingIn;

  void setAuthMode(AuthMode mode) {
    _authMode = mode;
    _status = AuthStatus.enteringPhone;
    _message = null;
    _error = null;
    _greenApiChallengeId = null;
    notifyListeners();
  }

  String? validatePhone(String? value) {
    if (!PhoneNumberFormatter.isValid(value ?? '')) {
      return 'Use a valid phone number, for example 012 345 6789.';
    }
    return null;
  }

  Future<void> sendCode(String phoneNumber) async {
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    _status = AuthStatus.sendingCode;
    _message = 'Sending a verification code through WhatsApp...';
    _error = null;
    _greenApiChallengeId = null;
    notifyListeners();

    try {
      await _appCheckGuard.ensureAuthorized();
      final response = await _firebaseFunctions
          .httpsCallable('sendGreenApiLoginCode')
          .call(<String, Object?>{'phoneNumber': normalized});
      final data = response.data;
      if (data is! Map || data['challengeId'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      _greenApiChallengeId = data['challengeId'] as String;
      _status = AuthStatus.enteringCode;
      _message = 'GreenAPI sent a WhatsApp code to $normalized.';
      _error = null;
    } catch (error) {
      _status = AuthStatus.enteringPhone;
      _message = null;
      _error = _friendlyFunctionsError(error);
    }
    notifyListeners();
  }

  Future<AppSession?> verifyOtp(String code) async {
    final challengeId = _greenApiChallengeId;
    if (challengeId == null) {
      _error = 'Send a verification code first.';
      notifyListeners();
      return null;
    }

    _status = AuthStatus.verifyingCode;
    _message = 'Verifying code...';
    _error = null;
    notifyListeners();

    try {
      await _appCheckGuard.ensureAuthorized();
      final response = await _firebaseFunctions
          .httpsCallable('verifyGreenApiLoginCode')
          .call(<String, Object?>{
            'challengeId': challengeId,
            'code': code.trim(),
          });
      final data = response.data;
      if (data is! Map ||
          data['customToken'] is! String ||
          data['phoneNumber'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      final credential = await _firebaseAuth.signInWithCustomToken(
        data['customToken'] as String,
      );
      if (credential.user == null) {
        throw FirebaseAuthException(
          code: 'green-api-sign-in-failed',
          message: 'Firebase could not complete the verification.',
        );
      }
      final session = AppSession(
        phoneNumber: data['phoneNumber'] as String,
        signedInAt: DateTime.now(),
      );
      _status = AuthStatus.signedIn;
      _message = null;
      _error = null;
      notifyListeners();
      await _onAutomaticallyVerified?.call(session);
      return session;
    } catch (error) {
      _status = AuthStatus.enteringCode;
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return null;
    }
  }

  Future<AppSession?> loginWithPassword(
    String phoneNumber,
    String password,
  ) async {
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    _status = AuthStatus.loggingIn;
    _message = 'Signing in...';
    _error = null;
    notifyListeners();

    try {
      final response = await _firebaseFunctions
          .httpsCallable('loginWithPassword')
          .call(<String, Object?>{
            'phoneNumber': normalized,
            'password': password,
          });
      final data = response.data;
      if (data is! Map ||
          data['customToken'] is! String ||
          data['phoneNumber'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'Login service returned invalid data.',
        );
      }
      final credential = await _firebaseAuth.signInWithCustomToken(
        data['customToken'] as String,
      );
      if (credential.user == null) {
        throw FirebaseAuthException(
          code: 'login-sign-in-failed',
          message: 'Firebase could not complete the login.',
        );
      }
      final session = AppSession(
        phoneNumber: data['phoneNumber'] as String,
        signedInAt: DateTime.now(),
      );
      _status = AuthStatus.signedIn;
      _message = null;
      _error = null;
      notifyListeners();
      await _onAutomaticallyVerified?.call(session);
      return session;
    } catch (error) {
      _status = AuthStatus.enteringPhone;
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return null;
    }
  }

  // ─── Password Reset ──────────────────────────────────────────

  String? _resetChallengeId;
  String? _resetToken;
  String? _resetQuestionField;
  String? _resetQuestionText;
  bool _resetSkipQuestion = false;

  String? get resetChallengeId => _resetChallengeId;
  String? get resetToken => _resetToken;
  String? get resetQuestionField => _resetQuestionField;
  String? get resetQuestionText => _resetQuestionText;
  bool get resetSkipQuestion => _resetSkipQuestion;

  Future<void> sendPasswordResetCode(String phoneNumber) async {
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    _message = 'Sending a verification code through WhatsApp...';
    _error = null;
    _resetChallengeId = null;
    notifyListeners();

    try {
      await _appCheckGuard.ensureAuthorized();
      final response = await _firebaseFunctions
          .httpsCallable('sendPasswordResetCode')
          .call(<String, Object?>{'phoneNumber': normalized});
      final data = response.data;
      if (data is! Map || data['challengeId'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      _resetChallengeId = data['challengeId'] as String;
      _message = 'GreenAPI sent a password reset code to $normalized.';
      _error = null;
    } catch (error) {
      _message = null;
      _error = _friendlyFunctionsError(error);
    }
    notifyListeners();
  }

  Future<bool> verifyPasswordResetOtp(String code) async {
    final challengeId = _resetChallengeId;
    if (challengeId == null || challengeId.isEmpty) {
      _error = 'Request a password reset code first.';
      notifyListeners();
      return false;
    }

    _message = 'Verifying code...';
    _error = null;
    notifyListeners();

    try {
      final response = await _firebaseFunctions
          .httpsCallable('verifyPasswordResetOtp')
          .call(<String, Object?>{
            'challengeId': challengeId,
            'code': code.trim(),
          });
      final data = response.data;
      if (data is! Map || data['resetToken'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The verification service returned invalid data.',
        );
      }
      _resetToken = data['resetToken'] as String;
      _resetQuestionField = data['questionField'] as String?;
      _resetQuestionText = data['questionText'] as String?;
      _resetSkipQuestion = data['skipQuestion'] == true;
      _message = null;
      _error = null;
      notifyListeners();
      return true;
    } catch (error) {
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkSafetyAnswer(String answer) async {
    final token = _resetToken;
    if (token == null || token.isEmpty) {
      _error = 'Password reset session expired. Start again.';
      notifyListeners();
      return false;
    }

    _error = null;
    _message = null;
    notifyListeners();

    try {
      await _firebaseFunctions.httpsCallable('checkSafetyAnswer').call(
        <String, Object?>{'resetToken': token, 'answer': answer},
      );
      return true;
    } catch (error) {
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String answer, String newPassword) async {
    final token = _resetToken;
    if (token == null || token.isEmpty) {
      _error = 'Password reset session expired. Start again.';
      notifyListeners();
      return false;
    }

    _message = 'Resetting password...';
    _error = null;
    notifyListeners();

    try {
      await _firebaseFunctions.httpsCallable('resetPassword').call(
        <String, Object?>{
          'resetToken': token,
          'answer': answer,
          'newPassword': newPassword,
        },
      );
      _message = 'Password has been reset. You can now sign in.';
      _error = null;
      notifyListeners();
      return true;
    } catch (error) {
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return false;
    }
  }

  void clearResetState() {
    _resetChallengeId = null;
    _resetToken = null;
    _resetQuestionField = null;
    _resetQuestionText = null;
    _resetSkipQuestion = false;
    _message = null;
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _message = null;
    _error = null;
    notifyListeners();
  }

  String _friendlyFunctionsError(Object error) {
    if (error is FirebaseAppCheckUnavailable) {
      return error.toString();
    }
    if (error is FirebaseFunctionsException) {
      return error.message ?? _codeMessage(error.code);
    }
    if (error is FirebaseAuthException) {
      return error.message ?? _codeMessage(error.code);
    }
    if (error is PlatformException) {
      return error.message ?? _codeMessage(error.code);
    }
    return _codeMessage('$error');
  }

  String _codeMessage(String code) {
    final normalizedCode = code
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(' ', '-');
    switch (normalizedCode) {
      case 'not-found':
        return 'No account found with this phone number. Please sign up first.';
      case 'invalid-argument':
        return 'Please check your input and try again.';
      case 'permission-denied':
        return 'Access denied. Please try again.';
      case 'unauthenticated':
        return 'You need to sign in again.';
      case 'unavailable':
        return 'Service is temporarily unavailable. Try again later.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait before trying again.';
      case 'deadline-exceeded':
        return 'The request timed out. Please try again.';
      case 'already-exists':
        return 'This request has already been processed.';
      case 'failed-precondition':
        return 'This operation cannot be completed right now.';
      case 'internal':
        return 'Something went wrong on our end. Please try again.';
      default:
        return 'Operation failed. Please try again.';
    }
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
