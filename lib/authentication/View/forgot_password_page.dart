import 'package:flutter/material.dart';

import '../ModelView/auth_view_model.dart';
import 'auth_brand_panel.dart';
import 'inline_notice.dart';

enum _ResetStep { phone, otp, question, newPassword }

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
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _ResetStep _step = _ResetStep.phone;
  bool _isProcessing = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _answerController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  AuthViewModel get _vm => widget.viewModel;

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    await _vm.sendPasswordResetCode(_phoneController.text);
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      if (_vm.resetChallengeId != null) {
        _step = _ResetStep.otp;
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    final ok = await _vm.verifyPasswordResetOtp(_otpController.text);
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      if (ok) {
        _step = _vm.resetSkipQuestion
            ? _ResetStep.newPassword
            : _ResetStep.question;
      }
    });
  }

  Future<void> _answerQuestion() async {
    if (_answerController.text.trim().length < 2) {
      _vm.clearMessages();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    final ok = await _vm.checkSafetyAnswer(_answerController.text.trim());
    if (!mounted) return;
    setState(() => _isProcessing = false);
    if (ok) {
      setState(() => _step = _ResetStep.newPassword);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);
    final ok = await _vm.resetPassword(
      _answerController.text.trim(),
      _newPasswordController.text,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);
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
              onPressed: () => Navigator.of(ctx)..pop()..pop(),
              child: const Text('Sign In'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _vm.clearResetState();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthBrandPanel(color: scheme.primary),
                    const SizedBox(height: 24),
                    _buildStepIndicator(theme, scheme),
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
                        icon: _isProcessing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
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
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: 'Verification code',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        onFieldSubmitted: (_) => _verifyOtp(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isProcessing ? null : _verifyOtp,
                        icon: _isProcessing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_user),
                        label: const Text('Verify Code'),
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
                            Icon(Icons.help_outline,
                                color: scheme.onSecondaryContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _vm.resetQuestionText ?? '',
                                style: theme.textTheme.bodyMedium?.copyWith(
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
                        onPressed: _answerQuestion,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue'),
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
                                () => _obscurePassword = !_obscurePassword),
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
                                () => _obscureConfirm = !_obscureConfirm),
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
                        icon: _isProcessing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_reset),
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
    );
  }

  Widget _buildStepIndicator(ThemeData theme, ColorScheme scheme) {
    const steps = [
      _ResetStep.phone,
      _ResetStep.otp,
      _ResetStep.question,
      _ResetStep.newPassword,
    ];
    final currentIndex = steps.indexOf(_step);

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == currentIndex;
        final isPast = i < currentIndex;
        return Expanded(
          child: Row(
            children: [
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isPast || isActive
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
              Container(
                width: 28,
                height: 28,
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
                      ? Icon(Icons.check, size: 16, color: scheme.onPrimaryContainer)
                      : Text(
                          '${i + 1}',
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
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isPast
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
