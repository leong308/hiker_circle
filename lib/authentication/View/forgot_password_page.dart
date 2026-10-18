// ForgotPasswordPage guides phone OTP, recovery method verification and password replacement.
import '../../core/widgets/password_capture_protection.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/page_header_style.dart';
import '../../core/widgets/verification_code_input.dart';

import '../Data/passkey_build_support.dart';
import '../ModelView/auth_view_model.dart';
import 'inline_notice.dart';

/// Recovery advances from phone OTP to an available security factor, then to the new password.
enum _ResetStep { phone, otp, method, question, authenticator, newPassword }

class _ResetPasswordHeader extends StatelessWidget {
  const _ResetPasswordHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          PageHeaderAction(
            tooltip: 'Back',
            icon: CupertinoIcons.chevron_back,
            onPressed: onBack,
            color: scheme.primary,
            surface: scheme.surfaceContainerHigh,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reset password',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.title(context, scheme.onSurface),
                ),
                Text(
                  'Verify your identity and secure your account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, required this.viewModel});

  final AuthViewModel viewModel;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _answerController = TextEditingController();
  final _authenticatorController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _loadingOverlayController = OverlayPortalController(
    debugLabel: 'reset-password-loading',
  );
  _ResetStep _step = _ResetStep.phone;
  String? _completedRecoveryMethod;
  Timer? _resendCooldownTimer;
  int _resendSecondsRemaining = 0;
  String? _loadingMessageOverride;
  bool _isProcessing = false;
  int _codeAttempt = 0;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _answerController.dispose();
    _authenticatorController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  AuthViewModel get _vm => widget.viewModel;

  void _setProcessing(bool value, {String? message}) {
    if (!mounted) return;
    setState(() {
      _isProcessing = value;
      _loadingMessageOverride = value ? message : null;
    });
    if (value) {
      _loadingOverlayController.show();
    } else {
      _loadingOverlayController.hide();
    }
  }

  void _startResendCooldown() {
    _resendCooldownTimer?.cancel();
    setState(() => _resendSecondsRemaining = 60);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
      } else {
        setState(() => _resendSecondsRemaining--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    await _vm.sendPasswordResetCode(_phoneController.text);
    if (!mounted) return;
    _setProcessing(false);
    if (_vm.resetChallengeId != null) {
      _otpController.clear();
      setState(() => _step = _ResetStep.otp);
      _startResendCooldown();
    }
  }

  Future<void> _resendCode() async {
    if (_isProcessing || _resendSecondsRemaining > 0) return;
    FocusScope.of(context).unfocus();
    _setProcessing(true, message: 'Sending a new reset code…');
    final sent = await _vm.resendPasswordResetCode(_phoneController.text);
    if (!mounted) return;
    _setProcessing(false);
    if (sent) {
      _otpController.clear();
      _startResendCooldown();
    }
  }

  Future<void> _verifyOtp() async {
    if (_isProcessing ||
        !RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim())) {
      return;
    }
    final attempt = ++_codeAttempt;
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    final ok = await _vm.verifyPasswordResetOtp(_otpController.text);
    if (!mounted || attempt != _codeAttempt) return;
    if (!ok) _otpController.clear();
    _setProcessing(false);
    if (ok) {
      setState(() => _step = _ResetStep.method);
    }
  }

  Future<void> _answerQuestion() async {
    if (_answerController.text.trim().length < 2) {
      _vm.clearMessages();
      return;
    }
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    final ok = await _vm.checkSafetyAnswer(_answerController.text.trim());
    if (!mounted) return;
    _setProcessing(false);
    setState(() {
      if (ok) {
        _completedRecoveryMethod = 'Secret Question';
        _step = _ResetStep.newPassword;
      }
    });
  }

  Future<void> _verifyAuthenticator() async {
    if (_isProcessing) return;
    final code = _authenticatorController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the current 6-digit Authenticator code.'),
        ),
      );
      return;
    }
    final attempt = ++_codeAttempt;
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    final ok = await _vm.verifyPasswordResetTotp(code);
    if (!mounted || attempt != _codeAttempt) return;
    if (!ok) _authenticatorController.clear();
    _setProcessing(false);
    setState(() {
      if (ok) {
        _completedRecoveryMethod = 'Authenticator';
        _step = _ResetStep.newPassword;
      }
    });
  }

  Future<void> _verifyPasskey() async {
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    final ok = await _vm.verifyPasswordResetPasskey();
    if (!mounted) return;
    _setProcessing(false);
    setState(() {
      if (ok) {
        _completedRecoveryMethod = 'Passkey';
        _step = _ResetStep.newPassword;
      }
    });
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _setProcessing(true);
    final ok = await _vm.resetPassword(_newPasswordController.text);
    if (!mounted) return;
    _setProcessing(false);
    if (ok) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Password Reset'),
          content: const Text(
            'Your password has been reset. You can now sign in with your new password.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx)
                ..pop()
                ..pop(),
              child: const Text('Sign In'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) =>
      PasswordCaptureProtection(child: _buildPasswordPage(context));

  Widget _buildPasswordPage(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return OverlayPortal(
      controller: _loadingOverlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) => HikerCircleLoadingToastOverlay(
        message:
            _loadingMessageOverride ??
            switch (_step) {
              _ResetStep.phone => 'Sending reset code…',
              _ResetStep.otp => 'Verifying reset code…',
              _ResetStep.method => 'Verifying your passkey…',
              _ResetStep.question => 'Checking your answer…',
              _ResetStep.authenticator => 'Checking your Authenticator code…',
              _ResetStep.newPassword => 'Resetting your password…',
            },
        detail: 'Updating your account securely. This may take a moment.',
        timeout: const Duration(seconds: 30),
        onTimeout: () {
          if (_step == _ResetStep.otp || _step == _ResetStep.authenticator) {
            _codeAttempt++;
          }
          if (_step == _ResetStep.otp) _otpController.clear();
          if (_step == _ResetStep.authenticator) {
            _authenticatorController.clear();
          }
          _setProcessing(false);
        },
      ),
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ResetPasswordHeader(
                            onBack: () {
                              _vm.clearResetState();
                              Navigator.of(context).pop();
                            },
                          ),
                          const SizedBox(height: 24),
                          _buildStepIndicator(scheme),
                          const SizedBox(height: 24),
                          if (_step == _ResetStep.phone) ...[
                            Text(
                              'Enter your phone number to receive a password reset code via WhatsApp.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                hintText: '012 345 6789',
                                prefixIcon: Icon(Icons.phone_iphone),
                              ),
                              validator: _vm.validatePhone,
                              onFieldSubmitted: (_) => _sendCode(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _isProcessing ? null : _sendCode,
                              icon: const Icon(Icons.send),
                              label: const Text('Send Reset Code'),
                            ),
                          ],
                          if (_step == _ResetStep.otp) ...[
                            Text(
                              'Enter the 6-digit code sent via WhatsApp.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            VerificationCodeInput(
                              controller: _otpController,
                              enabled: !_isProcessing,
                              semanticLabel: 'Password reset verification code',
                              onCompleted: (_) => _verifyOtp(),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Didn\'t receive the code?',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton(
                                  onPressed:
                                      _isProcessing ||
                                          _resendSecondsRemaining > 0
                                      ? null
                                      : _resendCode,
                                  child: Text(
                                    _resendSecondsRemaining > 0
                                        ? 'Resend in ${_resendSecondsRemaining}s'
                                        : 'Resend code',
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_step == _ResetStep.method) ...[
                            Text(
                              'Choose a verification method',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Only security methods already bound to this account are shown.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_vm.resetRecoveryMethods.isEmpty)
                              InlineNotice(
                                icon: Icons.gpp_bad_outlined,
                                color: scheme.error,
                                text:
                                    'No recovery method is bound to this account. Your password cannot be reset from this device.',
                              ),
                            if (_vm.resetRecoveryMethods.contains(
                              'secretQuestion',
                            ))
                              _buildRecoveryMethodCard(
                                theme: theme,
                                scheme: scheme,
                                icon: Icons.help_outline_rounded,
                                title: 'Secret Question',
                                subtitle:
                                    'Answer one of the secret questions saved on your account.',
                                onTap: () =>
                                    setState(() => _step = _ResetStep.question),
                              ),
                            if (_vm.resetRecoveryMethods.contains('totp'))
                              _buildRecoveryMethodCard(
                                theme: theme,
                                scheme: scheme,
                                icon: Icons.password_rounded,
                                title: 'Authenticator',
                                subtitle:
                                    'Enter the current 6-digit code from your authenticator app.',
                                onTap: () => setState(
                                  () => _step = _ResetStep.authenticator,
                                ),
                              ),
                            if (_vm.resetRecoveryMethods.contains('passkey'))
                              _buildRecoveryMethodCard(
                                theme: theme,
                                scheme: scheme,
                                icon: Icons.fingerprint_rounded,
                                title: 'Passkey',
                                subtitle: nativePasskeysEnabledForBuild()
                                    ? 'Verify with your device screen lock, fingerprint, or face.'
                                    : 'Passkeys are bound to this account but unavailable in this app build.',
                                onTap: nativePasskeysEnabledForBuild()
                                    ? _verifyPasskey
                                    : null,
                              ),
                          ],
                          if (_step == _ResetStep.question) ...[
                            Text(
                              'Answer your safety question to proceed.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.help_outline,
                                    color: scheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _vm.resetQuestionText ?? '',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSecondaryContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _answerController,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Your answer',
                                prefixIcon: Icon(Icons.edit),
                              ),
                              onFieldSubmitted: (_) => _answerQuestion(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _isProcessing ? null : _answerQuestion,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Continue'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () => setState(
                                      () => _step = _ResetStep.method,
                                    ),
                              child: const Text('Choose another method'),
                            ),
                          ],
                          if (_step == _ResetStep.authenticator) ...[
                            Text(
                              'Verify with Authenticator',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter the current 6-digit code. It refreshes every 30 seconds.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 18),
                            VerificationCodeInput(
                              controller: _authenticatorController,
                              enabled: !_isProcessing,
                              semanticLabel: 'Authenticator code',
                              onCompleted: (_) => _verifyAuthenticator(),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () => setState(
                                      () => _step = _ResetStep.method,
                                    ),
                              child: const Text('Choose another method'),
                            ),
                          ],
                          if (_step == _ResetStep.newPassword) ...[
                            Text(
                              'Set a new password for your account.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _newPasswordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'New password',
                                prefixIcon: const Icon(Icons.key),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.length < 8) {
                                  return 'Password must be at least 8 characters.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Confirm new password',
                                prefixIcon: const Icon(Icons.key),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (v != _newPasswordController.text) {
                                  return 'Passwords do not match.';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _resetPassword(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _isProcessing ? null : _resetPassword,
                              icon: const Icon(Icons.lock_reset),
                              label: const Text('Reset Password'),
                            ),
                          ],
                          if (_vm.message != null) ...[
                            const SizedBox(height: 16),
                            InlineNotice(
                              icon: Icons.check_circle_outline,
                              color: scheme.primary,
                              text: _vm.message!,
                            ),
                          ],
                          if (_vm.error != null) ...[
                            const SizedBox(height: 16),
                            InlineNotice(
                              icon: Icons.error_outline,
                              color: scheme.error,
                              text: _vm.error!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(ColorScheme scheme) {
    const stepCount = 4;
    final currentIndex = switch (_step) {
      _ResetStep.phone => 0,
      _ResetStep.otp => 1,
      _ResetStep.method || _ResetStep.question || _ResetStep.authenticator => 2,
      _ResetStep.newPassword => 3,
    };

    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const circleSize = 28.0;
          const tapTargetSize = 40.0;
          final trackWidth = constraints.maxWidth - tapTargetSize;
          final completedWidth = trackWidth * currentIndex / (stepCount - 1);

          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: tapTargetSize / 2,
                right: tapTargetSize / 2,
                child: Container(height: 2, color: scheme.outlineVariant),
              ),
              Positioned(
                left: tapTargetSize / 2,
                width: completedWidth,
                child: Container(height: 2, color: scheme.primary),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(stepCount, (i) {
                  final isActive = i == currentIndex;
                  final isPast = i < currentIndex;
                  return Tooltip(
                    message: _stepTooltip(i, currentIndex),
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 4),
                    textAlign: TextAlign.center,
                    child: SizedBox(
                      width: tapTargetSize,
                      height: tapTargetSize,
                      child: Center(
                        child: Container(
                          width: circleSize,
                          height: circleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? scheme.primary
                                : isPast
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                          ),
                          child: Center(
                            child: isPast
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: scheme.onPrimaryContainer,
                                  )
                                : Text(
                                    (i + 1).toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isActive
                                          ? scheme.onPrimary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  String _stepTooltip(int index, int currentIndex) {
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
        final method = _completedRecoveryMethod ?? 'a bound recovery method';
        return 'Step 3 complete\nIdentity verified with $method.';
      }
      if (index == currentIndex) {
        return switch (_step) {
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

  Widget _buildRecoveryMethodCard({
    required ThemeData theme,
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: enabled
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  enabled
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
