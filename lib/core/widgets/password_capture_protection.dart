// PasswordCaptureProtection enables native screen-capture protection only while password input is
// exposed.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final passwordRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Protection follows the visible password route, including push/pop transitions.
class PasswordCaptureProtection extends StatefulWidget {
  const PasswordCaptureProtection({super.key, required this.child});
  final Widget child;
  @override
  State<PasswordCaptureProtection> createState() =>
      _PasswordCaptureProtectionState();
}

class _PasswordCaptureProtectionState extends State<PasswordCaptureProtection>
    with RouteAware {
  static const _channel = MethodChannel('hiker_circle/security');
  late final String _id = 'password-${identityHashCode(this)}';
  PageRoute<dynamic>? _route;
  bool _ready = false;
  int _visibility = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      passwordRouteObserver.unsubscribe(this);
      _route = route;
      passwordRouteObserver.subscribe(this, route);
      unawaited(_protect(true));
    }
  }

  Future<void> _protect(bool enabled) async {
    try {
      if (enabled && _ready && mounted) setState(() => _ready = false);
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod<void>('protectPasswordPage', {
          'route': _id,
          'enabled': enabled,
        });
      }
      if (mounted && enabled) setState(() => _ready = true);
    } catch (_) {
      // Do not expose password fields before native protection is available.
      if (mounted && enabled) setState(() => _ready = false);
    }
  }

  @override
  void didPush() => unawaited(_protect(true));
  @override
  void didPopNext() {
    _visibility++;
    unawaited(_protect(true));
  }

  @override
  void didPushNext() {
    final epoch = ++_visibility;
    // Keep the outgoing password page protected throughout the route animation.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && epoch == _visibility) unawaited(_protect(false));
    });
  }

  @override
  void didPop() {
    _releaseAfterTransition();
  }

  void _releaseAfterTransition() {
    if (Platform.isAndroid || Platform.isIOS) {
      Future<void>.delayed(
        const Duration(milliseconds: 450),
        () => _protect(false),
      );
    } else {
      unawaited(_protect(false));
    }
  }

  @override
  void dispose() {
    passwordRouteObserver.unsubscribe(this);
    // The native route may still be visible during its outgoing transition.
    _releaseAfterTransition();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const ColoredBox(color: Colors.black);
}
