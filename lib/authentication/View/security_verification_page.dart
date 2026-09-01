import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/Model/app_session.dart';
import '../../core/widgets/loading_toast.dart';
import '../Data/multi_factor_auth_service.dart';
import '../Data/passkey_build_support.dart';
import '../Model/mfa_models.dart';

class SecurityVerificationPage extends StatefulWidget {
  const SecurityVerificationPage({
    super.key,
    required this.continuation,
    MultiFactorAuthService? service,
  }) : _service = service;

  final MfaContinuation continuation;
  final MultiFactorAuthService? _service;

  @override
  State<SecurityVerificationPage> createState() =>
      _SecurityVerificationPageState();
}

class _SecurityVerificationPageState extends State<SecurityVerificationPage> {
  late final MultiFactorAuthService _service;
  final TextEditingController _codeController = TextEditingController();
  TotpEnrollment? _totpEnrollment;
  bool _busy = false;
  String? _error;

  bool get _isEnrollment => widget.continuation.enrollmentRequired;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? MultiFactorAuthService();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startTotp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEnrollment) {
        final enrollment = await _service.beginTotpEnrollment(
          mfaToken: widget.continuation.token,
        );
        if (!mounted) return;
        setState(() => _totpEnrollment = enrollment);
      } else {
        setState(
          () => _totpEnrollment = TotpEnrollment(
            challengeId: '',
            secret: '',
            otpauthUri: '',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = readableMfaError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitTotp() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the current 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AppSession session;
      if (_isEnrollment) {
        final result = await _service.finishTotpEnrollment(
          challengeId: _totpEnrollment!.challengeId,
          code: code,
          mfaToken: widget.continuation.token,
        );
        if (result == null) throw StateError('Secure sign-in did not finish.');
        session = result;
      } else {
        session = await _service.verifyTotpLogin(
          mfaToken: widget.continuation.token,
          code: code,
        );
      }
      if (mounted) Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) setState(() => _error = readableMfaError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _usePasskey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = _isEnrollment
          ? await _service.enrollPasskey(
              mfaToken: widget.continuation.token,
              label: 'Mobile passkey',
            )
          : await _service.verifyPasskeyLogin(
              mfaToken: widget.continuation.token,
            );
      if (session == null) throw StateError('Secure sign-in did not finish.');
      if (mounted) Navigator.of(context).pop(session);
    } catch (error) {
      if (mounted) setState(() => _error = readableMfaError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final passkeysEnabled = nativePasskeysEnabledForBuild();
    final passkeyIsRelevant =
        _isEnrollment || widget.continuation.methods.contains('passkey');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEnrollment ? 'Protect your account' : 'Verify it is you',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
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
    );
  }

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
            TextField(
              controller: _codeController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-digit code',
                counterText: '',
                prefixIcon: Icon(Icons.lock_clock_rounded),
              ),
              onSubmitted: (_) => _submitTotp(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _submitTotp,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: HikerCircleMinorLoadingIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_rounded),
              label: Text(
                _isEnrollment ? 'Verify and bind' : 'Verify and sign in',
              ),
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
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: busy ? null : onPressed,
              icon: Icon(icon, size: 20),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
