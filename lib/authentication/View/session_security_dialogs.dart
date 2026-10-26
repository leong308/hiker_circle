// DeviceSessionReplacementDialog and SessionEndedDialog explain account session transitions.
import 'package:flutter/material.dart';

/// Displays the device session replacement dialog.
class DeviceSessionReplacementDialog extends StatelessWidget {
  /// Creates device session replacement dialog.
  const DeviceSessionReplacementDialog({
    super.key,
    required this.previousDevice,
  });
  final String previousDevice;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sign in on this phone?'),
    content: Text(
      'This account is signed in on $previousDevice. Continuing will sign out that device and sign you in here.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Continue'),
      ),
    ],
  );
}

/// Displays the session ended dialog.
class SessionEndedDialog extends StatelessWidget {
  /// Creates session ended dialog.
  const SessionEndedDialog({super.key, required this.message});
  final String message;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Signed out for your security'),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  );
}
