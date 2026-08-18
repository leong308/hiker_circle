import 'package:flutter/material.dart';

import '../../app/Data/session_repository.dart';
import '../../app/Model/app_session.dart';
import '../Model/auth_status.dart';
import '../ModelView/auth_view_model.dart';
import 'auth_brand_panel.dart';
import 'forgot_password_page.dart';
import 'inline_notice.dart';

class PhoneSignInPage extends StatefulWidget {
  const PhoneSignInPage({super.key, required this.onSignedIn});

  final Future<void> Function(AppSession session) onSignedIn;

  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends State<PhoneSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AuthViewModel _viewModel;
  bool _isCompletingSignIn = false;
  bool _obscurePassword = true;
  String? _signInError;

  @override
  void initState() {
    super.initState();
    _viewModel = AuthViewModel(onAutomaticallyVerified: _completeSignIn);
    _viewModel.addListener(_refresh);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    _viewModel.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await _viewModel.sendCode(_phoneController.text);
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.trim().length != 6) {
      return;
    }
    FocusScope.of(context).unfocus();
    final session = await _viewModel.verifyOtp(_otpController.text);
    if (session != null) {
      await _completeSignIn(session);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final session = await _viewModel.loginWithPassword(
      _phoneController.text,
      _passwordController.text,
    );
    if (session != null) {
      await _completeSignIn(session);
    }
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ForgotPasswordPage(viewModel: _viewModel),
      ),
    );
  }

  Future<void> _completeSignIn(AppSession session) async {
    if (_isCompletingSignIn) {
      return;
    }

    setState(() {
      _isCompletingSignIn = true;
      _signInError = null;
    });

    try {
      await widget.onSignedIn(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _signInError = _friendlySignInError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCompletingSignIn = false;
        });
      }
    }
  }

  String _friendlySignInError(Object error) {
    if (error is SessionRepositoryException) {
      return error.message;
    }
    return 'Unable to finish login. Please check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSignUp = _viewModel.authMode == AuthMode.signUp;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthBrandPanel(color: scheme.primary),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFCFE5D6),
                              ),
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    isSignUp ? 'Sign Up' : 'Login',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isSignUp
                                        ? 'Verify your phone via WhatsApp OTP.'
                                        : 'Sign in with your phone number and password.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _ModeToggle(
                                    currentMode: _viewModel.authMode,
                                    enabled:
                                        !_viewModel.isBusy &&
                                        !_isCompletingSignIn &&
                                        !_viewModel.hasCodeBeenSent,
                                    onChanged: _viewModel.setAuthMode,
                                  ),
                                  const SizedBox(height: 16),
                                  if (isSignUp) ...[
                                    _buildSignUpForm(theme, scheme),
                                  ] else ...[
                                    _buildLoginForm(theme, scheme),
                                  ],
                                  if (_viewModel.message != null) ...[
                                    const SizedBox(height: 16),
                                    InlineNotice(
                                      icon: Icons.check_circle_outline,
                                      color: scheme.primary,
                                      text: _viewModel.message!,
                                    ),
                                  ],
                                  if (_viewModel.error != null) ...[
                                    const SizedBox(height: 16),
                                    InlineNotice(
                                      icon: Icons.error_outline,
                                      color: scheme.error,
                                      text: _viewModel.error!,
                                    ),
                                  ],
                                  if (_signInError != null) ...[
                                    const SizedBox(height: 16),
                                    InlineNotice(
                                      icon: Icons.error_outline,
                                      color: scheme.error,
                                      text: _signInError!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSignUpForm(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          enabled:
              !_viewModel.isBusy &&
              !_isCompletingSignIn &&
              !_viewModel.hasCodeBeenSent,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '012 345 6789',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
          validator: _viewModel.validatePhone,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _viewModel.isSendingCode || _isCompletingSignIn
              ? null
              : _sendCode,
          icon: _viewModel.isSendingCode
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _viewModel.hasCodeBeenSent
                      ? Icons.refresh
                      : Icons.message_outlined,
                ),
          label: Text(_viewModel.hasCodeBeenSent ? 'Resend OTP' : 'Send OTP'),
        ),
        if (_viewModel.hasCodeBeenSent) ...[
          const SizedBox(height: 18),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            enabled: !_viewModel.isBusy && !_isCompletingSignIn,
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'Verification code',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            onFieldSubmitted: (_) => _verifyOtp(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _viewModel.isVerifyingCode || _isCompletingSignIn
                ? null
                : _verifyOtp,
            icon: _viewModel.isVerifyingCode || _isCompletingSignIn
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user),
            label: const Text('Verify and continue'),
          ),
          const SizedBox(height: 6),
          Text(
            'Code delivered by WhatsApp',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginForm(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          enabled: !_viewModel.isBusy && !_isCompletingSignIn,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '012 345 6789',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
          validator: _viewModel.validatePhone,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          enabled: !_viewModel.isBusy && !_isCompletingSignIn,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Enter your password.';
            }
            return null;
          },
          onFieldSubmitted: (_) => _login(),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _viewModel.isBusy || _isCompletingSignIn
                ? null
                : _openForgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _viewModel.isLoggingIn || _isCompletingSignIn
              ? null
              : _login,
          icon: _viewModel.isLoggingIn || _isCompletingSignIn
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: const Text('Login'),
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.currentMode,
    required this.enabled,
    required this.onChanged,
  });

  final AuthMode currentMode;
  final bool enabled;
  final void Function(AuthMode) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ToggleButton(
            label: 'Sign Up',
            isSelected: currentMode == AuthMode.signUp,
            enabled: enabled,
            onTap: () => onChanged(AuthMode.signUp),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ToggleButton(
            label: 'Login',
            isSelected: currentMode == AuthMode.login,
            enabled: enabled,
            onTap: () => onChanged(AuthMode.login),
          ),
        ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isSelected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? scheme.primary : const Color(0xFFCFE5D6),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
