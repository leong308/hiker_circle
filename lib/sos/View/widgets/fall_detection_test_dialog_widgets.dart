part of '../../fall_detection_test_dialog_feature.dart';

/// Isolated sensor readings. This test has no SOS dispatch path.
class FallDetectionTestCard extends StatefulWidget {
  /// Creates fall detection test card.
  const FallDetectionTestCard({
    super.key,
    this.initialSensitivity,
    this.events,
  });
  final double? initialSensitivity;
  final Stream<AccelerometerEvent>? events;

  /// Creates the presentation state for this widget.
  @override
  State<FallDetectionTestCard> createState() => _FallDetectionTestCardState();
}

/// Bind test state to the existing card and forward app lifecycle changes.
class _FallDetectionTestCardState extends State<FallDetectionTestCard>
    with WidgetsBindingObserver {
  late final FallDetectionTestViewModel _viewModel;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = FallDetectionTestViewModel(
      sensitivity: () => widget.initialSensitivity,
      events: () => widget.events,
    )..addListener(_refresh);
  }

  /// Repaint only while this card is attached.
  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _viewModel.setForeground(state == AppLifecycleState.resumed);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_refresh);
    _viewModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final passed = _viewModel.passed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FallAccelerationMeter(
          progress: _viewModel.progress,
          active: _viewModel.active,
          passed: passed,
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            _viewModel.status,
            key: const ValueKey('fall-test-status'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('fall-test-action'),
          onPressed: _viewModel.hasActiveHike
              ? null
              : _viewModel.active
              ? _viewModel.stop
              : _viewModel.start,
          icon: Icon(
            _viewModel.active ? Icons.stop_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(
            _viewModel.active
                ? 'Stop test'
                : _viewModel.phase == FallDetectionTestPhase.idle
                ? 'Start test'
                : 'Try again',
          ),
        ),
      ],
    );
  }
}
