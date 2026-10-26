part of '../sos_triggered_route_host_feature.dart';

/// Presents a newly triggered SOS above the entire signed-in navigation stack.
/// Historical dispatches and retry queues do not create a presentation.
class SosTriggeredRouteHost extends StatefulWidget {
  /// Creates sos triggered route host.
  const SosTriggeredRouteHost({
    super.key,
    required this.controller,
    required this.child,
    required this.onStopAlarm,
  });

  final SosPresentationController controller;
  final Widget child;
  final Future<void> Function(int eventId) onStopAlarm;

  /// Creates the presentation state for this widget.
  @override
  State<SosTriggeredRouteHost> createState() => _SosTriggeredRouteHostState();
}

/// Manages the sos triggered route host presentation and lifecycle.
class _SosTriggeredRouteHostState extends State<SosTriggeredRouteHost>
    with WidgetsBindingObserver {
  late final _SosTriggeredRouteHostStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  PageRoute<void>? _route;
  SosPresentationController? _routeController;
  bool _syncScheduled = false;
  bool _disposing = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _SosTriggeredRouteHostStateViewModel(
      effectScheduleSync: _scheduleSync,
      effectSyncPresentation: _syncPresentation,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onPresentationChanged);
    _scheduleSync();
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant SosTriggeredRouteHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPresentationChanged);
      widget.controller.addListener(_onPresentationChanged);
      _scheduleSync();
    }
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleSync();
  }

  /// Delegates on presentation changed to the ViewModel.
  void _onPresentationChanged() => _screenModel.commandOnPresentationChanged();

  /// Computes schedule sync.
  void _scheduleSync() {
    if (_syncScheduled || _disposing) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || _disposing) return;
      _syncPresentation();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Synchronizes presentation.
  void _syncPresentation() {
    if (!mounted || _disposing) return;
    if (widget.controller.current == null) {
      final route = _route;
      _route = null;
      _routeController = null;
      HikeStartNavigation.closeOwnedRoute(route);
      return;
    }
    if (_route?.isActive == true) {
      if (identical(_routeController, widget.controller)) return;
      final oldRoute = _route;
      _route = null;
      _routeController = null;
      HikeStartNavigation.closeOwnedRoute(oldRoute);
    }
    final controller = widget.controller;
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'sos-triggered'),
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final current = controller.current;
          if (current == null) return const SizedBox.shrink();
          return SosTriggeredPage(
            key: ValueKey(current.eventId),
            mode: current.mode,
            statusText: current.message,
            alarmActive: current.alarmActive,
            isSubmitting: current.isStopping,
            onSlideToCancel: () => widget.onStopAlarm(current.eventId),
          );
        },
      ),
    );
    _route = route;
    _routeController = controller;
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(route).then((_) {
        if (!mounted || _disposing || !identical(_route, route)) return;
        _route = null;
        _routeController = null;
        // A late pop from a different flow must not hide an active alarm.
        if (widget.controller.current != null) _scheduleSync();
      }),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onPresentationChanged);
    final route = _route;
    _route = null;
    _routeController = null;
    // Navigation may currently be tearing down this host's parent route.
    // Defer removal until the navigator finishes its own route mutation.
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HikeStartNavigation.closeOwnedRoute(route);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => widget.child;
}
