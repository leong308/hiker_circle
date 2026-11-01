// HikerCircleFirebaseRepository connects hike, chat, community and safety workflows to validated
// cloud operations and durable local queues.
import 'conditional_cloud_cache.dart';
import '../../achievements/Model/achievement_progress.dart';
import '../../achievements/Model/achievement_catalog.dart';
import '../../achievements/Data/achievement_notification_events.dart';
export '../../achievements/Model/achievement_progress.dart'
    show achievementProgressContentHash;
import '../../core/services/content_hash.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_module_paths.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/hiker_level.dart';
import '../../core/services/open_meteo_service.dart';
import '../../core/services/trail_geometry_storage.dart';
import '../../core/services/hiking_route_service.dart';
import '../../home/Model/hike_session_models.dart';
import '../../home/Model/upcoming_hike_request_inbox.dart';
import '../../home/Data/active_hike_live_status_service.dart';
import '../../home/Data/planned_hike_state_service.dart';
import '../../me/Model/hike_history_models.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/Model/nearby_sos_event.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/Model/trail_hazard_alert.dart';
import '../../trail/Model/trail_hazard_assessment.dart';
import '../../trail/Data/trail_caution_service.dart';
import '../../trail/Data/trail_checkpoint_weather_repository.dart';
import '../../trail/Model/trail_weather_location.dart';
import '../Model/app_session.dart';
import '../Model/community_post_draft.dart';
export '../Model/community_post_draft.dart';
import '../Model/preferred_time_zone.dart';
import 'firebase_bootstrap.dart';
import 'hike_completion_request.dart';
import 'firebase_user_repository.dart';
import 'local_session_database.dart';

part 'community_post_repository.dart';
part 'mobile_read_repository.dart';

const Set<String> _upcomingHikePreviewFields = {
  'sessionId',
  'trailId',
  'trailName',
  'latitude',
  'longitude',
  'area',
  'state',
  'country',
  'distanceKm',
  'durationMinutes',
  'difficulty',
  'startPointName',
  'destinationName',
  'departureTimeLocal',
  'departureTime',
  'expectedReturnTimeLocal',
  'expectedReturnTime',
  'hikeType',
  'participantCount',
  'creatorPhone',
  'creatorName',
  'createdAt',
  'createdAtLocal',
  'participantPhones',
  'joinRequestStatus',
  'joinPolicy',
  'departureReminderCount',
  'departureReminderSentByMe',
  'isDeleted',
  'deletedAtLocal',
};

/// Parses upcoming hike preview payload.
@visibleForTesting
List<UpcomingHike> parseUpcomingHikePreviewPayload(Object? payload) {
  if (payload is! Map) {
    return const [];
  }
  final rawHikes = payload['hikes'];
  if (rawHikes is! List) {
    return const [];
  }

  final hikes = <UpcomingHike>[];
  final seenIds = <String>{};
  for (final rawHike in rawHikes) {
    if (rawHike is! Map) {
      continue;
    }
    final rawId = rawHike['id'];
    if (rawId is! String) {
      continue;
    }
    final id = rawId.trim();
    if (id.isEmpty || seenIds.contains(id)) {
      continue;
    }

    final data = <String, dynamic>{};
    for (final entry in rawHike.entries) {
      final key = entry.key;
      if (key is String && _upcomingHikePreviewFields.contains(key)) {
        data[key] = entry.value;
      }
    }
    data['departureTimeLocal'] ??= data['departureTime'];
    data['expectedReturnTimeLocal'] ??= data['expectedReturnTime'];
    data['createdAt'] ??= data['createdAtLocal'];
    try {
      hikes.add(UpcomingHike.fromFirestore(id, data));
      seenIds.add(id);
    } catch (_) {
      // A malformed preview must not hide otherwise valid nearby hikes.
    }
  }
  return hikes;
}

/// Represents hiker circle firebase repository exception.
class HikerCircleFirebaseRepositoryException implements Exception {
  /// Creates hiker circle firebase repository exception.
  const HikerCircleFirebaseRepositoryException(
    this.message, {
    this.allowsOfflineFallback = false,
  });

  final String message;
  final bool allowsOfflineFallback;

  /// Converts to string.
  @override
  String toString() => message;
}

/// Represents buddy relationships.
class BuddyRelationships {
  /// Creates buddy relationships.
  const BuddyRelationships({
    required this.buddyPhoneNumbers,
    required this.outgoingRequestPhones,
    required this.incomingRequests,
  });

  final Set<String> buddyPhoneNumbers;
  final Set<String> outgoingRequestPhones;
  final List<Map<String, dynamic>> incomingRequests;
}

/// Represents nearby sos forward result.
class NearbySosForwardResult {
  /// Creates nearby sos forward result.
  const NearbySosForwardResult({
    required this.incidentId,
    required this.deduplicated,
    required this.reporterCount,
  });

  final String incidentId;
  final bool deduplicated;
  final int reporterCount;
}

/// Represents live location contact notification result.
class LiveLocationContactNotificationResult {
  /// Creates live location contact notification result.
  const LiveLocationContactNotificationResult({
    required this.contactCount,
    required this.sentCount,
    required this.retryableFailureCount,
    required this.uncertainCount,
    required this.inProgressCount,
    required this.failedCount,
  });

  final int contactCount;
  final int sentCount;
  final int retryableFailureCount;
  final int uncertainCount;
  final int inProgressCount;
  final int failedCount;

  /// Returns should retry.
  bool get shouldRetry => retryableFailureCount > 0 || inProgressCount > 0;
}

/// Computes active hike start allows offline fallback for functions code.
@visibleForTesting
bool activeHikeStartAllowsOfflineFallbackForFunctionsCode(String code) {
  return const {
    'aborted',
    'cancelled',
    'data-loss',
    'deadline-exceeded',
    'internal',
    'unavailable',
    'unknown',
  }.contains(code.trim().toLowerCase());
}

/// Represents active hike cloud restore result.
@immutable
class ActiveHikeCloudRestoreResult {
  /// Creates active hike cloud restore result.
  const ActiveHikeCloudRestoreResult({
    required this.sessionId,
    required this.ensured,
    required this.terminal,
    required this.status,
  });

  final String sessionId;
  final bool ensured;
  final bool terminal;
  final String status;
}

/// Represents active hike cloud completion result.
@immutable
class ActiveHikeCloudCompletionResult {
  /// Creates active hike cloud completion result.
  const ActiveHikeCloudCompletionResult({
    required this.sessionId,
    required this.completed,
    required this.terminal,
    required this.status,
  });

  final String sessionId;
  final bool completed;
  final bool terminal;
  final String status;
}

/// Represents active hike end result.
@immutable
class ActiveHikeEndResult {
  /// Creates active hike end result.
  const ActiveHikeEndResult({
    required this.cloudSynced,
    required this.sessionId,
    required this.completed,
    required this.status,
  });

  final bool cloudSynced;
  final String sessionId;
  final bool completed;
  final String status;

  /// Allows feedback after the durable local save, including pending cloud sync.
  bool get canCollectFeedback =>
      status == 'pending' || (completed && status == 'completed');
}

/// Represents active hike post completion sync exception.
class _ActiveHikePostCompletionSyncException implements Exception {
  /// Creates active hike post completion sync exception.
  const _ActiveHikePostCompletionSyncException({
    required this.completion,
    required this.cause,
  });

  final ActiveHikeCloudCompletionResult completion;
  final Object cause;

  /// Converts to string.
  @override
  String toString() => cause.toString();
}

const Set<String> _terminalActiveHikeStatuses = {
  'completed',
  'abandoned',
  'cancelled',
  'canceled',
  'expired',
};

/// Parses active hike cloud restore result.
@visibleForTesting
ActiveHikeCloudRestoreResult parseActiveHikeCloudRestoreResult(
  Object? payload, {
  required String requestedSessionId,
}) {
  final data = _callableMapFrom(payload);
  final responseSessionId = _topLevelStringFrom(data['sessionId']).trim();
  if (!_isValidCloudDocumentId(requestedSessionId) ||
      !_isValidCloudDocumentId(responseSessionId)) {
    throw const HikerCircleFirebaseRepositoryException(
      'The hike server returned an invalid recovery session.',
    );
  }

  final rawStatus = _topLevelStringFrom(data['status']).trim().toLowerCase();
  final explicitTerminal = data['terminal'] == true;
  final terminal =
      explicitTerminal || _terminalActiveHikeStatuses.contains(rawStatus);
  final ensured = data['ensured'] == true && !terminal;
  final status = rawStatus.isNotEmpty
      ? rawStatus
      : terminal
      ? 'completed'
      : ensured
      ? 'active'
      : 'unknown';
  return ActiveHikeCloudRestoreResult(
    sessionId: responseSessionId,
    ensured: ensured,
    terminal: terminal,
    status: status,
  );
}

/// Parses active hike cloud completion result.
@visibleForTesting
ActiveHikeCloudCompletionResult parseActiveHikeCloudCompletionResult(
  Object? payload, {
  required String requestedSessionId,
}) {
  final data = _callableMapFrom(payload);
  final responseSessionId = _topLevelStringFrom(data['sessionId']).trim();
  final status = _topLevelStringFrom(data['status']).trim().toLowerCase();
  final terminal =
      data['terminal'] == true || _terminalActiveHikeStatuses.contains(status);
  if (!_isValidCloudDocumentId(requestedSessionId) ||
      !_isValidCloudDocumentId(responseSessionId) ||
      !terminal) {
    throw const HikerCircleFirebaseRepositoryException(
      'The hike server returned an invalid completion result.',
    );
  }
  return ActiveHikeCloudCompletionResult(
    sessionId: responseSessionId,
    completed: data['completed'] == true || status == 'completed',
    terminal: true,
    status: status.isEmpty ? 'completed' : status,
  );
}

/// Computes team hike creation key for.
@visibleForTesting
String teamHikeCreationKeyFor({
  required String appInstanceId,
  required String trailId,
  required DateTime departureTime,
  required Iterable<String> inviteePhoneNumbers,
  String sourceUpcomingHikeId = '',
}) {
  final canonicalInvitees =
      inviteePhoneNumbers
          .map((phoneNumber) => phoneNumber.trim())
          .where((phoneNumber) => phoneNumber.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final canonicalInput = jsonEncode([
    appInstanceId.trim(),
    trailId.trim(),
    departureTime.toUtc().toIso8601String(),
    canonicalInvitees,
    sourceUpcomingHikeId.trim(),
  ]);
  final digest = crypto.sha256.convert(utf8.encode(canonicalInput));
  return 'team_create_$digest';
}

/// Computes upcoming hike creation key for.
@visibleForTesting
String upcomingHikeCreationKeyFor({
  required String appInstanceId,
  required String trailId,
  required DateTime departureTime,
  required DateTime expectedReturnTime,
  required HikeType hikeType,
  required String startPointName,
  required String destinationName,
  required Iterable<String> inviteePhoneNumbers,
}) {
  final canonicalInvitees =
      inviteePhoneNumbers
          .map((phoneNumber) => phoneNumber.trim())
          .where((phoneNumber) => phoneNumber.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final canonicalInput = jsonEncode([
    appInstanceId.trim(),
    trailId.trim(),
    departureTime.toUtc().toIso8601String(),
    expectedReturnTime.toUtc().toIso8601String(),
    hikeType.name,
    startPointName.trim(),
    destinationName.trim(),
    canonicalInvitees,
  ]);
  final digest = crypto.sha256.convert(utf8.encode(canonicalInput));
  return 'schedule_$digest';
}

/// Builds active hike completion payload.
@visibleForTesting
Map<String, dynamic> buildActiveHikeCompletionPayload({
  required ActiveHikeSession activeHike,
  required DateTime endedAt,
  HikeSummaryReport? summary,
}) {
  final sessionId = activeHike.sessionId.trim();
  final trailId = activeHike.trail.trailId.trim();
  final teamHikeSessionId = activeHike.teamHikeSessionId.trim();
  final sourceUpcomingHikeId = activeHike.sourceUpcomingHikeId.trim();
  final startedAtUtc = activeHike.startedAt.toUtc();
  final endedAtUtc = endedAt.toUtc();
  final duration = endedAtUtc.difference(startedAtUtc);
  if (!_isValidCloudDocumentId(sessionId) ||
      !_isValidCloudDocumentId(trailId) ||
      (teamHikeSessionId.isNotEmpty &&
          !_isValidCloudDocumentId(teamHikeSessionId)) ||
      (sourceUpcomingHikeId.isNotEmpty &&
          !_isValidCloudDocumentId(sourceUpcomingHikeId)) ||
      duration.isNegative) {
    throw const HikerCircleFirebaseRepositoryException(
      'The saved hike completion data is invalid.',
    );
  }
  final offlineMatch = RegExp(r'^session_([0-9]{13})$').firstMatch(sessionId);
  if (offlineMatch != null) {
    final encodedStart = int.tryParse(offlineMatch.group(1)!);
    if (encodedStart == null ||
        (startedAtUtc.millisecondsSinceEpoch - encodedStart).abs() >
            const Duration(minutes: 10).inMilliseconds) {
      throw const HikerCircleFirebaseRepositoryException(
        'The saved offline hike does not match its start time.',
      );
    }
  }

  final effectiveSummary =
      summary ??
      HikeSummaryReport.fromActiveHike(
        activeHike: activeHike,
        endedAt: endedAtUtc,
      );
  final distanceKm = effectiveSummary.distanceKm.isFinite
      ? effectiveSummary.distanceKm.clamp(0, 5000).toDouble()
      : 0.0;
  return {
    'sessionId': sessionId,
    'draft': activeHike.draft.toPersistence(),
    if (activeHike.latestLocation != null)
      'lastRecordedLocation': activeHike.latestLocation!.toFirestore(),
    'startedAtLocal': startedAtUtc.toIso8601String(),
    'endedAtLocal': endedAtUtc.toIso8601String(),
    if (teamHikeSessionId.isNotEmpty) 'teamHikeSessionId': teamHikeSessionId,
    if (sourceUpcomingHikeId.isNotEmpty)
      'sourceUpcomingHikeId': sourceUpcomingHikeId,
    'summary': {
      'distanceKm': distanceKm,
      'checkIns': effectiveSummary.checkIns.clamp(0, 100000),
      'manualPins': effectiveSummary.manualPins.clamp(0, 100000),
      'routePointCount': effectiveSummary.routePointCount.clamp(0, 1000000),
      'batteryStartPercent': effectiveSummary.batteryStartPercent.clamp(0, 100),
      'batteryEndPercent': effectiveSummary.batteryEndPercent.clamp(0, 100),
    },
  };
}

/// Computes downsample hike route for cloud.
@visibleForTesting
List<HikeCoordinate> downsampleHikeRouteForCloud(
  Iterable<HikeCoordinate> routePoints, {
  int maxPoints = 1200,
}) {
  if (maxPoints <= 0) {
    return const [];
  }
  final points = routePoints.where((point) => point.hasValidPosition).toList()
    ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  return _evenlyDownsample(points, maxPoints: maxPoints);
}

/// Computes callable map from.
Map<String, dynamic> _callableMapFrom(Object? payload) {
  if (payload is! Map) {
    throw const HikerCircleFirebaseRepositoryException(
      'The hike server returned an invalid response.',
    );
  }
  return Map<String, dynamic>.from(payload);
}

/// Computes top level string from.
String _topLevelStringFrom(Object? value) => value is String ? value : '';

/// Checks whether valid cloud document id.
bool _isValidCloudDocumentId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 200 ||
      normalized.contains('/')) {
    return false;
  }
  return !normalized.codeUnits.any((codeUnit) => codeUnit < 0x20);
}

/// Computes evenly downsample.
List<T> _evenlyDownsample<T>(List<T> values, {required int maxPoints}) {
  if (values.length <= maxPoints) {
    return List<T>.unmodifiable(values);
  }
  if (maxPoints == 1) {
    return List<T>.unmodifiable([values.last]);
  }
  final lastIndex = values.length - 1;
  final step = lastIndex / (maxPoints - 1);
  return List<T>.unmodifiable([
    for (var index = 0; index < maxPoints; index++)
      values[(index * step).round()],
  ]);
}

/// Represents admin trail image upload.
class AdminTrailImageUpload {
  /// Creates admin trail image upload.
  const AdminTrailImageUpload({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

/// Computes acknowledged location sample times.
@visibleForTesting
Set<int> acknowledgedLocationSampleTimes(
  Object? payload, {
  required String sessionId,
  required Set<int> requestedTimes,
}) {
  if (payload is! Map ||
      payload['sessionId'] != sessionId ||
      payload['committedRecordedAtMillis'] is! List) {
    return {};
  }
  final times = payload['committedRecordedAtMillis'] as List;
  if (payload['committedCount'] != times.length) return {};
  final acknowledged = <int>{};
  for (final time in times) {
    if (time is! num ||
        !time.isFinite ||
        time != time.toInt() ||
        !requestedTimes.contains(time.toInt()) ||
        !acknowledged.add(time.toInt())) {
      return {};
    }
  }
  return acknowledged;
}

/// Represents hiker circle firebase repository.
class HikerCircleFirebaseRepository {
  /// Creates hiker circle firebase repository.
  HikerCircleFirebaseRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    String? Function()? authenticatedUid,
    LocalSessionDatabase? localDatabase,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
    OpenMeteoService? openMeteoService,
    ConditionalCloudCache? readCache,
    @visibleForTesting
    Future<String> Function(Map<String, dynamic>)? scheduleHikeRequest,
    @visibleForTesting
    Future<void> Function(String, HikeReminderPreference)?
    reminderPreferenceRequest,
  }) : _firestore = firestore,
       _storage = storage,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _firebaseBootstrapResult = firebaseBootstrapResult,
       _functions = functions,
       _authenticatedUid = authenticatedUid,
       _providedReadCache = readCache,
       _scheduleHikeRequest = scheduleHikeRequest,
       _reminderPreferenceRequest = reminderPreferenceRequest;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final FirebaseFunctions? _functions;
  final String? Function()? _authenticatedUid;
  final ConditionalCloudCache? _providedReadCache;
  final Future<String> Function(Map<String, dynamic>)? _scheduleHikeRequest;
  final Future<void> Function(String, HikeReminderPreference)?
  _reminderPreferenceRequest;
  static final _planningChanges = StreamController<String>.broadcast();

  /// Returns planning changes.
  static Stream<String> get planningChanges => _planningChanges.stream;
  static final Map<String, Future<void>> _planningSyncs = {};
  final Map<String, String> _teamHikeCreationRetryKeys = {};
  final LocalSessionDatabase _localDatabase;
  late final _conditionalCache =
      _providedReadCache ??
      ConditionalCloudCache(_localDatabase, () => _resolvedFunctions);
  String? _trailCacheHash;

  final FirebaseBootstrapResult _firebaseBootstrapResult;

  static const Duration _firebaseReadTimeout = Duration(seconds: 12);
  static const Duration _firebaseWriteTimeout = Duration(seconds: 8);

  /// Returns local database.
  LocalSessionDatabase get localDatabase => _localDatabase;

  /// Returns resolved firestore.
  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  /// Returns firestore.
  FirebaseFirestore get firestore => _resolvedFirestore;

  /// Returns resolved storage.
  FirebaseStorage get _resolvedStorage => _storage ?? FirebaseStorage.instance;

  /// Returns resolved functions.
  FirebaseFunctions get _resolvedFunctions {
    _throwIfFirebaseUnavailable();
    return _functions ?? FirebaseFunctions.instance;
  }

  /// Captures account uid.
  String? _captureAccountUid(AppSession session) {
    try {
      final uid = _authenticatedUid != null
          ? _authenticatedUid()
          : FirebaseAuth.instance.currentUser?.uid;
      return uid == _userIdFor(session) ? uid : null;
    } catch (_) {
      return null;
    }
  }

  /// Computes account still matches.
  bool _accountStillMatches(AppSession session, String uid) =>
      _captureAccountUid(session) == uid;

  /// Computes require same account.
  void _requireSameAccount(AppSession session, String uid) {
    if (!_accountStillMatches(session, uid)) {
      throw const HikerCircleFirebaseRepositoryException(
        'The signed-in account changed. Saved hike data will retry for its owner.',
      );
    }
  }

  /// Computes register fcm token.
  Future<void> registerFcmToken({
    required AppSession session,
    required String token,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable ||
        token.isEmpty ||
        session.appInstanceId.isEmpty) {
      return;
    }
    final device = _moduleFor(session, UserModule.devices);
    await _resolvedFirestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(device);
      if (snapshot.data()?['boundAppInstanceId'] != session.appInstanceId) {
        return;
      }
      transaction.set(device, {
        'fcmTokenByAppId': {session.appInstanceId: token},
        'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'lastFcmTokenUpdatedAtLocal': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    });
  }

  /// Removes fcm token.
  Future<void> removeFcmToken({required AppSession session}) async {
    if (!_firebaseBootstrapResult.isAvailable ||
        session.appInstanceId.isEmpty) {
      return;
    }
    final device = _moduleFor(session, UserModule.devices);
    await _resolvedFirestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(device);
      if (!snapshot.exists) {
        return;
      }
      final updates = <String, dynamic>{
        'fcmTokenByAppId.${session.appInstanceId}': FieldValue.delete(),
      };
      if (snapshot.data()?['boundAppInstanceId'] == session.appInstanceId) {
        updates['boundAppInstanceId'] = FieldValue.delete();
      }
      transaction.update(device, updates);
    });
  }

  /// Updates active hike monitoring heartbeat.
  Future<void> updateActiveHikeMonitoringHeartbeat({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required String lifecycleState,
    String fcmToken = '',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _hikeSessions.doc(activeHike.sessionId).set({
      'monitoringHeartbeatAt': FieldValue.serverTimestamp(),
      'monitoringHeartbeatAtLocal': now.toIso8601String(),
      'monitoringLifecycleState': lifecycleState,
      'monitoringExpected': true,
      if (fcmToken.isNotEmpty) 'monitoringFcmToken': fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Computes signal active hike potential termination.
  Future<void> signalActiveHikePotentialTermination({
    required AppSession session,
    required ActiveHikeSession activeHike,
    String fcmToken = '',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _hikeSessions.doc(activeHike.sessionId).set({
      'terminationSignalNonce':
          '${now.microsecondsSinceEpoch}_${session.phoneNumber.hashCode}',
      'terminationSignalAt': FieldValue.serverTimestamp(),
      'terminationSignalAtLocal': now.toIso8601String(),
      'monitoringLifecycleState': 'detached',
      'monitoringExpected': true,
      if (fcmToken.isNotEmpty) 'monitoringFcmToken': fcmToken,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Returns trails.
  CollectionReference<Map<String, dynamic>> get _trails =>
      _resolvedFirestore.collection('trails');

  /// Returns users.
  CollectionReference<Map<String, dynamic>> get _users =>
      _resolvedFirestore.collection('users');

  /// Computes module for.
  DocumentReference<Map<String, dynamic>> _moduleFor(
    AppSession session,
    UserModule module,
  ) => userModuleDocument(_users.doc(_userIdFor(session)), module);

  /// Returns hike sessions.
  CollectionReference<Map<String, dynamic>> get _hikeSessions =>
      _resolvedFirestore.collection('hikeSessions');

  /// Returns hazard reports.
  CollectionReference<Map<String, dynamic>> get _hazardReports =>
      _resolvedFirestore.collection('hazardReports');

  /// Returns upcoming hikes.
  CollectionReference<Map<String, dynamic>> get _upcomingHikes =>
      _resolvedFirestore.collection('upcomingHikes');

  /// Returns team hike sessions.
  CollectionReference<Map<String, dynamic>> get _teamHikeSessions =>
      _resolvedFirestore.collection('teamHikeSessions');

  /// Returns community posts.
  CollectionReference<Map<String, dynamic>> get _communityPosts =>
      _resolvedFirestore.collection('communityPosts');

  /// Returns sos alerts.
  CollectionReference<Map<String, dynamic>> get _sosAlerts =>
      _resolvedFirestore.collection('sosAlerts');

  /// Computes community comments for.
  CollectionReference<Map<String, dynamic>> _communityCommentsFor(
    String postId,
  ) {
    return _communityPosts.doc(postId).collection('comments');
  }

  /// Returns achievements.
  CollectionReference<Map<String, dynamic>> get _achievements =>
      _resolvedFirestore.collection('achievements');

  /// Returns user achievements.
  CollectionReference<Map<String, dynamic>> get _userAchievements =>
      _resolvedFirestore.collection('userAchievements');

  /// Returns network observations.
  CollectionReference<Map<String, dynamic>> get _networkObservations =>
      _resolvedFirestore.collection('networkObservations');

  /// Returns hike route captures.
  CollectionReference<Map<String, dynamic>> get _hikeRouteCaptures =>
      _resolvedFirestore.collection('hikeRouteCaptures');

  /// Returns group chats.
  CollectionReference<Map<String, dynamic>> get _groupChats =>
      _resolvedFirestore.collection('groupChats');

  /// Computes group chat messages for.
  CollectionReference<Map<String, dynamic>> _groupChatMessagesFor(
    String chatId,
  ) {
    return _groupChats.doc(chatId).collection('messages');
  }

  /// Loads the server catalogue first, with a local fallback when unavailable.
  /// A content hash avoids rewriting an unchanged local catalogue.
  Future<List<Trail>> loadTrails() async {
    final cached = await _loadCachedTrails();
    if (!_firebaseBootstrapResult.isAvailable) {
      return cached;
    }

    try {
      final snapshot = await _trails
          .orderBy('isVerifiedTrail', descending: true)
          .orderBy('ratingAverage', descending: true)
          .get(const GetOptions(source: Source.server))
          .timeout(_firebaseReadTimeout);
      var liveTrails = snapshot.docs
          .map(
            (document) => _trailFromFirestore({
              'trailId': document.id,
              ...document.data(),
            }),
          )
          .whereType<Trail>()
          .toList();

      await _enrichWithLiveWeather(liveTrails, snapshot.docs);
      await _cacheTrails(liveTrails);
      return liveTrails;
    } catch (_) {
      return cached;
    }
  }

  /// Try the server before using the local catalogue; live updates remain authoritative.
  Stream<List<Trail>> watchTrails() async* {
    yield await loadTrails();
    if (!_firebaseBootstrapResult.isAvailable) return;
    yield* _trails
        .orderBy('isVerifiedTrail', descending: true)
        .orderBy('ratingAverage', descending: true)
        .snapshots(includeMetadataChanges: true)
        .where((snapshot) => !snapshot.metadata.isFromCache)
        .asyncMap((snapshot) async {
          final trails = snapshot.docs
              .map(
                (doc) =>
                    _trailFromFirestore({'trailId': doc.id, ...doc.data()}),
              )
              .whereType<Trail>()
              .toList();
          await _enrichWithLiveWeather(trails, snapshot.docs);
          await _cacheTrails(trails);
          return trails;
        })
        .handleError((Object _, StackTrace __) {});
  }

  /// Loads cached trails.
  Future<List<Trail>> _loadCachedTrails() async {
    try {
      final rows = await _localDatabase.loadCachedEntities(
        ownerPhoneNumber: '',
        entityType: 'trail',
        includeExpired: true,
      );
      return rows.map((row) => Trail.fromPersistence(row.payload)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Computes cache trails.
  Future<void> _cacheTrails(List<Trail> trails) async {
    final payload = trails.map((trail) => trail.toPersistence()).toList();
    final hash = stableContentHash(payload);
    _trailCacheHash ??= stableContentHash(
      (await _loadCachedTrails())
          .map((trail) => trail.toPersistence())
          .toList(),
    );
    if (_trailCacheHash == hash) return;
    final now = DateTime.now().toUtc();
    await _localDatabase.replaceCachedEntitySet(
      ownerPhoneNumber: '',
      entityType: 'trail',
      entities: trails
          .map(
            (trail) => LocalCachedEntity(
              ownerPhoneNumber: '',
              entityType: 'trail',
              entityId: trail.trailId,
              parentId: '',
              payload: trail.toPersistence(),
              cachedAt: now,
            ),
          )
          .toList(),
    );
    _trailCacheHash = hash;
  }

  /// Computes enrich with live weather.
  Future<void> _enrichWithLiveWeather(
    List<Trail> trails,
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    // Shared server cache owns provider fetches. A mobile snapshot never writes
    // weather back into Firestore or calls the provider independently.
    await Future.wait(
      trails.map((trail) async {
        if (!trail.weather.isStale) return;
        try {
          final data = await _conditionalCache.read(
            owner: '',
            type: 'trail_weather',
            policy: CacheReadPolicy.cloudFirst,
            registerForReconciliation: false,
            id: '${trail.trailId}:${trail.latitude.toStringAsFixed(4)}:${trail.longitude.toStringAsFixed(4)}',
            callable: 'fetchWeatherForTrail',
            arguments: {'trailId': trail.trailId},
            freshness: TrailWeather.cacheFreshness,
            online: _firebaseBootstrapResult.isAvailable,
          );
          final raw = data['weather'];
          if (raw is Map) {
            final index = trails.indexOf(trail);
            if (index >= 0) {
              trails[index] = trail.copyWith(
                weather: TrailWeather.fromPersistence(
                  Map<String, dynamic>.from(raw),
                ),
              );
            }
          }
        } catch (_) {
          /* Retain the last forecast and its truthful freshness. */
        }
      }),
    );
  }

  /// Refreshes trail weather via cloud.
  Future<Trail> refreshTrailWeatherViaCloud(Trail trail) async {
    final data = await _conditionalCache.read(
      owner: '',
      type: 'trail_weather',
      policy: CacheReadPolicy.cloudFirst,
      registerForReconciliation: false,
      id: '${trail.trailId}:${trail.latitude.toStringAsFixed(4)}:${trail.longitude.toStringAsFixed(4)}',
      callable: 'fetchWeatherForTrail',
      arguments: {'trailId': trail.trailId},
      freshness: TrailWeather.cacheFreshness,
      online: _firebaseBootstrapResult.isAvailable,
      force: true,
    );
    return data['weather'] is Map
        ? trail.copyWith(weather: weatherFromFirestore(data['weather']))
        : trail;
  }

  /// Uses the trail's shared forecast; manual reload may refresh after 15 minutes.
  Future<TrailWeather> loadTrailWeatherForecast(
    String trailId, {
    bool refresh = false,
  }) async {
    if (trailId.trim().isEmpty) {
      throw const FormatException(
        'A saved trail is required for this forecast.',
      );
    }
    final data = await _conditionalCache.read(
      owner: '',
      type: 'trail_weather',
      policy: CacheReadPolicy.cloudFirst,
      registerForReconciliation: false,
      id: trailId.trim(),
      callable: 'fetchWeatherForTrail',
      arguments: {
        'trailId': trailId.trim(),
        if (refresh) 'refreshIfOlderThanMinutes': 15,
      },
      freshness: TrailWeather.cacheFreshness,
      online: _firebaseBootstrapResult.isAvailable,
      force: refresh,
    );
    final raw = data['weather'];
    if (raw is! Map) {
      throw const FormatException('The trail forecast is unavailable.');
    }
    return TrailWeather.fromPersistence(Map<String, dynamic>.from(raw));
  }

  /// Reads a shared checkpoint forecast without replacing the default trailhead weather.
  Stream<TrailWeather> watchTrailCheckpointWeather(
    Trail trail,
    TrailWeatherLocation location,
  ) => TrailCheckpointWeatherRepository(
    readCached: (trailId, checkpointKey) async =>
        (await _resolvedFirestore
                .collection('trails')
                .doc(trailId)
                .collection('checkpointWeather')
                .doc(checkpointKey)
                .get()
                .timeout(_firebaseReadTimeout))
            .data(),
    fetchWeather: (trailId, checkpointKey) async {
      final result = await _resolvedFunctions
          .httpsCallable('fetchWeatherForTrailCheckpoint')
          .call({'trailId': trailId, 'checkpointKey': checkpointKey})
          .timeout(const Duration(seconds: 40));
      return Map<String, dynamic>.from(result.data as Map);
    },
  ).watch(trail, location);

  /// Loads upcoming hikes.
  Future<List<UpcomingHike>> loadUpcomingHikes() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }
    try {
      final response = await _resolvedFunctions
          .httpsCallable('listUpcomingHikePreviews')
          .call(<String, dynamic>{})
          .timeout(_firebaseReadTimeout);
      return parseUpcomingHikePreviewPayload(
        response.data,
      ).where(_shouldRenderUpcomingHike).toList();
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load upcoming hikes (${error.code}).',
      );
    } on TimeoutException {
      throw const HikerCircleFirebaseRepositoryException(
        'Upcoming hikes are taking too long to load. Try again shortly.',
      );
    } catch (_) {
      throw const HikerCircleFirebaseRepositoryException(
        'Unable to load upcoming hikes right now.',
      );
    }
  }

  /// Loads upcoming hike by id.
  Future<UpcomingHike?> loadUpcomingHikeById(String hikeId) async {
    if (!_firebaseBootstrapResult.isAvailable || hikeId.trim().isEmpty) {
      return null;
    }
    final normalizedHikeId = hikeId.trim();
    try {
      final response = await _resolvedFunctions
          .httpsCallable('listUpcomingHikePreviews')
          .call(<String, dynamic>{'hikeId': normalizedHikeId})
          .timeout(_firebaseReadTimeout);
      for (final hike in parseUpcomingHikePreviewPayload(response.data)) {
        if (hike.id == normalizedHikeId && _shouldRenderUpcomingHike(hike)) {
          return hike;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Safety actions need the member-only roster, never the public preview.
  Future<UpcomingHike?> loadParticipantUpcomingHikeForSafety({
    required String hikeId,
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw const HikerCircleFirebaseRepositoryException(
        'Reconnect to check the current hike roster.',
        allowsOfflineFallback: true,
      );
    }
    try {
      final snapshot = await _upcomingHikes
          .doc(hikeId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      final hike = UpcomingHike.fromFirestore(snapshot.id, data);
      if (hike.creatorPhone != session.phoneNumber &&
          !hike.participantPhones.contains(session.phoneNumber)) {
        throw const HikerCircleFirebaseRepositoryException(
          'You are no longer a participant in this hike.',
        );
      }
      return hike.isUpcomingAt(DateTime.now()) ? hike : null;
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Unable to check the current hike roster. Reconnect and try again.',
        allowsOfflineFallback: const {
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
        }.contains(error.code),
      );
    } on TimeoutException {
      throw const HikerCircleFirebaseRepositoryException(
        'The hike roster could not be checked. Reconnect and try again.',
        allowsOfflineFallback: true,
      );
    }
  }

  /// Render the owner's saved read model first; launch/roster checks still use the server.
  Future<List<UpcomingHike>> loadMyUpcomingHikes(
    String phoneNumber, {
    bool cacheOnly = false,
  }) async {
    try {
      var states = <LocalPlannedHikeState>[];
      try {
        states = await _localDatabase.loadPlannedHikeStates(
          ownerPhoneNumber: phoneNumber,
        );
      } catch (_) {
        /* A missing device cache does not prevent a cloud read. */
      }
      var data = await readMobileSnapshot(
        owner: phoneNumber,
        resourceType: 'my_upcoming_hikes',
        cacheOnly: true,
      );
      if (!cacheOnly) {
        if (data.containsKey('hikes') || states.isNotEmpty) {
          unawaited(
            readMobileSnapshot(
              owner: phoneNumber,
              resourceType: 'my_upcoming_hikes',
            ).catchError((Object _) => data),
          );
        } else {
          data = await readMobileSnapshot(
            owner: phoneNumber,
            resourceType: 'my_upcoming_hikes',
          );
        }
      }
      final consumed = {
        for (final state in states)
          if (state.isConsumed) state.upcomingHike.id,
      };
      final byId = {
        for (final row in _snapshotRows(data, 'hikes'))
          _stringFrom(row['hikeId']): UpcomingHike.fromFirestore(
            _stringFrom(row['hikeId']),
            row,
          ),
      };
      for (final state in states) {
        if (!state.isConsumed &&
            (state.scheduleSyncPending || !data.containsKey('hikes'))) {
          byId[state.upcomingHike.id] = state.upcomingHike;
        }
      }
      final results = byId.values
          .where((hike) => !consumed.contains(hike.id))
          .where(_shouldRenderUpcomingHike)
          .toList();
      results.sort((a, b) => b.departureTime.compareTo(a.departureTime));
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Watches my upcoming hikes.
  Stream<List<UpcomingHike>> watchMyUpcomingHikes(
    String phoneNumber, {
    void Function(bool authoritative)? onSourceChanged,
  }) async* {
    final cached = await loadMyUpcomingHikes(phoneNumber);
    onSourceChanged?.call(false);
    yield cached;
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    yield* Stream<List<UpcomingHike>>.multi((controller) {
      List<UpcomingHike>? created;
      List<UpcomingHike>? joined;
      var createdFromServer = false;
      var joinedFromServer = false;

      /// Computes emit.
      void emit() {
        if (created == null || joined == null) {
          return;
        }
        final seen = <String>{};
        final results = <UpcomingHike>[];
        for (final hike in [...created!, ...joined!]) {
          if (seen.add(hike.id) && _shouldRenderUpcomingHike(hike)) {
            results.add(hike);
          }
        }
        results.sort((a, b) => b.departureTime.compareTo(a.departureTime));
        onSourceChanged?.call(createdFromServer && joinedFromServer);
        controller.add(results);
      }

      final sub1 = _upcomingHikes
          .where('creatorPhone', isEqualTo: phoneNumber)
          .snapshots(includeMetadataChanges: true)
          .listen((s) {
            createdFromServer =
                !s.metadata.isFromCache && !s.metadata.hasPendingWrites;
            created = s.docs
                .map((d) => UpcomingHike.fromFirestore(d.id, d.data()))
                .toList();
            emit();
          }, onError: controller.addError);

      final sub2 = _upcomingHikes
          .where('participantPhones', arrayContains: phoneNumber)
          .snapshots(includeMetadataChanges: true)
          .listen((s) {
            joinedFromServer =
                !s.metadata.isFromCache && !s.metadata.hasPendingWrites;
            joined = s.docs
                .map((d) => UpcomingHike.fromFirestore(d.id, d.data()))
                .toList();
            emit();
          }, onError: controller.addError);
      final cacheSubscription = cachedReadUpdates.listen((change) async {
        if (change.owner != phoneNumber ||
            change.type != 'mobile_my_upcoming_hikes') {
          return;
        }
        try {
          final rows = await loadMyUpcomingHikes(phoneNumber, cacheOnly: true);
          onSourceChanged?.call(false);
          controller.add(rows);
        } catch (_) {
          /* Live membership still has its independent server listener. */
        }
      });

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
        cacheSubscription.cancel();
      };
    });
  }

  /// Computes join upcoming hike.
  Future<bool> joinUpcomingHike({required String hikeId}) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return false;
    }
    try {
      final callable = _resolvedFunctions.httpsCallable('joinUpcomingHike');
      final result = await callable.call(<String, dynamic>{'hikeId': hikeId});
      final data = result.data;
      return data is Map && data['joined'] == true;
    } on FirebaseFunctionsException {
      return false;
    }
  }

  /// Sets upcoming hike join policy.
  Future<void> setUpcomingHikeJoinPolicy({
    required String hikeId,
    required String joinPolicy,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      await _resolvedFunctions
          .httpsCallable('setUpcomingHikeJoinPolicy')
          .call(<String, dynamic>{
            'hikeId': hikeId.trim(),
            'joinPolicy': joinPolicy == 'open' ? 'open' : 'approval',
          });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to update who can join this hike.',
      );
    }
  }

  /// Computes remind upcoming hike host.
  Future<Map<String, dynamic>> remindUpcomingHikeHost({
    required String hikeId,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('remindUpcomingHikeHost')
          .call(<String, dynamic>{'hikeId': hikeId.trim()});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to remind the host right now.',
      );
    }
  }

  /// Computes request to join upcoming hike.
  Future<String> requestToJoinUpcomingHike({required String hikeId}) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('requestToJoinUpcomingHike')
          .call(<String, dynamic>{'hikeId': hikeId.trim()});
      final data = result.data;
      if (data is Map) {
        final status = _stringFrom(data['status']).trim();
        if (status.isNotEmpty) {
          return status;
        }
      }
      throw const HikerCircleFirebaseRepositoryException(
        'The hike server returned an invalid join-request status.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to send the join request right now.',
      );
    }
  }

  /// Invalidates host inboxes after a decision or a newly received request.
  final ValueNotifier<int> upcomingHikeJoinRequestRevision = ValueNotifier(0);

  /// Publishes a lightweight refresh signal without exposing request records.
  void notifyUpcomingHikeJoinRequestsChanged() {
    upcomingHikeJoinRequestRevision.value++;
  }

  /// Reads canonical pending totals for the signed-in host's visible hikes.
  Future<Map<String, int>> loadUpcomingHikeJoinRequestCounts(
    List<String> hikeIds,
  ) async {
    _throwIfFirebaseUnavailable();
    if (hikeIds.isEmpty) return {};
    try {
      final result = await _resolvedFunctions
          .httpsCallable('listUpcomingHikeJoinRequests')
          .call({'mode': 'counts', 'hikeIds': hikeIds});
      final counts = (result.data as Map)['counts'] as Map;
      return {
        for (final entry in counts.entries)
          entry.key.toString(): (entry.value as num).toInt().clamp(0, 100000),
      };
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load join requests.',
      );
    }
  }

  /// Reads one host-only page without giving the client access to private request documents.
  Future<UpcomingHikeRequestPage> loadUpcomingHikeJoinRequests({
    required String hikeId,
    required bool history,
    String? afterRequestId,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('listUpcomingHikeJoinRequests')
          .call({
            'hikeId': hikeId,
            'bucket': history ? 'history' : 'pending',
            if (afterRequestId != null) 'afterRequestId': afterRequestId,
          });
      return UpcomingHikeRequestPage.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load join requests.',
      );
    }
  }

  /// Loads upcoming hike join request.
  Future<UpcomingHikeJoinRequestReview> loadUpcomingHikeJoinRequest(
    String requestId,
  ) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('loadUpcomingHikeJoinRequest')
          .call(<String, dynamic>{'requestId': requestId.trim()});
      return UpcomingHikeJoinRequestReview.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load this join request.',
      );
    } catch (_) {
      throw const HikerCircleFirebaseRepositoryException(
        'The join request response was invalid.',
      );
    }
  }

  /// Resolves upcoming hike join request.
  Future<UpcomingHikeJoinRequestReview> resolveUpcomingHikeJoinRequest({
    required String requestId,
    required bool accept,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('resolveUpcomingHikeJoinRequest')
          .call(<String, dynamic>{
            'requestId': requestId.trim(),
            'action': accept ? 'accept' : 'reject',
          });
      notifyUpcomingHikeJoinRequestsChanged();
      return UpcomingHikeJoinRequestReview.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to respond to this join request.',
      );
    } catch (_) {
      throw const HikerCircleFirebaseRepositoryException(
        'The join request response was invalid.',
      );
    }
  }

  /// Loads public hiker profile.
  Future<Map<String, dynamic>> loadPublicHikerProfile({
    String userId = '',
    String phoneNumber = '',
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final result = await _resolvedFunctions
          .httpsCallable('loadPublicHikerProfile')
          .call(<String, dynamic>{
            if (userId.trim().isNotEmpty) 'userId': userId.trim(),
            if (phoneNumber.trim().isNotEmpty)
              'phoneNumber': phoneNumber.trim(),
          });
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load this hiker profile.',
      );
    }
  }

  /// Cached conversations are display data; message reads and membership remain server checked.
  Future<List<GroupChat>> loadUserGroupChats(String phoneNumber) async {
    try {
      var data = await readMobileSnapshot(
        owner: phoneNumber,
        resourceType: 'chat_list',
        cacheOnly: true,
      );
      final legacy = await _loadCachedGroupChats(phoneNumber);
      if (!data.containsKey('chats') && legacy.isNotEmpty) {
        unawaited(
          readMobileSnapshot(
            owner: phoneNumber,
            resourceType: 'chat_list',
          ).catchError((Object _) => data),
        );
        return legacy;
      }
      data = await readMobileSnapshot(
        owner: phoneNumber,
        resourceType: 'chat_list',
      );
      if (!data.containsKey('chats')) return _loadCachedGroupChats(phoneNumber);
      final chats = _snapshotRows(data, 'chats')
          .map(
            (row) => GroupChat.fromFirestore(_stringFrom(row['chatId']), row),
          )
          .where(_shouldRenderGroupChat)
          .toList();
      chats.sort(
        (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
          a.lastMessageAt ?? a.createdAt,
        ),
      );
      return chats;
    } on FirebaseFunctionsException catch (error) {
      if (const {
        'unauthenticated',
        'permission-denied',
        'not-found',
      }.contains(error.code)) {
        rethrow;
      }
      await readMobileSnapshot(
        owner: phoneNumber,
        resourceType: 'chat_list',
        cacheOnly: true,
      );
      return _loadCachedGroupChats(phoneNumber);
    } catch (_) {
      // Recheck scope before using the older normalized cache after a failure.
      await readMobileSnapshot(
        owner: phoneNumber,
        resourceType: 'chat_list',
        cacheOnly: true,
      );
      return _loadCachedGroupChats(phoneNumber);
    }
  }

  /// Loads group chat by id.
  Future<GroupChat?> loadGroupChatById(String chatId) async {
    if (!_firebaseBootstrapResult.isAvailable || chatId.trim().isEmpty) {
      return null;
    }
    try {
      final snapshot = await _groupChats.doc(chatId.trim()).get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }
      final chat = GroupChat.fromFirestore(snapshot.id, data);
      if (!_shouldRenderGroupChat(chat)) {
        return null;
      }
      return await _hydrateGroupChatWithPhotos(chat);
    } catch (_) {
      return null;
    }
  }

  /// Computes user group chats stream.
  Stream<List<GroupChat>> userGroupChatsStream(String phoneNumber) async* {
    final cached = await loadUserGroupChats(phoneNumber);
    if (cached.isNotEmpty || !_firebaseBootstrapResult.isAvailable) {
      yield cached;
    }
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    yield* _groupChats
        .where('participantPhones', arrayContains: phoneNumber)
        .orderBy('createdAtLocal', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final chats = snapshot.docs
              .map((doc) => GroupChat.fromFirestore(doc.id, doc.data()))
              .where(_shouldRenderGroupChat)
              .toList();
          chats.sort(
            (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
              a.lastMessageAt ?? a.createdAt,
            ),
          );
          final hydrated = await _hydrateGroupChatsWithPhotos(chats);
          await _cacheGroupChats(phoneNumber, hydrated);
          return hydrated;
        })
        .handleError((Object _, StackTrace __) {});
  }

  /// Loads cached group chats.
  Future<List<GroupChat>> _loadCachedGroupChats(String phoneNumber) async {
    try {
      final rows = await _localDatabase.loadCachedEntities(
        ownerPhoneNumber: phoneNumber,
        entityType: 'group_chat',
        includeExpired: true,
      );
      return rows
          .map((row) => GroupChat.fromFirestore(row.entityId, row.payload))
          .where(_shouldRenderGroupChat)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Computes cache group chats.
  Future<void> _cacheGroupChats(
    String phoneNumber,
    List<GroupChat> chats,
  ) async {
    final now = DateTime.now().toUtc();
    await _localDatabase.replaceCachedEntitySet(
      ownerPhoneNumber: phoneNumber,
      entityType: 'group_chat',
      entities: chats
          .map(
            (chat) => LocalCachedEntity(
              ownerPhoneNumber: phoneNumber,
              entityType: 'group_chat',
              entityId: chat.id,
              parentId: '',
              payload: chat.toFirestore(),
              cachedAt: now,
              sourceUpdatedAt: chat.lastMessageAt ?? chat.createdAt,
            ),
          )
          .toList(),
    );
  }

  /// Computes formed team chats for host stream.
  Stream<List<GroupChat>> formedTeamChatsForHostStream(String phoneNumber) {
    if (!_firebaseBootstrapResult.isAvailable) {
      return Stream<List<GroupChat>>.value(const []);
    }
    return _groupChats
        .where('creatorPhone', isEqualTo: phoneNumber.trim())
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupChat.fromFirestore(doc.id, doc.data()))
              .where(
                (chat) =>
                    _shouldRenderGroupChat(chat) &&
                    !chat.isDirect &&
                    chat.requiresHostNaming &&
                    !chat.namingPromptShown &&
                    chat.hikeEndedAt == null,
              )
              .toList(growable: false),
        );
  }

  /// Computes name formed hike group chat.
  Future<void> nameFormedHikeGroupChat({
    required String chatId,
    required String name,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final callable = _resolvedFunctions.httpsCallable(
        'nameFormedHikeGroupChat',
      );
      await callable.call(<String, dynamic>{
        'chatId': chatId.trim(),
        'name': name.trim(),
      });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to name the group chat right now.',
      );
    }
  }

  /// Marks formed hike group naming prompt shown.
  Future<void> markFormedHikeGroupNamingPromptShown({
    required String chatId,
    required String defaultName,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      await _resolvedFunctions
          .httpsCallable('markFormedHikeGroupNamingPromptShown')
          .call(<String, dynamic>{
            'chatId': chatId.trim(),
            'defaultName': defaultName.trim(),
          });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to prepare the group chat name.',
      );
    }
  }

  /// Opens direct chat.
  Future<GroupChat> openDirectChat({
    required AppSession session,
    required String otherPhoneNumber,
    required String otherDisplayName,
  }) async {
    _throwIfFirebaseUnavailable();
    final otherPhone = otherPhoneNumber.trim();
    if (otherPhone.isEmpty || _samePhone(session.phoneNumber, otherPhone)) {
      throw const HikerCircleFirebaseRepositoryException(
        'Choose another hiker to start a private conversation.',
      );
    }
    try {
      final response = await _resolvedFunctions
          .httpsCallable('openDirectChat')
          .call<Map<String, dynamic>>({
            'otherPhoneNumber': otherPhone,
            'expectedOwner': session.phoneNumber,
          });
      final payload = Map<String, dynamic>.from(response.data);
      final chatId = _stringFrom(payload['chatId']);
      final rawChat = payload['chat'];
      if (chatId.isEmpty || rawChat is! Map) {
        throw const HikerCircleFirebaseRepositoryException(
          'The chat server returned an invalid conversation.',
        );
      }
      await _invalidateReadModel(session.phoneNumber, 'chat_list');
      return GroupChat.fromFirestore(
        chatId,
        Map<String, dynamic>.from(rawChat),
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to start this conversation right now.',
      );
    }
  }

  /// Loads community profiles.
  Future<List<Map<String, dynamic>>> loadCommunityProfiles({
    required AppSession session,
  }) async {
    final cached = await _loadCachedMapEntities(
      ownerPhoneNumber: session.phoneNumber,
      entityType: 'community_profile',
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return cached;
    }
    try {
      final ownId = _userIdFor(session);
      final profiles = await _getPublicProfiles({'limit': 80});
      final visible = profiles
          .where((profile) => _stringFrom(profile['userId']) != ownId)
          .where((profile) => _stringFrom(profile['phoneNumber']).isNotEmpty)
          .toList();
      await _cacheMapEntities(
        ownerPhoneNumber: session.phoneNumber,
        entityType: 'community_profile',
        idKey: 'userId',
        rows: visible,
      );
      return visible;
    } catch (_) {
      return cached;
    }
  }

  /// Loads community profile.
  Future<Map<String, dynamic>?> loadCommunityProfile({
    String userId = '',
    String phoneNumber = '',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return null;
    }
    try {
      if (userId.trim().isNotEmpty) {
        final profiles = await _getPublicProfiles({'userId': userId.trim()});
        return profiles.isEmpty ? null : profiles.first;
      } else if (phoneNumber.trim().isNotEmpty) {
        final profiles = await _getPublicProfiles({
          'phoneNumber': phoneNumber.trim(),
        });
        return profiles.isEmpty ? null : profiles.first;
      } else {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Returns public profiles.
  Future<List<Map<String, dynamic>>> _getPublicProfiles(
    Map<String, dynamic> request,
  ) async {
    final result = await _resolvedFunctions
        .httpsCallable('getPublicProfiles')
        .call(request)
        .timeout(_firebaseReadTimeout);
    final payload = result.data;
    final rawProfiles = payload is Map ? payload['profiles'] : null;
    if (rawProfiles is! Iterable) {
      return const [];
    }
    return rawProfiles.whereType<Map>().map((raw) {
      final profile = Map<String, dynamic>.from(raw);
      final points = _intFrom(profile['achievementPoints']);
      final level = HikerLevel.fromPoints(points);
      return <String, dynamic>{
        'userId': _stringFrom(profile['userId']),
        'phoneNumber': _stringFrom(profile['phoneNumber']),
        'displayName': _stringFrom(profile['displayName']).trim().isEmpty
            ? 'Hiker'
            : _stringFrom(profile['displayName']).trim(),
        'handle': _stringFrom(profile['handle']),
        'photoURL': _stringFrom(profile['photoURL']),
        'gender': _stringFrom(profile['gender']),
        'hikerExperience': _stringFrom(profile['hikerExperience']),
        'hikeFrequency': _stringFrom(profile['hikeFrequency']),
        'residentialLocation': _stringFrom(profile['residentialLocation']),
        'achievementPoints': points,
        'level': level.number,
        'levelName': level.name,
      };
    }).toList();
  }

  /// Loads the locally cached social read model before background hash validation.
  Future<Set<String>> loadBuddyPhoneNumbers({
    required AppSession session,
  }) async {
    try {
      final raw = (await _readSocial(session))['buddyPhoneNumbers'];
      return raw is Iterable ? raw.whereType<String>().toSet() : <String>{};
    } catch (_) {
      return const {};
    }
  }

  Future<Set<String>> loadOutgoingBuddyRequestPhoneNumbers({
    required AppSession session,
  }) async {
    try {
      final raw = (await _readSocial(session))['buddyRequestsOutgoing'];
      return raw is Map
          ? raw.keys
                .map((key) => key.toString())
                .where((key) => key.isNotEmpty)
                .toSet()
          : <String>{};
    } catch (_) {
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> loadBuddyRequests({
    required AppSession session,
  }) async {
    final data = await _readSocial(session);
    return _buddyRequestsFromRaw(data['buddyRequestsIncoming']);
  }

  /// Watches buddy requests.
  Stream<List<Map<String, dynamic>>> watchBuddyRequests({
    required AppSession session,
  }) {
    if (!_firebaseBootstrapResult.isAvailable) {
      return Stream.value(const []);
    }
    return _moduleFor(session, UserModule.social).snapshots().map((snapshot) {
      final raw = snapshot.data()?['buddyRequestsIncoming'];
      return _buddyRequestsFromRaw(raw);
    });
  }

  /// Watches buddy relationships.
  Stream<BuddyRelationships> watchBuddyRelationships({
    required AppSession session,
  }) {
    /// Parses.
    BuddyRelationships parse(Map<String, dynamic> data) {
      final buddies = data['buddyPhoneNumbers'];
      final outgoing = data['buddyRequestsOutgoing'];
      return BuddyRelationships(
        buddyPhoneNumbers: buddies is Iterable
            ? buddies.whereType<String>().toSet()
            : const {},
        outgoingRequestPhones: outgoing is Map
            ? outgoing.keys.map((key) => key.toString()).toSet()
            : const {},
        incomingRequests: _buddyRequestsFromRaw(data['buddyRequestsIncoming']),
      );
    }

    if (!_firebaseBootstrapResult.isAvailable) {
      return Stream.value(parse(const {}));
    }
    return _moduleFor(
      session,
      UserModule.social,
    ).snapshots().map((snapshot) => parse(snapshot.data() ?? const {}));
  }

  /// Sends buddy request.
  Future<void> sendBuddyRequest({
    required AppSession session,
    required String buddyPhoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    final recipientPhone = buddyPhoneNumber.trim();
    if (recipientPhone.isEmpty ||
        _samePhone(session.phoneNumber, recipientPhone)) {
      return;
    }
    await _manageBuddyRequest(
      action: 'send',
      phoneNumber: recipientPhone,
      owner: session.phoneNumber,
    );
  }

  /// Accepts buddy request.
  Future<void> acceptBuddyRequest({
    required AppSession session,
    required String requesterPhoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    final requesterPhone = requesterPhoneNumber.trim();
    final requesterKey = _phoneKeyFor(requesterPhone);
    final ownKey = _phoneKeyFor(session.phoneNumber);
    if (requesterPhone.isEmpty || requesterKey.isEmpty || ownKey.isEmpty) {
      return;
    }
    await _manageBuddyRequest(
      action: 'accept',
      phoneNumber: requesterPhone,
      owner: session.phoneNumber,
    );
  }

  /// Cancels buddy request.
  Future<void> cancelBuddyRequest({
    required AppSession session,
    required String buddyPhoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    final phone = buddyPhoneNumber.trim();
    if (phone.isEmpty || _samePhone(session.phoneNumber, phone)) return;
    await _manageBuddyRequest(
      action: 'cancel',
      phoneNumber: phone,
      owner: session.phoneNumber,
    );
  }

  /// Declines buddy request.
  Future<void> declineBuddyRequest({
    required AppSession session,
    required String requesterPhoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    final requesterPhone = requesterPhoneNumber.trim();
    final requesterKey = _phoneKeyFor(requesterPhone);
    final ownKey = _phoneKeyFor(session.phoneNumber);
    if (requesterPhone.isEmpty || requesterKey.isEmpty || ownKey.isEmpty) {
      return;
    }
    await _manageBuddyRequest(
      action: 'decline',
      phoneNumber: requesterPhone,
      owner: session.phoneNumber,
    );
  }

  /// Computes manage buddy request.
  Future<void> _manageBuddyRequest({
    required String action,
    required String phoneNumber,
    required String owner,
  }) async {
    try {
      await _resolvedFunctions.httpsCallable('manageBuddyRequest').call({
        'action': action,
        'phoneNumber': phoneNumber,
        'expectedOwner': owner,
      });
      await _invalidateReadModel(owner, 'social');
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to update this buddy request.',
      );
    }
  }

  Future<bool> loadGroupChatNotificationsEnabled({
    required AppSession session,
  }) async {
    try {
      return (await _readPreferences(
            session,
          ))['groupChatNotificationsEnabled'] !=
          false;
    } catch (_) {
      return true;
    }
  }

  /// Sets group chat notifications enabled.
  Future<void> setGroupChatNotificationsEnabled({
    required AppSession session,
    required bool enabled,
  }) async {
    _throwIfFirebaseUnavailable();
    await _moduleFor(session, UserModule.preferences).set({
      'groupChatNotificationsEnabled': enabled,
      'groupChatNotificationSettingsUpdatedAt': FieldValue.serverTimestamp(),
      'groupChatNotificationSettingsUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
    }, SetOptions(merge: true));
    await _refreshPreferenceSnapshot(session);
  }

  Future<String?> loadPreferredTimeZone({required AppSession session}) async {
    try {
      final value = (await _readPreferences(session))['preferredTimeZone'];
      return value is String && PreferredTimeZone.isValid(value)
          ? value.trim()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Saves preferred time zone.
  Future<void> savePreferredTimeZone({
    required AppSession session,
    required String preferredTimeZone,
  }) async {
    _throwIfFirebaseUnavailable();
    if (!PreferredTimeZone.isValid(preferredTimeZone)) {
      throw const HikerCircleFirebaseRepositoryException(
        'Select a valid timezone before saving.',
      );
    }
    await _moduleFor(session, UserModule.preferences).set({
      'preferredTimeZone': preferredTimeZone.trim(),
      'preferredTimeZoneUpdatedAt': FieldValue.serverTimestamp(),
      'preferredTimeZoneUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
    }, SetOptions(merge: true));
    await _refreshPreferenceSnapshot(session);
  }

  /// Saves team safety preferences.
  Future<void> saveTeamSafetyPreferences({
    required AppSession session,
    required Map<String, dynamic> preferences,
  }) async {
    _throwIfFirebaseUnavailable();
    await _moduleFor(session, UserModule.safety).set({
      'teamSafetyPreferences': preferences,
      'teamSafetyPreferencesUpdatedAt': FieldValue.serverTimestamp(),
      'teamSafetyPreferencesUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
    }, SetOptions(merge: true));
    await _refreshPreferenceSnapshot(session);
  }

  Future<Map<String, dynamic>?> loadTeamSafetyPreferences({
    required AppSession session,
  }) async {
    try {
      final data = await readMobileSnapshot(
        owner: session.phoneNumber,
        resourceType: 'preferences',
      );
      final safety = data['safety'];
      final raw = safety is Map ? safety['teamSafetyPreferences'] : null;
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> loadGroupChatMutedUntil({
    required AppSession session,
    required String chatId,
  }) async {
    if (chatId.trim().isEmpty) return null;
    try {
      final raw = (await _readPreferences(session))['groupChatMutedUntil'];
      final until = raw is Map ? _dateFromValue(raw[chatId.trim()]) : null;
      return until != null && until.isAfter(DateTime.now()) ? until : null;
    } catch (_) {
      return null;
    }
  }

  /// Sets group chat muted until.
  Future<void> setGroupChatMutedUntil({
    required AppSession session,
    required String chatId,
    DateTime? mutedUntil,
  }) async {
    _throwIfFirebaseUnavailable();
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return;
    }
    final userReference = _moduleFor(session, UserModule.preferences);
    final now = DateTime.now().toUtc();
    await _resolvedFirestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userReference);
      final current = snapshot.data()?['groupChatMutedUntil'];
      final updated = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      updated.removeWhere((_, value) {
        final date = _dateFromValue(value);
        return date == null || !date.isAfter(now);
      });
      if (mutedUntil == null || !mutedUntil.isAfter(now)) {
        updated.remove(normalizedChatId);
      } else {
        updated[normalizedChatId] = mutedUntil.toUtc().toIso8601String();
      }
      transaction.set(userReference, {
        'groupChatMutedUntil': updated,
        'groupChatNotificationSettingsUpdatedAt': FieldValue.serverTimestamp(),
        'groupChatNotificationSettingsUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));
    });
    await _refreshPreferenceSnapshot(session);
  }

  Future<Set<String>> loadPinnedChats({required AppSession session}) async {
    try {
      final raw = (await _readPreferences(session))['pinnedChats'];
      return raw is Map
          ? raw.keys
                .where(
                  (key) => raw[key] == true || _dateFromValue(raw[key]) != null,
                )
                .map((key) => key.toString())
                .toSet()
          : <String>{};
    } catch (_) {
      return {};
    }
  }

  /// Sets chat pinned.
  Future<void> setChatPinned({
    required AppSession session,
    required String chatId,
    required bool pinned,
  }) async {
    _throwIfFirebaseUnavailable();
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return;
    }
    await _moduleFor(session, UserModule.preferences).set({
      'pinnedChats': {
        normalizedChatId: pinned
            ? FieldValue.serverTimestamp()
            : FieldValue.delete(),
      },
    }, SetOptions(merge: true));
    await _refreshPreferenceSnapshot(session);
  }

  /// Deletes chat for user.
  Future<void> deleteChatForUser({
    required AppSession session,
    required String chatId,
    required String senderName,
    required List<String> participantPhones,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      await _resolvedFunctions.httpsCallable('deleteChatForUser').call({
        'chatId': chatId.trim(),
        'expectedOwner': session.phoneNumber,
      });
      await _invalidateReadModel(session.phoneNumber, 'chat_list');
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to leave this conversation right now.',
      );
    }
  }

  /// Sends chat reminder.
  Future<Map<String, dynamic>> sendChatReminder({
    required String chatId,
    required String recipientPhone,
  }) async {
    _throwIfFirebaseUnavailable();
    final owner = (await _localDatabase.loadSession())?.phoneNumber ?? '';
    if (owner.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Sign in before sending a reminder.',
      );
    }
    final id = '$chatId:$recipientPhone';
    final cached = await _localDatabase.loadCachedEntity(
      ownerPhoneNumber: owner,
      entityType: 'chat_reminder',
      entityId: id,
      includeExpired: true,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final departure = cached?.payload['departureMillis'];
    final remaining = departure is num
        ? departure.toInt() - now
        : 13 * 60 * 60 * 1000;
    final cooldown = remaining > 12 * 60 * 60 * 1000
        ? const Duration(hours: 12)
        : remaining > 60 * 60 * 1000
        ? const Duration(hours: 1)
        : const Duration(minutes: 5);
    final last =
        (cached?.payload['lastRequestedAtMillis'] as num?)?.toInt() ?? 0;
    if (last > 0 && now < last + cooldown.inMilliseconds) {
      throw const HikerCircleFirebaseRepositoryException(
        'A reminder was sent recently. Please wait before sending another.',
      );
    }
    try {
      final response = await _resolvedFunctions
          .httpsCallable('sendChatReminder')
          .call<Map<String, dynamic>>({
            'chatId': chatId,
            'recipientPhone': recipientPhone,
            'expectedOwner': owner,
          });
      final data = Map<String, dynamic>.from(response.data);
      if ((await _localDatabase.loadSession())?.phoneNumber != owner) {
        throw const HikerCircleFirebaseRepositoryException(
          'The signed-in account changed. Try again.',
        );
      }
      await _localDatabase.saveCachedEntity(
        LocalCachedEntity(
          ownerPhoneNumber: owner,
          entityType: 'chat_reminder',
          entityId: id,
          parentId: chatId,
          payload: {
            ...data,
            'lastRequestedAtMillis': data['requestedAtMillis'] ?? now,
          },
          cachedAt: DateTime.now().toUtc(),
        ),
      );
      return data;
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to send this reminder right now.',
      );
    }
  }

  // sendGroupChatMessage preserves the caller-provided message identity across local queuing and
  // cloud submission.
  /// Sends group chat message.
  Future<void> sendGroupChatMessage({
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    required String localId,
    required DateTime sentAt,
    ChatAttachment? attachment,
    SharedCommunityPost? sharedPost,
  }) async {
    final senderPhotoURL = await _photoURLForPhone(senderPhone);
    final firestoreMessageId = _firestoreMessageIdForLocalId(localId);
    if (attachment == null) {
      await _localDatabase.insertPendingMessage(
        localId: localId,
        chatId: chatId,
        senderPhone: senderPhone,
        senderName: senderName,
        text: text,
        firestoreDocId: firestoreMessageId,
        sharedPost: sharedPost?.toMap(),
      );
    }

    try {
      // A retry must address the same Firestore document
      final msgDoc = _groupChatMessagesFor(chatId).doc(firestoreMessageId);
      final msg = ChatMessage(
        id: msgDoc.id,
        chatId: chatId,
        senderPhone: senderPhone,
        senderName: senderName,
        text: text,
        sentAt: sentAt,
        seenBy: [senderPhone],
        attachment: attachment,
        sharedPost: sharedPost,
        senderPhotoURL: senderPhotoURL,
      );

      await msgDoc.set(msg.toFirestore());
      await _groupChats.doc(chatId).set({
        'lastMessage': text.isNotEmpty ? text : _attachmentSummary(attachment),
        'lastMessageAtLocal': sentAt.toUtc().toIso8601String(),
        'lastMessageSenderPhone': senderPhone,
      }, SetOptions(merge: true));

      try {
        await msgDoc.get(const GetOptions(source: Source.server));
      } catch (_) {
        return;
      }

      if (attachment == null) {
        await _localDatabase.updateLocalMessageStatus(
          localId,
          'sent',
          firestoreDocId: msgDoc.id,
        );
      }
    } catch (error) {
      if (attachment != null) {
        throw HikerCircleFirebaseRepositoryException(
          'Unable to send attachment. Please try again.',
        );
      }
    }
  }

  /// Uploads group chat attachment.
  Future<ChatAttachment> uploadGroupChatAttachment({
    required String chatId,
    required String senderPhone,
    required ChatAttachmentType type,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    _throwIfFirebaseUnavailable();
    if (bytes.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'The selected attachment is empty.',
      );
    }
    const maxAttachmentBytes = 25 * 1024 * 1024;
    if (bytes.length > maxAttachmentBytes) {
      throw const HikerCircleFirebaseRepositoryException(
        'Attachments must be 25 MB or smaller.',
      );
    }

    final sanitizedName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final extensionStart = sanitizedName.lastIndexOf('.');
    final safeName = extensionStart <= 0
        ? sanitizedName
        : '${sanitizedName.substring(0, extensionStart)}${sanitizedName.substring(extensionStart).toLowerCase()}';
    final safePhone = senderPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final objectName =
        '${DateTime.now().microsecondsSinceEpoch}_${safePhone}_$safeName';
    final normalizedContentType = contentType.trim().isEmpty
        ? 'application/octet-stream'
        : contentType.trim();
    try {
      final firebaseUser = FirebaseBootstrap.requireAuthenticatedUser();
      final expectedUserId = FirebaseUserRepository.documentIdForPhoneNumber(
        senderPhone,
      );
      if (firebaseUser.uid != expectedUserId) {
        throw FirebaseAuthException(
          code: 'firebase-session-mismatch',
          message: 'The Firebase account does not match the chat sender.',
        );
      }
      final reference = _resolvedStorage.ref(
        'group_chats/$chatId/attachments/$objectName',
      );
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: normalizedContentType,
          customMetadata: {
            'chatId': chatId,
            'senderPhone': senderPhone,
            'attachmentType': type.name,
          },
        ),
      );
      return ChatAttachment(
        type: type,
        url: await reference.getDownloadURL(),
        fileName: fileName,
        contentType: normalizedContentType,
        sizeBytes: bytes.length,
      );
    } on FirebaseAuthException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ??
            'Your login could not be validated. Sign in again and retry.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized') {
        throw const HikerCircleFirebaseRepositoryException(
          'Attachment upload is blocked by Firebase Storage rules or Storage App Check.',
        );
      }
      throw HikerCircleFirebaseRepositoryException(
        'Attachment upload failed: ${error.message ?? error.code}',
      );
    }
  }

  /// Uploads profile photo.
  Future<String> uploadProfilePhoto({
    required String phoneNumber,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    _throwIfFirebaseUnavailable();
    if (bytes.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'The selected image is empty.',
      );
    }
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw const HikerCircleFirebaseRepositoryException(
        'Profile photos must be 10 MB or smaller.',
      );
    }
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final userId = FirebaseUserRepository.documentIdForPhoneNumber(phoneNumber);
    final objectName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';
    try {
      final firebaseUser = FirebaseBootstrap.requireAuthenticatedUser();
      if (firebaseUser.uid != userId) {
        throw FirebaseAuthException(
          code: 'firebase-session-mismatch',
          message: 'The Firebase account does not match the phone number.',
        );
      }
      final reference = _resolvedStorage.ref(
        'profile_photos/$userId/$objectName',
      );
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          customMetadata: {
            'userId': userId,
            'uploadedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ),
      );
      return await reference.getDownloadURL();
    } on FirebaseAuthException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ??
            'Your login could not be validated. Sign in again and retry.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized') {
        throw const HikerCircleFirebaseRepositoryException(
          'Upload is blocked by Firebase Storage rules.',
        );
      }
      throw HikerCircleFirebaseRepositoryException(
        'Profile photo upload failed: ${error.message ?? error.code}',
      );
    }
  }

  /// Computes attachment summary.
  String _attachmentSummary(ChatAttachment? attachment) {
    return switch (attachment?.type) {
      ChatAttachmentType.image => 'Photo',
      ChatAttachmentType.video => 'Video',
      ChatAttachmentType.document => 'Document',
      null => '',
    };
  }

  /// Marks message as seen.
  Future<void> markMessageAsSeen({
    required String chatId,
    required String messageId,
    required String phoneNumber,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    try {
      await _groupChatMessagesFor(chatId).doc(messageId).update({
        'seenBy': FieldValue.arrayUnion([phoneNumber]),
      });
    } catch (_) {}
  }

  /// Marks group chat as read.
  Future<void> markGroupChatAsRead({
    required String chatId,
    required String phoneNumber,
  }) async {
    final now = DateTime.now().toUtc();
    final phoneKey = _phoneKeyFor(phoneNumber);
    if (phoneKey.isEmpty) {
      return;
    }
    await _localDatabase.saveChatReadReceipt(
      chatId,
      now,
      ownerPhoneNumber: phoneNumber,
      synced: false,
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    try {
      await _groupChats.doc(chatId).set({
        'lastReadAt': {phoneKey: now.toIso8601String()},
        'unreadCount': {phoneKey: 0},
      }, SetOptions(merge: true));
      await _localDatabase.markChatReadReceiptSynced(
        chatId,
        ownerPhoneNumber: phoneNumber,
      );
    } catch (_) {}
  }

  /// Synchronizes pending read receipts.
  Future<void> syncPendingReadReceipts({required String phoneNumber}) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    final chatIds = await _localDatabase.loadUnsyncedReadReceiptChatIds(
      ownerPhoneNumber: phoneNumber,
    );
    if (chatIds.isEmpty) {
      return;
    }
    for (final chatId in chatIds) {
      try {
        final localReadAt = await _localDatabase.loadChatReadReceipt(
          chatId,
          ownerPhoneNumber: phoneNumber,
        );
        if (localReadAt == null) {
          continue;
        }
        final phoneKey = _phoneKeyFor(phoneNumber);
        if (phoneKey.isEmpty) {
          continue;
        }
        await _groupChats.doc(chatId).set({
          'lastReadAt': {phoneKey: localReadAt.toUtc().toIso8601String()},
          'unreadCount': {phoneKey: 0},
        }, SetOptions(merge: true));
        await _localDatabase.markChatReadReceiptSynced(
          chatId,
          ownerPhoneNumber: phoneNumber,
        );
      } catch (_) {}
    }
  }

  /// Loads local last read at.
  Future<DateTime?> loadLocalLastReadAt(
    String chatId, {
    required String ownerPhoneNumber,
  }) async {
    return _localDatabase.loadChatReadReceipt(
      chatId,
      ownerPhoneNumber: ownerPhoneNumber,
    );
  }

  /// Loads all local last read at.
  Future<Map<String, DateTime>> loadAllLocalLastReadAt({
    required String ownerPhoneNumber,
  }) async {
    return _localDatabase.loadAllChatReadReceipts(
      ownerPhoneNumber: ownerPhoneNumber,
    );
  }

  /// Loads pending messages for chat.
  Future<List<ChatMessage>> loadPendingMessagesForChat(
    String chatId, {
    required String ownerPhoneNumber,
  }) async {
    final rows = await _localDatabase.loadPendingMessagesForChat(
      chatId,
      ownerPhoneNumber: ownerPhoneNumber,
    );
    return rows
        .map(
          (row) => ChatMessage.fromPending(
            localId: row['local_id'] as String,
            chatId: row['chat_id'] as String,
            senderPhone: row['sender_phone'] as String,
            senderName: row['sender_name'] as String? ?? '',
            text: row['text'] as String,
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            attachment: _attachmentFromLocalRow(row),
            sharedPost: _sharedPostFromLocalRow(row),
          ),
        )
        .toList();
  }

  /// Loads all local messages for chat.
  Future<List<ChatMessage>> loadAllLocalMessagesForChat(
    String chatId, {
    required String ownerPhoneNumber,
  }) async {
    final rows = await _localDatabase.loadAllLocalMessagesForChat(
      chatId,
      ownerPhoneNumber: ownerPhoneNumber,
    );
    return rows.map((row) {
      final statusStr = row['send_status'] as String? ?? 'pending';
      final status = switch (statusStr) {
        'sent' => SendStatus.sent,
        'failed' || 'unsent' => SendStatus.failed,
        _ => SendStatus.sending,
      };
      return ChatMessage.fromPending(
        localId: row['local_id'] as String,
        chatId: row['chat_id'] as String,
        senderPhone: row['sender_phone'] as String,
        senderName: row['sender_name'] as String? ?? '',
        text: row['text'] as String,
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now(),
        sendStatus: status,
        attachment: _attachmentFromLocalRow(row),
        sharedPost: _sharedPostFromLocalRow(row),
      );
    }).toList();
  }

  /// Computes cache chat messages.
  Future<void> cacheChatMessages(
    List<ChatMessage> messages,
    String chatId, {
    required String ownerPhoneNumber,
  }) async {
    final rows = messages
        .map(
          (m) => {
            'local_id': m.id,
            'chat_id': chatId,
            'sender_phone': m.senderPhone,
            'sender_name': m.senderName,
            'text': m.text,
            'created_at': m.sentAt.toUtc().toIso8601String(),
            'send_status': m.sendStatus == SendStatus.sent ? 'sent' : 'pending',
            'retry_count': 0,
            'firestore_doc_id': '',
            'shared_post_json': m.sharedPost == null
                ? ''
                : jsonEncode(m.sharedPost!.toMap()),
            'attachment_json': m.attachment == null
                ? ''
                : jsonEncode(m.attachment!.toFirestore()),
            'owner_phone_number': ownerPhoneNumber.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'last_error': '',
          },
        )
        .toList();
    await _localDatabase.upsertChatMessages(rows);
  }

  /// Flushes pending messages.
  Future<void> flushPendingMessages({String? ownerPhoneNumber}) async {
    final owner = ownerPhoneNumber?.trim().isNotEmpty == true
        ? ownerPhoneNumber!.trim()
        : (await _localDatabase.loadSession())?.phoneNumber.trim() ?? '';
    if (owner.isEmpty) {
      return;
    }
    final rows = await _localDatabase.loadPendingMessages(
      ownerPhoneNumber: owner,
    );
    for (final row in rows) {
      final localId = row['local_id'] as String;
      final chatId = row['chat_id'] as String;
      final senderPhone = row['sender_phone'] as String;
      final senderName = row['sender_name'] as String? ?? '';
      final text = row['text'] as String;
      final storedFirestoreDocId = row['firestore_doc_id'] as String? ?? '';
      final firestoreDocId = storedFirestoreDocId.isNotEmpty
          ? storedFirestoreDocId
          : _firestoreMessageIdForLocalId(localId);
      final sentAt =
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now();

      try {
        final existing = await _groupChatMessagesFor(
          chatId,
        ).doc(firestoreDocId).get(const GetOptions(source: Source.server));
        if (existing.exists) {
          await _localDatabase.updateLocalMessageStatus(
            localId,
            'sent',
            firestoreDocId: firestoreDocId,
          );
          continue;
        }

        final msgDoc = _groupChatMessagesFor(chatId).doc(firestoreDocId);
        final msg = ChatMessage(
          id: msgDoc.id,
          chatId: chatId,
          senderPhone: senderPhone,
          senderName: senderName,
          text: text,
          sharedPost: _sharedPostFromLocalRow(row),
          sentAt: sentAt,
          seenBy: [senderPhone],
        );
        await msgDoc.set(msg.toFirestore());
        await _groupChats.doc(chatId).set({
          'lastMessage': text,
          'lastMessageAtLocal': sentAt.toUtc().toIso8601String(),
          'lastMessageSenderPhone': senderPhone,
        }, SetOptions(merge: true));

        try {
          await msgDoc.get(const GetOptions(source: Source.server));
        } catch (_) {
          await _localDatabase.incrementPendingMessageRetry(localId);
          continue;
        }

        await _localDatabase.updateLocalMessageStatus(
          localId,
          'sent',
          firestoreDocId: msgDoc.id,
        );
      } catch (error) {
        await _localDatabase.updateLocalMessageStatus(
          localId,
          'failed',
          lastError: error.toString(),
        );
        await _localDatabase.incrementPendingMessageRetry(localId);
      }
    }
  }

  /// Restores a shared post from the durable message cache or retry queue.
  SharedCommunityPost? _sharedPostFromLocalRow(Map<String, dynamic> row) {
    try {
      final raw = row['shared_post_json'];
      return raw is String && raw.isNotEmpty
          ? SharedCommunityPost.fromMap(jsonDecode(raw))
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Computes firestore message id for local id.
  String _firestoreMessageIdForLocalId(String localId) {
    final normalized = localId.trim().replaceAll(RegExp(r'[/\\]'), '_');
    if (normalized.isNotEmpty && normalized.length <= 512) {
      return normalized;
    }
    final encoded =
        'local_${base64Url.encode(utf8.encode(localId)).replaceAll('=', '')}';
    return encoded.length <= 512 ? encoded : encoded.substring(0, 512);
  }

  /// Computes attachment from local row.
  ChatAttachment? _attachmentFromLocalRow(Map<String, dynamic> row) {
    final raw = row['attachment_json'];
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? ChatAttachment.fromFirestore(Map<String, dynamic>.from(decoded))
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Loads upcoming hike for chat.
  Future<UpcomingHike?> loadUpcomingHikeForChat(String hikeSessionId) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return null;
    }
    try {
      final doc = await _upcomingHikes.doc(hikeSessionId).get();
      if (!doc.exists) {
        return null;
      }
      return UpcomingHike.fromFirestore(doc.id, doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Computes group chat messages stream.
  Stream<List<ChatMessage>> groupChatMessagesStream(String chatId) {
    return _groupChatMessagesFor(chatId)
        .orderBy('sentAtLocal', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessage.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Cancels upcoming hike.
  Future<void> cancelUpcomingHike({
    required String hikeId,
    bool withdrawSelf = false,
    String? hazardId,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      await _resolvedFunctions.httpsCallable('cancelUpcomingHike').call<void>({
        'hikeId': hikeId,
        if (withdrawSelf) 'withdrawSelf': true,
        if (hazardId != null) 'hazardId': hazardId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to cancel this hike. Please try again.',
      );
    }
  }

  /// Commit the full plan and its retry metadata before attempting any network work.
  Future<String> scheduleUpcomingHike({
    required AppSession session,
    required HikeSessionDraft draft,
    String joinPolicy = 'approval',
    HikeReminderPreference reminderPreference = const HikeReminderPreference(),
  }) async {
    final creationKey = upcomingHikeCreationKeyFor(
      appInstanceId: session.appInstanceId,
      trailId: draft.trail.trailId,
      departureTime: draft.departureTime,
      expectedReturnTime: draft.expectedReturnTime,
      hikeType: draft.hikeType,
      startPointName: draft.startPointName,
      destinationName: draft.destinationName,
      inviteePhoneNumbers: draft.teamBuddies.map((buddy) => buddy.phoneNumber),
    );
    final hike = PlannedHikeStateResolver.provisionalFromConfirmedDraft(
      draft: draft,
      creatorPhone: session.phoneNumber,
      creatorName: session.username,
      localId: 'local_pending_$creationKey',
    );
    final id = await _localDatabase.queueScheduledHike(
      ownerPhoneNumber: session.phoneNumber,
      hike: hike,
      creationKey: creationKey,
      joinPolicy: joinPolicy,
      reminderPreference: reminderPreference.fitToDeparture(
        draft.departureTime,
        DateTime.now(),
      ),
    );
    _planningChanges.add(session.phoneNumber);
    unawaited(flushPendingUpcomingHikes(session: session));
    return id;
  }

  /// Flushes pending upcoming hikes.
  Future<void> flushPendingUpcomingHikes({required AppSession session}) {
    if (!_firebaseBootstrapResult.isAvailable) return Future.value();
    final owner = session.phoneNumber;
    final running = _planningSyncs[owner];
    if (running != null) return running;
    final work = _flushPendingUpcomingHikes(session).catchError((Object error) {
      debugPrint('Upcoming hike sync will retry: $error');
    });
    _planningSyncs[owner] = work;
    return work.whenComplete(() {
      if (identical(_planningSyncs[owner], work)) _planningSyncs.remove(owner);
    });
  }

  /// Flushes pending upcoming hikes.
  Future<void> _flushPendingUpcomingHikes(AppSession session) async {
    final uid = _captureAccountUid(session);
    if (uid == null) return;
    final states = await _localDatabase.loadPlannedHikeStates(
      ownerPhoneNumber: session.phoneNumber,
    );
    for (final state in states) {
      if (state.isConsumed ||
          !state.upcomingHike.departureTime.isAfter(DateTime.now().toUtc())) {
        continue;
      }
      if (!_accountStillMatches(session, uid)) return;
      var hikeId = state.upcomingHike.id;
      try {
        if (state.scheduleSyncPending) {
          final draft = state.upcomingHike.draft;
          if (draft == null || state.creationKey.isEmpty) continue;
          final payload = <String, dynamic>{
            'creationKey': state.creationKey,
            'draft': draft.toPersistence(),
            'joinPolicy': state.joinPolicy,
          };
          final request = _scheduleHikeRequest;
          hikeId =
              await (request != null
                      ? request(payload)
                      : _resolvedFunctions
                            .httpsCallable('scheduleUpcomingHike')
                            .call<Map<String, dynamic>>(payload)
                            .then(
                              (result) => _stringFrom(result.data['hikeId']),
                            ))
                  .timeout(_firebaseReadTimeout);
          _requireSameAccount(session, uid);
          if (!_isValidCloudDocumentId(hikeId) ||
              hikeId.startsWith('local_pending_')) {
            throw const HikerCircleFirebaseRepositoryException(
              'The hike server returned an invalid schedule.',
            );
          }
          await _localDatabase.confirmScheduledHike(
            ownerPhoneNumber: session.phoneNumber,
            creationKey: state.creationKey,
            cloudHikeId: hikeId,
          );
          _planningChanges.add(session.phoneNumber);
        }
        if (hikeId.startsWith('local_pending_')) continue;
        // Read again: a preference may have changed while creation was in flight.
        final current = await _localPlanningState(session, hikeId);
        final preference = current?.reminderPreference;
        if (current?.reminderSyncPending != true || preference == null) {
          continue;
        }
        _requireSameAccount(session, uid);
        final request = _reminderPreferenceRequest;
        await (request != null
                ? request(hikeId, preference)
                : _upcomingHikes
                      .doc(hikeId)
                      .collection('reminderPreferences')
                      .doc(_userIdFor(session))
                      .set({
                        ...preference.normalized().toFirestore(),
                        // Remove retired choices while preserving delivery receipts.
                        'finalReminderMinutesBefore': FieldValue.delete(),
                        'maximumReminders': FieldValue.delete(),
                        'hikeId': hikeId,
                        'ownerUserId': _userIdFor(session),
                        'ownerPhoneNumber': session.phoneNumber,
                        'updatedAt': FieldValue.serverTimestamp(),
                        'updatedAtLocal': DateTime.now()
                            .toUtc()
                            .toIso8601String(),
                      }, SetOptions(merge: true)))
            .timeout(_firebaseWriteTimeout);
        _requireSameAccount(session, uid);
        await _localDatabase.acknowledgePlannedReminderPreference(
          ownerPhoneNumber: session.phoneNumber,
          hikeId: hikeId,
          preference: preference,
        );
      } catch (error) {
        // The transactionally saved local plan remains usable after a failure or timeout.
        debugPrint(
          'Saved hike ${state.upcomingHike.id} is waiting to sync: $error',
        );
      }
    }
  }

  /// Computes local planning state.
  Future<LocalPlannedHikeState?> _localPlanningState(
    AppSession session,
    String hikeId,
  ) async {
    for (final state in await _localDatabase.loadPlannedHikeStates(
      ownerPhoneNumber: session.phoneNumber,
    )) {
      if (state.upcomingHike.id == hikeId) return state;
    }
    return null;
  }

  /// Loads upcoming hike reminder preference.
  Future<HikeReminderPreference> loadUpcomingHikeReminderPreference({
    required AppSession session,
    required String hikeId,
  }) async {
    final local = await _localPlanningState(session, hikeId);
    if (local?.reminderPreference != null) return local!.reminderPreference!;
    if (!_firebaseBootstrapResult.isAvailable ||
        hikeId.trim().isEmpty ||
        hikeId.startsWith('local_pending_')) {
      return const HikeReminderPreference();
    }
    try {
      final snapshot = await _upcomingHikes
          .doc(hikeId.trim())
          .collection('reminderPreferences')
          .doc(_userIdFor(session))
          .get()
          .timeout(_firebaseReadTimeout);
      final preference = HikeReminderPreference.fromFirestore(
        snapshot.data() ?? {},
      );
      // Do not replace a local edit made during the network read.
      final current = await _localPlanningState(session, hikeId);
      if (current?.reminderPreference != null) {
        return current!.reminderPreference!;
      }
      await _localDatabase.savePlannedReminderPreference(
        ownerPhoneNumber: session.phoneNumber,
        hikeId: hikeId,
        preference: preference,
        pendingSync: false,
      );
      _planningChanges.add(session.phoneNumber);
      return preference;
    } catch (_) {
      return const HikeReminderPreference();
    }
  }

  /// Saves upcoming hike reminder preference.
  Future<void> saveUpcomingHikeReminderPreference({
    required AppSession session,
    required String hikeId,
    required HikeReminderPreference preference,
    UpcomingHike? hike,
  }) async {
    if (hikeId.trim().isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'This hike is unavailable for reminders.',
      );
    }
    if (hike != null) {
      await _localDatabase.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: session.phoneNumber,
        upcomingHikes: [hike],
      );
    }
    final local = await _localPlanningState(session, hikeId);
    if (local == null) {
      throw const HikerCircleFirebaseRepositoryException(
        'Open this hike again before changing its reminders.',
      );
    }
    await _localDatabase.savePlannedReminderPreference(
      ownerPhoneNumber: session.phoneNumber,
      hikeId: hikeId.trim(),
      preference: preference.fitToDeparture(
        local.upcomingHike.departureTime,
        DateTime.now(),
      ),
    );
    _planningChanges.add(session.phoneNumber);
    unawaited(flushPendingUpcomingHikes(session: session));
  }

  /// Creates active hike session.
  Future<ActiveHikeSession> createActiveHikeSession({
    required AppSession session,
    required HikeSessionDraft draft,
    String teamHikeSessionId = '',
    TeamHikeSession? teamHikeSession,
    String sourceUpcomingHikeId = '',
  }) async {
    final localSession = ActiveHikeSession.fromDraft(
      draft,
      teamHikeSessionId: teamHikeSessionId,
      teamHikeSession: teamHikeSession,
      sourceUpcomingHikeId: sourceUpcomingHikeId.trim(),
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return localSession;
    }

    try {
      final response = await _resolvedFunctions
          .httpsCallable('startActiveHikeSession')
          .call<Map<String, dynamic>>({
            'creationKey': localSession.sessionId,
            'draft': draft.toPersistence(),
            'startedAtLocal': localSession.startedAt.toUtc().toIso8601String(),
            if (sourceUpcomingHikeId.trim().isNotEmpty)
              'sourceUpcomingHikeId': sourceUpcomingHikeId.trim(),
            if (teamHikeSessionId.trim().isNotEmpty)
              'teamHikeSessionId': teamHikeSessionId.trim(),
          })
          .timeout(const Duration(seconds: 2));
      final sessionId = _stringFrom(response.data['sessionId']);
      if (sessionId.isEmpty) {
        throw const HikerCircleFirebaseRepositoryException(
          'The hike server returned an invalid session.',
        );
      }
      return localSession.copyWith(sessionId: sessionId);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Cloud sync failed (${error.code}). ${error.message ?? 'Please try again.'}',
        allowsOfflineFallback:
            activeHikeStartAllowsOfflineFallbackForFunctionsCode(error.code),
      );
    } on TimeoutException {
      return localSession;
    }
  }

  /// Notifies emergency contacts of live location.
  Future<LiveLocationContactNotificationResult>
  notifyEmergencyContactsOfLiveLocation({
    required String activeHikeSessionId,
    required String shareId,
  }) async {
    _throwIfFirebaseUnavailable();
    try {
      final response = await _resolvedFunctions
          .httpsCallable('notifyEmergencyContactsOfLiveLocation')
          .call<Map<String, dynamic>>({
            'sessionId': activeHikeSessionId.trim(),
            'shareId': shareId.trim(),
          })
          .timeout(const Duration(seconds: 120));
      final data = response.data;
      return LiveLocationContactNotificationResult(
        contactCount: _intFrom(data['contactCount']),
        sentCount: _intFrom(data['sentCount']),
        retryableFailureCount: _intFrom(data['retryableFailureCount']),
        uncertainCount: _intFrom(data['uncertainCount']),
        inProgressCount: _intFrom(data['inProgressCount']),
        failedCount: _intFrom(data['failedCount']),
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ??
            'The live location link could not be sent to SOS contacts.',
      );
    } on TimeoutException {
      throw const HikerCircleFirebaseRepositoryException(
        'Live location contact delivery is still being processed.',
      );
    }
  }

  /// Creates team hike session.
  Future<TeamHikeSession> createTeamHikeSession({
    required AppSession session,
    required HikeSessionDraft draft,
    String sourceUpcomingHikeId = '',
  }) async {
    _throwIfFirebaseUnavailable();
    final invitedPhoneNumbers =
        draft.teamBuddies
            .map((buddy) => buddy.phoneNumber.trim())
            .where((phoneNumber) => phoneNumber.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final creationKey = teamHikeCreationKeyFor(
      appInstanceId: session.appInstanceId,
      trailId: draft.trail.trailId,
      departureTime: draft.departureTime,
      inviteePhoneNumbers: invitedPhoneNumbers,
      sourceUpcomingHikeId: sourceUpcomingHikeId,
    );
    final retryScope = '${session.phoneNumber}:$creationKey';

    /// Computes submit.
    Future<TeamHikeSession> submit(String key) async =>
        _teamHikeSessionFromCallable(
          await _callTeamHikeFunction(
            callableName: 'createTeamHikeSession',
            data: {
              'creationKey': key,
              'draft': draft.toPersistence(),
              'invitedPhoneNumbers': invitedPhoneNumbers,
              if (sourceUpcomingHikeId.trim().isNotEmpty)
                'sourceUpcomingHikeId': sourceUpcomingHikeId.trim(),
            },
          ),
        );
    final key = _teamHikeCreationRetryKeys[retryScope] ?? creationKey;
    final team = await submit(key);
    if (sourceUpcomingHikeId.trim().isNotEmpty ||
        team.phase != TeamHikePhase.completed) {
      return team;
    }
    // An explicitly cancelled instant launch cannot begin readiness again.
    // Keep its replacement key across uncertain responses so Retry is idempotent.
    if ((_teamHikeCreationRetryKeys[retryScope] ?? creationKey) == key) {
      _teamHikeCreationRetryKeys[retryScope] =
          '${creationKey}_retry_${DateTime.now().microsecondsSinceEpoch}';
    }
    return submit(_teamHikeCreationRetryKeys[retryScope]!);
  }

  /// Watches team hike session.
  Stream<TeamHikeSession?> watchTeamHikeSession(String teamHikeSessionId) {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return Stream<TeamHikeSession?>.value(null);
    }
    return _teamHikeSessions
        .doc(teamHikeSessionId)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites,
        )
        .map(_teamHikeSessionFromDocument);
  }

  /// Watches team readiness for participant.
  Stream<List<TeamHikeSession>> watchTeamReadinessForParticipant(
    String phoneNumber,
  ) {
    final normalizedPhone = phoneNumber.trim();
    if (!_firebaseBootstrapResult.isAvailable || normalizedPhone.isEmpty) {
      return Stream<List<TeamHikeSession>>.value(const []);
    }
    return _teamHikeSessions
        .where('participantPhoneNumbers', arrayContains: normalizedPhone)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites,
        )
        .map((snapshot) {
          final sessions = snapshot.docs
              .map(_teamHikeSessionFromDocument)
              .whereType<TeamHikeSession>()
              .where(
                (teamSession) =>
                    teamSession.readinessStartedAt != null &&
                    teamSession.phase != TeamHikePhase.completed &&
                    teamSession.phase != TeamHikePhase.active &&
                    teamSession.hostPhoneNumber.trim() != normalizedPhone,
              )
              .toList();
          sessions.sort(
            (left, right) =>
                right.readinessStartedAt!.compareTo(left.readinessStartedAt!),
          );
          return sessions;
        });
  }

  /// Finds a participant-authorized launch for the selected upcoming hike.
  Future<TeamHikeSession?> loadTeamHikeForUpcoming(
    String upcomingId, {
    required String phoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    final snapshot = await _teamHikeSessions
        .where('participantPhoneNumbers', arrayContains: phoneNumber.trim())
        .get(const GetOptions(source: Source.server))
        .timeout(_firebaseReadTimeout);
    return snapshot.docs
        .map(_teamHikeSessionFromDocument)
        .whereType<TeamHikeSession>()
        .where(
          (team) =>
              team.sourceUpcomingHikeId == upcomingId &&
              team.phase != TeamHikePhase.completed,
        )
        .firstOrNull;
  }

  /// Commits an explicit cancellation or withdrawal before leaving readiness.
  Future<TeamHikeSession> cancelTeamReadiness({
    required AppSession session,
    required String teamHikeSessionId,
    required bool isHost,
  }) => _manageTeamHikeAction(
    action: isHost ? 'cancel' : 'leaveReadiness',
    teamHikeSessionId: teamHikeSessionId,
  );

  /// Loads team hike session.
  Future<TeamHikeSession?> loadTeamHikeSession(String teamHikeSessionId) async {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return null;
    }
    return _manageTeamHikeAction(
      action: 'read',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Accepts team hike invite.
  Future<TeamHikeSession> acceptTeamHikeInvite({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    return _manageTeamHikeAction(
      action: 'accept',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Begins team hike readiness.
  Future<TeamHikeSession> beginTeamHikeReadiness({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    return _manageTeamHikeAction(
      action: 'beginReadiness',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Marks team participant ready.
  Future<TeamHikeSession> markTeamParticipantReady({
    required AppSession session,
    required String teamHikeSessionId,
    required Map<String, dynamic> safetySettings,
  }) async {
    if (safetySettings['liveLocationSharing'] != true ||
        safetySettings['pathDeviationAlerts'] != true ||
        safetySettings['teammateSeparationAlerts'] != true ||
        safetySettings['sensorSensitivity'] is! num ||
        safetySettings['fallResponseDurationSeconds'] is! num ||
        safetySettings['longestRestDurationSeconds'] is! num) {
      throw const HikerCircleFirebaseRepositoryException(
        'Complete the required team safety settings before marking ready.',
      );
    }
    return _manageTeamHikeAction(
      action: 'ready',
      teamHikeSessionId: teamHikeSessionId,
      data: {'safetySettings': safetySettings},
    );
  }

  /// Ensures active hike session in cloud.
  Future<ActiveHikeCloudRestoreResult> ensureActiveHikeSessionInCloud({
    required AppSession session,
    required ActiveHikeSession activeHike,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return ActiveHikeCloudRestoreResult(
        sessionId: activeHike.sessionId,
        ensured: false,
        terminal: false,
        status: 'offline',
      );
    }
    try {
      final response = await _resolvedFunctions
          .httpsCallable('ensureActiveHikeSessionInCloud')
          .call<Map<String, dynamic>>({
            'sessionId': activeHike.sessionId,
            'draft': activeHike.draft.toPersistence(),
            'startedAtLocal': activeHike.startedAt.toUtc().toIso8601String(),
            if (activeHike.teamHikeSessionId.isNotEmpty)
              'teamHikeSessionId': activeHike.teamHikeSessionId,
            if (activeHike.sourceUpcomingHikeId.trim().isNotEmpty)
              'sourceUpcomingHikeId': activeHike.sourceUpcomingHikeId.trim(),
          });
      return parseActiveHikeCloudRestoreResult(
        response.data,
        requestedSessionId: activeHike.sessionId,
      );
    } on FirebaseFunctionsException catch (error) {
      final terminalResult = _terminalRestoreResultFromException(
        error,
        requestedSessionId: activeHike.sessionId,
      );
      if (terminalResult != null) {
        return terminalResult;
      }
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to restore this hike in the cloud.',
      );
    } on TypeError {
      throw const HikerCircleFirebaseRepositoryException(
        'The hike server returned an invalid recovery response.',
      );
    }
  }

  /// Removes pending team invitees.
  Future<TeamHikeSession> removePendingTeamInvitees({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    return _manageTeamHikeAction(
      action: 'removePending',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Cancels team hike session.
  Future<void> cancelTeamHikeSession({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    await _manageTeamHikeAction(
      action: 'cancel',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Computes activate team hike session.
  Future<TeamHikeSession> activateTeamHikeSession({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    return _manageTeamHikeAction(
      action: 'activate',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  /// Records the caller's own preparation fix without creating an active hike.
  Future<TeamHikeSession> recordTeamReadinessLocation({
    required String teamHikeSessionId,
    required SosTriggerLocation location,
  }) => _manageTeamHikeAction(
    action: 'readinessLocation',
    teamHikeSessionId: teamHikeSessionId,
    data: {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'accuracyMeters': location.accuracyMeters,
      'capturedAtMillis': location.capturedAt?.millisecondsSinceEpoch,
    },
  );

  /// Synchronizes team hike participant location.
  Future<TeamHikeSession?> syncTeamHikeParticipantLocation({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation location,
  }) async {
    final teamHikeSessionId = activeHike.teamHikeSessionId;
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return activeHike.teamHikeSession;
    }
    final coordinate = HikeCoordinate.fromTriggerLocation(location);
    final progressMeters = _progressMetersFor(activeHike, coordinate);
    return _manageTeamHikeAction(
      action: 'location',
      teamHikeSessionId: teamHikeSessionId,
      data: {
        'activeHikeSessionId': activeHike.sessionId,
        'latitude': coordinate.latitude,
        'longitude': coordinate.longitude,
        'accuracyMeters': location.accuracyMeters,
        'progressMeters': progressMeters,
      },
    );
  }

  /// Computes ping team participant.
  Future<TeamHikeSession> pingTeamParticipant({
    required AppSession session,
    required String teamHikeSessionId,
    required String participantPhoneNumber,
  }) async {
    return _manageTeamHikeAction(
      action: 'ping',
      teamHikeSessionId: teamHikeSessionId,
      data: {'participantPhoneNumber': participantPhoneNumber},
    );
  }

  /// Computes respond to team ping.
  Future<TeamHikeSession> respondToTeamPing({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    return _manageTeamHikeAction(
      action: 'respond',
      teamHikeSessionId: teamHikeSessionId,
    );
  }

  // drainNativeLocationSamples imports native samples for the active account before acknowledging
  // the local transfer.
  /// Computes drain native location samples.
  Future<void> drainNativeLocationSamples({
    required AppSession session,
    String? sessionId,
  }) async {
    final uid = _captureAccountUid(session);
    if (uid == null) {
      return;
    }
    const native = ActiveHikeLiveStatusService();
    final sessions = sessionId == null
        ? await native.getNativeLocationBufferSessions().timeout(
            _firebaseWriteTimeout,
          )
        : [sessionId];
    if (!_accountStillMatches(session, uid)) {
      return;
    }
    for (final id in sessions) {
      final seen = <String>{};
      while (true) {
        if (!_accountStillMatches(session, uid)) {
          return;
        }
        final rows = await native
            .getPendingNativeLocationSamples(id)
            .timeout(_firebaseWriteTimeout);
        if (!_accountStillMatches(session, uid)) {
          return;
        }
        if (rows.isEmpty) {
          break;
        }
        final transferred = <String>[];
        for (final row in rows) {
          final lat = row['latitude'];
          final lon = row['longitude'];
          final time = row['sampledAtMillis'];
          final sampleId = row['sampleId'];
          if (lat is! num ||
              lon is! num ||
              time is! num ||
              sampleId is! String) {
            continue;
          }
          if (row['ownerUid'] != null && row['ownerUid'] != uid) {
            continue;
          }
          if (!seen.add(sampleId)) {
            continue;
          }
          if (!_accountStillMatches(session, uid)) {
            return;
          }
          await _localDatabase.insertFootprint(
            ownerPhoneNumber: session.phoneNumber,
            sessionId: id,
            latitude: lat.toDouble(),
            longitude: lon.toDouble(),
            accuracy: (row['accuracyMeters'] as num?)?.toDouble(),
            altitude: (row['altitudeMeters'] as num?)?.toDouble(),
            recordedAt: DateTime.fromMillisecondsSinceEpoch(
              time.toInt(),
              isUtc: true,
            ),
            fixCapturedAt: row['capturedAtMillis'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (row['capturedAtMillis'] as num).toInt(),
                    isUtc: true,
                  )
                : null,
            pointType: 'tracking',
            isSynced: row['cloudAcknowledged'] == true,
          );
          transferred.add(sampleId);
        }
        if (transferred.isEmpty) {
          break;
        }
        if (!_accountStillMatches(session, uid)) {
          return;
        }
        await native
            .acknowledgeNativeLocationSamples(id, transferred)
            .timeout(_firebaseWriteTimeout);
        if (rows.length < 500) {
          break;
        }
      }
    }
  }

  /// Computes merge stored route.
  Future<ActiveHikeSession> mergeStoredRoute({
    required AppSession session,
    required ActiveHikeSession activeHike,
  }) async {
    final stored = await _localDatabase.loadFootprints(
      sessionId: activeHike.sessionId,
      ownerPhoneNumber: session.phoneNumber,
    );
    final points = <int, HikeCoordinate>{
      for (final p in activeHike.routePoints)
        p.capturedAt.millisecondsSinceEpoch: p,
      for (final p in stored)
        p.recordedAt.millisecondsSinceEpoch: HikeCoordinate(
          latitude: p.latitude,
          longitude: p.longitude,
          capturedAt: p.recordedAt,
          accuracyMeters: p.accuracy,
          altitudeMeters: p.altitude,
        ),
    }.values.toList()..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return activeHike.copyWith(
      routePoints: points,
      latestLocation: points.isEmpty ? activeHike.latestLocation : points.last,
    );
  }

  // recordFootprint persists the sample in SQLite first, keeping route recording independent of
  // connectivity.
  /// Records footprint.
  Future<int> recordFootprint({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation location,
    required String pointType,
    int? batteryLevel,
    DateTime? recordedAt,
  }) async {
    await _localDatabase.insertFootprint(
      ownerPhoneNumber: session.phoneNumber,
      sessionId: activeHike.sessionId,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracyMeters,
      batteryLevel: batteryLevel ?? activeHike.batteryLevel,
      pointType: pointType,
      recordedAt: recordedAt,
      fixCapturedAt: location.capturedAt,
    );
    // Local recording must never wait for connectivity or a cloud ACK.
    return _localDatabase.countUnsentFootprints(
      activeHike.sessionId,
      ownerPhoneNumber: session.phoneNumber,
    );
  }

  final Map<String, Future<int>> _footprintUploads = {};

  /// Flushes footprints.
  Future<int> flushFootprints({
    required AppSession session,
    required ActiveHikeSession activeHike,
    int limit = 200,
  }) {
    final key = '${session.phoneNumber}:${activeHike.sessionId}';
    final pending = _footprintUploads[key];
    if (pending != null) {
      return pending;
    }
    final future = _flushFootprints(
      session: session,
      activeHike: activeHike,
      limit: limit,
    );
    _footprintUploads[key] = future;
    return future.whenComplete(() => _footprintUploads.remove(key));
  }

  // _flushFootprints uploads bounded batches and clears only sample times explicitly acknowledged
  // by the backend.
  /// Flushes footprints.
  Future<int> _flushFootprints({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required int limit,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return _localDatabase.countUnsentFootprints(
        activeHike.sessionId,
        ownerPhoneNumber: session.phoneNumber,
      );
    }
    final uid = _captureAccountUid(session);
    if (uid == null) {
      return _localDatabase.countUnsentFootprints(
        activeHike.sessionId,
        ownerPhoneNumber: session.phoneNumber,
      );
    }
    // A tick sends the entire pending route, in bounded batches. A lost ACK
    // leaves its batch pending; the server deduplicates by session + sample time.
    final cutoff = DateTime.now().toUtc();
    try {
      while (true) {
        if (!_accountStillMatches(session, uid)) {
          break;
        }
        final points =
            (await _localDatabase.loadUnsentFootprints(
                  sessionId: activeHike.sessionId,
                  ownerPhoneNumber: session.phoneNumber,
                  limit: limit.clamp(1, 200),
                ))
                .where(
                  (p) =>
                      p.ownerPhoneNumber == session.phoneNumber &&
                      !p.recordedAt.isAfter(cutoff),
                )
                .toList();
        if (points.isEmpty || !_accountStillMatches(session, uid)) {
          break;
        }
        final response = await _resolvedFunctions
            .httpsCallable('appendHikeFootprints')
            .call({
              'sessionId': activeHike.sessionId,
              'footprints': points
                  .map(
                    (point) => {
                      'recordedAtMillis':
                          point.recordedAt.millisecondsSinceEpoch,
                      'latitude': point.latitude,
                      'longitude': point.longitude,
                      if (point.altitude != null)
                        'altitudeMeters': point.altitude,
                      if (point.accuracy != null)
                        'accuracyMeters': point.accuracy,
                      if (point.fixCapturedAt != null)
                        'fixCapturedAtMillis':
                            point.fixCapturedAt!.millisecondsSinceEpoch,
                      if (point.batteryLevel != null)
                        'batteryLevel': point.batteryLevel,
                      'pointType': point.pointType,
                    },
                  )
                  .toList(),
            })
            .timeout(_firebaseWriteTimeout);
        if (!_accountStillMatches(session, uid)) {
          break;
        }
        final acked = acknowledgedLocationSampleTimes(
          response.data,
          sessionId: activeHike.sessionId,
          requestedTimes: points
              .map((p) => p.recordedAt.millisecondsSinceEpoch)
              .toSet(),
        );
        final committed = points
            .where((p) => acked.contains(p.recordedAt.millisecondsSinceEpoch))
            .toList();
        if (committed.isEmpty) {
          break;
        }
        await _localDatabase.markFootprintsSynced(committed.map((p) => p.id));
        if (!_accountStillMatches(session, uid)) {
          break;
        }
        await const ActiveHikeLiveStatusService()
            .markNativeLocationSamplesCloudAcknowledged(
              activeHike.sessionId,
              committed
                  .map((p) => p.recordedAt.millisecondsSinceEpoch)
                  .toList(),
            )
            .timeout(_firebaseWriteTimeout);
        if (committed.length != points.length) {
          break;
        }
      }
    } catch (_) {
      // No committed response means retry later, including an uncertain commit.
    }
    return _localDatabase.countUnsentFootprints(
      activeHike.sessionId,
      ownerPhoneNumber: session.phoneNumber,
    );
  }

  /// Flushes sync outbox.
  Future<void> flushSyncOutbox({required AppSession session}) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    final operations = await _localDatabase.loadDueSyncOperations(
      ownerPhoneNumber: session.phoneNumber,
    );
    for (final operation in operations) {
      if (operation.entityType != 'active_hike_check_in') {
        continue;
      }
      try {
        await _resolvedFunctions
            .httpsCallable('recordActiveHikeCheckIn')
            .call(operation.payload)
            .timeout(_firebaseWriteTimeout);
        await _localDatabase.deleteSyncOperation(operation.operationId);
      } catch (error) {
        final delaySeconds = math.min(
          3600,
          30 * math.pow(2, operation.attemptCount).toInt(),
        );
        await _localDatabase.markSyncOperationRetry(
          operation.operationId,
          lastError: error.toString(),
          nextAttemptAt: DateTime.now().toUtc().add(
            Duration(seconds: delaySeconds),
          ),
        );
      }
    }
  }

  /// Records path deviation alert.
  Future<void> recordPathDeviationAlert({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeCoordinate coordinate,
    required double distanceMeters,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }
    if (activeHike.teamHikeSessionId.isNotEmpty) {
      await _manageTeamHikeAction(
        action: 'pathDeviation',
        teamHikeSessionId: activeHike.teamHikeSessionId,
        data: {
          'activeHikeSessionId': activeHike.sessionId,
          'latitude': coordinate.latitude,
          'longitude': coordinate.longitude,
          'distanceMeters': distanceMeters,
        },
      );
      return;
    }
    final now = DateTime.now().toUtc();
    await _hikeSessions.doc(activeHike.sessionId).set({
      'lastPathDeviation': {
        'coordinate': coordinate.toFirestore(),
        'distanceMeters': distanceMeters,
        'detectedAtLocal': now.toIso8601String(),
      },
      'lastPathDeviationAt': FieldValue.serverTimestamp(),
      'lastPathDeviationAtLocal': now.toIso8601String(),
      'pathDeviationAlertCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Ends a hike durably. When [ActiveHikeEndResult.cloudSynced] is false, the
  /// cloud completion is queued locally for the next network connection.
  Future<ActiveHikeEndResult> endHikeSession({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
  }) async {
    final endedAt = summary?.endedAt.toUtc() ?? DateTime.now().toUtc();
    await _localDatabase.queuePendingHikeEnd(
      ownerPhoneNumber: session.phoneNumber,
      activeHike: activeHike,
      summary: summary,
      endedAt: endedAt,
    );
    final trail = activeHike.draft.trail;
    await recordLocalAchievementEvents(
      session: session,
      events: completedHikeAchievementEvents(
        owner: session.phoneNumber,
        sessionId: activeHike.sessionId,
        sourceUpcomingHikeId: activeHike.sourceUpcomingHikeId,
        teamSessionId: activeHike.teamHikeSessionId,
        trailId: trail.trailId,
        state: trail.state,
        country: trail.isUnlisted ? '' : trail.country,
        distanceMetres: ((summary?.distanceKm ?? 0) * 1000).round().clamp(
          0,
          AchievementCatalog.eventLimit('completed_hike_distance_m'),
        ),
        durationMinutes: (summary?.duration.inMinutes ?? 0).clamp(
          0,
          AchievementCatalog.eventLimit('completed_hike_duration_min'),
        ),
      ),
    );
    // Durable local completion is the UI boundary. Cloud completion, route
    // uploads and team synchronization retry independently in the background.
    unawaited(
      flushPendingHikeEnds(session: session).catchError((Object _) => 0),
    );
    return ActiveHikeEndResult(
      cloudSynced: false,
      sessionId: activeHike.sessionId,
      completed: false,
      status: 'pending',
    );
  }

  final Map<String, Future<int>> _pendingEndUploads = {};
  final Map<String, Future<ActiveHikeCloudCompletionResult>>
  _hikeCompletionUploads = {};

  /// Foreground sharing joins the same idempotent completion upload as the
  /// background queue. Queueing a local end alone is never cloud confirmation.
  Future<ActiveHikeCloudCompletionResult> _syncHikeCompletionOnce({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport summary,
    required DateTime endedAt,
    required String expectedUid,
  }) {
    final key = '$expectedUid:${activeHike.sessionId}';
    final existing = _hikeCompletionUploads[key];
    if (existing != null) return existing;
    final future = _syncEndedHikeToCloud(
      session: session,
      activeHike: activeHike,
      summary: summary,
      endedAt: endedAt,
      expectedUid: expectedUid,
    );
    _hikeCompletionUploads[key] = future;
    return future.whenComplete(() {
      if (identical(_hikeCompletionUploads[key], future)) {
        _hikeCompletionUploads.remove(key);
      }
    });
  }

  /// Computes confirm ended hike for sharing.
  Future<ActiveHikeEndResult> confirmEndedHikeForSharing({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport summary,
  }) async {
    _throwIfFirebaseUnavailable();
    final uid = _captureAccountUid(session);
    if (uid == null) {
      throw const HikerCircleFirebaseRepositoryException(
        'Sign in again to sync and share this hike. Your hike and draft remain saved.',
      );
    }
    final hike = await mergeStoredRoute(
      session: session,
      activeHike: await _withCanonicalTeamSource(activeHike),
    );
    final completion = await _syncHikeCompletionOnce(
      session: session,
      activeHike: hike,
      summary: summary,
      endedAt: summary.endedAt.toUtc(),
      expectedUid: uid,
    );
    _requireSameAccount(session, uid);
    await _localDatabase.deletePendingHikeEnd(
      ownerPhoneNumber: session.phoneNumber,
      sessionId: activeHike.sessionId,
    );
    return ActiveHikeEndResult(
      cloudSynced: true,
      sessionId: completion.sessionId,
      completed: completion.completed,
      status: completion.status,
    );
  }

  // flushPendingHikeEnds retries durable completion intents while retaining the original hike end
  // time.
  /// Flushes pending hike ends.
  Future<int> flushPendingHikeEnds({
    required AppSession session,
    int limit = 20,
  }) {
    if (!_firebaseBootstrapResult.isAvailable) {
      return Future.value(0);
    }
    final uid = _captureAccountUid(session);
    if (uid == null) {
      return Future.value(0);
    }
    final key = '${session.phoneNumber}:$uid';
    final pending = _pendingEndUploads[key];
    if (pending != null) {
      return pending;
    }
    final future = _flushPendingHikeEnds(
      session: session,
      limit: limit,
      uid: uid,
    );
    _pendingEndUploads[key] = future;
    return future.whenComplete(() => _pendingEndUploads.remove(key));
  }

  /// Flushes pending hike ends.
  Future<int> _flushPendingHikeEnds({
    required AppSession session,
    required int limit,
    required String uid,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return 0;
    }
    _requireSameAccount(session, uid);
    await drainNativeLocationSamples(session: session);
    _requireSameAccount(session, uid);
    final pendingEnds = await _localDatabase.loadPendingHikeEnds(
      ownerPhoneNumber: session.phoneNumber,
      limit: limit,
    );
    var synced = 0;
    for (final pending in pendingEnds) {
      _requireSameAccount(session, uid);
      final savedHike = pending.activeHike;
      if (savedHike == null) {
        await _localDatabase.markPendingHikeEndRetry(
          ownerPhoneNumber: session.phoneNumber,
          sessionId: pending.sessionId,
          lastError: 'The saved hike completion payload is invalid.',
        );
        continue;
      }
      final hike = await mergeStoredRoute(
        session: session,
        activeHike: await _withCanonicalTeamSource(savedHike),
      );
      final endedAt = pending.endedAt ?? DateTime.now().toUtc();
      final report = HikeSummaryReport.fromActiveHike(
        activeHike: hike,
        endedAt: endedAt,
      );
      try {
        await _syncHikeCompletionOnce(
          session: session,
          activeHike: hike,
          summary: report,
          endedAt: endedAt,
          expectedUid: uid,
        );
        _requireSameAccount(session, uid);
        await _localDatabase.deletePendingHikeEnd(
          ownerPhoneNumber: session.phoneNumber,
          sessionId: pending.sessionId,
        );
        synced += 1;
      } catch (error) {
        await _localDatabase.markPendingHikeEndRetry(
          ownerPhoneNumber: session.phoneNumber,
          sessionId: pending.sessionId,
          lastError: error.toString(),
        );
      }
    }
    return synced;
  }

  /// Applies canonical team source.
  Future<ActiveHikeSession> _withCanonicalTeamSource(
    ActiveHikeSession activeHike,
  ) async {
    if (!_firebaseBootstrapResult.isAvailable ||
        activeHike.sourceUpcomingHikeId.trim().isNotEmpty ||
        activeHike.teamHikeSessionId.trim().isEmpty) {
      return activeHike;
    }
    try {
      final teamSession = await loadTeamHikeSession(
        activeHike.teamHikeSessionId,
      ).timeout(_firebaseReadTimeout);
      final sourceUpcomingHikeId =
          teamSession?.sourceUpcomingHikeId.trim() ?? '';
      if (teamSession == null || sourceUpcomingHikeId.isEmpty) {
        return activeHike;
      }
      return activeHike.copyWith(
        sourceUpcomingHikeId: sourceUpcomingHikeId,
        teamHikeSession: teamSession,
      );
    } catch (_) {
      return activeHike;
    }
  }

  /// Synchronizes ended hike to cloud.
  Future<ActiveHikeCloudCompletionResult> _syncEndedHikeToCloud({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required DateTime endedAt,
    required String expectedUid,
    HikeSummaryReport? summary,
  }) async {
    _requireSameAccount(session, expectedUid);
    final now = endedAt.toUtc();
    final completion = await _completeActiveHikeSession(
      activeHike: activeHike,
      endedAt: now,
      summary: summary,
    );
    _requireSameAccount(session, expectedUid);
    if (!completion.completed) return completion;
    try {
      var cloudHike = completion.sessionId == activeHike.sessionId
          ? activeHike
          : activeHike.copyWith(sessionId: completion.sessionId);
      if (cloudHike.sessionId != activeHike.sessionId) {
        await const ActiveHikeLiveStatusService().remapNativeLocationSession(
          activeHike.sessionId,
          cloudHike.sessionId,
        );
        await _localDatabase.migrateActiveHikeSessionId(
          ownerPhoneNumber: session.phoneNumber,
          activeHike: activeHike,
          newSessionId: cloudHike.sessionId,
        );
      }
      _requireSameAccount(session, expectedUid);
      // Pending completion keeps its original idempotency identity. SQLite may
      // already have moved its samples on an earlier attempt: merge the canonical
      // route again before replacing the cloud capture.
      cloudHike = await mergeStoredRoute(
        session: session,
        activeHike: cloudHike,
      );
      _requireSameAccount(session, expectedUid);
      final cloudSummary = HikeSummaryReport.fromActiveHike(
        activeHike: cloudHike,
        endedAt: now,
      );
      await _saveActualHikeRouteCapture(
        session: session,
        activeHike: cloudHike,
        summary: cloudSummary,
        capturedAt: now,
      ).timeout(_firebaseWriteTimeout);

      _requireSameAccount(session, expectedUid);
      // The idempotent terminal trigger closes team participation independently.
      final remaining = await flushFootprints(
        session: session,
        activeHike: cloudHike,
      );
      if (remaining > 0) {
        throw StateError(
          'Route samples are still awaiting a cloud acknowledgement.',
        );
      }
      return completion;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _ActiveHikePostCompletionSyncException(
          completion: completion,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  /// Computes complete active hike session.
  Future<ActiveHikeCloudCompletionResult> _completeActiveHikeSession({
    required ActiveHikeSession activeHike,
    required DateTime endedAt,
    HikeSummaryReport? summary,
  }) async {
    final payload = buildActiveHikeCompletionPayload(
      activeHike: activeHike,
      endedAt: endedAt,
      summary: summary,
    );
    try {
      final response = await waitForHikeCompletion(
        _resolvedFunctions
            .httpsCallable(
              'completeActiveHikeSession',
              options: HttpsCallableOptions(timeout: hikeCompletionTimeout),
            )
            .call<Map<String, dynamic>>(payload),
      );
      return parseActiveHikeCloudCompletionResult(
        response.data,
        requestedSessionId: activeHike.sessionId,
      );
    } on FirebaseFunctionsException catch (error) {
      final terminalResult = _terminalCompletionResultFromException(
        error,
        requestedSessionId: activeHike.sessionId,
      );
      if (terminalResult != null) {
        return terminalResult;
      }
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to complete this hike in the cloud.',
      );
    } on TypeError {
      throw const HikerCircleFirebaseRepositoryException(
        'The hike server returned an invalid completion response.',
      );
    }
  }

  /// Confirms a locally ended hike before submitting its public trail feedback.
  Future<void> submitEndedHikeRating({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport summary,
    required int rating,
    required String difficulty,
    String comment = '',
  }) async {
    final completion = await confirmEndedHikeForSharing(
      session: session,
      activeHike: activeHike,
      summary: summary,
    );
    if (!completion.completed || completion.status != 'completed') {
      throw const HikerCircleFirebaseRepositoryException(
        'This hike was not marked completed, so it cannot be rated.',
      );
    }
    await submitCompletedHikeRating(
      session: session,
      sessionId: completion.sessionId,
      trailId: activeHike.trail.trailId,
      rating: rating,
      difficulty: difficulty,
      comment: comment,
    );
  }

  /// Saves a vote only after the backend validates the completed owner session.
  Future<void> submitCompletedHikeRating({
    required AppSession session,
    required String sessionId,
    required String trailId,
    required int rating,
    required String difficulty,
    String comment = '',
  }) async {
    _throwIfFirebaseUnavailable();
    final normalizedDifficulty = difficulty.trim().toLowerCase();
    if (sessionId.trim().isEmpty ||
        trailId.trim().isEmpty ||
        rating < 1 ||
        rating > 5 ||
        !const {'easy', 'moderate', 'hard'}.contains(normalizedDifficulty) ||
        comment.trim().length > 500) {
      throw const HikerCircleFirebaseRepositoryException(
        'Choose 1 to 5 stars, select Easy, Moderate, or Hard, and keep the optional comment under 500 characters.',
      );
    }
    try {
      await _resolvedFunctions.httpsCallable('submitCompletedHikeRating').call({
        'sessionId': sessionId.trim(),
        'trailId': trailId.trim(),
        'rating': rating,
        'difficulty': normalizedDifficulty,
        'comment': comment.trim(),
      });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to save this trail rating.',
      );
    }
  }

  /// Computes submit hazard report.
  Future<void> submitHazardReport({
    required AppSession session,
    required Trail trail,
    required String hazardType,
    required String description,
    required String severity,
    SosTriggerLocation? location,
    String? reportId,
    List<PendingCautionMedia> media = const [],
  }) async {
    _throwIfFirebaseUnavailable();
    if (location?.hasValidPosition != true) {
      throw const HikerCircleFirebaseRepositoryException(
        'A current GPS location is needed.',
      );
    }
    final hazardId =
        reportId ?? 'report_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final uploaded = await TrailCautionService().upload(hazardId, media);
      await _resolvedFunctions.httpsCallable('submitTrailCaution').call({
        'hazardId': hazardId,
        'trailId': trail.trailId,
        'trailName': trail.name,
        'hazardType': hazardType,
        'description': description.trim(),
        'latitude': location!.latitude,
        'longitude': location.longitude,
        'media': uploaded,
      });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to submit this caution.',
      );
    }
  }

  /// A locally ended hike remains shareable while completion is queued. Retry
  /// the durable completion before publishing, preserving the original end time.
  Future<void> createEndedHikePost({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport summary,
    required ActiveHikeEndResult endResult,
    required String caption,
    List<CommunityPostImageUpload> images = const [],
    String? postId,
  }) async {
    final savedDraft = postId == null
        ? await loadCommunityPostDraft(
            session: session,
            draftKey: 'hike:${activeHike.sessionId}',
          )
        : null;
    final stablePostId = postId ?? savedDraft?.postId;
    var completion = endResult;
    if (completion.status != 'abandoned' && !completion.completed) {
      completion = await confirmEndedHikeForSharing(
        session: session,
        activeHike: activeHike,
        summary: summary,
      );
    }
    if (completion.status == 'abandoned') {
      throw const HikerCircleFirebaseRepositoryException(
        'This session was marked abandoned and cannot be posted as a completed hike.',
      );
    }
    if (!completion.completed) {
      throw const HikerCircleFirebaseRepositoryException(
        'Your hike is saved on this phone, but its completion has not synced yet. '
        'Tap Post to Community again to retry server confirmation. '
        'Your caption and photos are still here.',
      );
    }
    final cloudHike = completion.sessionId == activeHike.sessionId
        ? activeHike
        : activeHike.copyWith(sessionId: completion.sessionId);
    final cloudSummary = completion.sessionId == summary.sessionId
        ? summary
        : HikeSummaryReport.fromActiveHike(
            activeHike: cloudHike,
            endedAt: summary.endedAt,
          );
    await createCompletedHikePost(
      session: session,
      activeHike: cloudHike,
      summary: cloudSummary,
      caption: caption,
      images: images,
      postId: stablePostId,
    );
  }

  /// Creates completed hike post.
  Future<void> createCompletedHikePost({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
    String caption = 'Trail completed safely.',
    String postType = 'completed_hike',
    List<CommunityPostImageUpload> images = const [],
    String? postId,
  }) => _publishCommunity(
    this,
    session: session,
    activeHike: activeHike,
    summary: summary,
    caption: caption,
    images: images,
    postId: postId,
  );

  /// Creates community post.
  Future<void> createCommunityPost({
    required AppSession session,
    required String caption,
    List<CommunityPostImageUpload> images = const [],
    ActiveHikeSession? activeHike,
    String? postId,
    String? trailId,
  }) => _publishCommunity(
    this,
    session: session,
    caption: caption,
    images: images,
    activeHike: activeHike,
    postId: postId,
    trailId: trailId,
  );

  /// Loads community posts.
  Future<List<Map<String, dynamic>>> loadCommunityPosts({
    AppSession? session,
    int limit = 20,
    String? afterPostId,
  }) => _readCommunityPosts(
    this,
    session: session,
    limit: limit,
    afterPostId: afterPostId,
  );

  /// Sets community post liked.
  Future<int> setCommunityPostLiked({
    required AppSession session,
    required String postId,
    required bool liked,
  }) async {
    final uid = _communityAccount(this, session);
    final result = await _communityCall(this, 'setCommunityPostLike', {
      'postId': postId,
      'liked': liked,
    });
    _requireSameAccount(session, uid);
    final count = _intFrom(result['likeCount']);
    try {
      await _localDatabase.cacheCommunityReaction(
        ownerPhoneNumber: session.phoneNumber,
        postId: postId,
        liked: result['liked'] == true,
        likeCount: count,
      );
    } catch (_) {
      /* The canonical server acknowledgement is still valid. */
    }
    return count;
  }

  /// Adds community comment.
  Future<void> addCommunityComment({
    required AppSession session,
    required String postId,
    required String body,
    String? commentId,
  }) async {
    final uid = _communityAccount(this, session);
    final result = await _communityCall(this, 'writeCommunityComment', {
      'postId': postId,
      'commentId': commentId ?? _communityCommentsFor(postId).doc().id,
      'body': body.trim(),
    });
    _requireSameAccount(session, uid);
    try {
      await _localDatabase.updateCachedCommunityCommentCount(
        postId,
        _intFrom(result['commentCount']),
      );
    } catch (_) {}
  }

  /// Loads community comments.
  Future<List<Map<String, dynamic>>> loadCommunityComments({
    required String postId,
    String? afterCommentId,
    int limit = 50,
  }) => _readCommunityComments(
    this,
    postId,
    afterCommentId: afterCommentId,
    limit: limit,
  );

  /// Deletes community post.
  Future<void> deleteCommunityPost({
    required AppSession session,
    required String postId,
  }) async {
    final uid = _communityAccount(this, session);
    await _communityCall(this, 'deleteCommunityPost', {'postId': postId});
    _requireSameAccount(session, uid);
    try {
      await _localDatabase.removeCachedCommunityPost(postId);
    } catch (_) {}
  }

  /// Loads community post draft.
  Future<CommunityPostDraftData?> loadCommunityPostDraft({
    required AppSession session,
    required String draftKey,
  }) => _loadCommunityDraft(this, session, draftKey);

  /// Saves community post draft.
  Future<void> saveCommunityPostDraft({
    required AppSession session,
    required String draftKey,
    required String postId,
    required String caption,
    required List<CommunityPostImageUpload> images,
    required bool includeHike,
  }) => _localDatabase.saveCommunityDraft(
    ownerPhoneNumber: session.phoneNumber,
    draftKey: draftKey,
    postId: postId,
    caption: caption,
    includeHike: includeHike,
    images: images
        .map(
          (image) => <String, Object?>{
            'fileName': image.fileName,
            'contentType': image.contentType,
            'bytes': image.bytes,
          },
        )
        .toList(),
  );

  /// Deletes community post draft.
  Future<void> deleteCommunityPostDraft({
    required AppSession session,
    required String draftKey,
  }) => _localDatabase.deleteCommunityDraft(
    ownerPhoneNumber: session.phoneNumber,
    draftKey: draftKey,
  );

  /// Watches lifecycle metadata without dropping older or undated reports.
  Stream<List<Map<String, dynamic>>> watchAdminHazardReports({
    required AppSession session,
  }) async* {
    _throwIfAdminUnavailable(session);
    final uid = _captureAccountUid(session);
    if (uid == null) {
      throw const HikerCircleFirebaseRepositoryException(
        'Sign in again to view safety reports.',
      );
    }
    await for (final snapshot in _hazardReports.snapshots()) {
      if (!_accountStillMatches(session, uid)) {
        yield const [];
        throw const HikerCircleFirebaseRepositoryException(
          'The signed-in administrator changed.',
        );
      }
      yield snapshot.docs
          .map((doc) => <String, dynamic>{...doc.data(), 'hazardId': doc.id})
          .toList();
    }
  }

  /// Watches recent community evidence for an administrator's report detail.
  Stream<List<Map<String, dynamic>>> watchAdminHazardUpdates({
    required AppSession session,
    required String hazardId,
  }) async* {
    _throwIfAdminUnavailable(session);
    final uid = _captureAccountUid(session);
    if (uid == null || hazardId.isEmpty || hazardId.contains('/')) {
      throw const HikerCircleFirebaseRepositoryException(
        'This safety report is unavailable.',
      );
    }
    await for (final snapshot
        in _hazardReports
            .doc(hazardId)
            .collection('updates')
            .orderBy('createdAt', descending: true)
            .limit(30)
            .snapshots()) {
      if (!_accountStillMatches(session, uid)) {
        yield const [];
        throw const HikerCircleFirebaseRepositoryException(
          'The signed-in administrator changed.',
        );
      }
      yield snapshot.docs
          .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
          .toList();
    }
  }

  /// Loads admin community posts.
  Future<List<Map<String, dynamic>>> loadAdminCommunityPosts({
    required AppSession session,
  }) {
    _throwIfAdminUnavailable(session);
    return _readCommunityPosts(this, session: session, limit: 50, admin: true);
  }

  /// Loads admin dashboard analytics.
  Future<Map<String, dynamic>> loadAdminDashboardAnalytics({
    required AppSession session,
    bool forceRefresh = false,
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final response = await _resolvedFunctions
          .httpsCallable(
            'getAdminDashboardAnalytics',
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 120),
            ),
          )
          .call({'forceRefresh': forceRefresh});
      if (response.data is! Map) {
        throw const HikerCircleFirebaseRepositoryException(
          'Statistics returned an invalid response.',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Statistics could not load. Refresh to retry.',
      );
    }
  }

  /// Loads admin trails.
  Future<List<Trail>> loadAdminTrails({required AppSession session}) async {
    _throwIfAdminUnavailable(session);
    try {
      final snapshot = await _trails
          .orderBy('isVerifiedTrail', descending: true)
          .orderBy('ratingAverage', descending: true)
          .get();
      return snapshot.docs
          .map(
            (document) => _trailFromFirestore({
              'trailId': document.id,
              ...document.data(),
            }),
          )
          .whereType<Trail>()
          .toList();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to load trails: ${error.message ?? error.code}',
      );
    }
  }

  /// Updates trail by admin.
  Future<void> updateTrailByAdmin({
    required AppSession session,
    required Trail trail,
  }) async {
    _throwIfAdminUnavailable(session);
    final trailData = trail.toFirestore()
      ..remove('ratingAverage')
      ..remove('ratingCount')
      ..remove('difficulty')
      ..remove('difficultyVoteCounts')
      ..remove('difficultyRatingCount');
    await _saveTrailWithGeometry(trail, {
      ...trailData,
      'updatedByAdminId': _userIdFor(session),
      'updatedByAdminPhoneNumber': session.phoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Creates trail by admin.
  Future<void> createTrailByAdmin({
    required AppSession session,
    required Trail trail,
  }) async {
    _throwIfAdminUnavailable(session);
    final trailId = trail.trailId.isEmpty
        ? _newTrailId(trail.name)
        : trail.trailId;
    final trailToSave = trail.copyWith(trailId: trailId);
    await _saveTrailWithGeometry(
      trailToSave,
      _adminTrailCreationData(session, trailToSave),
    );
  }

  /// Computes admin trail creation data.
  Map<String, dynamic> _adminTrailCreationData(
    AppSession session,
    Trail trail,
  ) => {
    ...trail.toFirestore(),
    'ratingAverage': 0,
    'ratingCount': 0,
    'ratingSum': 0,
    'difficultyVoteCounts': const {'easy': 0, 'moderate': 0, 'hard': 0},
    'difficultyRatingCount': 0,
    'createdByAdminId': _userIdFor(session),
    'createdByAdminPhoneNumber': session.phoneNumber,
    'createdAt': FieldValue.serverTimestamp(),
    'createdAtLocal': DateTime.now().toUtc().toIso8601String(),
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
  };

  /// Computes approve recorded trail request.
  Future<void> approveRecordedTrailRequest({
    required AppSession session,
    required String requestId,
    required Trail trail,
    required List<HikeCoordinate> points,
  }) async {
    _throwIfAdminUnavailable(session);
    final geometry = TrailGeometryStorage.fromCoordinates([
      for (final p in points)
        {
          'lat': p.latitude,
          'lon': p.longitude,
          if (p.altitudeMeters?.isFinite == true) 'ele': p.altitudeMeters!,
        },
    ]);
    final saved = trail.copyWith(
      trailId: 'trail_request_$requestId',
      routeEncodedPolyline: geometry.encodedPolyline,
      routeCheckpointsHash: HikingRouteService.checkpointsHash(
        trail.checkpoints,
      ),
      routeProvider: 'stored-polyline',
    );
    await _saveTrailWithGeometry(
      saved,
      _adminTrailCreationData(session, saved),
      recordedGeometry: geometry,
      trailRequestId: requestId,
    );
  }

  /// Fetch canonical reports, falling back to an explicitly stale cache offline.
  Future<TrailHazardAssessment> loadTrailHazardAssessment(
    String trailId,
  ) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const TrailHazardAssessment(alerts: [], isFresh: false);
    }
    final query = _hazardReports.where('trailId', isEqualTo: trailId);
    QuerySnapshot<Map<String, dynamic>> snapshot;
    var fresh = true;
    try {
      snapshot = await query
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      fresh = false;
      try {
        snapshot = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        return const TrailHazardAssessment(alerts: [], isFresh: false);
      }
    }
    final now = DateTime.now();
    final alerts =
        snapshot.docs
            .map((doc) => TrailHazardAlert.fromMap(doc.id, doc.data()))
            .where((alert) => alert.trailId == trailId && alert.active(now))
            .toList()
          ..sort((a, b) {
            final risk = (b.isFatal ? 1 : 0).compareTo(a.isFatal ? 1 : 0);
            return risk != 0 ? risk : a.id.compareTo(b.id);
          });
    final detailed = await Future.wait(
      alerts.map((alert) async {
        if (!alert.isCriticalWeather) return alert;
        final updates = _hazardReports.doc(alert.id).collection('updates');
        try {
          final result = await updates
              .get(GetOptions(source: fresh ? Source.server : Source.cache))
              .timeout(const Duration(seconds: 6));
          return alert.withReportUpdates(
            result.docs.map((doc) => doc.data()),
            complete: fresh && !result.metadata.isFromCache,
          );
        } catch (_) {
          try {
            final cached = await updates
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(seconds: 2));
            return alert.withReportUpdates(
              cached.docs.map((doc) => doc.data()),
              complete: false,
            );
          } catch (_) {
            return alert.withReportUpdates(const [], complete: false);
          }
        }
      }),
    );
    return TrailHazardAssessment(alerts: detailed, isFresh: fresh);
  }

  /// Watches pending trail requests.
  Stream<bool> watchPendingTrailRequests({required AppSession session}) {
    if (!session.isAdmin || !_firebaseBootstrapResult.isAvailable) {
      return Stream.value(false);
    }
    return _resolvedFirestore
        .collection('trailRequests')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty)
        .distinct();
  }

  /// Loads admin trail requests.
  Future<List<Map<String, dynamic>>> loadAdminTrailRequests({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    final query = await _resolvedFirestore
        .collection('trailRequests')
        .where('status', isEqualTo: 'pending')
        .get();
    final rows = query.docs
        .map((d) => {'requestId': d.id, ...d.data()})
        .toList();
    rows.sort(
      (a, b) => ((b['submittedAtMillis'] as num?) ?? 0).compareTo(
        (a['submittedAtMillis'] as num?) ?? 0,
      ),
    );
    return rows;
  }

  /// Loads recorded trail request points.
  Future<List<HikeCoordinate>> loadRecordedTrailRequestPoints({
    required AppSession session,
    required String requestId,
  }) async {
    _throwIfAdminUnavailable(session);
    final ref = _resolvedFirestore.collection('trailRequests').doc(requestId);
    final meta = await ref.get();
    final chunks = await ref.collection('routeChunks').orderBy('index').get();
    final raw = <Map<String, dynamic>>[
      for (final chunk in chunks.docs) ..._listOfMaps(chunk.data()['points']),
    ];
    if (raw.length != meta.data()?['pointCount'] ||
        _recordedRequestHash(raw) != meta.data()?['routeHash']) {
      throw const HikerCircleFirebaseRepositoryException(
        'The recorded route is incomplete. Refresh before reviewing.',
      );
    }
    return [
      for (final p in raw)
        HikeCoordinate(
          latitude: _doubleFrom(p['lat']),
          longitude: _doubleFrom(p['lon']),
          capturedAt: DateTime.parse(p['time'] as String),
          accuracyMeters: (p['accuracyMeters'] as num?)?.toDouble(),
          altitudeMeters: (p['altitudeMeters'] as num?)?.toDouble(),
        ),
    ];
  }

  /// Computes reject recorded trail request.
  Future<void> rejectRecordedTrailRequest({
    required AppSession session,
    required String requestId,
    required String note,
  }) async {
    _throwIfAdminUnavailable(session);
    await _resolvedFirestore.collection('trailRequests').doc(requestId).update({
      'status': 'rejected',
      'reviewNote': note.trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedAtLocal': DateTime.now().toUtc().toIso8601String(),
      'reviewedByAdminId': _userIdFor(session),
    });
  }

  /// Computes recorded request hash.
  String _recordedRequestHash(List<Map<String, dynamic>> points) => crypto
      .sha256
      .convert(
        utf8.encode(
          points
              .map(
                (p) =>
                    '${(p['lat'] as num).toStringAsFixed(8)},${(p['lon'] as num).toStringAsFixed(8)},${p['time']}',
              )
              .join('\n'),
        ),
      )
      .toString();

  /// Computes recorded trail callable.
  Future<Map<String, dynamic>> _recordedTrailCallable(
    String name,
    Map<String, dynamic> data, {
    int timeoutSeconds = 30,
  }) async {
    try {
      final response = await _resolvedFunctions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(
              timeout: Duration(seconds: timeoutSeconds),
            ),
          )
          .call(data);
      if (response.data is! Map) {
        throw const HikerCircleFirebaseRepositoryException(
          'The trail request response was incomplete. Retry to recover the saved request.',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ??
            'The trail request could not sync. Reconnect and retry.',
      );
    }
  }

  /// Computes submit recorded trail request.
  Future<String> submitRecordedTrailRequest({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport report,
    required Map<String, String> proposed,
    required List<Map<String, dynamic>> checkpointSelections,
    ValueChanged<double>? onProgress,
  }) async {
    _throwIfFirebaseUnavailable();
    final uid = FirebaseBootstrap.requireAuthenticatedUser().uid;
    _requireSameAccount(session, uid);
    final points = HikeSummaryReport.recordedRoutePointsFor(activeHike);
    final raw = [
      for (final p in points)
        <String, dynamic>{
          'lat': p.latitude,
          'lon': p.longitude,
          'time': p.capturedAt.toUtc().toIso8601String(),
          if (p.altitudeMeters?.isFinite == true)
            'altitudeMeters': p.altitudeMeters,
          if (p.accuracyMeters?.isFinite == true)
            'accuracyMeters': p.accuracyMeters,
        },
    ];
    final completion = await _completeActiveHikeSession(
      activeHike: activeHike,
      endedAt: report.endedAt,
      summary: report,
    );
    _requireSameAccount(session, uid);
    if (!completion.completed) {
      throw const HikerCircleFirebaseRepositoryException(
        'Your hike completion must sync before this route can be submitted. Your GPS track remains saved on this phone.',
      );
    }
    final data = await _recordedTrailCallable('beginRecordedTrailRequest', {
      'sessionId': completion.sessionId,
      'pointCount': points.length,
      'routeHash': _recordedRequestHash(raw),
      'proposed': proposed,
      'checkpoints': checkpointSelections,
    });
    final id = data['requestId'] as String;
    if (data['status'] == 'pending' || data['status'] == 'approved') {
      return id;
    }
    if (data['status'] != 'uploading') {
      throw const HikerCircleFirebaseRepositoryException(
        'This hike already has a reviewed trail request.',
      );
    }
    final ref = _resolvedFirestore.collection('trailRequests').doc(id);
    for (var offset = 0; offset < raw.length; offset += 5000) {
      _requireSameAccount(session, uid);
      final batch = _resolvedFirestore.batch();
      for (var i = offset; i < raw.length && i < offset + 5000; i += 500) {
        batch.set(ref.collection('routeChunks').doc('${i ~/ 500}'), {
          'index': i ~/ 500,
          'points': raw.sublist(i, math.min(i + 500, raw.length)),
        });
      }
      await batch.commit().timeout(const Duration(seconds: 30));
      onProgress?.call(math.min(offset + 5000, raw.length) / raw.length);
    }
    _requireSameAccount(session, uid);
    await _recordedTrailCallable('finalizeRecordedTrailRequest', {
      'requestId': id,
    }, timeoutSeconds: 120);
    return id;
  }

  /// Commit the main route and full coordinates together, or neither.
  Future<void> _saveTrailWithGeometry(
    Trail trail,
    Map<String, dynamic> trailData, {
    TrailGeometryStorage? recordedGeometry,
    String? trailRequestId,
  }) async {
    final encoded = trail.routeEncodedPolyline?.trim() ?? '';
    if (encoded.isEmpty ||
        !HikingRouteService.savedRouteMatchesCheckpoints(trail)) {
      throw const HikerCircleFirebaseRepositoryException(
        'Fetch a route for the current checkpoints before saving.',
      );
    }
    late TrailGeometryStorage geometry;
    try {
      geometry = recordedGeometry ?? TrailGeometryStorage.fromPolyline(encoded);
    } catch (_) {
      throw const HikerCircleFirebaseRepositoryException(
        'The route geometry is invalid or too large. Refetch the route before saving.',
      );
    }
    final reference = _trails.doc(trail.trailId);
    await _resolvedFirestore.runTransaction((transaction) async {
      final requestReference = trailRequestId == null
          ? null
          : _resolvedFirestore.collection('trailRequests').doc(trailRequestId);
      if (requestReference != null) {
        final request = await transaction.get(requestReference);
        if (!request.exists || request.data()?['status'] != 'pending') {
          throw const HikerCircleFirebaseRepositoryException(
            'This trail request has already been reviewed.',
          );
        }
      }
      final existing = await transaction.get(reference);
      if (requestReference != null && existing.exists) {
        throw const HikerCircleFirebaseRepositoryException(
          'A trail already exists for this request. Refresh before reviewing.',
        );
      }
      var writeGeometry = false;
      final previous = existing.data();
      final previousMetadata = previous?['routeGeometryMetadata'];
      final priorPath = previousMetadata is Map
          ? previousMetadata['geometryDocument']
          : null;
      // Imported geometry can contain higher precision and per-point altitude.
      // Preserve it on unrelated edits instead of replacing it with decoded XY.
      final reusable =
          previous?['routeEncodedPolyline'] == encoded &&
          previousMetadata is Map &&
          previousMetadata['geometrySha256'] == geometry.checksum &&
          priorPath is String &&
          (priorPath.startsWith('${reference.path}/routeGeometry/') ||
              priorPath.contains(
                '/documents/${reference.path}/routeGeometry/',
              ));
      final now = DateTime.now().toUtc().toIso8601String();
      final geometryReference = reference
          .collection('routeGeometry')
          .doc(geometry.checksum);
      Map<String, dynamic> metadata;
      if (reusable) {
        final relativePath = priorPath.contains('/documents/')
            ? priorPath.split('/documents/').last
            : priorPath;
        final stored = await transaction.get(
          _resolvedFirestore.doc(relativePath),
        );
        if (stored.exists) {
          metadata = Map<String, dynamic>.from(previousMetadata);
        } else {
          metadata = geometry.metadata(geometryReference.path, now);
          writeGeometry = true;
          transaction.set(geometryReference, geometry.document(now));
        }
      } else {
        metadata = geometry.metadata(geometryReference.path, now);
        writeGeometry = true;
        transaction.set(geometryReference, geometry.document(now));
      }
      for (var i = 0; writeGeometry && i < geometry.chunks.length; i++) {
        transaction.set(geometryReference.collection('chunks').doc('$i'), {
          'index': i,
          'points': geometry.chunks[i],
        });
      }
      if (requestReference != null) {
        transaction.update(requestReference, {
          'status': 'approved',
          'publishedTrailId': trail.trailId,
          'reviewedByAdminId': trailData['createdByAdminId'],
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedAtLocal': now,
        });
      }
      transaction.set(reference, {
        ...trailData,
        'dataSource': 'Stored route coordinates',
        'routeProvider': 'stored-polyline',
        // Native saves must not restore obsolete references from a cached trail.
        for (final field in const [
          'dataSourceUrl',
          'routeReferenceName',
          'routeReferenceUrl',
          'routeReferenceNote',
          'routeVerifiedAtLocal',
          'osmRelationId',
        ])
          field: FieldValue.delete(),
        'routeCheckpointsHash': HikingRouteService.checkpointsHash(
          trail.checkpoints,
        ),
        'routeGeometryMetadata': metadata,
      }, SetOptions(merge: true));
    });
  }

  /// Computes new trail id for name.
  String newTrailIdForName(String name) => _newTrailId(name);

  /// Uploads trail cover images by admin.
  Future<List<String>> uploadTrailCoverImagesByAdmin({
    required AppSession session,
    required String trailId,
    required List<AdminTrailImageUpload> images,
  }) async {
    _throwIfAdminUnavailable(session);
    if (trailId.trim().isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'A trail id is required before uploading images.',
      );
    }
    if (images.isEmpty) {
      return const [];
    }

    final uploadedReferences = <Reference>[];
    final downloadUrls = <String>[];
    try {
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        if (image.bytes.isEmpty) {
          continue;
        }
        final safeName = _safeStorageFileName(image.fileName, index);
        final reference = _resolvedStorage.ref(
          'trail_covers/$trailId/'
          '${DateTime.now().microsecondsSinceEpoch}_$safeName',
        );
        final metadata = SettableMetadata(
          contentType: image.contentType ?? _contentTypeForFileName(safeName),
          customMetadata: {
            'trailId': trailId,
            'uploadedByAdminPhoneNumber': session.phoneNumber,
          },
        );
        await reference.putData(image.bytes, metadata);
        uploadedReferences.add(reference);
        downloadUrls.add(await reference.getDownloadURL());
      }
      return downloadUrls;
    } on FirebaseException catch (error) {
      for (final reference in uploadedReferences) {
        try {
          await reference.delete();
        } catch (_) {
          // Cleanup is best effort if a later image fails.
        }
      }
      throw HikerCircleFirebaseRepositoryException(
        'Image upload failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      for (final reference in uploadedReferences) {
        try {
          await reference.delete();
        } catch (_) {
          // Cleanup is best effort if a later image fails.
        }
      }
      throw HikerCircleFirebaseRepositoryException(
        'Image upload failed: $error',
      );
    }
  }

  /// Deletes trail by admin.
  Future<void> deleteTrailByAdmin({
    required AppSession session,
    required Trail trail,
  }) async {
    _throwIfAdminUnavailable(session);
    if (trail.trailId.trim().isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Trail is missing an id.',
      );
    }

    try {
      await _trails.doc(trail.trailId).delete();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to delete trail: ${error.message ?? error.code}',
      );
    }
  }

  /// Loads admin sos alerts.
  Future<List<Map<String, dynamic>>> loadAdminSosAlerts({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final snapshot = await _sosAlerts
          .orderBy('triggeredAtLocal', descending: true)
          .limit(100)
          .get();
      return snapshot.docs.map((document) {
        return {'alertId': document.id, ...document.data()};
      }).toList();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to load SOS alerts: ${error.message ?? error.code}',
      );
    }
  }

  /// Loads more admin community posts.
  Future<List<Map<String, dynamic>>> loadMoreAdminCommunityPosts({
    required AppSession session,
    required String afterPostId,
  }) {
    _throwIfAdminUnavailable(session);
    return _readCommunityPosts(
      this,
      session: session,
      limit: 50,
      afterPostId: afterPostId,
      admin: true,
    );
  }

  /// Loads a specific readable post, including current author and reaction data.
  Future<Map<String, dynamic>?> loadCommunityPost({
    required AppSession session,
    required String postId,
  }) async {
    final uid = _communityAccount(this, session);
    if (postId.isEmpty || postId.length > 200 || postId.contains('/')) {
      return null;
    }
    try {
      final snapshot = await _communityPosts
          .doc(postId)
          .get()
          .timeout(_firebaseReadTimeout);
      if (!snapshot.exists) return null;
      final data = snapshot.data()!;
      // A chat preview never grants access to hidden or removed content.
      if (data['visibility'] != 'public' &&
          data['authorId'] != uid &&
          !session.isAdmin) {
        return null;
      }
      var liked = false;
      if (data['visibility'] == 'public') {
        liked =
            (await snapshot.reference
                    .collection('reactions')
                    .doc(uid)
                    .get()
                    .timeout(_firebaseReadTimeout))
                .exists;
      }
      final rows = await _hydrateCommunityAuthorLevels([
        communityPostViewData(
          data,
          postId: postId,
          viewerId: uid,
          liked: liked,
        ),
      ]);
      _requireSameAccount(session, uid);
      return rows.single;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        return null;
      }
      throw const HikerCircleFirebaseRepositoryException(
        'Unable to open this story. Please try again.',
      );
    }
  }

  /// Edits only the signed-in author's post using its confirmed content revision.
  Future<Map<String, dynamic>> editOwnCommunityPost({
    required AppSession session,
    required Map<String, dynamic> original,
    required String caption,
    required List<String> imageUrls,
  }) async {
    final uid = _communityAccount(this, session);
    if (original['authorId'] != uid) {
      throw const HikerCircleFirebaseRepositoryException(
        'You can only edit your own stories.',
      );
    }
    return _editCommunityPost(
      session: session,
      original: original,
      caption: caption,
      imageUrls: imageUrls,
    );
  }

  /// Computes edit admin community post.
  Future<void> editAdminCommunityPost({
    required AppSession session,
    required Map<String, dynamic> original,
    required String caption,
    required List<String> imageUrls,
  }) async {
    _throwIfAdminUnavailable(session);
    await _editCommunityPost(
      session: session,
      original: original,
      caption: caption,
      imageUrls: imageUrls,
    );
  }

  /// Retains only existing photos and invalidates cached content after confirmation.
  Future<Map<String, dynamic>> _editCommunityPost({
    required AppSession session,
    required Map<String, dynamic> original,
    required String caption,
    required List<String> imageUrls,
  }) async {
    final uid = _communityAccount(this, session);
    final images = _listOfMaps(original['images']);
    final selected = images
        .where((image) => imageUrls.contains(image['url']))
        .toList();
    if (selected.length != imageUrls.length) {
      throw const HikerCircleFirebaseRepositoryException(
        'Only existing post photos can be retained.',
      );
    }
    final result = await _communityCall(this, 'editCommunityPost', {
      'postId': original['postId'],
      'caption': caption,
      'retainedImagePaths': selected.map((image) => image['path']).toList(),
      'expectedUpdatedAtMillis': original['updatedAtMillis'],
      'expectedOwner': uid,
    });
    _requireSameAccount(session, uid);
    try {
      await _localDatabase.removeCachedCommunityPost(
        _stringFrom(original['postId']),
      );
    } catch (_) {
      // The edit is committed even if this phone cannot invalidate its cache.
    }
    return {
      ...original,
      'caption': caption.trim(),
      'images': selected,
      'imageUrls': imageUrls,
      'updatedAtMillis': result['updatedAtMillis'],
    };
  }

  /// Computes moderate community post.
  Future<void> moderateCommunityPost({
    required AppSession session,
    required String postId,
    required String moderationStatus,
    String reason = '',
    int? expectedUpdatedAtMillis,
  }) async {
    _throwIfAdminUnavailable(session);
    final uid = _communityAccount(this, session);
    await _communityCall(this, 'moderateCommunityPost', {
      'postId': postId,
      'status': moderationStatus.trim().toLowerCase(),
      'reason': reason.trim(),
      if (expectedUpdatedAtMillis != null)
        'expectedUpdatedAtMillis': expectedUpdatedAtMillis,
      'expectedOwner': uid,
    });
    _requireSameAccount(session, uid);
    try {
      await _localDatabase.removeCachedCommunityPost(postId);
    } catch (_) {}
  }

  /// Removes admin community comment.
  Future<void> removeAdminCommunityComment({
    required AppSession session,
    required String postId,
    required String commentId,
  }) async {
    _throwIfAdminUnavailable(session);
    final uid = _communityAccount(this, session);
    await _communityCall(this, 'removeCommunityComment', {
      'postId': postId,
      'commentId': commentId,
      'expectedOwner': uid,
    });
    _requireSameAccount(session, uid);
    try {
      // Evict the thread too so offline reads cannot resurrect a removed reply.
      await _localDatabase.removeCachedCommunityPost(postId);
    } catch (_) {
      // The server decision succeeded; a cache failure must not imply failure.
    }
  }

  /// Computes local achievement seeds.
  List<Map<String, dynamic>> _localAchievementSeeds() =>
      _achievementProgressFrom(
        achievements: _achievementSeedRows(),
        userAwardsByAchievementId: const {},
      );

  /// The notification host is awaited before callers may start their cloud work.
  Future<void> recordLocalAchievementEvents({
    required AppSession session,
    required List<AchievementMetricEvent> events,
  }) async {
    await AchievementCatalog.load();
    await _localDatabase.updateLocalAchievementProgress(
      ownerPhoneNumber: session.phoneNumber,
      seedRows: _localAchievementSeeds(),
      events: events,
    );
    await AchievementNotificationEvents.changed(session.phoneNumber);
  }

  /// Computes merge achievement rows.
  Future<List<Map<String, dynamic>>> _mergeAchievementRows({
    required AppSession session,
    List<Map<String, dynamic>>? serverRows,
    bool fresh = false,
  }) async {
    await AchievementCatalog.load();
    final rows = await _localDatabase.updateLocalAchievementProgress(
      ownerPhoneNumber: session.phoneNumber,
      seedRows: _localAchievementSeeds(),
      serverRows: serverRows,
      freshServerSnapshot: fresh,
    );
    await AchievementNotificationEvents.changed(session.phoneNumber);
    return rows;
  }

  /// Watches both rule visibility and awards, so archiving never waits for the hiker's next achievement.
  Stream<List<Map<String, dynamic>>> watchUserAchievementProgress({
    required AppSession session,
  }) {
    if (!_firebaseBootstrapResult.isAvailable) return const Stream.empty();
    final uid = _userIdFor(session);
    return Stream.multi((output) {
      List<Map<String, dynamic>>? definitions, awards;
      var definitionsFresh = false, awardsFresh = false, closed = false;
      var revision = 0;

      /// Publishes the newest authoritative rule flags alongside this hiker's private progress.
      Future<void> publish() async {
        if (definitions == null || awards == null) return;
        final generation = ++revision;
        final currentDefinitions = [...definitions!],
            currentAwards = [...awards!];
        if (closed ||
            generation != revision ||
            !_accountStillMatches(session, uid)) {
          return;
        }
        final awardsById = <String, Map<String, dynamic>>{
          for (final row in currentAwards)
            _stringFrom(row['achievementId']): row,
        };
        final known = currentDefinitions
            .map((row) => row['achievementId'])
            .toSet();
        // Keep historical points for removed definitions, but never resurrect their cards from stale awards.
        for (final row in currentAwards) {
          if (known.add(row['achievementId']) && row['isUnlocked'] == true) {
            currentDefinitions.add({
              ...row,
              'title': row['title'] ?? row['achievementTitle'],
              'isActive': false,
            });
          }
        }
        final rows = await _mergeAchievementRows(
          session: session,
          serverRows: _achievementProgressFrom(
            achievements: currentDefinitions,
            userAwardsByAchievementId: awardsById,
          ),
          fresh: definitionsFresh && awardsFresh,
        );
        if (!closed &&
            generation == revision &&
            _accountStillMatches(session, uid)) {
          output.add(rows);
        }
      }

      /// Retains cached content if a listener temporarily loses access or connectivity.
      void report(Object error, StackTrace stack) {
        if (!closed) output.addError(error, stack);
      }

      final definitionSubscription = _achievements
          .orderBy('sortOrder')
          .snapshots()
          .listen((snapshot) {
            definitions = snapshot.docs
                .map((doc) => {'achievementId': doc.id, ...doc.data()})
                .toList();
            definitionsFresh = !snapshot.metadata.isFromCache;
            unawaited(
              publish().catchError(
                (Object error, StackTrace stack) => report(error, stack),
              ),
            );
          }, onError: report);
      final awardSubscription = _userAchievements
          .where('userId', isEqualTo: uid)
          .snapshots()
          .listen((snapshot) {
            awards = snapshot.docs
                .map((doc) => {'userAchievementId': doc.id, ...doc.data()})
                .toList();
            awardsFresh = !snapshot.metadata.isFromCache;
            unawaited(
              publish().catchError(
                (Object error, StackTrace stack) => report(error, stack),
              ),
            );
          }, onError: report);
      output.onCancel = () {
        closed = true;
        revision++;
        unawaited(definitionSubscription.cancel());
        unawaited(awardSubscription.cancel());
      };
    });
  }

  /// Loads cached achievement progress.
  Future<LocalAchievementProgressCache?> loadCachedAchievementProgress({
    required AppSession session,
  }) {
    return _localDatabase.loadAchievementProgressCache(
      ownerPhoneNumber: session.phoneNumber,
    );
  }

  /// Loads local achievement progress.
  Future<List<Map<String, dynamic>>> loadLocalAchievementProgress({
    required AppSession session,
  }) => _mergeAchievementRows(session: session);

  /// Saves cached achievement progress.
  Future<void> saveCachedAchievementProgress({
    required AppSession session,
    required String contentHash,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _mergeAchievementRows(session: session, serverRows: rows);
  }

  /// Reuse the same cached read model instead of a separate hash-only endpoint.
  Future<String> loadAchievementProgressHash({
    required AppSession session,
  }) async {
    try {
      final data = await readMobileSnapshot(
        owner: session.phoneNumber,
        resourceType: 'achievement_progress',
      );
      return _stringFrom(data['contentHash']);
    } catch (_) {
      return '';
    }
  }

  /// Local progress stays available while the server-owned catalogue is hash validated.
  Future<List<Map<String, dynamic>>> loadUserAchievementProgress({
    required AppSession session,
  }) async {
    try {
      final data = await readMobileSnapshot(
        owner: session.phoneNumber,
        resourceType: 'achievement_progress',
      );
      final definitions = _snapshotRows(data, 'achievements');
      final awards = _snapshotRows(data, 'awards');
      if (!data.containsKey('achievements')) {
        return _mergeAchievementRows(session: session);
      }
      final byId = <String, Map<String, dynamic>>{
        for (final award in awards) _stringFrom(award['achievementId']): award,
      };
      final rows = _achievementProgressFrom(
        achievements: definitions,
        userAwardsByAchievementId: byId,
      );
      // Cached read models do not establish a new live notification baseline.
      // The authoritative rule/award streams retain that responsibility.
      return _mergeAchievementRows(session: session, serverRows: rows);
    } catch (_) {
      return _mergeAchievementRows(session: session);
    }
  }

  /// Loads community posts for user.
  Future<List<Map<String, dynamic>>> loadCommunityPostsForUser({
    required AppSession session,
  }) => _readCommunityPosts(
    this,
    session: session,
    authorId: _userIdFor(session),
    limit: 100,
  );

  /// Loads achievement leaderboard.
  Future<List<Map<String, dynamic>>> loadAchievementLeaderboard({
    String period = 'month',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }
    try {
      final response = await _resolvedFunctions
          .httpsCallable('loadAchievementLeaderboard')
          .call(<String, dynamic>{
            'period': period == 'year' ? 'year' : 'month',
          });
      final data = Map<String, dynamic>.from(response.data as Map);
      final entries = data['entries'];
      return entries is Iterable
          ? entries
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList(growable: false)
          : const [];
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load the hiking leaderboard.',
      );
    }
  }

  /// Watches common team snapshot versions so open history pages refresh after another member finishes.
  Stream<String> watchTeamHistoryChanges(String phone) => _teamHikeSessions
      .where('participantPhoneNumbers', arrayContains: phone)
      .snapshots()
      .map((snapshot) {
        final versions =
            snapshot.docs
                .map(
                  (doc) =>
                      '${doc.id}:${doc.data()['summarySnapshot']?['generatedAtLocal'] ?? ''}',
                )
                .toList()
              ..sort();
        return versions.join('|');
      })
      .distinct();

  /// Loads my hike history.
  Future<String> _historyCacheOwner() async {
    final owner =
        (await _localDatabase.loadSession())?.phoneNumber.trim() ?? '';
    if (owner.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message:
            'A restored signed-in account is required to load hike history.',
      );
    }
    return owner;
  }

  /// Loads my hike history.
  Future<List<HikeHistorySummary>> loadMyHikeHistory({
    int limit = 100,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    final owner = await _historyCacheOwner();
    final bounded = limit.clamp(1, 200);
    final data = await _conditionalCache.read(
      owner: owner,
      type: 'hike_history_list',
      id: 'latest-$bounded',
      callable: 'listMyHikeHistory',
      arguments: {'limit': bounded},
      freshness: const Duration(minutes: 2),
      online: _firebaseBootstrapResult.isAvailable,
      force: force,
      cacheOnly: cacheOnly,
    );
    return parseHikeHistoryList(data);
  }

  /// Loads my hike history detail.
  Future<HikeHistoryDetail> loadMyHikeHistoryDetail(
    String sessionId, {
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (sessionId.trim().isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'The hike history entry is invalid.',
      );
    }
    final owner = await _historyCacheOwner();
    final data = await _conditionalCache.read(
      owner: owner,
      type: 'hike_history_detail',
      id: sessionId.trim(),
      callable: 'loadMyHikeHistoryDetail',
      arguments: {'sessionId': sessionId.trim()},
      freshness: const Duration(minutes: 10),
      online: _firebaseBootstrapResult.isAvailable,
      force: force,
      cacheOnly: cacheOnly,
    );
    return parseHikeHistoryDetail(data);
  }

  /// Ensures achievement seeds.
  Future<void> ensureAchievementSeeds() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    try {
      await _resolvedFunctions
          .httpsCallable('manageAchievementDefinition')
          .call({'action': 'seed'})
          .timeout(_firebaseWriteTimeout);
    } catch (_) {}
  }

  /// Loads admin achievements.
  Future<List<Map<String, dynamic>>> loadAdminAchievements({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    await ensureAchievementSeeds();
    final snapshot = await _achievements.orderBy('sortOrder').get();
    return snapshot.docs
        .map((document) => {'achievementId': document.id, ...document.data()})
        .where(AchievementCatalog.visible)
        .toList();
  }

  /// Saves achievement by admin.
  Future<String> saveAchievementByAdmin({
    required AppSession session,
    required Map<String, dynamic> achievement,
    String achievementId = '',
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final response = await _resolvedFunctions
          .httpsCallable('manageAchievementDefinition')
          .call<Map<String, dynamic>>({
            'action': 'save',
            'achievementId': achievementId.trim(),
            'achievement': achievement,
          });
      final id = _stringFrom(response.data['achievementId']);
      if (id.isEmpty) {
        throw const HikerCircleFirebaseRepositoryException(
          'The achievement server returned an invalid id.',
        );
      }
      return id;
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to save this achievement.',
      );
    }
  }

  /// Sets achievement active by admin.
  Future<void> setAchievementActiveByAdmin({
    required AppSession session,
    required String achievementId,
    required bool isActive,
  }) async {
    _throwIfAdminUnavailable(session);
    if (achievementId.trim().isEmpty) {
      return;
    }
    try {
      await _resolvedFunctions
          .httpsCallable('manageAchievementDefinition')
          .call({
            'action': 'setActive',
            'achievementId': achievementId.trim(),
            'isActive': isActive,
          });
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to update this achievement.',
      );
    }
  }

  /// Computes achievement seed rows.
  List<Map<String, dynamic>> _achievementSeedRows() => AchievementCatalog.seeds;

  /// Computes achievement progress from.
  List<Map<String, dynamic>> _achievementProgressFrom({
    required List<Map<String, dynamic>> achievements,
    required Map<String, Map<String, dynamic>> userAwardsByAchievementId,
  }) {
    final rows = achievements
        .where((row) {
          final award = userAwardsByAchievementId[row['achievementId']];
          return AchievementCatalog.visible(row) ||
              award?['isUnlocked'] == true ||
              award?['awardedAt'] != null ||
              award?['awardedAtLocal'] != null;
        })
        .map((achievement) {
          final achievementId = _stringFrom(achievement['achievementId']);
          final award = userAwardsByAchievementId[achievementId];
          final isActive = achievement['isActive'] != false;

          final awardedAt = award == null
              ? null
              : _dateFromValue(award['awardedAt']) ??
                    _dateFromValue(award['awardedAtLocal']);
          final title = _stringFrom(achievement['title']);
          final condition = _stringFrom(achievement['condition']);
          final category = _stringFrom(achievement['category']);
          final iconName = _stringFrom(achievement['iconName']);
          final sortOrder = _intFrom(achievement['sortOrder']);

          final rewardType =
              _stringFrom(achievement['rewardType']) == 'cumulative'
              ? 'cumulative'
              : 'one_time';
          final targetCount = rewardType == 'one_time'
              ? 1
              : _intFrom(achievement['targetCount']).clamp(1, 1000000000);
          final isUnlocked =
              award?['isUnlocked'] == true ||
              award?['awardedAt'] != null ||
              award?['awardedAtLocal'] != null;
          final progressCount = isUnlocked
              ? targetCount
              : _intFrom(award?['progressCount']).clamp(0, targetCount);

          return <String, dynamic>{
            'achievementId': achievementId,
            'title': title.isEmpty ? 'Achievement' : title,
            'condition': condition.isEmpty
                ? 'Complete a safety milestone'
                : condition,
            'category': category.isEmpty ? 'Safety' : category,
            'iconName': iconName.isEmpty ? 'emoji_events' : iconName,
            ...AchievementCatalog.content(achievement),
            'rewardPoints': _intFrom(achievement['rewardPoints']),
            'pointsAwarded': isUnlocked
                ? (_intFrom(award?['pointsAwarded']) > 0
                      ? _intFrom(award?['pointsAwarded'])
                      : _intFrom(achievement['rewardPoints']))
                : 0,
            'rewardType': rewardType,
            'metricKey': _stringFrom(achievement['metricKey']),
            'targetCount': targetCount,
            'progressCount': progressCount,
            'sortOrder': sortOrder,
            'accentColorValue': _intFrom(achievement['accentColorValue']),
            'isActive': isActive,
            'isUnlocked': isUnlocked,
            if (award != null)
              'userAchievementId': _stringFrom(award['userAchievementId']),
            if (awardedAt != null)
              'awardedAtLocal': awardedAt.toIso8601String(),
          };
        })
        .where((row) => row.isNotEmpty)
        .toList();

    rows.sort((left, right) {
      final orderComparison = _intFrom(
        left['sortOrder'],
      ).compareTo(_intFrom(right['sortOrder']));
      if (orderComparison != 0) {
        return orderComparison;
      }
      return _stringFrom(left['title']).compareTo(_stringFrom(right['title']));
    });
    return rows;
  }

  // _hydrateCommunityAuthorLevels adds current public profile/level fields to views without
  // expanding canonical post documents.
  /// Computes hydrate community author levels.
  Future<List<Map<String, dynamic>>> _hydrateCommunityAuthorLevels(
    List<Map<String, dynamic>> rows,
  ) async {
    final authorIds = rows
        .map((row) => _stringFrom(row['authorId']))
        .where((id) => id.isNotEmpty)
        .toSet();
    if (authorIds.isEmpty) {
      return rows;
    }
    try {
      final profiles = await _getPublicProfiles({
        'userIds': authorIds.toList(),
      });
      final profilesById = <String, Map<String, dynamic>>{
        for (final profile in profiles)
          if (_stringFrom(profile['userId']).isNotEmpty)
            _stringFrom(profile['userId']): profile,
      };
      return rows.map((row) {
        final profile = profilesById[_stringFrom(row['authorId'])];
        if (profile == null) {
          return row;
        }
        final points = _intFrom(profile['achievementPoints']);
        final level = HikerLevel.fromPoints(points);
        final username = _stringFrom(profile['displayName']).trim();
        final photoURL = _stringFrom(profile['photoURL']).trim();
        return {
          ...row,
          'authorProfileLoaded': true,
          'authorIsAdmin': profile['isAdmin'] == true,
          'authorPhoneNumber': _stringFrom(profile['phoneNumber']),
          'authorHandle': _stringFrom(profile['handle']),
          if (username.isNotEmpty) 'authorName': username,
          'authorPhotoURL': photoURL,
          'authorAchievementPoints': points,
          'authorLevel': level.number,
          'authorLevelName': level.name,
          'authorLevelBadge': level.badgeLabel,
        };
      }).toList();
    } catch (_) {
      return rows;
    }
  }

  /// Computes hydrate group chats with photos.
  Future<List<GroupChat>> _hydrateGroupChatsWithPhotos(
    List<GroupChat> chats,
  ) async {
    if (chats.isEmpty) {
      return chats;
    }
    final resolved = await _photoURLsForPhones(
      chats.expand((chat) => chat.participantPhones),
    );
    if (resolved.isEmpty) {
      return chats;
    }
    return chats
        .map(
          (chat) => chat.copyWith(
            participantPhotoURLs: {
              ...chat.participantPhotoURLs,
              for (final phone in chat.participantPhones)
                if (resolved[_phoneKeyFor(phone)] case final photoURL?)
                  _phoneKeyFor(phone): photoURL,
            },
          ),
        )
        .toList(growable: false);
  }

  /// Loads cached map entities.
  Future<List<Map<String, dynamic>>> _loadCachedMapEntities({
    required String ownerPhoneNumber,
    required String entityType,
    String? parentId,
  }) async {
    try {
      final rows = await _localDatabase.loadCachedEntities(
        ownerPhoneNumber: ownerPhoneNumber,
        entityType: entityType,
        parentId: parentId,
        includeExpired: true,
      );
      return rows.map((row) => row.payload).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Computes cache map entities.
  Future<void> _cacheMapEntities({
    required String ownerPhoneNumber,
    required String entityType,
    required String idKey,
    required List<Map<String, dynamic>> rows,
    String parentId = '',
  }) async {
    final now = DateTime.now().toUtc();
    await _localDatabase.replaceCachedEntitySet(
      ownerPhoneNumber: ownerPhoneNumber,
      entityType: entityType,
      parentId: parentId,
      entities: rows.indexed.map((entry) {
        final id = _stringFrom(entry.$2[idKey]);
        return LocalCachedEntity(
          ownerPhoneNumber: ownerPhoneNumber,
          entityType: entityType,
          entityId: id.isEmpty ? '${entry.$1}' : id,
          parentId: parentId,
          payload: _jsonSafeMap(entry.$2),
          cachedAt: now,
          sourceUpdatedAt: _dateFromValue(entry.$2['createdAtLocal']),
        );
      }).toList(),
    );
  }

  /// Computes json safe map.
  Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> source) {
    /// Computes convert.
    Object? convert(Object? value) {
      if (value == null || value is String || value is num || value is bool) {
        return value;
      }
      if (value is Timestamp) {
        return value.toDate().toUtc().toIso8601String();
      }
      if (value is DateTime) {
        return value.toUtc().toIso8601String();
      }
      if (value is GeoPoint) {
        return {'latitude': value.latitude, 'longitude': value.longitude};
      }
      if (value is Map) {
        return value.map(
          (key, nested) => MapEntry(key.toString(), convert(nested)),
        );
      }
      if (value is Iterable) {
        return value.map(convert).toList();
      }
      return value.toString();
    }

    return Map<String, dynamic>.from(convert(source) as Map);
  }

  /// Computes hydrate group chat with photos.
  Future<GroupChat> _hydrateGroupChatWithPhotos(GroupChat chat) async {
    final resolved = await _photoURLsForPhones(chat.participantPhones);
    if (resolved.isEmpty) {
      return chat;
    }
    return chat.copyWith(
      participantPhotoURLs: {...chat.participantPhotoURLs, ...resolved},
    );
  }

  /// Computes should render upcoming hike.
  bool _shouldRenderUpcomingHike(UpcomingHike hike) {
    return hike.isUpcomingAt(DateTime.now());
  }

  /// Computes should render group chat.
  bool _shouldRenderGroupChat(GroupChat chat) {
    if (chat.isDeleted) {
      return false;
    }
    final removesAt = chat.chatRemovesAt;
    if (removesAt != null && !removesAt.isAfter(DateTime.now().toUtc())) {
      return false;
    }
    return true;
  }

  /// Computes photo urls for phones.
  Future<Map<String, String>> _photoURLsForPhones(
    Iterable<String> phoneNumbers,
  ) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const {};
    }
    final uniquePhones = phoneNumbers
        .map((phone) => phone.trim())
        .where((phone) => phone.isNotEmpty)
        .toSet();
    if (uniquePhones.isEmpty) {
      return const {};
    }
    try {
      final profiles = await _getPublicProfiles({
        'phoneNumbers': uniquePhones.toList(),
      });
      final result = <String, String>{};
      for (final profile in profiles) {
        final phone = _stringFrom(profile['phoneNumber']);
        final photoURL = _stringFrom(profile['photoURL']).trim();
        if (photoURL.isNotEmpty) {
          result[_phoneKeyFor(phone)] = photoURL;
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Computes photo urlfor phone.
  Future<String> _photoURLForPhone(String phoneNumber) async {
    final photos = await _photoURLsForPhones([phoneNumber]);
    return photos[_phoneKeyFor(phoneNumber)] ?? '';
  }

  // recordNetworkObservation submits best-effort cloud diagnostics; the actual pin is persisted
  // separately as a footprint.
  /// Records network observation.
  Future<void> recordNetworkObservation({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation location,
    required bool apiRequestSuccess,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    try {
      await _networkObservations
          .add({
            'sessionId': activeHike.sessionId,
            'userId': _userIdFor(session),
            'trailId': activeHike.trail.trailId,
            'latitude': location.latitude,
            'longitude': location.longitude,
            if (location.accuracyMeters != null)
              'gpsAccuracy': location.accuracyMeters,
            'networkType': 'unknown',
            'apiRequestSuccess': apiRequestSuccess,
            'recordedAt': FieldValue.serverTimestamp(),
            'recordedAtLocal': DateTime.now().toUtc().toIso8601String(),
          })
          .timeout(_firebaseWriteTimeout);
    } catch (_) {
      // This cloud observation is best effort; footprints preserve the actual pin.
    }
  }

  /// Forwards a non-owner BLE observation as an explicitly unverified report.
  /// The callable derives a deterministic incident ID and deduplicates reports
  /// from the same signed-in phone; it never starts the reporter's own SOS.
  Future<NearbySosForwardResult> forwardNearbySosIncident({
    required NearbySosEvent event,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      throw const HikerCircleFirebaseRepositoryException(
        'Nearby SOS forwarding is waiting for an internet connection.',
        allowsOfflineFallback: true,
      );
    }

    /// Computes location payload.
    Map<String, Object?> locationPayload(SosTriggerLocation value) => {
      'latitude': value.latitude,
      'longitude': value.longitude,
      if (value.accuracyMeters != null) 'accuracyMeters': value.accuracyMeters,
      if (value.capturedAt != null)
        'capturedAtMillis': value.capturedAt!.toUtc().millisecondsSinceEpoch,
    };
    try {
      final response = await _resolvedFunctions
          .httpsCallable('forwardNearbySosIncident')
          .call<Map<String, dynamic>>({
            'deviceId': event.deviceId,
            if (event.counter != null) 'counter': event.counter,
            'receivedAtMillis': event.receivedAt.toUtc().millisecondsSinceEpoch,
            if (event.rssi != null) 'rssi': event.rssi,
            if (event.location case final location?)
              'reportedLocation': locationPayload(location),
            if (event.detectorLocation case final detector?)
              'detectorLocation': locationPayload(detector),
          });
      final data = response.data;
      final incidentId = (data['incidentId'] as String?)?.trim() ?? '';
      if (incidentId.isEmpty) {
        throw const FormatException('Missing incident ID');
      }
      return NearbySosForwardResult(
        incidentId: incidentId,
        deduplicated: data['deduplicated'] == true,
        reporterCount: (data['reporterCount'] as num?)?.toInt() ?? 1,
      );
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to forward the nearby SOS report.',
        allowsOfflineFallback:
            error.code == 'unavailable' || error.code == 'deadline-exceeded',
      );
    } on FormatException {
      throw const HikerCircleFirebaseRepositoryException(
        'The nearby SOS server returned an invalid incident receipt.',
      );
    }
  }

  /// Computes call team hike function.
  Future<Map<String, dynamic>> _callTeamHikeFunction({
    required String callableName,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _resolvedFunctions
          .httpsCallable(callableName)
          .call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(response.data);
    } on FirebaseFunctionsException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to update the team hike right now.',
      );
    } on TypeError {
      throw const HikerCircleFirebaseRepositoryException(
        'The team hike server returned an invalid response.',
      );
    }
  }

  /// Computes manage team hike action.
  Future<TeamHikeSession> _manageTeamHikeAction({
    required String action,
    required String teamHikeSessionId,
    Map<String, dynamic> data = const {},
  }) async {
    _throwIfFirebaseUnavailable();
    final response = await _callTeamHikeFunction(
      callableName: 'manageTeamHikeSession',
      data: {'action': action, 'teamHikeSessionId': teamHikeSessionId, ...data},
    );
    return _teamHikeSessionFromCallable(response);
  }

  /// Computes team hike session from callable.
  TeamHikeSession _teamHikeSessionFromCallable(Map<String, dynamic> response) {
    final rawSession = response['teamSession'];
    if (rawSession is! Map) {
      throw const HikerCircleFirebaseRepositoryException(
        'The team hike server returned an invalid response.',
      );
    }
    final data = Map<String, dynamic>.from(rawSession);
    final teamHikeSessionId = _stringFrom(data['teamHikeSessionId']);
    if (teamHikeSessionId.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'The team hike server returned an invalid session.',
      );
    }
    return TeamHikeSession.fromFirestore(data, id: teamHikeSessionId);
  }

  /// Computes team hike session from document.
  TeamHikeSession? _teamHikeSessionFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      return null;
    }
    return TeamHikeSession.fromFirestore(data, id: document.id);
  }

  // _saveActualHikeRouteCapture stores replay geometry and source counts; endpoints, bounds and
  // stored-array counts are derived by readers.
  /// Saves actual hike route capture.
  Future<void> _saveActualHikeRouteCapture({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required DateTime capturedAt,
    HikeSummaryReport? summary,
  }) async {
    final routePoints = _actualRoutePointsFor(activeHike);
    final storedRoutePoints = downsampleHikeRouteForCloud(routePoints);
    final validManualPins =
        activeHike.manualPinLocations
            .where((pin) => pin.coordinate.hasValidPosition)
            .toList()
          ..sort((left, right) => left.pinnedAt.compareTo(right.pinnedAt));
    final storedManualPins = _evenlyDownsample(validManualPins, maxPoints: 250);

    await _hikeRouteCaptures.doc(activeHike.sessionId).set({
      'sessionId': activeHike.sessionId,
      'userId': _userIdFor(session),
      'userPhoneNumber': session.phoneNumber,
      'trailId': activeHike.trail.trailId,
      'trailName': activeHike.trail.name,
      'routePoints': storedRoutePoints.map(_hikeCoordinateForCloud).toList(),
      'routePointCount': routePoints.length,
      'routePointsDownsampled': storedRoutePoints.length < routePoints.length,
      'manualPins': storedManualPins.map(_hikeManualPinForCloud).toList(),
      'manualPinCount': validManualPins.length,
      if (summary != null) 'summaryReport': summary.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': capturedAt.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': capturedAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Computes actual route points for.
  List<HikeCoordinate> _actualRoutePointsFor(ActiveHikeSession activeHike) {
    final points = activeHike.routePoints
        .where((point) => point.hasValidPosition)
        .toList();
    final latest = activeHike.latestLocation;
    if (latest?.hasValidPosition == true &&
        (points.isEmpty || points.last.distanceTo(latest!) > 2)) {
      points.add(latest!);
    }
    points.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return points;
  }

  /// Computes hike coordinate for cloud.
  Map<String, dynamic> _hikeCoordinateForCloud(HikeCoordinate coordinate) {
    final accuracy = coordinate.accuracyMeters;
    final altitude = coordinate.altitudeMeters;
    return {
      'latitude': coordinate.latitude,
      'longitude': coordinate.longitude,
      if (accuracy != null && accuracy.isFinite && accuracy >= 0)
        'accuracyMeters': accuracy,
      if (altitude != null && altitude.isFinite) 'altitudeMeters': altitude,
      'capturedAtLocal': coordinate.capturedAt.toUtc().toIso8601String(),
    };
  }

  /// Computes hike manual pin for cloud.
  Map<String, dynamic> _hikeManualPinForCloud(HikeManualPin pin) {
    final normalizedId = pin.id.trim();
    return {
      'pinId': normalizedId.length <= 200
          ? normalizedId
          : normalizedId.substring(0, 200),
      'coordinate': _hikeCoordinateForCloud(pin.coordinate),
      'pinnedAtLocal': pin.pinnedAt.toUtc().toIso8601String(),
    };
  }

  /// Computes progress meters for.
  double _progressMetersFor(
    ActiveHikeSession activeHike,
    HikeCoordinate coordinate,
  ) {
    if (activeHike.routePoints.length >= 2) {
      return activeHike.recordedDistanceKm * 1000;
    }
    final checkpoints = activeHike.trail.checkpoints;
    if (checkpoints.isEmpty) {
      return 0;
    }
    final start = checkpoints.first;
    final startCoordinate = HikeCoordinate(
      latitude: start.latitude,
      longitude: start.longitude,
      capturedAt: coordinate.capturedAt,
    );
    return startCoordinate.distanceTo(coordinate);
  }

  /// Computes same phone.
  bool _samePhone(String first, String second) {
    final firstKey = _phoneKeyFor(first);
    final secondKey = _phoneKeyFor(second);
    return firstKey.isNotEmpty && firstKey == secondKey;
  }

  /// Computes phone key for.
  String _phoneKeyFor(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Computes terminal restore result from exception.
  ActiveHikeCloudRestoreResult? _terminalRestoreResultFromException(
    FirebaseFunctionsException error, {
    required String requestedSessionId,
  }) {
    if (error.code != 'failed-precondition' && error.code != 'already-exists') {
      return null;
    }
    try {
      final result = parseActiveHikeCloudRestoreResult(
        error.details,
        requestedSessionId: requestedSessionId,
      );
      return result.terminal ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Computes terminal completion result from exception.
  ActiveHikeCloudCompletionResult? _terminalCompletionResultFromException(
    FirebaseFunctionsException error, {
    required String requestedSessionId,
  }) {
    if (error.code != 'failed-precondition' && error.code != 'already-exists') {
      return null;
    }
    try {
      final result = parseActiveHikeCloudCompletionResult(
        error.details,
        requestedSessionId: requestedSessionId,
      );
      return result.terminal ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Computes buddy requests from raw.
  List<Map<String, dynamic>> _buddyRequestsFromRaw(Object? raw) {
    if (raw is! Map) {
      return const [];
    }
    final requests = raw.entries
        .map((entry) {
          final data = entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : <String, dynamic>{};
          return <String, dynamic>{
            'requestKey': entry.key.toString(),
            'phoneNumber': _stringFrom(data['phoneNumber']),
            'displayName': _stringFrom(data['displayName']).isEmpty
                ? 'Hiker'
                : _stringFrom(data['displayName']),
            'handle': _stringFrom(data['handle']),
            'photoURL': _stringFrom(data['photoURL']),
            'createdAtLocal': _stringFrom(data['createdAtLocal']),
          };
        })
        .where((request) => _stringFrom(request['phoneNumber']).isNotEmpty)
        .toList();
    requests.sort((a, b) {
      final first = _dateFromValue(a['createdAtLocal']) ?? DateTime(1970);
      final second = _dateFromValue(b['createdAtLocal']) ?? DateTime(1970);
      return second.compareTo(first);
    });
    return requests;
  }

  /// Computes trail from firestore.
  Trail? _trailFromFirestore(Map<String, dynamic> data) {
    final checkpoints = _listOfMaps(
      data['checkpoints'],
    ).map(_checkpointFromFirestore).whereType<TrailCheckpoint>().toList();

    if (checkpoints.length < 2) {
      return null;
    }
    final rawDifficultyVoteCounts = data['difficultyVoteCounts'];
    final difficultyVoteCounts = rawDifficultyVoteCounts is Map
        ? Map<String, dynamic>.from(rawDifficultyVoteCounts)
        : const <String, dynamic>{};

    return Trail(
      trailId: _stringFrom(data['trailId']),
      name: _stringFrom(data['name']),
      area: _stringFrom(data['area']),
      state: _stringFrom(data['state']),
      country: _stringFrom(data['country']),
      latitude: _doubleFrom(data['latitude']),
      longitude: _doubleFrom(data['longitude']),
      distanceKm: _doubleFrom(data['distanceKm']),
      difficulty: _titleCase(_stringFrom(data['difficulty'])),
      estimatedDurationMinutes: _intFrom(data['estimatedDurationMinutes']),
      elevationGainMeters: _intFrom(data['elevationGainMeters']),
      minElevationMeters: _nullableIntFrom(data['minElevationMeters']),
      maxElevationMeters: _nullableIntFrom(data['maxElevationMeters']),
      ratingAverage: _doubleFrom(data['ratingAverage']),
      ratingCount: _intFrom(data['ratingCount']),
      easyDifficultyVotes: _intFrom(difficultyVoteCounts['easy']),
      moderateDifficultyVotes: _intFrom(difficultyVoteCounts['moderate']),
      hardDifficultyVotes: _intFrom(difficultyVoteCounts['hard']),
      offlineMapAvailable: data['offlineMapAvailable'] == true,
      offlineMapDownloaded: data['offlineMapDownloaded'] == true,
      isVerifiedTrail: data['isVerifiedTrail'] == true,
      routeFilePath: _stringFrom(data['routeFilePath']),
      coverColorValue: _intFrom(data['coverColorValue']),
      coverImageUrls: _coverImageUrlsFrom(data),
      coverImageCredits: _listOfMaps(
        data['coverImageCredits'],
      ).map(TrailImageCredit.fromPersistence).toList(),
      checkpoints: checkpoints,
      weather: weatherFromFirestore(data['weather']),
      hazards: _listOfMaps(
        data['hazards'],
      ).map(_hazardFromFirestore).whereType<TrailHazard>().toList(),
      routeEncodedPolyline: _nullableStringFrom(data['routeEncodedPolyline']),
      routeCheckpointsHash: _nullableStringFrom(data['routeCheckpointsHash']),
      dataSource: _stringFrom(data['dataSource']),
      dataSourceUrl: _stringFrom(data['dataSourceUrl']),
      osmRelationId: _stringFrom(data['osmRelationId']),
      routeGeometryMetadata: data['routeGeometryMetadata'] is Map
          ? Map<String, dynamic>.from(data['routeGeometryMetadata'] as Map)
          : const <String, dynamic>{},
      routeProvider: _stringFrom(data['routeProvider']),
      routeActivity: _stringFrom(data['routeActivity']),
      routeShape: _stringFrom(data['routeShape']),
      routeReferenceName: _stringFrom(data['routeReferenceName']),
      routeReferenceUrl: _stringFrom(data['routeReferenceUrl']),
      routeReferenceNote: _stringFrom(data['routeReferenceNote']),
      routeVerifiedAtLocal: _stringFrom(data['routeVerifiedAtLocal']),
    );
  }

  /// Computes checkpoint from firestore.
  TrailCheckpoint? _checkpointFromFirestore(Map<String, dynamic> data) {
    final name = _stringFrom(data['name']);
    if (name.isEmpty) {
      return null;
    }
    return TrailCheckpoint(
      name: name,
      latitude: _doubleFrom(data['latitude']),
      longitude: _doubleFrom(data['longitude']),
      order: _intFrom(data['order']),
    );
  }

  /// Computes weather from firestore.
  TrailWeather weatherFromFirestore(Object? value) {
    final data = value is Map ? Map<String, dynamic>.from(value) : {};
    final hourlyData = data['hourlyForecast'];
    return TrailWeather(
      forecastData: data['forecastData'] is Map
          ? Map<String, dynamic>.from(data['forecastData'] as Map)
          : const {},
      summary: _stringFrom(data['summary']),
      temperatureRange: _stringFrom(data['temperatureRange']),
      rainProbability: _intFrom(data['rainProbability']),
      cachedAt: _dateFromValue(data['cachedAtLocal']) ?? DateTime.now().toUtc(),
      humidity: _nullableIntFrom(data['humidity']),
      windSpeed: _nullableDoubleFrom(data['windSpeed']),
      uvIndex: _nullableDoubleFrom(data['uvIndex']),
      feelsLike: _nullableDoubleFrom(data['feelsLike']),
      hourlyForecast: hourlyData is List
          ? hourlyData
                .map((h) => _hourlyForecastFromFirestore(h))
                .whereType<HourlyForecast>()
                .toList()
          : const [],
    );
  }

  /// Computes hourly forecast from firestore.
  HourlyForecast? _hourlyForecastFromFirestore(Object? value) {
    final data = value is Map ? Map<String, dynamic>.from(value) : {};
    final time = _dateFromValue(data['timeLocal']);
    if (time == null) {
      return null;
    }
    return HourlyForecast(
      time: time,
      temperature: _doubleFrom(data['temperature']),
      precipitationProbability: _intFrom(data['precipitationProbability']),
      weatherCode: _intFrom(data['weatherCode']),
    );
  }

  /// Computes nullable int from.
  int? _nullableIntFrom(Object? value) {
    return value is num ? value.toInt() : null;
  }

  /// Computes nullable double from.
  double? _nullableDoubleFrom(Object? value) {
    return value is num ? value.toDouble() : null;
  }

  /// Computes hazard from firestore.
  TrailHazard? _hazardFromFirestore(Map<String, dynamic> data) {
    final description = _stringFrom(data['description']);
    if (description.isEmpty) {
      return null;
    }
    return TrailHazard(
      type: _stringFrom(data['type']),
      description: description,
      severity: _titleCase(_stringFrom(data['severity'])),
      locationLabel: _stringFrom(data['locationLabel']),
      reportedAt: _dateFromValue(data['reportedAtLocal']) ?? DateTime.now(),
    );
  }

  /// Computes list of maps.
  List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// Computes user id for.
  String _userIdFor(AppSession session) {
    return FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber);
  }

  /// Computes string from.
  String _stringFrom(Object? value) {
    return value is String ? value : '';
  }

  /// Computes cover image urls from.
  List<String> _coverImageUrlsFrom(Map<String, dynamic> data) {
    final raw = data['coverImageUrl'];
    if (raw is List) {
      return raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    }
    final legacy = _stringFrom(raw);
    return legacy.isNotEmpty ? [legacy] : const [];
  }

  /// Computes nullable string from.
  String? _nullableStringFrom(Object? value) {
    return value is String ? value : null;
  }

  /// Computes double from.
  double _doubleFrom(Object? value) {
    return value is num ? value.toDouble() : 0;
  }

  /// Computes int from.
  int _intFrom(Object? value) {
    return value is num ? value.toInt() : 0;
  }

  /// Computes date from value.
  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Computes title case.
  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  /// Computes new trail id.
  String _newTrailId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeSlug = slug.isEmpty ? 'trail' : slug;
    return 'trail_${safeSlug}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Computes safe storage file name.
  String _safeStorageFileName(String fileName, int index) {
    final normalized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'trail_image_$index.jpg' : normalized;
  }

  /// Computes content type for file name.
  String _contentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  /// Computes throw if admin unavailable.
  void _throwIfAdminUnavailable(AppSession session) {
    _throwIfFirebaseUnavailable();
    if (session.isAdmin) {
      return;
    }
    throw const HikerCircleFirebaseRepositoryException(
      'Admin privilege is required for this action.',
    );
  }

  /// Computes throw if firebase unavailable.
  void _throwIfFirebaseUnavailable() {
    if (_firebaseBootstrapResult.isAvailable) {
      return;
    }

    throw HikerCircleFirebaseRepositoryException(
      'Firebase is not ready yet. ${_firebaseBootstrapResult.errorMessage ?? ''}'
          .trim(),
    );
  }
}
