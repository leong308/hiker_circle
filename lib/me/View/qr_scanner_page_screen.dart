part of '../qr_scanner_page_feature.dart';

/// Displays the qr scanner page.
class QrScannerPage extends StatefulWidget {
  /// Creates qr scanner page.
  const QrScannerPage({
    super.key,
    required this.session,
    required this.repository,
    required this.ownPhoneNumber,
    required this.ownHandle,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final String ownPhoneNumber;
  final String ownHandle;

  /// Creates the presentation state for this widget.
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

/// Manages the qr scanner page presentation and lifecycle.
class _QrScannerPageState extends State<QrScannerPage> {
  late final _QrScannerPageStateViewModel _screenModel;

  /// Returns is processing.
  bool get _isProcessing => _screenModel.stateIsProcessing;

  /// Updates is processing.
  set _isProcessing(bool value) => _screenModel.stateIsProcessing = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _eventChannel = EventChannel('hiker_circle/qr_scanner_events');

  String? _scannerError;
  StreamSubscription<dynamic>? _subscription;
  Timer? _processingResetTimer;
  int _scannerInstance = 0;
  bool _retryingScanner = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _QrScannerPageStateViewModel(
      readOwnHandle: () => widget.ownHandle,
      readOwnPhoneNumber: () => widget.ownPhoneNumber,
      effectShowAddBuddyPrompt: _showAddBuddyPrompt,
      effectShowOwnQrMessage: _showOwnQrMessage,
    )..addListener(_renderScreenModel);

    _listenForQrEvents();
  }

  void _listenForQrEvents() {
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        _onQrDetected,
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
            _scannerError = 'The camera scanner stopped unexpectedly.';
          });
        },
        onDone: () {
          if (!mounted || _subscription == null) return;
          setState(() {
            _isProcessing = false;
            _scannerError =
                'The camera scanner stopped. Try again to continue.';
          });
        },
      );
    } catch (_) {
      _scannerError = 'The camera scanner is unavailable on this device.';
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _processingResetTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((_) {}));
    }

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates on qr detected to the ViewModel.
  void _onQrDetected(dynamic rawValue) =>
      _screenModel.commandOnQrDetected(rawValue);

  /// Shows own qr message.
  void _showOwnQrMessage() {
    _showScanMessage('That is your own HikerCircle QR. No action taken.');
  }

  void _showScanMessage(String message) {
    if (!mounted) return;
    _processingResetTimer?.cancel();
    setState(() => _isProcessing = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    _processingResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }

  Future<void> _retryScanner() async {
    if (_retryingScanner) return;
    _retryingScanner = true;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel().catchError((_) {});
    }
    if (!mounted) return;
    setState(() {
      _scannerInstance++;
      _scannerError = null;
      _isProcessing = false;
      _retryingScanner = false;
    });
    _listenForQrEvents();
  }

  /// Shows add buddy prompt.
  Future<void> _showAddBuddyPrompt({
    required String name,
    required String handle,
    required String phoneNumber,
  }) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);

    if (phoneNumber.isEmpty) {
      _showScanMessage('This QR is missing a phone number.');
      return;
    }

    try {
      final relationships =
          await _QrScannerPageDataActions.loadBuddyRelationships(
            widget.repository,
          )(session: widget.session, force: true).timeout(
            const Duration(seconds: 15),
          );
      if (!mounted) return;
      final statusMessage = relationships.requestStatusMessage(
        phoneNumber: phoneNumber,
        displayName: name,
      );
      if (statusMessage != null) {
        _showScanMessage(statusMessage);
        return;
      }
    } catch (_) {
      if (mounted) {
        _showScanMessage(
          'Could not check this profile. Check your connection and scan again.',
        );
      }
      return;
    }

    bool? shouldAdd;
    try {
      shouldAdd = await _presentShowAddBuddyPromptEffect1(name, handle);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _scannerError = 'Unable to open the scanned profile.';
        });
      }
      return;
    }

    if (!mounted) return;

    if (shouldAdd == true) {
      try {
        await _QrScannerPageDataActions.sendBuddyRequest(widget.repository)(
          session: widget.session,
          buddyPhoneNumber: phoneNumber,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Unable to send buddy request: $error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        setState(() => _isProcessing = false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Friend request sent to $name.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      _processingResetTimer?.cancel();
      _processingResetTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          _presentShowAddBuddyPromptEffect2();
        }
      });
    } else {
      setState(() => _isProcessing = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageHeaderAppBar(
        backgroundColor: Colors.black87,
        title: const Text('Scan QR', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (defaultTargetPlatform == TargetPlatform.iOS)
            UiKitView(
              key: ValueKey(_scannerInstance),
              viewType: 'hiker_circle/qr_scanner',
              creationParams: null,
              creationParamsCodec: const StandardMessageCodec(),
            )
          else if (defaultTargetPlatform == TargetPlatform.android)
            AndroidView(
              key: ValueKey(_scannerInstance),
              viewType: 'hiker_circle/qr_scanner',
              creationParams: null,
              creationParamsCodec: const StandardMessageCodec(),
            )
          else
            const Center(
              child: Text(
                'QR scanning is only available on iOS and Android.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (_scannerError case final scannerError?)
            ColoredBox(
              color: Colors.black87,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white70,
                          size: 42,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          scannerError,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: _retryingScanner ? null : _retryScanner,
                          child: const Text('Try Again'),
                        ),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_isProcessing) Container(color: Colors.black54),
        ],
      ),
    );
  }

  /// Presents the show add buddy prompt effect1 UI.
  Future<bool?> _presentShowAddBuddyPromptEffect1(
    String name,
    String handle,
  ) => showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Add $name as a buddy?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                handle.isEmpty
                    ? 'This QR belongs to a HikerCircle profile.'
                    : '$handle can be added to your Trail Buddies for future team hikes and shared trail plans.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Not Now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add Buddy'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Presents the show add buddy prompt effect2 UI.
  void _presentShowAddBuddyPromptEffect2() => Navigator.of(context).pop();
}
