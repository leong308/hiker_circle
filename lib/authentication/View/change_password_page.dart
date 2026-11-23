// ChangePasswordPage validates a replacement password and submits the account change.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/password_capture_protection.dart';
import '../../core/widgets/page_header_style.dart';
import '../Model/password_validator.dart';

/// Displays the change password page.
class ChangePasswordPage extends StatefulWidget {
  /// Creates change password page.
  const ChangePasswordPage({super.key});

  /// Creates the presentation state for this widget.
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

/// Manages the change password page presentation and lifecycle.
class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// Saves.
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Update cloud: change account password
      await FirebaseFunctions.instance
          .httpsCallable('changeAccountPassword')
          .call({'newPassword': _password.text});
      if (!mounted) return;
      Navigator.pop(context);
      _presentSaveEffect1();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.message ?? 'Unable to change your password.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PasswordCaptureProtection(
    child: Scaffold(
      appBar: const PageHeaderAppBar(title: Text('Change password')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Choose a new password. Recent account verification is required to save this change.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (value) {
                final result = PasswordValidator.validate(value ?? '');
                return result.isValid ? null : result.errorMessage;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Change password'),
            ),
          ],
        ),
      ),
    ),
  );

  /// Presents the save effect1 UI.
  void _presentSaveEffect1() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Your password has been changed.')),
  );
}
