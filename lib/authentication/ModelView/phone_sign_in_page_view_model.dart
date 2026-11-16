part of '../phone_sign_in_page_feature.dart';

/// Owns the state and non-visual actions of PhoneSignInPage.
class _PhoneSignInPageStateViewModel extends ChangeNotifier {
  /// Creates phone sign in page state view model.
  _PhoneSignInPageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  /// Refreshes.
  void commandRefresh() {
    if (mounted) {
      _publish(() {});
    }
  }

  /// Computes friendly sign in error.
  String commandFriendlySignInError(Object error) =>
      signInCompletionErrorMessage(error);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function(AppSession session) Function()
  readOnSignedIn;

  late final void Function() effectResetOtpEntry;

  late final Future<bool?> Function(String previous)
  effectPresentCompleteSignInEffect1;

  late final void Function(bool visible) effectSetLoadingOverlayVisible;

  late final Future<void> Function() effectPresentOpenForgotPasswordEffect1;
  late final Future<void> Function(String phoneNumber) effectSyncPrivacyConsent;

  bool stateIsCompletingSignIn = false;

  String? stateSignInError;

  /// Opens forgot password.
  Future<void> commandOpenForgotPassword() async {
    await effectPresentOpenForgotPasswordEffect1();
  }

  /// Computes complete sign in.
  Future<void> commandCompleteSignIn(AppSession session) async {
    if (stateIsCompletingSignIn) {
      return;
    }

    _publish(() {
      stateIsCompletingSignIn = true;
      stateSignInError = null;
    });
    effectSetLoadingOverlayVisible(true);

    var stage = 'prepare-mobile-session';
    try {
      AuthFlowDiagnostics.event(stage, 'start');
      final login = await MobileSecurityService.prepareLogin();
      AuthFlowDiagnostics.event(stage, 'success');
      if (!mounted) return;
      if (login['replacementRequired'] == true) {
        effectSetLoadingOverlayVisible(false);
        final previous =
            login['previousDeviceName'] as String? ?? 'another phone';
        final confirmed = await effectPresentCompleteSignInEffect1(previous);
        if (confirmed != true) {
          await FirebaseAuth.instance.signOut();
          if (mounted) effectResetOtpEntry();
          return;
        }
        effectSetLoadingOverlayVisible(true);
      }
      stage = 'activate-mobile-session';
      AuthFlowDiagnostics.event(stage, 'start');
      await MobileSecurityService.activateLogin(
        login['expectedPreviousSessionId'] as String? ?? '',
      );
      AuthFlowDiagnostics.event(stage, 'success');
      // Pre-sign-up acceptance stays local until this account is authenticated
      // and owns an active mobile session. A failure remains queued for recovery.
      unawaited(
        effectSyncPrivacyConsent(session.phoneNumber).catchError((Object _) {}),
      );
      stage = 'persist-app-session';
      AuthFlowDiagnostics.event(stage, 'start');
      await readOnSignedIn()(session);
      AuthFlowDiagnostics.event(stage, 'success');
    } catch (error) {
      AuthFlowDiagnostics.event(stage, 'failure', error: error);
      if (!mounted) {
        return;
      }
      // WhatsApp verification has already consumed this challenge. Release the
      // form for a fresh login instead of leaving its fields/button disabled.
      effectResetOtpEntry();
      _publish(() {
        stateSignInError = commandFriendlySignInError(error);
      });
    } finally {
      if (mounted) {
        effectSetLoadingOverlayVisible(false);
        _publish(() {
          stateIsCompletingSignIn = false;
        });
      }
    }
  }
}
