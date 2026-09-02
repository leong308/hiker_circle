import 'package:flutter/material.dart';

import '../../app/Model/app_session.dart';
import '../../core/widgets/loading_toast.dart';
import '../Model/auth_status.dart';
import '../ModelView/auth_view_model.dart';
import 'inline_notice.dart';
import 'security_verification_page.dart';

class RecentSecurityVerificationPage extends StatefulWidget {
  const RecentSecurityVerificationPage({super.key, required this.phoneNumber});

  final String phoneNumber;

  @override
  State<RecentSecurityVerificationPage> createState() =>
      _RecentSecurityVerificationPageState();
}

class _RecentSecurityVerificationPageState
    extends State<RecentSecurityVerificationPage> {
  final TextEditingController _codeController = TextEditingController();
  late final AuthViewModel _viewModel;
  bool _completing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewModel = AuthViewModel();
    _viewModel.setAuthMode(AuthMode.login);
    _viewModel.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    _viewModel.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _sendCode() async {
    if (!mounted || _viewModel.isBusy) return;
    setState(() => _error = null);
    await _viewModel.sendCode(widget.phoneNumber);
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6 || _viewModel.isBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _completing = true;
      _error = null;
    });
    final continuation = await _viewModel.verifyOtp(_codeController.text);
    if (!mounted) return;
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
    final session = await Navigator.of(context).push<AppSession>(
      MaterialPageRoute<AppSession>(
        builder: (context) =>
            SecurityVerificationPage(continuation: continuation),
      ),
    );
    if (!mounted) return;
    if (session == null) {
      setState(() => _completing = false);
      return;
    }
    Navigator.of(context).pop(true);
  }

  String get _maskedPhone {
    final value = widget.phoneNumber;
    if (value.length <= 6) return value;
    return '${value.substring(0, 4)} •••• ${value.substring(value.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final waitingForCode = _viewModel.hasCodeBeenSent;
    final busy = _viewModel.isBusy || _completing;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm it is you')),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
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
                              'Security check required',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Before changing login security, verify WhatsApp and one existing security method.',
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
                              : 'Sending code',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Verified account: $_maskedPhone'),
                        if (!waitingForCode) ...[
                          const HikerCircleLoadingView(
                            message: 'Sending WhatsApp code…',
                            detail:
                                'This usually arrives within a few seconds.',
                            compact: true,
                            padding: EdgeInsets.only(top: 14),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: _codeController,
                            enabled: !busy,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '6-digit verification code',
                              counterText: '',
                              prefixIcon: Icon(Icons.message_outlined),
                            ),
                            onSubmitted: (_) => _verifyCode(),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: busy ? null : _verifyCode,
                            icon: const Icon(Icons.verified_user_rounded),
                            label: const Text('Verify and continue'),
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
            if (busy)
              HikerCircleLoadingToastOverlay(
                message: _completing
                    ? 'Verifying WhatsApp code…'
                    : 'Sending WhatsApp code…',
                detail:
                    'Confirming your account securely. This may take a moment.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
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
}
