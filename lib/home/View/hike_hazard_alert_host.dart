import 'dart:async';

import 'package:flutter/material.dart';

import '../../trail/Model/trail_hazard_alert.dart';
import '../../trail/View/trail_hazard_alert_dialog.dart';

/// A notification opens hike details first, then this owned alert above them.
class HikeHazardAlertHost extends StatefulWidget {
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

  @override
  State<HikeHazardAlertHost> createState() => _HikeHazardAlertHostState();
}

class _HikeHazardAlertHostState extends State<HikeHazardAlertHost> {
  DialogRoute<TrailHazardAlertAction>? _alertRoute;
  DialogRoute<bool>? _errorRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

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
    final action = await Navigator.of(context).push(route);
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('OK'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Review again'),
            ),
          ],
        ),
      );
      _errorRoute = errorRoute;
      final reviewAgain = await Navigator.of(context).push(errorRoute);
      if (identical(_errorRoute, errorRoute)) _errorRoute = null;
      if (mounted && reviewAgain == true) await _open();
    }
  }

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

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NotificationHazardDialog extends StatefulWidget {
  const _NotificationHazardDialog({
    required this.loadAlerts,
    required this.canCancelHike,
  });

  final Future<List<TrailHazardAlert>> Function() loadAlerts;
  final bool canCancelHike;

  @override
  State<_NotificationHazardDialog> createState() =>
      _NotificationHazardDialogState();
}

class _NotificationHazardDialogState extends State<_NotificationHazardDialog> {
  List<TrailHazardAlert>? _alerts;
  bool _failed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final alerts = await widget.loadAlerts();
      if (mounted) {
        setState(
          () => _alerts = alerts
              .where((alert) => alert.active(DateTime.now()))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _alerts;
    if (!_loading && !_failed && alerts != null && alerts.isNotEmpty) {
      return TrailHazardAlertDialog(
        alerts: alerts,
        beforeStart: false,
        canCancelHike: widget.canCancelHike,
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
}
