import 'package:flutter/material.dart';

import '../../app/Model/app_session.dart';
import '../ModelView/auth_view_model.dart';
import 'auth_brand_panel.dart';
import 'inline_notice.dart';

class PhoneSignInPage extends StatefulWidget {
  const PhoneSignInPage({super.key, required this.onSignedIn});

  final ValueChanged<AppSession> onSignedIn;

  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends State<PhoneSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  late final AuthViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AuthViewModel();
    _viewModel.addListener(_refresh);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_refresh);
    _viewModel.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await _viewModel.sendCode(_phoneController.text);
  }

  void _verifyCode() {
    FocusScope.of(context).unfocus();
    final session = _viewModel.verifyCode(_otpController.text);
    if (session != null) {
      widget.onSignedIn(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                                    'WhatsApp login',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.done,
                                    enabled:
                                        !_viewModel.isSendingCode &&
                                        !_viewModel.isVerifyingCode,
                                    decoration: const InputDecoration(
                                      labelText: 'Phone number',
                                      hintText: '012 345 6789',
                                      prefixIcon: Icon(Icons.phone_iphone),
                                    ),
                                    validator: _viewModel.validatePhone,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _viewModel.isSendingCode
                                        ? null
                                        : _sendCode,
                                    icon: _viewModel.isSendingCode
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            _viewModel.hasCodeBeenSent
                                                ? Icons.refresh
                                                : Icons.message_outlined,
                                          ),
                                    label: Text(
                                      _viewModel.hasCodeBeenSent
                                          ? 'Resend code'
                                          : 'Send code',
                                    ),
                                  ),
                                  if (_viewModel.hasCodeBeenSent) ...[
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: _otpController,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      maxLength: 6,
                                      enabled: !_viewModel.isVerifyingCode,
                                      decoration: const InputDecoration(
                                        counterText: '',
                                        labelText: 'Verification code',
                                        prefixIcon: Icon(Icons.lock_outline),
                                      ),
                                      onSubmitted: (_) => _verifyCode(),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _viewModel.isVerifyingCode
                                          ? null
                                          : _verifyCode,
                                      icon: _viewModel.isVerifyingCode
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.verified_user),
                                      label: const Text('Verify and continue'),
                                    ),
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
}
