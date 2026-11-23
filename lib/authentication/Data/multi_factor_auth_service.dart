// MultiFactorAuthService coordinates TOTP, passkey enrollment and server-verified login challenges.
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../../app/Model/app_session.dart';
import '../Model/mfa_models.dart';
import 'passkey_build_support.dart';
import 'auth_flow_diagnostics.dart';

/// Represents multi factor auth service.
class MultiFactorAuthService {
  /// Creates multi factor auth service.
  MultiFactorAuthService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    PasskeyAuthenticator? passkeyAuthenticator,
  }) : _functionsOverride = functions,
       _authOverride = auth,
       _passkeys = passkeyAuthenticator ?? PasskeyAuthenticator();

  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _authOverride;
  final PasskeyAuthenticator _passkeys;

  /// Returns functions.
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  /// Returns auth.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// Read the verified phone claim from the authenticated token before changing security factors.
  Future<String> authenticatedPhoneNumber() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign in again before changing security methods.',
      );
    }
    final token = await user.getIdTokenResult();
    final phoneNumber = token.claims?['phoneNumber'];
    if (phoneNumber is String &&
        RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phoneNumber)) {
      return phoneNumber;
    }
    throw FirebaseAuthException(
      code: 'missing-phone-number',
      message: 'Your verified phone number is unavailable. Sign in again.',
    );
  }

  /// Begins totp enrollment.
  Future<TotpEnrollment> beginTotpEnrollment({String? mfaToken}) async {
    // Update cloud: create TOTP enrollment challenge
    final data = await _call(
      'beginTotpEnrollment',
      mfaToken == null ? const {} : {'mfaToken': mfaToken},
    );
    return TotpEnrollment(
      challengeId: _requiredString(data, 'challengeId'),
      secret: _requiredString(data, 'secret'),
      otpauthUri: _requiredString(data, 'otpauthUri'),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        _requiredInt(data, 'expiresAtMillis'),
      ),
    );
  }

  /// Finishes totp enrollment.
  Future<AppSession?> finishTotpEnrollment({
    required String challengeId,
    required String code,
    String? mfaToken,
  }) async {
    // Update cloud: verify and save TOTP factor
    final data = await _call('finishTotpEnrollment', {
      'challengeId': challengeId,
      'code': code,
      if (mfaToken != null) 'mfaToken': mfaToken,
    });
    return _sessionFromTokenResponse(data);
  }

  /// Complete the server challenge around the platform passkey registration operation.
  Future<AppSession?> enrollPasskey({String? mfaToken, String? label}) async {
    AuthFlowDiagnostics.event('passkey-enrollment', 'start');
    _requirePasskeysEnabled();
    // Update cloud: create passkey enrollment challenge
    final begin = await _call(
      'beginPasskeyEnrollment',
      mfaToken == null ? const {} : {'mfaToken': mfaToken},
    );
    final options = _requiredMap(begin, 'options');
    final platformResponse = await _runPasskeyOperation(
      operation: 'register',
      callback: () => _passkeys.register(RegisterRequestType.fromJson(options)),
    );
    // Update cloud: save enrolled passkey
    final completed = await _call('finishPasskeyEnrollment', {
      'challengeId': _requiredString(begin, 'challengeId'),
      'response': platformResponse.toJson(),
      if (mfaToken != null) 'mfaToken': mfaToken,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    AuthFlowDiagnostics.event('passkey-enrollment', 'server-verified');
    return _sessionFromTokenResponse(completed);
  }

  /// Computes verify totp login.
  Future<AppSession> verifyTotpLogin({
    required String mfaToken,
    required String code,
  }) async {
    // Update cloud: verify TOTP login session
    final data = await _call('verifyTotpLogin', {
      'mfaToken': mfaToken,
      'code': code,
    });
    return _requiredSession(data);
  }

  /// Exchange the server's passkey challenge and assertion result for the verified app session.
  Future<AppSession> verifyPasskeyLogin({required String mfaToken}) async {
    _requirePasskeysEnabled();
    // Update cloud: create passkey login challenge
    final begin = await _call('beginPasskeyLogin', {'mfaToken': mfaToken});
    final platformResponse = await _runPasskeyOperation(
      operation: 'authenticate',
      callback: () => _passkeys.authenticate(
        AuthenticateRequestType.fromJson(_requiredMap(begin, 'options')),
      ),
    );
    // Update cloud: verify passkey login session
    final data = await _call('finishPasskeyLogin', {
      'mfaToken': mfaToken,
      'challengeId': _requiredString(begin, 'challengeId'),
      'response': platformResponse.toJson(),
    });
    return _requiredSession(data);
  }

  /// Computes verify password reset passkey.
  Future<void> verifyPasswordResetPasskey({required String resetToken}) async {
    _requirePasskeysEnabled();
    // Update cloud: create recovery passkey challenge
    final begin = await _call('beginPasswordResetPasskey', {
      'resetToken': resetToken,
    });
    final platformResponse = await _runPasskeyOperation(
      operation: 'authenticate for password reset',
      callback: () => _passkeys.authenticate(
        AuthenticateRequestType.fromJson(_requiredMap(begin, 'options')),
      ),
    );
    // Update cloud: verify recovery passkey
    await _call('finishPasswordResetPasskey', {
      'resetToken': resetToken,
      'challengeId': _requiredString(begin, 'challengeId'),
      'response': platformResponse.toJson(),
    });
  }

  /// Loads status.
  Future<MfaStatus> loadStatus() async {
    // Query enrolled MFA factors and status
    final data = await _call('getMfaStatus', const {});
    final rawFactors = data['factors'];
    final factors = rawFactors is List
        ? rawFactors
              .whereType<Map>()
              .map((factor) => _stringMap(factor))
              .map(
                (factor) => MfaFactor(
                  id: _requiredString(factor, 'id'),
                  type: _requiredString(factor, 'type'),
                  label: _requiredString(factor, 'label'),
                  createdAtLocal: factor['createdAtLocal'] as String?,
                ),
              )
              .toList()
        : <MfaFactor>[];
    return MfaStatus(
      required: data['required'] == true,
      factorCount: (data['factorCount'] as num?)?.toInt() ?? factors.length,
      methods: _stringList(data['methods']),
      factors: factors,
      canRemove: data['canRemove'] == true,
    );
  }

  /// Removes factor.
  Future<void> removeFactor(String factorId) async {
    // Update cloud: remove enrolled MFA factor
    await _call('removeMfaFactor', {'factorId': factorId});
  }

  /// Computes require passkeys enabled.
  void _requirePasskeysEnabled() {
    if (!nativePasskeysEnabledForBuild()) {
      throw const PasskeysUnavailableForBuildException();
    }
  }

  /// Computes run passkey operation.
  Future<T> _runPasskeyOperation<T>({
    required String operation,
    required Future<T> Function() callback,
  }) async {
    try {
      return await callback();
    } catch (error, stackTrace) {
      if (error is UnhandledAuthenticatorException) {
        debugPrint(
          'HikerCircle.Passkey $operation provider failure: '
          'code=${error.code}; message=${error.message}; '
          'details=${error.details}',
        );
        developer.log(
          'Android passkey $operation failed: code=${error.code}; '
          'message=${error.message}; details=${error.details}',
          name: 'HikerCircle.Passkey',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
      } else {
        developer.log(
          'Passkey $operation failed with ${error.runtimeType}: $error',
          name: 'HikerCircle.Passkey',
          error: error,
          stackTrace: stackTrace,
          level: 900,
        );
      }
      rethrow;
    }
  }

  /// Computes call.
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final result = await _functions.httpsCallable(name).call(data);
    if (result.data is! Map) {
      throw FirebaseFunctionsException(
        code: 'invalid-response',
        message: 'The security service returned invalid data.',
      );
    }
    return _stringMap(result.data as Map);
  }

  /// Computes session from token response.
  Future<AppSession?> _sessionFromTokenResponse(
    Map<String, dynamic> data,
  ) async {
    if (data['customToken'] == null) return null;
    return _requiredSession(data);
  }

  /// Accept the Firebase custom token only after the backend completes factor verification.
  Future<AppSession> _requiredSession(Map<String, dynamic> data) async {
    final customToken = _requiredString(data, 'customToken');
    final phoneNumber = _requiredString(data, 'phoneNumber');
    AuthFlowDiagnostics.event('firebase-custom-token-sign-in', 'start');
    final credential = await _auth.signInWithCustomToken(customToken);
    if (credential.user == null) {
      throw FirebaseAuthException(
        code: 'mfa-sign-in-failed',
        message: 'Firebase could not complete secure sign-in.',
      );
    }
    AuthFlowDiagnostics.event('firebase-custom-token-sign-in', 'success');
    return AppSession(phoneNumber: phoneNumber, signedInAt: DateTime.now());
  }

  /// Computes string map.
  static Map<String, dynamic> _stringMap(Map raw) => raw.map(
    (key, value) => MapEntry(
      key.toString(),
      value is Map
          ? _stringMap(value)
          : value is List
          ? value.map((item) => item is Map ? _stringMap(item) : item).toList()
          : value,
    ),
  );

  /// Computes required map.
  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    if (value is Map) return _stringMap(value);
    throw const FormatException('Missing security options.');
  }

  /// Computes required string.
  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Missing security field: $key');
  }

  /// Computes required int.
  static int _requiredInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num) return value.toInt();
    throw FormatException('Missing security field: $key');
  }

  /// Computes string list.
  static List<String> _stringList(Object? value) => value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const [];
}

/// Computes readable mfa error.
String readableMfaError(Object error) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? 'The security request could not be completed.';
  }
  if (error is FirebaseAuthException) {
    return error.message ?? 'Secure sign-in could not be completed.';
  }
  if (error is PasskeysUnavailableForBuildException) {
    return personalSigningPasskeyMessage;
  }
  if (error is PasskeyAuthCancelledException) {
    return 'The passkey request was cancelled.';
  }
  if (error is DomainNotAssociatedException) {
    return 'Passkeys are not yet associated with this app build.';
  }
  if (error is NoCredentialsAvailableException) {
    return 'No matching passkey is available on this device.';
  }
  if (error is DeviceNotSupportedException ||
      error is PasskeyUnsupportedException) {
    return 'This device does not support passkeys.';
  }
  if (error is TimeoutException) {
    return 'The passkey request timed out. Please try again.';
  }
  if (error is ExcludeCredentialsCanNotBeRegisteredException) {
    return 'This passkey is already registered on this device.';
  }
  if (error is MissingGoogleSignInException) {
    return 'Sign in to a Google account on this device to use passkeys.';
  }
  if (error is SyncAccountNotAvailableException) {
    return 'The passkey sync account is unavailable on this device.';
  }
  if (error is NoCreateOptionException) {
    return 'No passkey provider is enabled. Enable Google Password Manager or another credential provider in Android Settings.';
  }
  if (error is UnhandledAuthenticatorException) {
    final diagnostic = <String>[
      if (error.message?.trim().isNotEmpty == true) error.message!.trim(),
      if (error.details?.toString().trim().isNotEmpty == true)
        error.details.toString().trim(),
    ].join(' - ');
    final normalized = diagnostic.toLowerCase();
    if (normalized.contains('incoming request cannot be validated') ||
        normalized.contains('not associated')) {
      return 'Android could not validate HikerCircle for passkeys. Check your internet connection, update Google Play services, and try again.';
    }
    if (normalized.contains('sync account') ||
        normalized.contains('google account')) {
      return 'Google Password Manager could not access its sync account. Confirm that Google Password Manager sync is enabled and try again.';
    }
    if (normalized.contains('unable to create key') ||
        normalized.contains('key creation')) {
      return 'Android could not create the passkey after device verification. Restart the phone, confirm a screen lock is enabled, and retry.';
    }
    final safeCode = error.code.replaceAll(RegExp(r'[^A-Za-z0-9._:/-]'), '');
    return 'Android Credential Manager rejected the passkey request '
        '(${safeCode.isEmpty ? 'unknown-provider-error' : safeCode}). '
        'Update Google Play services and Google Password Manager, then retry.';
  }
  final text = error.toString().toLowerCase();
  if (text.contains('cancelled') || text.contains('canceled')) {
    return 'The passkey request was cancelled.';
  }
  if (text.contains('domain-not-associated') ||
      text.contains('not associated with domain')) {
    return 'Passkeys are not yet associated with this app build.';
  }
  if (text.contains('no-credentials')) {
    return 'No matching passkey is available on this device.';
  }
  return 'The security request could not be completed. Please try again.';
}

/// Computes requires recent mfa authentication.
bool requiresRecentMfaAuthentication(Object error) {
  if (error is! FirebaseFunctionsException ||
      error.code != 'failed-precondition') {
    return false;
  }
  if (error.details is Map &&
      (error.details as Map)['reason'] == 'recent-verification-required') {
    return true;
  }
  final message = (error.message ?? '').toLowerCase();
  return message.contains('sign in again before') &&
      message.contains('security method');
}
