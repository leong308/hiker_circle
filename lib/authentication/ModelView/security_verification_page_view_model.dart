part of '../security_verification_page_feature.dart';

/// Owns the state and non-visual actions of SecurityVerificationPage.
class _SecurityVerificationPageStateViewModel extends ChangeNotifier {
  /// Creates security verification page state view model.
  _SecurityVerificationPageStateViewModel({
    required this.readContinuation,
    required this.effectBeginBusy,
  });
  final MfaContinuation Function() readContinuation;
  final void Function(String message) effectBeginBusy;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final MultiFactorAuthService stateService;

  TotpEnrollment? stateTotpEnrollment;

  bool stateBusy = false;

  String? stateError;

  /// Returns command is enrollment.
  bool get commandIsEnrollment => readContinuation().enrollmentRequired;

  /// Ends busy.
  void commandEndBusy() {
    if (mounted) _publish(() => stateBusy = false);
  }

  /// Starts totp.
  Future<void> commandStartTotp() async {
    effectBeginBusy(
      commandIsEnrollment
          ? 'Setting up Authenticator…'
          : 'Opening Authenticator…',
    );
    try {
      if (commandIsEnrollment) {
        final enrollment = await stateService.beginTotpEnrollment(
          mfaToken: readContinuation().token,
        );
        if (!mounted) return;
        _publish(() => stateTotpEnrollment = enrollment);
      } else {
        _publish(
          () => stateTotpEnrollment = TotpEnrollment(
            challengeId: '',
            secret: '',
            otpauthUri: '',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          ),
        );
      }
    } catch (error) {
      if (mounted) _publish(() => stateError = readableMfaError(error));
    } finally {
      commandEndBusy();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final void Function(AppSession session) effectPresentUsePasskeyEffect1;

  /// Computes use passkey.
  Future<void> commandUsePasskey() async {
    effectBeginBusy(
      commandIsEnrollment
          ? 'Creating your passkey…'
          : 'Verifying your passkey…',
    );
    try {
      final session = commandIsEnrollment
          ? await stateService.enrollPasskey(
              mfaToken: readContinuation().token,
              label: 'Mobile passkey',
            )
          : await stateService.verifyPasskeyLogin(
              mfaToken: readContinuation().token,
            );
      if (session == null) throw StateError('Secure sign-in did not finish.');
      if (mounted) effectPresentUsePasskeyEffect1(session);
    } catch (error) {
      if (mounted) _publish(() => stateError = readableMfaError(error));
    } finally {
      commandEndBusy();
    }
  }
}
