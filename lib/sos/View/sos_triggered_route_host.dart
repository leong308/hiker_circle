import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../home/View/hike_start_navigation.dart';
import '../Model/sos_presentation_controller.dart';
import 'sos_triggered_page.dart';

/// Presents a newly triggered SOS above the entire signed-in navigation stack.
/// Historical dispatches and retry queues do not create a presentation.
class SosTriggeredRouteHost extends StatefulWidget {
  const SosTriggeredRouteHost({
    super.key,
    required this.controller,
    required this.child,
    required this.onStopAlarm,
  });

  final SosPresentationController controller;
  final Widget child;
  final Future<void> Function(int eventId) onStopAlarm;

  @override
  State<SosTriggeredRouteHost> createState() => _SosTriggeredRouteHostState();
}

class _SosTriggeredRouteHostState extends State<SosTriggeredRouteHost>
    with WidgetsBindingObserver {
  PageRoute<void>? _route;
  SosPresentationController? _routeController;
  bool _syncScheduled = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onPresentationChanged);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant SosTriggeredRouteHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPresentationChanged);
      widget.controller.addListener(_onPresentationChanged);
      _scheduleSync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleSync();
  }

  void _onPresentationChanged() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _scheduleSync();
    } else {
      _syncPresentation();
    }
  }

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
