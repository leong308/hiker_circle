import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Debug-only stage markers. Never include request bodies, identifiers or tokens.
abstract final class AuthFlowDiagnostics {
  static void event(
    String stage,
    String event, {
    Object? error,
    int? elapsedMilliseconds,
  }) {
    if (!kDebugMode) return;
    final code = switch (error) {
      FirebaseException value => value.code,
      PlatformException value => value.code,
      _ => null,
    };
    debugPrint(
      'HikerCircle.Auth stage=$stage event=$event'
      '${error == null ? '' : ' errorType=${error.runtimeType}'}'
      '${elapsedMilliseconds == null ? '' : ' elapsedMs=$elapsedMilliseconds'}'
      '${code == null ? '' : ' code=${code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}'}',
    );
  }
}
