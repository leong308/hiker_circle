import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../authentication/Data/phone_number_formatter.dart';
import '../Data/account_deletion_service.dart';

Future<void> showAccountDeletionConfirmations(
  BuildContext context, {
  required String ownerPhoneNumber,
  AccountDeletionService? service,
}) async {
  final review = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.privacy_tip_outlined),
      title: const Text('Delete your HikerCircle account?'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This removes your main HikerCircle account record and Firebase Authentication login, then signs you out.',
            ),
            SizedBox(height: 16),
            Text(
              'Location records, trail history, uploaded files and other saved data will remain.',
            ),
            SizedBox(height: 12),
            Text(
              'To return, sign up again and set up a new password and Authenticator or passkey. You can cancel here to keep your account.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep my account'),
        ),
        FilledButton(
          key: const Key('review-account-deletion'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Review deletion'),
        ),
      ],
    ),
  );
  if (review != true || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FinalAccountDeletionDialog(
      owner: ownerPhoneNumber,
      service: service ?? AccountDeletionService.instance,
    ),
  );
}

class _FinalAccountDeletionDialog extends StatefulWidget {
  const _FinalAccountDeletionDialog({
    required this.owner,
    required this.service,
  });
  final String owner;
  final AccountDeletionService service;
  @override
  State<_FinalAccountDeletionDialog> createState() =>
      _FinalAccountDeletionDialogState();
}

class _FinalAccountDeletionDialogState
    extends State<_FinalAccountDeletionDialog> {
  final _confirmation = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || _confirmation.text != 'DELETE') return;
    final confirmationRoute = ModalRoute.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.deleteAccount(widget.owner);
      // Sign-out may already be dismissing this dialog. A mounted widget can
      // remain during that transition; only pop if this is still its route.
      if (mounted && confirmationRoute?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FirebaseFunctionsException && error.message != null
              ? error.message
              : 'We could not confirm account deletion. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: errorColor),
        title: const Text('Confirm account deletion'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account: ${PhoneNumberFormatter.maskForDisplay(widget.owner)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account record and Firebase Authentication login will be removed. You will need to register again to sign in.',
              ),
              const SizedBox(height: 12),
              const Text(
                'An internet connection is required. After deletion is confirmed, you will be signed out and returned to Login.',
              ),
              const SizedBox(height: 18),
              TextField(
                key: const Key('account-deletion-confirmation'),
                controller: _confirmation,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: errorColor)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Go back'),
          ),
          FilledButton(
            key: const Key('delete-account-permanently'),
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: _busy || _confirmation.text != 'DELETE' ? null : _delete,
            child: Text(_busy ? 'Closing account…' : 'Delete my account'),
          ),
        ],
      ),
    );
  }
}
