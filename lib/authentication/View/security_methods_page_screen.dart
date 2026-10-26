part of '../security_methods_page_feature.dart';

/// Show enrolled factors and their enrollment/removal actions using MultiFactorAuthService.
class SecurityMethodsPage extends StatefulWidget {
  /// Creates security methods page.
  const SecurityMethodsPage({super.key, MultiFactorAuthService? service})
    : _service = service;

  final MultiFactorAuthService? _service;

  /// Creates the presentation state for this widget.
  @override
  State<SecurityMethodsPage> createState() => _SecurityMethodsPageState();
}

/// Manages the security methods page presentation and lifecycle.
class _SecurityMethodsPageState extends State<SecurityMethodsPage> {
  /// Returns busy.
  bool get _busy => _screenModel.stateBusy;

  /// Updates busy.
  set _busy(bool value) => _screenModel.stateBusy = value;

  late final _SecurityMethodsPageStateViewModel _screenModel;

  /// Returns service.
  MultiFactorAuthService get _service => _screenModel.stateService;

  /// Updates service.
  set _service(MultiFactorAuthService value) =>
      _screenModel.stateService = value;

  /// Returns status future.
  Future<MfaStatus> get _statusFuture => _screenModel.stateStatusFuture;

  /// Updates status future.
  set _statusFuture(Future<MfaStatus> value) =>
      _screenModel.stateStatusFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SecurityMethodsPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentAddPasskeyEffect1 = _presentAddPasskeyEffect1;
    _screenModel.effectPresentAddAuthenticatorEffect1 =
        _presentAddAuthenticatorEffect1;
    _screenModel.effectPresentRemoveEffect1 = _presentRemoveEffect1;
    _screenModel.effectShowError = _showError;
    _screenModel.effectPresentVerifyRecentLoginEffect1 =
        _presentVerifyRecentLoginEffect1;
    _screenModel.effectPresentRemoveEffect2 = _presentRemoveEffect2;

    _service = widget._service ?? MultiFactorAuthService();
    _statusFuture = _SecurityMethodsPageDataActions.loadStatus(_service)();
  }

  /// Delegates reload to the ViewModel.
  void _reload() => _screenModel.commandReload();

  /// Shows error.
  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(readableMfaError(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Delegates add passkey to the ViewModel.
  Future<void> _addPasskey() => _screenModel.commandAddPasskey();

  /// Delegates add authenticator to the ViewModel.
  Future<void> _addAuthenticator() => _screenModel.commandAddAuthenticator();

  /// Honor the current factor-removal rule and refresh enrollment state after the backend accepts removal.
  Future<void> _remove(MfaFactor factor, bool canRemove) =>
      _screenModel.commandRemove(factor, canRemove);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: PageHeaderAppBar(title: const Text('Login security')),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _statusFuture;
              },
              child: FutureBuilder<MfaStatus>(
                future: _statusFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const HikerCircleLoadingView(
                      message: 'Loading login security…',
                      detail: 'Checking your bound verification methods.',
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          'Unable to load security methods.',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
                      ],
                    );
                  }
                  final status = snapshot.data!;
                  final hasTotp = status.methods.contains('totp');
                  final hasPasskey = status.methods.contains('passkey');
                  final passkeysEnabled = nativePasskeysEnabledForBuild();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_rounded, color: scheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    passkeysEnabled
                                        ? '${status.methods.length} of 2 method types protected'
                                        : hasTotp
                                        ? 'Authenticator is protecting this account'
                                        : 'Add Authenticator to protect this account',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    !passkeysEnabled
                                        ? 'Native passkeys are unavailable with personal iOS signing. Authenticator remains fully supported.'
                                        : hasTotp && hasPasskey
                                        ? 'Both methods are bound. Security Guardian achievement progress is complete.'
                                        : 'At least one method must always remain. Bind both to complete the Security Guardian achievement.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Bound methods',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final factor in status.factors)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: Icon(
                              factor.type == 'passkey'
                                  ? Icons.fingerprint_rounded
                                  : Icons.password_rounded,
                              color: scheme.primary,
                            ),
                            title: Text(factor.label),
                            subtitle: Text(
                              factor.type == 'passkey'
                                  ? 'Passkey · protected by device security'
                                  : 'Authenticator · 6 digits every 30 seconds',
                            ),
                            trailing: IconButton(
                              tooltip: status.canRemove
                                  ? 'Remove'
                                  : 'Add another method first',
                              onPressed: _busy
                                  ? null
                                  : () => _remove(factor, status.canRemove),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a method',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hasTotp)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _addAuthenticator,
                          icon: const Icon(Icons.password_rounded),
                          label: const Text('Add Authenticator'),
                        ),
                      if (!hasPasskey && passkeysEnabled) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _addPasskey,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Add passkey'),
                        ),
                      ] else if (!hasPasskey) ...[
                        const SizedBox(height: 8),
                        Text(
                          personalSigningPasskeyMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Removing a method requires a recent two-step login. HikerCircle never receives your fingerprint, face data, or device PIN.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (_busy)
              HikerCircleLoadingToastOverlay(
                message: 'Updating login security…',
                detail:
                    'Applying your security method change. This may take a moment.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  if (mounted && _busy) setState(() => _busy = false);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the add passkey effect1 UI.
  void _presentAddPasskeyEffect1() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Passkey added successfully.')));

  /// Presents the verify recent login effect1 UI.
  Future<bool?> _presentVerifyRecentLoginEffect1(String phoneNumber) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) =>
              RecentSecurityVerificationPage(phoneNumber: phoneNumber),
        ),
      );

  /// Presents the add authenticator effect1 UI.
  Future<bool?> _presentAddAuthenticatorEffect1(TotpEnrollment enrollment) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => _AuthenticatorSetupPage(
            service: _service,
            enrollment: enrollment,
            onEnrolled: _reload,
          ),
        ),
      );

  /// Presents the remove effect1 UI.
  void _presentRemoveEffect1() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Add another security method before removing this one.'),
    ),
  );

  /// Presents the remove effect2 UI.
  Future<bool?> _presentRemoveEffect2(MfaFactor factor) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${factor.label}?'),
      content: const Text(
        'You will no longer be able to use this method to verify login.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

/// Displays the authenticator setup page.
class _AuthenticatorSetupPage extends StatefulWidget {
  /// Creates authenticator setup page.
  const _AuthenticatorSetupPage({
    required this.service,
    required this.enrollment,
    required this.onEnrolled,
  });

  final MultiFactorAuthService service;
  final TotpEnrollment enrollment;
  final VoidCallback onEnrolled;

  /// Creates the presentation state for this widget.
  @override
  State<_AuthenticatorSetupPage> createState() =>
      _AuthenticatorSetupPageState();
}

/// Manages the authenticator setup page presentation and lifecycle.
class _AuthenticatorSetupPageState extends State<_AuthenticatorSetupPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  int _codeAttempt = 0;
  String? _error;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Finishes.
  Future<void> _finish() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the current 6-digit code.');
      return;
    }
    final attempt = ++_codeAttempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _SecurityMethodsPageDataActions.finishTotpEnrollment(
        widget.service,
      )(challengeId: widget.enrollment.challengeId, code: code);
      // A successful server write still matters if setup was closed or timed out.
      widget.onEnrolled();
      if (mounted && attempt == _codeAttempt) _presentFinishEffect1();
    } catch (error) {
      if (mounted && attempt == _codeAttempt) {
        _codeController.clear();
        setState(() => _error = readableMfaError(error));
      }
    } finally {
      if (mounted && attempt == _codeAttempt) setState(() => _busy = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final enrollment = widget.enrollment;
    return Scaffold(
      appBar: PageHeaderAppBar(title: const Text('Add Authenticator')),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '1. Open Google Authenticator, Authy, 1Password, or another TOTP app.\n2. Scan the QR code or enter the key.\n3. Enter the current code to confirm.',
                ),
                const SizedBox(height: 18),
                ...[
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: enrollment.otpauthUri,
                        size: 210,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    enrollment.secret,
                    textAlign: TextAlign.center,
                  ),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: enrollment.secret),
                    ),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy setup key'),
                  ),
                  const SizedBox(height: 12),
                  VerificationCodeInput(
                    controller: _codeController,
                    enabled: !_busy,
                    semanticLabel: 'Authenticator verification code',
                    onCompleted: (_) => _finish(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            if (_busy)
              HikerCircleLoadingToastOverlay(
                message: 'Verifying Authenticator code…',
                detail: 'Adding your security method. This may take a moment.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  if (!mounted || !_busy) return;
                  _codeAttempt++;
                  _codeController.clear();
                  setState(() {
                    _busy = false;
                    _error = 'Verification timed out. Please try again.';
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Presents the finish effect1 UI.
  void _presentFinishEffect1() => Navigator.of(context).pop(true);
}
