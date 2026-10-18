// PrivacyPolicyLink presents the shared policy action and handles its asynchronous launch state.
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/privacy_policy_launcher.dart';

class PrivacyPolicyLink extends StatelessWidget {
  const PrivacyPolicyLink({super.key});

  Future<void> _open(BuildContext context) async {
    final launched = await launchPrivacyPolicy();
    if (!context.mounted || launched) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the Privacy Policy. Check your connection and try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => unawaited(_open(context)),
      icon: const Icon(Icons.privacy_tip_outlined, size: 18),
      label: const Text('Privacy Policy'),
    );
  }
}
