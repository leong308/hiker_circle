import 'mfa_models.dart';

/// Describes available login protection without changing enrollment policy.
class SecurityMethodsPresentation {
  /// Builds concise labels from the server's enrollment status.
  SecurityMethodsPresentation(this.status, {required this.passkeysEnabled});

  final MfaStatus status;
  final bool passkeysEnabled;

  /// Whether the account already has an authenticator method.
  bool get hasAuthenticator => status.methods.contains('totp');

  /// Whether a passkey is already enrolled, including on another device.
  bool get hasPasskey => status.methods.contains('passkey');

  /// Keeps each supported enrollment action available once per method type.
  bool get canAddAuthenticator => !hasAuthenticator;

  /// Respects the existing native passkey capability gate.
  bool get canAddPasskey => !hasPasskey && passkeysEnabled;

  /// Names the current protection state using actual enrolled factors.
  String get title =>
      status.factorCount > 0 ? 'Your login is protected' : 'Protect your login';

  /// Explains the existing requirement to keep a verification method enrolled.
  String get description => status.factorCount > 0
      ? 'Keep at least one verification method set up for your account.'
      : 'Add a verification method to keep your account secure.';

  /// Counts actual factors rather than presenting a progress target.
  String get countLabel =>
      '${status.factorCount} '
      '${status.factorCount == 1 ? 'method' : 'methods'} set up';
}
