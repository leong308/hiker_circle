part of '../security_methods_page_feature.dart';

/// Owns the state and non-visual actions of SecurityMethodsPage.
class _SecurityMethodsPageStateViewModel extends ChangeNotifier {
  /// Creates security methods page state view model.
  _SecurityMethodsPageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final MultiFactorAuthService stateService;

  late Future<MfaStatus> stateStatusFuture;

  /// Computes reload.
  void commandReload() {
    if (!mounted) return;
    final statusFuture = stateService.loadStatus();
    _publish(() {
      stateStatusFuture = statusFuture;
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final void Function() effectPresentAddPasskeyEffect1;

  late final Future<bool?> Function(TotpEnrollment enrollment)
  effectPresentAddAuthenticatorEffect1;

  late final void Function() effectPresentRemoveEffect1;

  late final void Function(Object error) effectShowError;

  late final Future<bool?> Function(String phoneNumber)
  effectPresentVerifyRecentLoginEffect1;

  late final Future<bool?> Function(MfaFactor factor)
  effectPresentRemoveEffect2;

  bool stateBusy = false;

  /// Adds passkey.
  Future<void> commandAddPasskey() async {
    _publish(() => stateBusy = true);
    try {
      try {
        await stateService.enrollPasskey(label: 'Mobile passkey');
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await commandVerifyRecentLogin();
        if (!verified) return;
        await stateService.enrollPasskey(label: 'Mobile passkey');
      }
      if (!mounted) return;
      effectPresentAddPasskeyEffect1();
      commandReload();
    } catch (error) {
      effectShowError(error);
    } finally {
      if (mounted) _publish(() => stateBusy = false);
    }
  }

  /// Require recent security verification before applying sensitive enrolled-factor changes.
  Future<bool> commandVerifyRecentLogin() async {
    final phoneNumber = await stateService.authenticatedPhoneNumber();
    if (!mounted) return false;
    return await effectPresentVerifyRecentLoginEffect1(phoneNumber) == true;
  }

  /// Adds authenticator.
  Future<void> commandAddAuthenticator() async {
    _publish(() => stateBusy = true);
    TotpEnrollment enrollment;
    try {
      try {
        enrollment = await stateService.beginTotpEnrollment();
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await commandVerifyRecentLogin();
        if (!verified) return;
        enrollment = await stateService.beginTotpEnrollment();
      }
    } catch (error) {
      effectShowError(error);
      return;
    } finally {
      if (mounted) _publish(() => stateBusy = false);
    }
    if (!mounted) return;
    final added = await effectPresentAddAuthenticatorEffect1(enrollment);
    // Back or a UI timeout can hide a factor already committed by the server.
    // Successful enrollment refreshes through onEnrolled, including late replies.
    if (added != true) commandReload();
  }

  /// Honor the current factor-removal rule and refresh enrollment state after the backend accepts removal.
  Future<void> commandRemove(MfaFactor factor, bool canRemove) async {
    if (!canRemove) {
      effectPresentRemoveEffect1();
      return;
    }
    final confirmed = await effectPresentRemoveEffect2(factor);
    if (confirmed != true) return;
    _publish(() => stateBusy = true);
    try {
      try {
        await stateService.removeFactor(factor.id);
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await commandVerifyRecentLogin();
        if (!verified) return;
        await stateService.removeFactor(factor.id);
      }
      commandReload();
    } catch (error) {
      effectShowError(error);
    } finally {
      if (mounted) _publish(() => stateBusy = false);
    }
  }
}
