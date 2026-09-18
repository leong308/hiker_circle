import 'package:flutter/material.dart';

/// Route ownership matters during async starts: a mounted page may already have
/// been popped, or a new dialog may now be above the one being closed.
abstract final class HikeStartNavigation {
  /// Reveal the home shell that owns the active-hike state, preserving any
  /// authentication/navigation history below it.
  static void revealHome(BuildContext homeContext) {
    if (!homeContext.mounted) return;
    final route = ModalRoute.of(homeContext);
    final navigator = route?.navigator;
    if (route == null || !route.isActive || navigator == null) return;
    navigator.popUntil((candidate) => identical(candidate, route));
  }

  /// Close only this route; late cleanup must never pop the new top route.
  static void closeOwnedRoute<T>(Route<T>? route, [T? result]) {
    final navigator = route?.navigator;
    if (route == null ||
        !route.isActive ||
        route.isFirst ||
        navigator == null) {
      return;
    }
    if (route.isCurrent) {
      navigator.pop<T>(result);
    } else {
      navigator.removeRoute<T>(route, result);
    }
  }

  /// Complete a nested flow (for example, team readiness with a safety page
  /// above it) and deliver its result exactly to that flow's caller.
  static void completeFlow<T>(Route<T>? route, [T? result]) {
    final navigator = route?.navigator;
    if (route == null ||
        !route.isActive ||
        route.isFirst ||
        navigator == null) {
      return;
    }
    navigator.popUntil((candidate) => identical(candidate, route));
    closeOwnedRoute(route, result);
  }
}
