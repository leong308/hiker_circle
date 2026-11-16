import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum AccountDeletionPhase { idle, requesting, clearing, thanking, fading }

/// Deletes the main account record and Firebase Auth login, then signs out.
/// Location records, hiking histories, uploads and native data are retained.
class AccountDeletionService extends ChangeNotifier {
  AccountDeletionService({
    Future<Map<String, dynamic>> Function(String, Map<String, Object?>)? call,
    Future<String?> Function()? currentOwner,
    Future<void> Function()? signOut,
    this.thankYouDuration = const Duration(seconds: 4),
    this.fadeDuration = const Duration(milliseconds: 1200),
  }) : _call = call ?? _firebaseCall,
       _currentOwner =
           currentOwner ?? (() async => FirebaseAuth.instance.currentUser?.uid),
       _signOut = signOut ?? (() => FirebaseAuth.instance.signOut());

  static final instance = AccountDeletionService();
  final Future<Map<String, dynamic>> Function(String, Map<String, Object?>)
  _call;
  final Future<String?> Function() _currentOwner;
  final Future<void> Function() _signOut;
  final Duration thankYouDuration;
  final Duration fadeDuration;
  AccountDeletionPhase phase = AccountDeletionPhase.idle;
  bool accepted = false;
  String? deletedOwner;
  Future<void>? _running;
  Timer? _timer;

  static Future<Map<String, dynamic>> _firebaseCall(
    String name,
    Map<String, Object?> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        )
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  void _set(AccountDeletionPhase value) {
    phase = value;
    notifyListeners();
  }

  Future<void> deleteAccount(String owner) =>
      _running ??= _delete(owner).whenComplete(() => _running = null);

  Future<void> _delete(String owner) async {
    if (accepted) return;
    if (await _currentOwner() != owner) {
      throw StateError('Sign in to delete your own account.');
    }
    _set(AccountDeletionPhase.requesting);
    try {
      final result = await _call('deleteHikerCircleAccount', {
        'expectedOwner': owner,
        'confirmation': 'DELETE',
      });
      if (result['deleted'] != true) {
        throw StateError('Account deletion was not confirmed.');
      }
      accepted = true;
      deletedOwner = owner;
      _set(AccountDeletionPhase.clearing);
      // The app root also uses its normal session sign-out when this is accepted.
      try {
        await _signOut();
      } catch (_) {}
      _set(AccountDeletionPhase.thanking);
      _timer = Timer(thankYouDuration, () {
        _set(AccountDeletionPhase.fading);
        _timer = Timer(fadeDuration, () {
          accepted = false;
          deletedOwner = null;
          _set(AccountDeletionPhase.idle);
        });
      });
    } catch (_) {
      _set(AccountDeletionPhase.idle);
      rethrow;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
