import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../../app/Data/session_repository.dart';

/// Explain the failed completion step without treating every failure as offline.
/// Intentional service messages already describe expiry and device conflicts.
String signInCompletionErrorMessage(Object error) {
  if (error is SessionRepositoryException) return error.message;
  if (error is FirebaseFunctionsException) {
    return _serviceMessage(error.code, error.message);
  }
  if (error is FirebaseAuthException) {
    return _serviceMessage(error.code, error.message);
  }
  if (error is TimeoutException) {
    return 'Finishing sign-in took too long. Please try again.';
  }
  if (error is MissingPluginException) {
    return 'This phone’s security service is unavailable. Reopen HikerCircle and try again.';
  }
  if (error is PlatformException) {
    final code = _normalizedCode(error.code);
    if (code.contains('database') || code.contains('sqlite')) {
      return 'This phone could not open its saved data. Reopen HikerCircle and try again.';
    }
    return 'This phone’s security check could not finish. Reopen HikerCircle and try again.';
  }
  return 'Unable to finish login. Please try again.';
}

String _normalizedCode(String code) => code
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'^(functions|firebase-auth|auth)/'), '')
    .replaceAll('_', '-');

String _serviceMessage(String code, String? message) {
  final normalized = _normalizedCode(code);
  final text = message?.trim();
  // Callable frameworks sometimes provide only "UNAUTHENTICATED" or another
  // status label. Preserve explanatory backend text, rather than those labels.
  if (text != null && text.isNotEmpty && _normalizedCode(text) != normalized) {
    return text;
  }
  return switch (normalized) {
    'unauthenticated' || 'invalid-user-token' || 'user-token-expired' =>
      'Your secure login could not be verified. Start login again.',
    'failed-precondition' ||
    'aborted' => 'Your login state has changed. Start login again.',
    'not-found' || 'user-not-found' =>
      'This login session could not be found. Start login again.',
    'user-disabled' => 'This account has been disabled.',
    'permission-denied' => 'This account is not allowed to complete sign-in.',
    'invalid-argument' =>
      'The login details could not be verified. Start login again.',
    'unavailable' || 'network-request-failed' =>
      'The login service is unavailable. Check your connection and try again.',
    'deadline-exceeded' ||
    'timeout' => 'Finishing sign-in took too long. Please try again.',
    'resource-exhausted' || 'too-many-requests' =>
      'Too many login requests. Please wait before trying again.',
    _ => 'The login service could not finish this request. Please try again.',
  };
}
