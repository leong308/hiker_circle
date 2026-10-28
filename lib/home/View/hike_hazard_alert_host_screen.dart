part of '../hike_hazard_alert_host_feature.dart';

/// Shows an informational in-hike alert without changing the hike or its route.
Future<void> showActiveTrailHazardNotification(
  BuildContext context, {
  required Future<List<TrailHazardAlert>> Function() loadAlerts,
}) async {
  await showDialog<TrailHazardAlertAction>(
    context: context,
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: 'active-hike-trail-hazard'),
    builder: (_) => _NotificationHazardDialog(
      loadAlerts: loadAlerts,
      canCancelHike: false,
      duringHike: true,
    ),
  );
}

/// A notification opens hike details first, then this owned alert above them.
class HikeHazardAlertHost extends StatefulWidget {
  /// Creates hike hazard alert host.
  const HikeHazardAlertHost({
    super.key,
    required this.child,
    required this.loadAlerts,
    required this.onAction,
    required this.canCancelHike,
  });

  final Widget child;
  final Future<List<TrailHazardAlert>> Function() loadAlerts;
  final Future<void> Function(TrailHazardAlertAction) onAction;
  final bool canCancelHike;

  /// Creates the presentation state for this widget.
  @override
  State<HikeHazardAlertHost> createState() => _HikeHazardAlertHostState();
}

/// Manages the hike hazard alert host presentation and lifecycle.
class _HikeHazardAlertHostState extends State<HikeHazardAlertHost> {
  DialogRoute<TrailHazardAlertAction>? _alertRoute;
  DialogRoute<bool>? _errorRoute;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  /// Opens.
  Future<void> _open() async {
    if (!mounted ||
        _alertRoute != null ||
        _errorRoute != null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final route = DialogRoute<TrailHazardAlertAction>(
      context: context,
      barrierDismissible: false,
      settings: const RouteSettings(name: 'hike-hazard-notification'),
      builder: (_) => _NotificationHazardDialog(
        loadAlerts: widget.loadAlerts,
        canCancelHike: widget.canCancelHike,
      ),
    );
    _alertRoute = route;
    final action = await _presentOpenEffect1(route);
    if (identical(_alertRoute, route)) _alertRoute = null;
    if (!mounted ||
        action == null ||
        action == TrailHazardAlertAction.acknowledge) {
      return;
    }
    try {
      await widget.onAction(action);
    } catch (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final errorRoute = DialogRoute<bool>(
        context: context,
        settings: const RouteSettings(name: 'hike-hazard-action-error'),
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Unable to confirm the change'),
          content: const Text(
            'Refresh the hike details before trying again. Your plan may already have updated.',
          ),
          actions: [
            TextButton(
              onPressed: () => _presentOpenEffect2(dialogContext),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () => _presentOpenEffect3(dialogContext),
              child: const Text('Review again'),
            ),
          ],
        ),
      );
      _errorRoute = errorRoute;
      final reviewAgain = await _presentOpenEffect4(errorRoute);
      if (identical(_errorRoute, errorRoute)) _errorRoute = null;
      if (mounted && reviewAgain == true) await _open();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    for (final route in <Route<dynamic>?>[_alertRoute, _errorRoute]) {
      if (route == null) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => widget.child;

  /// Presents the open effect1 UI.
  Future<TrailHazardAlertAction?> _presentOpenEffect1(
    DialogRoute<TrailHazardAlertAction> route,
  ) => Navigator.of(context).push(route);

  /// Presents the open effect2 UI.
  void _presentOpenEffect2(BuildContext dialogContext) =>
      Navigator.of(dialogContext).pop(false);

  /// Presents the open effect3 UI.
  void _presentOpenEffect3(BuildContext dialogContext) =>
      Navigator.of(dialogContext).pop(true);

  /// Presents the open effect4 UI.
  Future<bool?> _presentOpenEffect4(DialogRoute<bool> errorRoute) =>
      Navigator.of(context).push(errorRoute);
}

/// Displays the notification hazard dialog.
class _NotificationHazardDialog extends StatefulWidget {
  /// Creates notification hazard dialog.
  const _NotificationHazardDialog({
    required this.loadAlerts,
    required this.canCancelHike,
    this.duringHike = false,
  });

  final Future<List<TrailHazardAlert>> Function() loadAlerts;
  final bool canCancelHike;
  final bool duringHike;

  /// Creates the presentation state for this widget.
  @override
  State<_NotificationHazardDialog> createState() =>
      _NotificationHazardDialogState();
}

/// Manages the notification hazard dialog presentation and lifecycle.
class _NotificationHazardDialogState extends State<_NotificationHazardDialog> {
  late final _NotificationHazardDialogStateViewModel _screenModel;

  /// Returns alerts.
  List<TrailHazardAlert>? get _alerts => _screenModel.stateAlerts;

  /// Returns failed.
  bool get _failed => _screenModel.stateFailed;

  /// Returns loading.
  bool get _loading => _screenModel.stateLoading;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _NotificationHazardDialogStateViewModel(
      readLoadAlerts: () => widget.loadAlerts,
    )..addListener(_renderScreenModel);

    unawaited(_load());
  }

  /// Delegates load to the ViewModel.
  Future<void> _load() => _screenModel.commandLoad();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final alerts = _alerts;
    if (!_loading && !_failed && alerts != null && alerts.isNotEmpty) {
      return TrailHazardAlertDialog(
        alerts: alerts,
        beforeStart: false,
        canCancelHike: widget.canCancelHike,
        duringHike: widget.duringHike,
      );
    }
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: Text(
          _loading
              ? 'Checking this trail report'
              : _failed
              ? 'Unable to check this report'
              : 'This caution is no longer active',
        ),
        content: _loading
            ? const SizedBox(
                height: 32,
                child: Center(child: CircularProgressIndicator()),
              )
            : Text(
                _failed
                    ? 'Connect to the internet to check its current status.'
                    : widget.duringHike
                    ? 'The report may have been resolved, removed or expired. Check the latest trail conditions while hiking.'
                    : 'The report may have been resolved, removed or expired. Check the latest trail conditions before you start.',
              ),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(TrailHazardAlertAction.acknowledge),
              child: const Text('Close'),
            ),
          if (!_loading && _failed)
            FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
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
