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

  /// Uses Profile's shared header, section labels and inset settings cards.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0C120F)
          : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: _screenModel.commandRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PageHeader(
                            title: 'Login security',
                            subtitle: 'Manage how you verify your login',
                            onBack: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(height: 20),
                          FutureBuilder<MfaStatus>(
                            future: _statusFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const HikerCircleLoadingView(
                                  message: 'Loading login security…',
                                  detail: 'Checking your verification methods.',
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                );
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return _SecurityCard(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const _SecurityMethodTile(
                                          icon: Icons.cloud_off_rounded,
                                          title: 'Could not load your methods',
                                          subtitle:
                                              'Check your connection and try again.',
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          onPressed: _reload,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                          label: const Text('Try again'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              return _buildMethods(snapshot.data!);
                            },
                          ),
                          const SizedBox(height: 22),
                          const SectionLabel(label: 'Coming next'),
                          const SizedBox(height: 8),
                          const _MoreSecurityMethodsCard(),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Changes may require a recent two-step login. Your fingerprint, face data and device PIN stay on your device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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

  /// Keeps existing enrollment and removal commands in the redesigned layout.
  Widget _buildMethods(MfaStatus status) {
    final presentation = _screenModel.commandPresentation(status);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SecurityOverview(presentation: presentation),
        const SizedBox(height: 22),
        const SectionLabel(label: 'Verification methods'),
        const SizedBox(height: 8),
        _BoundSecurityMethods(status: status, busy: _busy, onRemove: _remove),
        if (presentation.canAddAuthenticator || presentation.canAddPasskey) ...[
          const SizedBox(height: 22),
          const SectionLabel(label: 'Add a method'),
          const SizedBox(height: 8),
          _SecurityCard(
            child: Column(
              children: [
                if (presentation.canAddAuthenticator)
                  _SecurityMethodTile(
                    icon: Icons.password_rounded,
                    title: 'Add Authenticator',
                    subtitle:
                        'Verify your login with one-time codes from an authenticator app.',
                    onTap: _busy ? null : _addAuthenticator,
                    trailing: Icon(
                      Icons.add_circle_outline_rounded,
                      color: colors.primary,
                    ),
                  ),
                if (presentation.canAddAuthenticator &&
                    presentation.canAddPasskey)
                  const Padding(
                    padding: EdgeInsets.only(left: 72),
                    child: Divider(height: 1),
                  ),
                if (presentation.canAddPasskey)
                  _SecurityMethodTile(
                    icon: Icons.fingerprint_rounded,
                    title: 'Add passkey',
                    subtitle: 'Use your device security to verify your login.',
                    onTap: _busy ? null : _addPasskey,
                    trailing: Icon(
                      Icons.add_circle_outline_rounded,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (!presentation.passkeysEnabled && !presentation.hasPasskey) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Passkeys are unavailable in this version. Use Authenticator to verify your login.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
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
