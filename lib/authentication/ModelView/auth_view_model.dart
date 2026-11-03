// AuthViewModel coordinates sign-in, registration, verification, recovery and session changes.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../Data/multi_factor_auth_service.dart';
import '../Data/auth_flow_diagnostics.dart';
import '../Data/phone_number_formatter.dart';
import '../Model/auth_status.dart';
import '../Model/mfa_models.dart';

/// Coordinates auth view model state and actions.
class AuthViewModel extends ChangeNotifier {
  /// Creates auth view model.
  AuthViewModel({
    FirebaseFunctions? firebaseFunctions,
    MultiFactorAuthService? multiFactorAuthService,
    FirebaseAppCheck? firebaseAppCheck,
  }) : _firebaseFunctions = firebaseFunctions ?? FirebaseFunctions.instance,
       _firebaseAppCheckOverride = firebaseAppCheck,
       _multiFactorAuthService =
           multiFactorAuthService ??
           MultiFactorAuthService(
             functions: firebaseFunctions ?? FirebaseFunctions.instance,
           );

  final FirebaseFunctions _firebaseFunctions;
  final MultiFactorAuthService _multiFactorAuthService;
  final FirebaseAppCheck? _firebaseAppCheckOverride;

  /// A rejected app token never reaches the public login/password handler.
  /// Refresh it once, retaining server App Check enforcement and user identity.
  /// Other failures may have reached the handler, so they must not be replayed.
  Future<T> _withAppCheckRecovery<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'unauthenticated') rethrow;
      AuthFlowDiagnostics.event('authentication-app-check', 'refresh');
      try {
        final token =
            await (_firebaseAppCheckOverride ?? FirebaseAppCheck.instance)
                .getToken(true)
                .timeout(const Duration(seconds: 15));
        // Native SDKs can supply a placeholder when attestation fails. Do not
        // repeat the request with a missing/malformed JWT. Firebase verifies it.
        final parts = token?.split('.');
        if (parts == null ||
            parts.length != 3 ||
            parts.any((part) => part.isEmpty)) {
          throw StateError('App verification did not return a token.');
        }
      } catch (refreshError) {
        AuthFlowDiagnostics.event(
          'authentication-app-check',
          'failure',
          error: refreshError,
        );
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message:
              'Unable to verify this app securely. Check your connection and try again.',
        );
      }
      AuthFlowDiagnostics.event('authentication-app-check', 'retry');
      // Deliberately outside the first attempt's try: a second rejection stops.
      return request();
    }
  }

  AuthMode _authMode = AuthMode.signUp;
  AuthStatus _status = AuthStatus.enteringPhone;
  String? _greenApiChallengeId;
  String? _message;
  String? _error;
  bool _isDisposed = false;

  /// Returns auth mode.
  AuthMode get authMode => _authMode;

  /// Returns status.
  AuthStatus get status => _status;

  /// Returns message.
  String? get message => _message;

  /// Returns error.
  String? get error => _error;

  /// Returns is sending code.
  bool get isSendingCode => _status == AuthStatus.sendingCode;

  /// Returns is verifying code.
  bool get isVerifyingCode => _status == AuthStatus.verifyingCode;

  /// Returns has code been sent.
  bool get hasCodeBeenSent => _greenApiChallengeId != null;

  /// Returns is busy.
  bool get isBusy =>
      _status == AuthStatus.sendingCode ||
      _status == AuthStatus.verifyingCode ||
      _status == AuthStatus.loggingIn;

  /// Returns is logging in.
  bool get isLoggingIn => _status == AuthStatus.loggingIn;

  /// Sets auth mode.
  void setAuthMode(AuthMode mode) {
    _authMode = mode;
    _status = AuthStatus.enteringPhone;
    _message = null;
    _error = null;
    _greenApiChallengeId = null;
    notifyListeners();
  }

  /// Validates phone.
  String? validatePhone(String? value) {
    if (!PhoneNumberFormatter.isValid(value ?? '')) {
      return 'Use a valid phone number, for example 012 345 6789.';
    }
    return null;
  }

  /// Begin the current login or registration OTP flow and expose its processing state to the form.
  Future<void> sendCode(
    String phoneNumber, {
    String? password,
    bool authenticatedReverification = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    AuthFlowDiagnostics.event('whatsapp-code-request', 'start');
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    _status = AuthStatus.sendingCode;
    _message = _authMode == AuthMode.login && !authenticatedReverification
        ? 'Verifying your password before sending a WhatsApp code...'
        : 'Sending a verification code through WhatsApp...';
    _error = null;
    _greenApiChallengeId = null;
    notifyListeners();

    try {
      final parameters = <String, Object?>{
        'phoneNumber': normalized,
        'intent': authenticatedReverification
            ? 'reauth'
            : _authMode == AuthMode.signUp
            ? 'sign_up'
            : 'sign_in',
        if (_authMode == AuthMode.login && !authenticatedReverification)
          'password': password ?? '',
      };
      Future<HttpsCallableResult<dynamic>> request() => _firebaseFunctions
          .httpsCallable('sendGreenApiLoginCode')
          .call(parameters);
      // Authenticated security changes retain their own session checks and do
      // not use the public login retry path.
      final response = authenticatedReverification
          ? await request()
          : await _withAppCheckRecovery(request);
      final data = response.data;
      if (data is! Map || data['challengeId'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      _greenApiChallengeId = data['challengeId'] as String;
      AuthFlowDiagnostics.event(
        'whatsapp-code-request',
        'success',
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      _status = AuthStatus.enteringCode;
      _message =
          'OTP sent to ${PhoneNumberFormatter.maskForDisplay(normalized)} via WhatsApp.';
      _error = null;
    } catch (error) {
      AuthFlowDiagnostics.event(
        'whatsapp-code-request',
        'failure',
        error: error,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      _status = AuthStatus.enteringPhone;
      _message = null;
      _error = _friendlyFunctionsError(error);
    }
    notifyListeners();
  }

  /// Computes resend code.
  Future<bool> resendCode(
    String phoneNumber, {
    String? password,
    bool authenticatedReverification = false,
  }) async {
    final previousChallengeId = _greenApiChallengeId;
    await sendCode(
      phoneNumber,
      password: password,
      authenticatedReverification: authenticatedReverification,
    );
    final sent = _greenApiChallengeId != null;
    if (sent) return true;

    // Keep the original challenge usable when a resend fails. The original
    // WhatsApp message may still arrive, so the user must remain on the OTP
    // step instead of being sent back to the phone-number form.
    _greenApiChallengeId = previousChallengeId;
    if (previousChallengeId != null) {
      _status = AuthStatus.enteringCode;
    }
    notifyListeners();
    return false;
  }

  /// Continue to MFA when required; create the signed-in session only after successful verification.
  Future<MfaContinuation?> verifyOtp(String code) async {
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
      final response = await _firebaseFunctions
          .httpsCallable('verifyGreenApiLoginCode')
          .call(<String, Object?>{
            'challengeId': challengeId,
            'code': code.trim(),
          });
      final data = response.data;
      if (data is! Map ||
          data['mfaToken'] is! String ||
          data['phoneNumber'] is! String ||
          data['expiresAtMillis'] is! num) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      final continuation = MfaContinuation(
        token: data['mfaToken'] as String,
        phoneNumber: data['phoneNumber'] as String,
        methods: data['methods'] is List
            ? (data['methods'] as List)
                  .map((method) => method.toString())
                  .toList(growable: false)
            : const [],
        enrollmentRequired: data['enrollmentRequired'] == true,
        isNewAccount: data['isNewAccount'] == true,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (data['expiresAtMillis'] as num).toInt(),
        ),
      );
      _status = AuthStatus.enteringCode;
      _message = null;
      _error = null;
      notifyListeners();
      return continuation;
    } catch (error) {
      _status = AuthStatus.enteringCode;
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
  List<String> _resetRecoveryMethods = const [];

  /// Returns reset challenge id.
  String? get resetChallengeId => _resetChallengeId;

  /// Returns reset token.
  String? get resetToken => _resetToken;

  /// Returns reset question field.
  String? get resetQuestionField => _resetQuestionField;

  /// Returns reset question text.
  String? get resetQuestionText => _resetQuestionText;

  /// Returns reset skip question.
  bool get resetSkipQuestion => _resetSkipQuestion;

  /// Returns reset recovery methods.
  List<String> get resetRecoveryMethods => _resetRecoveryMethods;

  /// Sends password reset code.
  Future<void> sendPasswordResetCode(String phoneNumber) async {
    final stopwatch = Stopwatch()..start();
    AuthFlowDiagnostics.event('password-reset-code-request', 'start');
    final normalized = PhoneNumberFormatter.normalize(phoneNumber);
    _message = 'Sending a verification code through WhatsApp...';
    _error = null;
    _resetChallengeId = null;
    _resetToken = null;
    _resetQuestionField = null;
    _resetQuestionText = null;
    _resetSkipQuestion = false;
    _resetRecoveryMethods = const [];
    notifyListeners();

    try {
      final response = await _withAppCheckRecovery(
        () => _firebaseFunctions.httpsCallable('sendPasswordResetCode').call(
          <String, Object?>{'phoneNumber': normalized},
        ),
      );
      final data = response.data;
      if (data is! Map || data['challengeId'] is! String) {
        throw FirebaseFunctionsException(
          code: 'invalid-response',
          message: 'The WhatsApp verification service returned invalid data.',
        );
      }
      _resetChallengeId = data['challengeId'] as String;
      AuthFlowDiagnostics.event(
        'password-reset-code-request',
        'success',
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      _message = 'A password reset code was sent through WhatsApp.';
      _error = null;
    } catch (error) {
      AuthFlowDiagnostics.event(
        'password-reset-code-request',
        'failure',
        error: error,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
      _message = null;
      _error = _friendlyFunctionsError(error);
    }
    notifyListeners();
  }

  /// Computes resend password reset code.
  Future<bool> resendPasswordResetCode(String phoneNumber) async {
    final previousChallengeId = _resetChallengeId;
    await sendPasswordResetCode(phoneNumber);
    final sent = _resetChallengeId != null;
    if (sent) {
      _message = 'A new password reset code was sent through WhatsApp.';
      notifyListeners();
      return true;
    }

    // A transport failure must not invalidate the previous challenge in the
    // client. It may still be usable if the original WhatsApp message arrives
    // late, while the error remains visible so the user can retry later.
    _resetChallengeId = previousChallengeId;
    notifyListeners();
    return false;
  }

  /// Retain the reset challenge for the next recovery factor rather than signing the user in.
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
      _resetRecoveryMethods = data['recoveryMethods'] is List
          ? (data['recoveryMethods'] as List)
                .map((method) => method.toString())
                .toList(growable: false)
          : const [];
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

  /// Checks safety answer.
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

  /// Computes verify password reset totp.
  Future<bool> verifyPasswordResetTotp(String code) async {
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
      await _firebaseFunctions.httpsCallable('verifyPasswordResetTotp').call(
        <String, Object?>{'resetToken': token, 'code': code.trim()},
      );
      return true;
    } catch (error) {
      _message = null;
      _error = _friendlyFunctionsError(error);
      notifyListeners();
      return false;
    }
  }

  /// Computes verify password reset passkey.
  Future<bool> verifyPasswordResetPasskey() async {
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
      await _multiFactorAuthService.verifyPasswordResetPasskey(
        resetToken: token,
      );
      return true;
    } catch (error) {
      _message = null;
      _error = readableMfaError(error);
      notifyListeners();
      return false;
    }
  }

  /// Submit the verified reset challenge and the replacement password through the recovery backend.
  Future<bool> resetPassword(String newPassword) async {
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
        <String, Object?>{'resetToken': token, 'newPassword': newPassword},
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

  /// Clears reset state.
  void clearResetState() {
    _resetChallengeId = null;
    _resetToken = null;
    _resetQuestionField = null;
    _resetQuestionText = null;
    _resetSkipQuestion = false;
    _resetRecoveryMethods = const [];
    _message = null;
    _error = null;
    notifyListeners();
  }

  /// Clears messages.
  void clearMessages() {
    _message = null;
    _error = null;
    notifyListeners();
  }

  /// Releases a UI that is waiting on a network authentication operation.
  /// The underlying request may still finish in the background, but the user
  /// can retry instead of being trapped behind a disabled form.
  void cancelPendingOperation({
    String message = 'The request timed out. Please try again.',
  }) {
    if (!isBusy) return;
    _status = _greenApiChallengeId == null
        ? AuthStatus.enteringPhone
        : AuthStatus.enteringCode;
    _message = null;
    _error = message;
    notifyListeners();
  }

  /// Computes friendly functions error.
  String _friendlyFunctionsError(Object error) {
    if (error is FirebaseFunctionsException) {
      return _functionsErrorMessage(error.code, error.message);
    }
    if (error is PlatformException) {
      return _functionsErrorMessage(error.code, error.message);
    }
    return _codeMessage('$error');
  }

  String _functionsErrorMessage(String code, String? message) {
    final text = message?.trim();
    final codeOnly = text?.toLowerCase().replaceFirst('functions/', '');
    return text == null || text.isEmpty || codeOnly == code.toLowerCase()
        ? _codeMessage(code)
        : text;
  }

  /// Computes code message.
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
        return 'Unable to verify this app securely. Check your connection and try again.';
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

  /// Notifies listeners.
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
