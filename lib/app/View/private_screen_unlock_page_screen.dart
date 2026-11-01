part of '../private_screen_unlock_page_feature.dart';

/// Resume private content only after the device authentication attempt succeeds.
class PrivateScreenUnlockPage extends StatefulWidget {
  /// Creates private screen unlock page.
  const PrivateScreenUnlockPage({
    super.key,
    required this.onUnlocked,
    required this.onSignOut,
  });
  final VoidCallback onUnlocked;
  final VoidCallback onSignOut;

  /// Creates the presentation state for this widget.
  @override
  State<PrivateScreenUnlockPage> createState() =>
      _PrivateScreenUnlockPageState();
}

/// Manages the private screen unlock page presentation and lifecycle.
class _PrivateScreenUnlockPageState extends State<PrivateScreenUnlockPage> {
  late final _PrivateScreenUnlockPageStateViewModel _screenModel;

  /// Returns busy.
  bool get _busy => _screenModel.stateBusy;

  /// Returns failed.
  bool get _failed => _screenModel.stateFailed;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _PrivateScreenUnlockPageStateViewModel(
      readOnUnlocked: () => widget.onUnlocked,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  /// Delegates unlock to the ViewModel.
  Future<void> _unlock() => _screenModel.commandUnlock();

  /// Builds this widget from its current presentation state.
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
                    : 'Use Face ID or fingerprints to unlock HikerCircle.',
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

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}
