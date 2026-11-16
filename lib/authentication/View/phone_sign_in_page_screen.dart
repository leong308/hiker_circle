part of '../phone_sign_in_page_feature.dart';

/// Keep the login/register card state while routing OTP and any required security verification.
class PhoneSignInPage extends StatefulWidget {
  /// Creates phone sign in page.
  const PhoneSignInPage({
    super.key,
    required this.onSignedIn,
    AuthViewModel? viewModel,
    this.privacyConsentRepository,
  }) : _viewModel = viewModel;

  final Future<void> Function(AppSession session) onSignedIn;
  final AuthViewModel? _viewModel;
  final PrivacyConsentRepository? privacyConsentRepository;

  /// Creates the presentation state for this widget.
  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

/// Manages the phone sign in page presentation and lifecycle.
class _PhoneSignInPageState extends State<PhoneSignInPage> {
  /// Returns is completing sign in.
  bool get _isCompletingSignIn => _screenModel.stateIsCompletingSignIn;

  /// Updates is completing sign in.
  set _isCompletingSignIn(bool value) =>
      _screenModel.stateIsCompletingSignIn = value;

  /// Returns sign in error.
  String? get _signInError => _screenModel.stateSignInError;

  /// Updates sign in error.
  set _signInError(String? value) => _screenModel.stateSignInError = value;

  late final _PhoneSignInPageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _loadingOverlayController = OverlayPortalController(
    debugLabel: 'phone-sign-in-loading',
  );
  final _resendCountdown = ValueNotifier<int>(0);
  late final AuthViewModel _viewModel;
  late final PrivacyConsentRepository _privacyConsentRepository;
  Timer? _resendCooldownTimer;
  bool _otpDialogOpen = false;
  bool _isResendingOtp = false;
  bool _isVerifyingOtp = false;
  int _otpAttempt = 0;
  bool _isSubmittingPhone = false;

  bool get _canEditCredentials =>
      !_viewModel.isBusy &&
      !_isCompletingSignIn &&
      !_viewModel.hasCodeBeenSent &&
      !_isSubmittingPhone;

  bool _obscurePassword = true;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _PhoneSignInPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.readOnSignedIn = () => widget.onSignedIn;
    _screenModel.effectResetOtpEntry = _resetOtpEntry;
    _screenModel.effectPresentCompleteSignInEffect1 =
        _presentCompleteSignInEffect1;
    _screenModel.effectSetLoadingOverlayVisible = _setLoadingOverlayVisible;
    _screenModel.effectPresentOpenForgotPasswordEffect1 =
        _presentOpenForgotPasswordEffect1;
    _privacyConsentRepository =
        widget.privacyConsentRepository ?? PrivacyConsentRepository();
    _screenModel.effectSyncPrivacyConsent = _privacyConsentRepository.flush;

    _viewModel = widget._viewModel ?? AuthViewModel();
    _viewModel.setAuthMode(AuthMode.login);
    _viewModel.addListener(_refresh);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    if (widget._viewModel == null) _viewModel.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _resendCooldownTimer?.cancel();
    _resendCountdown.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates refresh to the ViewModel.
  void _refresh() => _screenModel.commandRefresh();

  /// Sets loading overlay visible.
  void _setLoadingOverlayVisible(bool visible) {
    if (visible) {
      _loadingOverlayController.show();
    } else {
      _loadingOverlayController.hide();
    }
  }

  /// Starts resend cooldown.
  void _startResendCooldown() {
    _resendCooldownTimer?.cancel();
    _resendCountdown.value = 60;
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown.value <= 1) {
        timer.cancel();
        _resendCountdown.value = 0;
      } else {
        _resendCountdown.value--;
      }
    });
  }

  /// Resets otp entry.
  void _resetOtpEntry() {
    _otpAttempt++;
    _isVerifyingOtp = false;
    _resendCooldownTimer?.cancel();
    _resendCountdown.value = 0;
    _otpController.clear();
    _viewModel.setAuthMode(_viewModel.authMode);
  }

  /// Shows otp dialog.
  Future<void> _showOtpDialog() async {
    if (!mounted || _otpDialogOpen) return;
    _otpDialogOpen = true;
    final deliveryMessage = _viewModel.message ?? 'OTP sent via WhatsApp.';
    final verified = await _presentShowOtpDialogEffect1(deliveryMessage);
    _otpDialogOpen = false;
    if (mounted && verified != true) {
      _resetOtpEntry();
    }
  }

  /// Sends code.
  Future<void> _sendCode() async {
    if (!_canEditCredentials || !_formKey.currentState!.validate()) return;
    final mode = _viewModel.authMode;
    final phone = PhoneNumberFormatter.normalize(_phoneController.text);
    final password = _passwordController.text;
    setState(() => _isSubmittingPhone = true);
    FocusScope.of(context).unfocus();
    try {
      if (mode == AuthMode.signUp) {
        final accepted = await requestSignupPrivacyConsent(
          context,
          phoneNumber: phone,
          repository: _privacyConsentRepository,
        );
        if (!mounted || !accepted) return;
        // A delayed choice must not submit a different phone or login mode.
        if (_viewModel.authMode != mode ||
            PhoneNumberFormatter.normalize(_phoneController.text) != phone) {
          return;
        }
      }
      if (!mounted) return;
      _setLoadingOverlayVisible(true);
      await _viewModel.sendCode(
        phone,
        password: mode == AuthMode.login ? password : null,
      );
      if (!mounted) return;
      _setLoadingOverlayVisible(false);
      if (_viewModel.hasCodeBeenSent) {
        _otpController.clear();
        _startResendCooldown();
        await _showOtpDialog();
      }
    } finally {
      if (mounted) {
        _setLoadingOverlayVisible(false);
        setState(() => _isSubmittingPhone = false);
      }
    }
  }

  /// Computes resend otp.
  Future<void> _resendOtp() async {
    if (_viewModel.isBusy ||
        _isCompletingSignIn ||
        _isResendingOtp ||
        _resendCountdown.value > 0) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isResendingOtp = true);
    _setLoadingOverlayVisible(true);
    final sent = await _viewModel.resendCode(
      _phoneController.text,
      password: _viewModel.authMode == AuthMode.login
          ? _passwordController.text
          : null,
    );
    if (!mounted) return;
    _setLoadingOverlayVisible(false);
    setState(() => _isResendingOtp = false);
    if (sent) {
      _otpController.clear();
      _startResendCooldown();
    }
  }

  /// Delegates open forgot password to the ViewModel.
  Future<void> _openForgotPassword() =>
      _screenModel.commandOpenForgotPassword();

  /// Computes verify otp.
  Future<void> _verifyOtp() async {
    if (_isVerifyingOtp ||
        _viewModel.isBusy ||
        _isCompletingSignIn ||
        _isResendingOtp ||
        !RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim())) {
      return;
    }
    final attempt = ++_otpAttempt;
    setState(() => _isVerifyingOtp = true);
    FocusScope.of(context).unfocus();
    _setLoadingOverlayVisible(true);
    final continuation = await _viewModel.verifyOtp(_otpController.text);
    if (!mounted || attempt != _otpAttempt) return;
    setState(() => _isVerifyingOtp = false);
    if (continuation == null) _otpController.clear();
    _setLoadingOverlayVisible(false);
    if (continuation != null && mounted) {
      if (_otpDialogOpen) {
        _otpDialogOpen = false;
        _presentVerifyOtpEffect1();
      }
      final session = await _presentVerifyOtpEffect2(continuation);
      if (session != null) {
        await _completeSignIn(session);
      } else if (mounted) {
        // The WhatsApp challenge has already been consumed. Returning from
        // the second-factor page must re-enable the login form for a fresh OTP.
        _resetOtpEntry();
      }
    }
  }

  /// Delegates complete sign in to the ViewModel.
  Future<void> _completeSignIn(AppSession session) =>
      _screenModel.commandCompleteSignIn(session);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSignUp = _viewModel.authMode == AuthMode.signUp;

    return OverlayPortal(
      controller: _loadingOverlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context) => HikerCircleLoadingToastOverlay(
        message: _isCompletingSignIn
            ? 'Finishing sign in…'
            : _isResendingOtp
            ? 'Sending a new OTP…'
            : _isVerifyingOtp || _viewModel.isVerifyingCode
            ? 'Verifying WhatsApp code…'
            : isSignUp
            ? 'Sending WhatsApp code…'
            : 'Verifying password and sending OTP…',
        detail: 'Securing your HikerCircle account. This may take a moment.',
        timeout: const Duration(seconds: 30),
        onTimeout: () {
          if (_isVerifyingOtp) {
            _otpAttempt++;
            _otpController.clear();
          }
          _viewModel.cancelPendingOperation();
          _setLoadingOverlayVisible(false);
          if (mounted) {
            setState(() {
              _isResendingOtp = false;
              _isVerifyingOtp = false;
              if (_isCompletingSignIn) {
                _isCompletingSignIn = false;
                _signInError = 'Sign in timed out. Please try again.';
              }
            });
          }
        },
      ),
      child: Scaffold(
        body: AuthTrailSignalShell(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isSignUp ? 'Find your circle' : 'Welcome back',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSignUp
                        ? 'Create an account for safer adventures.'
                        : 'Sign in to your trails, friends and adventures.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModeToggle(
                    currentMode: _viewModel.authMode,
                    enabled: _canEditCredentials,
                    onChanged: (mode) {
                      _resendCooldownTimer?.cancel();
                      _otpController.clear();
                      _passwordController.clear();
                      _resendCountdown.value = 0;
                      _viewModel.setAuthMode(mode);
                    },
                  ),
                  const SizedBox(height: 16),
                  Theme(
                    data: theme.copyWith(
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: scheme.primary.withValues(alpha: 0.045),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      alignment: Alignment.topCenter,
                      child: _buildWhatsAppForm(),
                    ),
                  ),
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
        ),
      ),
    );
  }

  /// Builds whats app form.
  Widget _buildWhatsAppForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          enabled: _canEditCredentials,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '012 345 6789',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
          validator: _viewModel.validatePhone,
        ),
        if (_viewModel.authMode == AuthMode.login) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            enabled: _canEditCredentials,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                onPressed: _canEditCredentials
                    ? () => setState(() => _obscurePassword = !_obscurePassword)
                    : null,
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
              ),
            ),
            validator: (value) {
              if (_viewModel.authMode == AuthMode.login &&
                  (value == null || value.isEmpty)) {
                return 'Enter your password.';
              }
              return null;
            },
            onFieldSubmitted: (_) => _sendCode(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _canEditCredentials ? _openForgotPassword : null,
              child: const Text('Forgot password?'),
            ),
          ),
        ],
        if (!_viewModel.hasCodeBeenSent) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _canEditCredentials ? _sendCode : null,
            icon: const Icon(Icons.message_outlined),
            label: Text(
              _viewModel.authMode == AuthMode.login ? 'Proceed' : 'Send OTP',
            ),
          ),
        ],
      ],
    );
  }

  /// Presents the show otp dialog effect1 UI.
  Future<bool?> _presentShowOtpDialogEffect1(String deliveryMessage) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _WhatsAppOtpDialog(
          controller: _otpController,
          viewModel: _viewModel,
          deliveryMessage: deliveryMessage,
          resendCountdown: _resendCountdown,
          isResending: () => _isResendingOtp,
          isVerifying: () => _isVerifyingOtp,
          onVerify: _verifyOtp,
          onResend: _resendOtp,
          onCancel: () => Navigator.of(dialogContext).pop(false),
        ),
      );

  /// Presents the open forgot password effect1 UI.
  Future<void> _presentOpenForgotPasswordEffect1() =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ForgotPasswordPage(viewModel: _viewModel),
        ),
      );

  /// Presents the verify otp effect1 UI.
  void _presentVerifyOtpEffect1() =>
      Navigator.of(context, rootNavigator: true).pop(true);

  /// Presents the verify otp effect2 UI.
  Future<AppSession?> _presentVerifyOtpEffect2(MfaContinuation continuation) =>
      Navigator.of(context).push<AppSession>(
        MaterialPageRoute<AppSession>(
          builder: (context) =>
              SecurityVerificationPage(continuation: continuation),
        ),
      );

  /// Presents the complete sign in effect1 UI.
  Future<bool?> _presentCompleteSignInEffect1(String previous) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            DeviceSessionReplacementDialog(previousDevice: previous),
      );
}

/// Displays the whats app otp dialog.
class _WhatsAppOtpDialog extends StatelessWidget {
  /// Creates whats app otp dialog.
  const _WhatsAppOtpDialog({
    required this.controller,
    required this.viewModel,
    required this.deliveryMessage,
    required this.resendCountdown,
    required this.isResending,
    required this.isVerifying,
    required this.onVerify,
    required this.onResend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final AuthViewModel viewModel;
  final String deliveryMessage;
  final ValueNotifier<int> resendCountdown;
  final bool Function() isResending;
  final bool Function() isVerifying;
  final Future<void> Function() onVerify;
  final Future<void> Function() onResend;
  final VoidCallback onCancel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: resendCountdown,
        builder: (context, secondsRemaining, _) {
          final busy = viewModel.isBusy || isResending() || isVerifying();
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            backgroundColor: scheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.message_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Check WhatsApp',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                deliveryMessage,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: busy ? null : onCancel,
                          tooltip: 'Use a different number',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Enter the six-digit code to continue.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    VerificationCodeInput(
                      controller: controller,
                      enabled: !busy,
                      autofocus: true,
                      semanticLabel: 'WhatsApp verification code',
                      onCompleted: (_) => onVerify(),
                    ),
                    if (viewModel.error != null) ...[
                      const SizedBox(height: 14),
                      InlineNotice(
                        icon: Icons.error_outline_rounded,
                        color: scheme.error,
                        text: viewModel.error!,
                      ),
                    ],
                    const SizedBox(height: 12),
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
                          onPressed: busy || secondsRemaining > 0
                              ? null
                              : onResend,
                          child: Text(
                            secondsRemaining > 0
                                ? 'Resend in ${secondsRemaining}s'
                                : 'Resend code',
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                      label: const Text('Use a different number'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Displays the mode toggle.
class _ModeToggle extends StatelessWidget {
  /// Creates mode toggle.
  const _ModeToggle({
    required this.currentMode,
    required this.enabled,
    required this.onChanged,
  });

  final AuthMode currentMode;
  final bool enabled;
  final void Function(AuthMode) onChanged;

  /// Builds this widget from its current presentation state.
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
