import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../app/Data/firebase_app_check_guard.dart';

class GreenApiSendResult {
  const GreenApiSendResult({
    required this.wasSent,
    required this.retryable,
    this.deliveryUncertain = false,
    this.providerMessageId,
    this.message,
  });

  final bool wasSent;
  final bool retryable;
  final bool deliveryUncertain;
  final String? providerMessageId;
  final String? message;
}

class GreenApiClient {
  GreenApiClient({
    FirebaseFunctions? firebaseFunctions,
    FirebaseAuth? firebaseAuth,
    FirebaseAppCheckGuard? appCheckGuard,
  }) : _firebaseFunctions = firebaseFunctions,
       _firebaseAuth = firebaseAuth,
       _appCheckGuard = appCheckGuard ?? FirebaseAppCheckGuard();

  final FirebaseFunctions? _firebaseFunctions;
  final FirebaseAuth? _firebaseAuth;
  final FirebaseAppCheckGuard _appCheckGuard;

  FirebaseFunctions get _resolvedFunctions =>
      _firebaseFunctions ?? FirebaseFunctions.instance;

  FirebaseAuth get _resolvedAuth => _firebaseAuth ?? FirebaseAuth.instance;

  Future<GreenApiSendResult> sendMessage({
    required String chatId,
    required String dispatchId,
    required String mode,
    required DateTime triggeredAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? customNote,
    String triggerSource = 'mobile_phone',
    bool isTest = false,
  }) async {
    final digits = chatId.replaceAll(RegExp(r'\D'), '');
    const allowedModes = {
      'manual',
      'medical',
      'fall_stillness',
      'prolonged_stillness',
      'duress',
      'test',
    };
    const allowedTriggerSources = {
      'mobile_phone',
      'emergency_button',
      'automatic_detection',
    };
    if (digits.length < 8 ||
        digits.length > 15 ||
        !RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(dispatchId) ||
        !allowedModes.contains(mode) ||
        !allowedTriggerSources.contains(triggerSource) ||
        (isTest && mode != 'test') ||
        (!isTest && mode == 'test')) {
      throw const GreenApiException(
        'The emergency dispatch request is invalid.',
        retryable: false,
      );
    }
    if ((latitude == null) != (longitude == null) ||
        (latitude != null &&
            (!latitude.isFinite || latitude < -90 || latitude > 90)) ||
        (longitude != null &&
            (!longitude.isFinite || longitude < -180 || longitude > 180)) ||
        (accuracyMeters != null &&
            (!accuracyMeters.isFinite ||
                accuracyMeters < 0 ||
                accuracyMeters > 10000))) {
      throw const GreenApiException(
        'The emergency location is invalid.',
        retryable: false,
      );
    }

    try {
      await _appCheckGuard.ensureAuthorized();
      final user = _resolvedAuth.currentUser;
      if (user == null) {
        throw const GreenApiException(
          'Your secure login has expired. Reopen HikerCircle or sign in again before sending an SOS message.',
          retryable: false,
        );
      }
      // A restored local Firebase user can briefly retain an old ID token.
      // Refresh it before the safety-critical callable so Cloud Functions
      // receives the current UID and HikerCircle phone-number claims.
      await user.getIdToken(true);
      final response = await _resolvedFunctions
          .httpsCallable('sendSosWhatsAppMessage')
          .call(<String, dynamic>{
            'phoneNumber': '+$digits',
            'dispatchId': dispatchId,
            'mode': mode,
            'triggerSource': triggerSource,
            'triggeredAtLocal': triggeredAt.toUtc().toIso8601String(),
            if (latitude != null && longitude != null) ...{
              'latitude': latitude,
              'longitude': longitude,
              if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
            },
            if (customNote?.trim().isNotEmpty == true)
              'customNote': customNote!.trim(),
            'isTest': isTest,
          });
      final raw = response.data;
      if (raw is! Map) {
        throw const GreenApiException(
          'Emergency messaging returned an invalid response.',
        );
      }
      final status = raw['status']?.toString() ?? '';
      final providerMessageId = raw['idMessage']?.toString().trim();
      if (raw['sent'] == true || status == 'sent' || status == 'already_sent') {
        return GreenApiSendResult(
          wasSent: true,
          retryable: false,
          providerMessageId: providerMessageId?.isEmpty == true
              ? null
              : providerMessageId,
        );
      }
      if (status == 'delivery_uncertain') {
        return GreenApiSendResult(
          wasSent: false,
          retryable: false,
          deliveryUncertain: true,
          message:
              'Delivery could not be confirmed. To avoid a duplicate alert, HikerCircle will not resend this dispatch automatically. Call emergency services directly.',
        );
      }
      return GreenApiSendResult(
        wasSent: false,
        retryable: raw['retryable'] != false,
        message: raw['message']?.toString(),
      );
    } on FirebaseFunctionsException catch (error) {
      final retryable = const {
        'aborted',
        'deadline-exceeded',
        'internal',
        'resource-exhausted',
        'unavailable',
        'unknown',
      }.contains(error.code);
      throw GreenApiException(
        error.message ??
            'Emergency messaging is unavailable. Call emergency services directly.',
        retryable: retryable,
      );
    } on GreenApiException {
      rethrow;
    } on FirebaseAppCheckUnavailable catch (error) {
      throw GreenApiException(error.toString(), retryable: false);
    } catch (_) {
      throw const GreenApiException(
        'Emergency messaging is unavailable. Call emergency services directly.',
      );
    }
  }
}

class GreenApiException implements Exception {
  const GreenApiException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}
