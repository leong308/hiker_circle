part of '../forgot_password_page_feature.dart';

/// Owns the state and non-visual actions of ForgotPasswordPage.
class _ForgotPasswordPageStateViewModel extends ChangeNotifier {
  /// Creates forgot password page state view model.
  _ForgotPasswordPageStateViewModel({required this.readViewModel});
  final AuthViewModel Function() readViewModel;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  _ResetStep stateStep = _ResetStep.phone;

  String? stateCompletedRecoveryMethod;

  Timer? stateResendCooldownTimer;

  int stateResendSecondsRemaining = 0;

  /// Returns command vm.
  AuthViewModel get commandVm => readViewModel();

  /// Starts resend cooldown.
  void commandStartResendCooldown() {
    stateResendCooldownTimer?.cancel();
    _publish(() => stateResendSecondsRemaining = 60);
    stateResendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (stateResendSecondsRemaining <= 1) {
        timer.cancel();
        _publish(() => stateResendSecondsRemaining = 0);
      } else {
        _publish(() => stateResendSecondsRemaining--);
      }
    });
  }

  /// Computes step tooltip.
  String commandStepTooltip(int index, int currentIndex) {
    if (index == 0) {
      return index < currentIndex
          ? 'Step 1 complete\nPhone number confirmed and reset code sent.'
          : 'Step 1 of 4\nEnter the account phone number.';
    }
    if (index == 1) {
      if (index < currentIndex) {
        return 'Step 2 complete\nWhatsApp reset code verified.';
      }
      return index == currentIndex
          ? 'Step 2 of 4\nVerify the reset code sent through WhatsApp.'
          : 'Step 2 of 4\nWhatsApp reset-code verification.';
    }
    if (index == 2) {
      if (index < currentIndex) {
        final method =
            stateCompletedRecoveryMethod ?? 'a bound recovery method';
        return 'Step 3 complete\nIdentity verified with $method.';
      }
      if (index == currentIndex) {
        return switch (stateStep) {
          _ResetStep.question =>
            'Step 3 of 4\nVerify with your Secret Question.',
          _ResetStep.authenticator =>
            'Step 3 of 4\nVerify with your Authenticator code.',
          _ => 'Step 3 of 4\nChoose a bound identity-verification method.',
        };
      }
      return 'Step 3 of 4\nAdditional identity verification.';
    }
    return index == currentIndex
        ? 'Step 4 of 4\nCreate and confirm your new password.'
        : 'Step 4 of 4\nSet a new password.';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
