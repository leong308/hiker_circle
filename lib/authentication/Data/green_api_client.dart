// GreenApiClient submits validated WhatsApp SOS dispatch requests through the backend.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Represents green api send result.
class GreenApiSendResult {
  /// Creates green api send result.
  const GreenApiSendResult({
    required this.wasSent,
    required this.retryable,
    this.deliveryUncertain = false,
    this.confirmationStatus = '',
    this.providerMessageId,
    this.message,
  });

  final bool wasSent;
  final bool retryable;
  final bool deliveryUncertain;
  final String confirmationStatus;
  final String? providerMessageId;
  final String? message;
}

/// Represents green api client.
class GreenApiClient {
  /// Creates green api client.
  GreenApiClient({
    FirebaseFunctions? firebaseFunctions,
    FirebaseAuth? firebaseAuth,
  }) : _firebaseFunctions = firebaseFunctions,
       _firebaseAuth = firebaseAuth;

  final FirebaseFunctions? _firebaseFunctions;
  final FirebaseAuth? _firebaseAuth;

  /// Returns resolved functions.
  FirebaseFunctions get _resolvedFunctions =>
      _firebaseFunctions ?? FirebaseFunctions.instance;

  /// Returns resolved auth.
  FirebaseAuth get _resolvedAuth => _firebaseAuth ?? FirebaseAuth.instance;

  /// Validate SOS dispatch identity and preserve retryable or uncertain delivery results from the backend.
  Future<GreenApiSendResult> sendMessage({
    required String chatId,
    required String dispatchId,
    required String mode,
    required DateTime triggeredAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? customNote,
    String? shirtColor,
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
      final user = _resolvedAuth.currentUser;
      if (user == null) {
        throw const GreenApiException(
          'Your secure login has expired. Reopen HikerCircle or sign in again before sending an SOS message.',
          retryable: false,
        );
      }
      // The callable SDK attaches both Auth and App Check credentials. Avoid
      // separate token lookups here: either can perform an extra network
      // refresh before the emergency request even reaches Firebase.
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
            if (!isTest && shirtColor != null) 'shirtColor': shirtColor,
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
      if (status == 'delivery_uncertain' ||
          (!isTest && status == 'in_progress')) {
        return GreenApiSendResult(
          wasSent: false,
          retryable: false,
          deliveryUncertain: status == 'delivery_uncertain',
          confirmationStatus: status == 'in_progress'
              ? 'sending'
              : 'unconfirmed',
          message:
              'No confirmation yet. HikerCircle is checking this contact without blindly resending.',
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
    } catch (_) {
      throw const GreenApiException(
        'Emergency messaging is unavailable. Call emergency services directly.',
      );
    }
  }
}

/// Represents green api exception.
class GreenApiException implements Exception {
  /// Creates green api exception.
  const GreenApiException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  /// Converts to string.
  @override
  String toString() => message;
}
