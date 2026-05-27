import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../Data/green_api_client.dart';
import '../Data/green_api_config.dart';
import '../Data/green_api_otp_repository.dart';
import '../Data/phone_number_formatter.dart';
import '../Model/auth_status.dart';
import '../Model/otp_challenge.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({GreenApiOtpRepository? otpRepository})
    : _otpRepository =
          otpRepository ??
          GreenApiOtpRepository(
            greenApiClient: GreenApiClient(config: const GreenApiConfig()),
          );

  final GreenApiOtpRepository _otpRepository;

  AuthStatus _status = AuthStatus.enteringPhone;
  OtpChallenge? _challenge;
  String? _message;
  String? _error;

  AuthStatus get status => _status;
  String? get message => _message;
  String? get error => _error;
  bool get isSendingCode => _status == AuthStatus.sendingCode;
  bool get isVerifyingCode => _status == AuthStatus.verifyingCode;
  bool get hasCodeBeenSent => _challenge != null;

  String? validatePhone(String? value) {
    if (!PhoneNumberFormatter.isValid(value ?? '')) {
      return 'Use a valid phone number, for example 012 345 6789.';
    }
    return null;
  }

  Future<void> sendCode(String phoneNumber) async {
    _status = AuthStatus.sendingCode;
    _message = 'Sending verification code...';
    _error = null;
    notifyListeners();

    try {
      _challenge = await _otpRepository.sendLoginCode(phoneNumber);
      _status = AuthStatus.enteringCode;
      _message = 'Verification code sent to ${_challenge!.phoneNumber}.';
    } catch (error) {
      _status = AuthStatus.enteringPhone;
      _message = null;
      _error = _friendlyError(error);
    }

    notifyListeners();
  }

  AppSession? verifyCode(String input) {
    final challenge = _challenge;
    if (challenge == null) {
      _error = 'Send a verification code first.';
      notifyListeners();
      return null;
    }

    _status = AuthStatus.verifyingCode;
    _message = 'Verifying code...';
    _error = null;
    notifyListeners();

    if (!challenge.verify(input)) {
      _status = AuthStatus.enteringCode;
      _message = null;
      _error = challenge.isExpired
          ? 'The code expired. Send a new code.'
          : 'The verification code is incorrect.';
      notifyListeners();
      return null;
    }

    _status = AuthStatus.signedIn;
    _message = null;
    _error = null;
    notifyListeners();

    return AppSession(
      phoneNumber: challenge.phoneNumber,
      signedInAt: DateTime.now(),
    );
  }

  String _friendlyError(Object error) {
    if (error is GreenApiConfigException) {
      return error.message;
    }
    if (error is GreenApiException) {
      return error.message;
    }
    return 'Unable to send the verification code. Please try again.';
  }
}
