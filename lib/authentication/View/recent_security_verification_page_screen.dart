part of '../recent_security_verification_page_feature.dart';

/// Recheck a current factor for sensitive settings without restarting the ordinary sign-in screen.
class RecentSecurityVerificationPage extends StatefulWidget {
  /// Creates recent security verification page.
  const RecentSecurityVerificationPage({
    super.key,
    required this.phoneNumber,
    this.sendCodeOnOpen = true,
    AuthViewModel? viewModel,
  }) : _viewModel = viewModel;

  final String phoneNumber;

  /// Whether an existing verification flow requests its code on entry.
  final bool sendCodeOnOpen;
  final AuthViewModel? _viewModel;

  /// Creates the presentation state for this widget.
  @override
  State<RecentSecurityVerificationPage> createState() =>
      _RecentSecurityVerificationPageState();
}

/// Manages the recent security verification page presentation and lifecycle.
class _RecentSecurityVerificationPageState
    extends State<RecentSecurityVerificationPage> {
  late final _RecentSecurityVerificationPageStateViewModel _screenModel;

  /// Returns view model.
  AuthViewModel get _viewModel => _screenModel.stateViewModel;

  /// Updates view model.
  set _viewModel(AuthViewModel value) => _screenModel.stateViewModel = value;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final TextEditingController _codeController = TextEditingController();

  bool _completing = false;
  int _codeAttempt = 0;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _RecentSecurityVerificationPageStateViewModel(
      readPhoneNumber: () => widget.phoneNumber,
    )..addListener(_renderScreenModel);

    _viewModel = widget._viewModel ?? AuthViewModel();
    _viewModel.setAuthMode(AuthMode.login);
    _viewModel.addListener(_refresh);
    if (widget.sendCodeOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendCode();
      });
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    if (widget._viewModel == null) _viewModel.dispose();
    _codeController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates refresh to the ViewModel.
  void _refresh() => _screenModel.commandRefresh();

  /// Delegates send code to the ViewModel.
  Future<void> _sendCode() => _screenModel.commandSendCode();

  /// Computes verify code.
  Future<void> _verifyCode() async {
    if (_completing ||
        _viewModel.isBusy ||
        !RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim())) {
      return;
    }
    final attempt = ++_codeAttempt;
    FocusScope.of(context).unfocus();
    setState(() {
      _completing = true;
      _error = null;
    });
    final continuation = await _viewModel.verifyOtp(_codeController.text);
    if (!mounted || attempt != _codeAttempt) return;
    _codeController.clear();
    if (continuation == null) {
      setState(() => _completing = false);
      return;
    }
    if (continuation.enrollmentRequired ||
        continuation.phoneNumber != widget.phoneNumber) {
      setState(() {
        _completing = false;
        _error = 'This verification could not be matched to your account.';
      });
      return;
    }
    final session = await _presentVerifyCodeEffect1(continuation);
    if (!mounted) return;
    if (session == null) {
      setState(() => _completing = false);
      return;
    }
    _presentVerifyCodeEffect2();
  }

  /// Returns masked phone.
  String get _maskedPhone => _screenModel.commandMaskedPhone;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waitingForCode = _viewModel.hasCodeBeenSent;
    final busy = _viewModel.isBusy || _completing;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          title: 'Confirm it is you',
                          subtitle: 'Verify your identity to continue',
                          onBack: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.security_rounded,
                                color: scheme.primary,
                                size: 30,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Security check required',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 5),
                                    const Text(
                                      'Before changing protected account settings, verify WhatsApp and one existing security method.',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  waitingForCode
                                      ? 'Enter WhatsApp code'
                                      : 'Verify with WhatsApp',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text('Verified account: $_maskedPhone'),
                                if (!waitingForCode) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Send a verification code when you are ready to continue.',
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: busy ? null : _sendCode,
                                    icon: const Icon(Icons.send_rounded),
                                    label: const Text('Send WhatsApp code'),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 16),
                                  VerificationCodeInput(
                                    controller: _codeController,
                                    enabled: !busy,
                                    autofocus: true,
                                    semanticLabel: 'WhatsApp verification code',
                                    onCompleted: (_) => _verifyCode(),
                                  ),
                                  TextButton(
                                    onPressed: busy ? null : _sendCode,
                                    child: const Text('Resend WhatsApp code'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_viewModel.message != null) ...[
                          const SizedBox(height: 14),
                          InlineNotice(
                            icon: Icons.info_outline_rounded,
                            color: scheme.primary,
                            text: _viewModel.message!,
                          ),
                        ],
                        if (_viewModel.error != null || _error != null) ...[
                          const SizedBox(height: 14),
                          InlineNotice(
                            icon: Icons.error_outline_rounded,
                            color: scheme.error,
                            text: _error ?? _viewModel.error!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (busy)
              HikerCircleLoadingToastOverlay(
                message: _completing
                    ? 'Verifying WhatsApp code…'
                    : 'Sending WhatsApp code…',
                detail:
                    'Confirming your account securely. This may take a moment.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  if (_completing) {
                    _codeAttempt++;
                    _codeController.clear();
                  }
                  _viewModel.cancelPendingOperation();
                  if (mounted && _completing) {
                    setState(() {
                      _completing = false;
                      _error = 'Verification timed out. Please try again.';
                    });
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Presents the verify code effect1 UI.
  Future<AppSession?> _presentVerifyCodeEffect1(MfaContinuation continuation) =>
      Navigator.of(context).push<AppSession>(
        MaterialPageRoute<AppSession>(
          builder: (context) =>
              SecurityVerificationPage(continuation: continuation),
        ),
      );

  /// Presents the verify code effect2 UI.
  void _presentVerifyCodeEffect2() => Navigator.of(context).pop(true);
}
