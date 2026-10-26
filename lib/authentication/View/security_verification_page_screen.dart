part of '../security_verification_page_feature.dart';

/// Finish the pending MFA continuation before returning an authenticated session to the caller.
class SecurityVerificationPage extends StatefulWidget {
  /// Creates security verification page.
  const SecurityVerificationPage({
    super.key,
    required this.continuation,
    MultiFactorAuthService? service,
  }) : _service = service;

  final MfaContinuation continuation;
  final MultiFactorAuthService? _service;

  /// Creates the presentation state for this widget.
  @override
  State<SecurityVerificationPage> createState() =>
      _SecurityVerificationPageState();
}

/// Manages the security verification page presentation and lifecycle.
class _SecurityVerificationPageState extends State<SecurityVerificationPage> {
  late final _SecurityVerificationPageStateViewModel _screenModel;

  /// Returns service.
  MultiFactorAuthService get _service => _screenModel.stateService;

  /// Updates service.
  set _service(MultiFactorAuthService value) =>
      _screenModel.stateService = value;

  /// Returns totp enrollment.
  TotpEnrollment? get _totpEnrollment => _screenModel.stateTotpEnrollment;

  /// Updates totp enrollment.
  set _totpEnrollment(TotpEnrollment? value) =>
      _screenModel.stateTotpEnrollment = value;

  /// Returns busy.
  bool get _busy => _screenModel.stateBusy;

  /// Updates busy.
  set _busy(bool value) => _screenModel.stateBusy = value;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Updates error.
  set _error(String? value) => _screenModel.stateError = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final TextEditingController _codeController = TextEditingController();

  int _codeAttempt = 0;
  String _busyMessage = 'Checking your security method…';

  /// Returns is enrollment.
  bool get _isEnrollment => _screenModel.commandIsEnrollment;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SecurityVerificationPageStateViewModel(
      readContinuation: () => widget.continuation,
      effectBeginBusy: _beginBusy,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentUsePasskeyEffect1 = _presentUsePasskeyEffect1;

    _service = widget._service ?? MultiFactorAuthService();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _codeController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Begins busy.
  void _beginBusy(String message) {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _busyMessage = message;
      _error = null;
    });
  }

  /// Delegates end busy to the ViewModel.
  void _endBusy() => _screenModel.commandEndBusy();

  /// Delegates start totp to the ViewModel.
  Future<void> _startTotp() => _screenModel.commandStartTotp();

  /// Computes submit totp.
  Future<void> _submitTotp() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the current 6-digit code.');
      return;
    }
    final attempt = ++_codeAttempt;
    _beginBusy('Verifying security code…');
    try {
      final AppSession session;
      if (_isEnrollment) {
        final result =
            await _SecurityVerificationPageDataActions.finishTotpEnrollment(
              _service,
            )(
              challengeId: _totpEnrollment!.challengeId,
              code: code,
              mfaToken: widget.continuation.token,
            );
        if (result == null) throw StateError('Secure sign-in did not finish.');
        session = result;
      } else {
        session = await _SecurityVerificationPageDataActions.verifyTotpLogin(
          _service,
        )(mfaToken: widget.continuation.token, code: code);
      }
      if (mounted && attempt == _codeAttempt) {
        _presentSubmitTotpEffect1(session);
      }
    } catch (error) {
      if (mounted && attempt == _codeAttempt) {
        _codeController.clear();
        setState(() => _error = readableMfaError(error));
      }
    } finally {
      if (attempt == _codeAttempt) _endBusy();
    }
  }

  /// Delegates use passkey to the ViewModel.
  Future<void> _usePasskey() => _screenModel.commandUsePasskey();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final passkeysEnabled = nativePasskeysEnabledForBuild();
    final passkeyIsRelevant =
        _isEnrollment || widget.continuation.methods.contains('passkey');
    return Scaffold(
      // Keep the loading barrier full-screen while the keyboard dismisses.
      resizeToAvoidBottomInset: !_busy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SecurityVerificationHeader(
                        title: _isEnrollment
                            ? 'Protect your account'
                            : 'Verify it is you',
                        subtitle: _isEnrollment
                            ? 'Add a secure method for future sign-ins'
                            : 'Complete your second verification step',
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 24),
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
                                    _isEnrollment
                                        ? 'One security method is required'
                                        : 'WhatsApp verification completed',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _isEnrollment
                                        ? 'Bind Authenticator or a passkey before your account can be used. You can add the other method later in Settings.'
                                        : 'Complete the second step using one of your bound methods.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_totpEnrollment != null)
                        _buildTotpPanel(theme, scheme)
                      else ...[
                        if (_isEnrollment ||
                            widget.continuation.methods.contains('totp'))
                          _MethodCard(
                            icon: Icons.password_rounded,
                            title: 'Authenticator app',
                            subtitle: _isEnrollment
                                ? 'Use Google Authenticator, Authy, 1Password, or another TOTP app.'
                                : 'Enter the 6-digit code that refreshes every 30 seconds.',
                            buttonLabel: _isEnrollment
                                ? 'Set up Authenticator'
                                : 'Use Authenticator',
                            busy: _busy,
                            onPressed: _startTotp,
                          ),
                        if (passkeyIsRelevant && passkeysEnabled) ...[
                          const SizedBox(height: 12),
                          _MethodCard(
                            icon: Icons.fingerprint_rounded,
                            title: 'Passkey',
                            subtitle:
                                'Use the secure screen lock, fingerprint, or face verification provided by this device.',
                            buttonLabel: _isEnrollment
                                ? 'Create passkey'
                                : 'Use passkey',
                            busy: _busy,
                            onPressed: _usePasskey,
                          ),
                        ] else if (passkeyIsRelevant) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _isEnrollment
                                        ? personalSigningPasskeyMessage
                                        : 'This account has a passkey, but personal-signed iOS builds cannot use native passkeys. Use Authenticator, or sign in on Android or the web and add Authenticator first.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            HikerCircleLoadingToastOverlay(
              message: _busyMessage,
              detail: 'Keeping your account secure. This may take a moment.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (!mounted || !_busy) return;
                _codeAttempt++;
                _codeController.clear();
                setState(() {
                  _busy = false;
                  _error = 'The security check timed out. Please try again.';
                });
              },
            ),
        ],
      ),
    );
  }

  /// Builds totp panel.
  Widget _buildTotpPanel(ThemeData theme, ColorScheme scheme) {
    final enrollment = _totpEnrollment!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEnrollment ? 'Set up Authenticator' : 'Authenticator code',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_isEnrollment) ...[
              const SizedBox(height: 8),
              Text(
                '1. Open your Authenticator app and add an account.\n2. Scan this QR code or enter the setup key.\n3. Enter the current 6-digit code below.',
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: enrollment.otpauthUri,
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                enrollment.secret
                    .replaceAllMapped(
                      RegExp(r'.{4}'),
                      (match) => '${match.group(0)} ',
                    )
                    .trim(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.2,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: enrollment.secret),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Setup key copied.')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy setup key'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'Enter the current code from your Authenticator app. Each code can be used once.',
              ),
            ],
            const SizedBox(height: 12),
            VerificationCodeInput(
              controller: _codeController,
              enabled: !_busy,
              semanticLabel: 'Authenticator verification code',
              onCompleted: (_) => _submitTotp(),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _totpEnrollment = null;
                      _codeController.clear();
                      _error = null;
                    }),
              child: const Text('Choose another method'),
            ),
          ],
        ),
      ),
    );
  }

  /// Presents the submit totp effect1 UI.
  void _presentSubmitTotpEffect1(AppSession session) =>
      Navigator.of(context).pop(session);

  /// Presents the use passkey effect1 UI.
  void _presentUsePasskeyEffect1(AppSession session) =>
      Navigator.of(context).pop(session);
}
