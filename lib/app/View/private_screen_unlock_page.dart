// PrivateScreenUnlockPage gates private screens behind device authentication.
import 'package:flutter/material.dart';
import '../../core/services/private_screen_unlock.dart';

/// Resume private content only after the device authentication attempt succeeds.
class PrivateScreenUnlockPage extends StatefulWidget {
  const PrivateScreenUnlockPage({
    super.key,
    required this.onUnlocked,
    required this.onSignOut,
  });
  final VoidCallback onUnlocked;
  final VoidCallback onSignOut;
  @override
  State<PrivateScreenUnlockPage> createState() =>
      _PrivateScreenUnlockPageState();
}

class _PrivateScreenUnlockPageState extends State<PrivateScreenUnlockPage> {
  bool _busy = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await PrivateScreenUnlock.authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint_rounded, size: 64),
              const SizedBox(height: 20),
              Text(
                'Unlock HikerCircle',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _failed
                    ? 'Biometric verification was not completed. Try again, or sign out to verify your account again.'
                    : 'Use your enrolled biometrics to open your private screens.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: Text(_busy ? 'Verifying…' : 'Unlock'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
