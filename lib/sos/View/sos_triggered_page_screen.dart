part of '../sos_triggered_page_feature.dart';

/// A blocking, app-wide SOS surface. Hardware and dispatch stay with the caller.
/// The caller removes this page only after [onSlideToCancel] finishes safely.
class SosTriggeredPage extends StatefulWidget {
  /// Creates sos triggered page.
  const SosTriggeredPage({
    super.key,
    required this.mode,
    required this.statusText,
    required this.onSlideToCancel,
    this.isSubmitting = false,
    this.errorText,
    this.detailsText,
    this.alarmActive = true,
  });

  final SosAlertMode mode;
  final String statusText;
  final Future<void> Function() onSlideToCancel;
  final bool isSubmitting;
  final String? errorText;
  final String? detailsText;
  final bool alarmActive;

  /// Creates the presentation state for this widget.
  @override
  State<SosTriggeredPage> createState() => _SosTriggeredPageState();
}

/// Manages the sos triggered page presentation and lifecycle.
class _SosTriggeredPageState extends State<SosTriggeredPage> {
  bool _isCancelling = false;
  String? _cancellationError;

  /// Returns busy.
  bool get _busy => _isCancelling || widget.isSubmitting;

  /// Returns is silent.
  bool get _isSilent => !widget.mode.usesLoudEmergencyPattern;

  /// Returns slide label.
  String get _slideLabel => _cancellationError != null
      ? 'Slide to retry stop'
      : widget.alarmActive && !_isSilent
      ? 'Slide to stop alarm'
      : 'Slide to close';

  /// Cancels.
  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _isCancelling = true;
      _cancellationError = null;
    });
    try {
      await widget.onSlideToCancel();
      // Keep this surface blocking until its owner confirms hardware stopped
      // and removes it. A successful callback must not expose a live alarm.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCancelling = false;
        _cancellationError = 'Couldn’t stop SOS. Slide again to retry.';
      });
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final error = _cancellationError ?? widget.errorText;
    final details = widget.detailsText?.trim();
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF210D16),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF240F1C), Color(0xFF6D1830), Color(0xFFB73640)],
              stops: [0, 0.56, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                top: -120,
                right: -140,
                child: _SosGlow(size: 430, color: Color(0x40FF8A87)),
              ),
              const Positioned(
                bottom: -130,
                left: -170,
                child: _SosGlow(size: 400, color: Color(0x20FFCFB2)),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final padding = constraints.maxWidth < 360 ? 20.0 : 28.0;
                    return Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, contentConstraints) =>
                                SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: contentConstraints.maxHeight,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        padding,
                                        24,
                                        padding,
                                        24,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Text(
                                            'HIKERCIRCLE',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFFFFD9D8),
                                              fontSize: 11,
                                              letterSpacing: 2.8,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 28,
                                            ),
                                            child: Column(
                                              children: [
                                                _SosEmblem(isSilent: _isSilent),
                                                const SizedBox(height: 28),
                                                Semantics(
                                                  header: true,
                                                  liveRegion: true,
                                                  child: Text(
                                                    'SOS triggered',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize:
                                                          constraints.maxWidth <
                                                              360
                                                          ? 26
                                                          : 34,
                                                      height: 1.15,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: -1,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  widget.mode.label,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFD9D8),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 22),
                                                Semantics(
                                                  liveRegion: true,
                                                  child: Text(
                                                    widget.statusText,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      height: 1.45,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                if (details != null &&
                                                    details.isNotEmpty) ...[
                                                  const SizedBox(height: 10),
                                                  Text(
                                                    details,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Color(0xFFFFD9D8),
                                                      fontSize: 14,
                                                      height: 1.5,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(padding, 8, padding, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (error != null && error.trim().isNotEmpty) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    error,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              _SlideToEndSos(
                                label: _slideLabel,
                                busy: _busy,
                                onConfirmed: _cancel,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Sent messages cannot be recalled. Queued alerts will still retry.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFF5CBCD),
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the sos glow.
class _SosGlow extends StatelessWidget {
  /// Creates sos glow.
  const _SosGlow({required this.size, required this.color});
  final double size;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Displays the sos emblem.
class _SosEmblem extends StatelessWidget {
  /// Creates sos emblem.
  const _SosEmblem({required this.isSilent});
  final bool isSilent;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 126,
        height: 126,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x30FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x20FFFFFF), Color(0x05FFFFFF)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20FF6F75),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE8DC), Color(0xFFFFC6BF)],
            ),
            border: Border.all(color: const Color(0x60FFFFFF)),
          ),
          child: Icon(
            isSilent ? Icons.shield_outlined : Icons.sos_rounded,
            color: const Color(0xFF842039),
            size: 48,
          ),
        ),
      ),
    );
  }
}

/// Displays the slide to end sos.
class _SlideToEndSos extends StatefulWidget {
  /// Creates slide to end sos.
  const _SlideToEndSos({
    required this.label,
    required this.busy,
    required this.onConfirmed,
  });

  final String label;
  final bool busy;
  final Future<void> Function() onConfirmed;

  /// Creates the presentation state for this widget.
  @override
  State<_SlideToEndSos> createState() => _SlideToEndSosState();
}

/// Manages the slide to end sos presentation and lifecycle.
class _SlideToEndSosState extends State<_SlideToEndSos> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SlideToEndSosStateViewModel(
      readBusy: () => widget.busy,
      readOnConfirmed: () => widget.onConfirmed,
    )..addListener(_renderScreenModel);
  }

  late final _SlideToEndSosStateViewModel _screenModel;

  /// Returns progress.
  double get _progress => _screenModel.stateProgress;

  /// Updates progress.
  set _progress(double value) => _screenModel.stateProgress = value;

  /// Returns dragging.
  bool get _dragging => _screenModel.stateDragging;

  /// Updates dragging.
  set _dragging(bool value) => _screenModel.stateDragging = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _thumbSize = 58.0;
  static const _inset = 7.0;

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _SlideToEndSos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy && !widget.busy) _progress = 0;
  }

  /// Delegates confirm to the ViewModel.
  void _confirm() => _screenModel.commandConfirm();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      key: const ValueKey('sos-cancel-slider'),
      label: widget.busy ? 'Stopping SOS' : widget.label,
      value: widget.busy ? null : '${(_progress * 100).round()} percent',
      enabled: !widget.busy,
      slider: true,
      liveRegion: widget.busy,
      customSemanticsActions: widget.busy
          ? null
          : {CustomSemanticsAction(label: widget.label): _confirm},
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelStyle = DefaultTextStyle.of(context).style.merge(
              const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            );
            final label = widget.busy ? 'Stopping SOS…' : widget.label;
            final labelPadding = widget.busy ? 44.0 : 74.0;
            final labelLayout =
                TextPainter(
                  text: TextSpan(text: label, style: labelStyle),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  textAlign: TextAlign.center,
                )..layout(
                  maxWidth: math.max(
                    1,
                    constraints.maxWidth - 2 * labelPadding,
                  ),
                );
            final height = math.max(
              math.max(74.0, 38 + 30 * textScale),
              labelLayout.height + 24,
            );
            labelLayout.dispose();
            final travel = math.max(
              1.0,
              constraints.maxWidth - _thumbSize - 2 * _inset,
            );
            return Container(
              height: height,
              decoration: BoxDecoration(
                color: const Color(0x2A1C0611),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(color: const Color(0x60FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: labelPadding),
                    child: Opacity(
                      opacity: widget.busy ? 1 : 1 - _progress,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: labelStyle,
                      ),
                    ),
                  ),
                  if (!widget.busy)
                    AnimatedPositionedDirectional(
                      duration: _dragging || reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      start: _inset + travel * _progress,
                      top: (height - _thumbSize) / 2,
                      child: GestureDetector(
                        key: const ValueKey('sos-cancel-thumb'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) {
                          if (widget.busy) return;
                          setState(() => _dragging = true);
                        },
                        onHorizontalDragUpdate: (details) {
                          if (widget.busy) return;
                          final delta = details.delta.dx * (isRtl ? -1 : 1);
                          setState(() {
                            _progress = (_progress + delta / travel).clamp(
                              0,
                              1,
                            );
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          if (widget.busy) return;
                          if (_progress >= 0.88) {
                            _confirm();
                          } else {
                            setState(() {
                              _dragging = false;
                              _progress = 0;
                            });
                          }
                        },
                        onHorizontalDragCancel: () {
                          setState(() {
                            _dragging = false;
                            _progress = 0;
                          });
                        },
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.white, Color(0xFFFFE1DA)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x30000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            isRtl
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            color: const Color(0xFF842039),
                            size: 34,
                          ),
                        ),
                      ),
                    )
                  else
                    const PositionedDirectional(
                      start: 22,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}
