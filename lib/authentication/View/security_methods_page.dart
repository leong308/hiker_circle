import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/verification_code_input.dart';

import '../Data/multi_factor_auth_service.dart';
import '../Data/passkey_build_support.dart';
import '../Model/mfa_models.dart';
import 'recent_security_verification_page.dart';

class SecurityMethodsPage extends StatefulWidget {
  const SecurityMethodsPage({super.key, MultiFactorAuthService? service})
    : _service = service;

  final MultiFactorAuthService? _service;

  @override
  State<SecurityMethodsPage> createState() => _SecurityMethodsPageState();
}

class _SecurityMethodsPageState extends State<SecurityMethodsPage> {
  late final MultiFactorAuthService _service;
  late Future<MfaStatus> _statusFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget._service ?? MultiFactorAuthService();
    _statusFuture = _service.loadStatus();
  }

  void _reload() {
    setState(() => _statusFuture = _service.loadStatus());
  }

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

  Future<void> _addPasskey() async {
    setState(() => _busy = true);
    try {
      try {
        await _service.enrollPasskey(label: 'Mobile passkey');
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await _verifyRecentLogin();
        if (!verified) return;
        await _service.enrollPasskey(label: 'Mobile passkey');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passkey added successfully.')),
      );
      _reload();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _verifyRecentLogin() async {
    final phoneNumber = await _service.authenticatedPhoneNumber();
    if (!mounted) return false;
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (context) =>
                RecentSecurityVerificationPage(phoneNumber: phoneNumber),
          ),
        ) ==
        true;
  }

  Future<void> _addAuthenticator() async {
    setState(() => _busy = true);
    TotpEnrollment enrollment;
    try {
      try {
        enrollment = await _service.beginTotpEnrollment();
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await _verifyRecentLogin();
        if (!verified) return;
        enrollment = await _service.beginTotpEnrollment();
      }
    } catch (error) {
      _showError(error);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) =>
            _AuthenticatorSetupPage(service: _service, enrollment: enrollment),
      ),
    );
    if (added == true) _reload();
  }

  Future<void> _remove(MfaFactor factor, bool canRemove) async {
    if (!canRemove) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add another security method before removing this one.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      try {
        await _service.removeFactor(factor.id);
      } catch (error) {
        if (!requiresRecentMfaAuthentication(error)) rethrow;
        final verified = await _verifyRecentLogin();
        if (!verified) return;
        await _service.removeFactor(factor.id);
      }
      _reload();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
}

class _AuthenticatorSetupPage extends StatefulWidget {
  const _AuthenticatorSetupPage({
    required this.service,
    required this.enrollment,
  });

  final MultiFactorAuthService service;
  final TotpEnrollment enrollment;

  @override
  State<_AuthenticatorSetupPage> createState() =>
      _AuthenticatorSetupPageState();
}

class _AuthenticatorSetupPageState extends State<_AuthenticatorSetupPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  int _codeAttempt = 0;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

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
      await widget.service.finishTotpEnrollment(
        challengeId: widget.enrollment.challengeId,
        code: code,
      );
      if (mounted && attempt == _codeAttempt) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && attempt == _codeAttempt) {
        _codeController.clear();
        setState(() => _error = readableMfaError(error));
      }
    } finally {
      if (mounted && attempt == _codeAttempt) setState(() => _busy = false);
    }
  }

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
}
