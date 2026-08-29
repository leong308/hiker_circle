import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../../app/Model/app_session.dart';
import '../Model/mfa_models.dart';
import 'passkey_build_support.dart';

class MultiFactorAuthService {
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

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  Future<TotpEnrollment> beginTotpEnrollment({String? mfaToken}) async {
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

  Future<AppSession?> finishTotpEnrollment({
    required String challengeId,
    required String code,
    String? mfaToken,
  }) async {
    final data = await _call('finishTotpEnrollment', {
      'challengeId': challengeId,
      'code': code,
      if (mfaToken != null) 'mfaToken': mfaToken,
    });
    return _sessionFromTokenResponse(data);
  }

  Future<AppSession?> enrollPasskey({String? mfaToken, String? label}) async {
    _requirePasskeysEnabled();
    final begin = await _call(
      'beginPasskeyEnrollment',
      mfaToken == null ? const {} : {'mfaToken': mfaToken},
    );
    final options = _requiredMap(begin, 'options');
    final platformResponse = await _passkeys.register(
      RegisterRequestType.fromJson(options),
    );
    final completed = await _call('finishPasskeyEnrollment', {
      'challengeId': _requiredString(begin, 'challengeId'),
      'response': platformResponse.toJson(),
      if (mfaToken != null) 'mfaToken': mfaToken,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    return _sessionFromTokenResponse(completed);
  }

  Future<AppSession> verifyTotpLogin({
    required String mfaToken,
    required String code,
  }) async {
    final data = await _call('verifyTotpLogin', {
      'mfaToken': mfaToken,
      'code': code,
    });
    return _requiredSession(data);
  }

  Future<AppSession> verifyPasskeyLogin({required String mfaToken}) async {
    _requirePasskeysEnabled();
    final begin = await _call('beginPasskeyLogin', {'mfaToken': mfaToken});
    final platformResponse = await _passkeys.authenticate(
      AuthenticateRequestType.fromJson(_requiredMap(begin, 'options')),
    );
    final data = await _call('finishPasskeyLogin', {
      'mfaToken': mfaToken,
      'challengeId': _requiredString(begin, 'challengeId'),
      'response': platformResponse.toJson(),
    });
    return _requiredSession(data);
  }

  Future<MfaStatus> loadStatus() async {
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

  Future<void> removeFactor(String factorId) async {
    await _call('removeMfaFactor', {'factorId': factorId});
  }

  void _requirePasskeysEnabled() {
    if (!nativePasskeysEnabledForBuild()) {
      throw const PasskeysUnavailableForBuildException();
    }
  }

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

  Future<AppSession?> _sessionFromTokenResponse(
    Map<String, dynamic> data,
  ) async {
    if (data['customToken'] == null) return null;
    return _requiredSession(data);
  }

  Future<AppSession> _requiredSession(Map<String, dynamic> data) async {
    final customToken = _requiredString(data, 'customToken');
    final phoneNumber = _requiredString(data, 'phoneNumber');
    final credential = await _auth.signInWithCustomToken(customToken);
    if (credential.user == null) {
      throw FirebaseAuthException(
        code: 'mfa-sign-in-failed',
        message: 'Firebase could not complete secure sign-in.',
      );
    }
    return AppSession(phoneNumber: phoneNumber, signedInAt: DateTime.now());
  }

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

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    if (value is Map) return _stringMap(value);
    throw const FormatException('Missing security options.');
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Missing security field: $key');
  }

  static int _requiredInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is num) return value.toInt();
    throw FormatException('Missing security field: $key');
  }

  static List<String> _stringList(Object? value) => value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const [];
}

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
