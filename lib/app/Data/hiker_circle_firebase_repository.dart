import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../home/Model/hike_session_models.dart';
import '../../sos/Model/sos_models.dart';
import '../../trail/Data/trail_repository.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/app_session.dart';
import 'firebase_bootstrap.dart';
import 'firebase_user_repository.dart';
import 'local_session_database.dart';

class HikerCircleFirebaseRepositoryException implements Exception {
  const HikerCircleFirebaseRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HikerCircleFirebaseRepository {
  HikerCircleFirebaseRepository({
    FirebaseFirestore? firestore,
    LocalSessionDatabase? localDatabase,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
  }) : _firestore = firestore,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _firebaseBootstrapResult = firebaseBootstrapResult;

  final FirebaseFirestore? _firestore;
  final LocalSessionDatabase _localDatabase;
  final FirebaseBootstrapResult _firebaseBootstrapResult;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _trails =>
      _resolvedFirestore.collection('trails');
  CollectionReference<Map<String, dynamic>> get _hikeSessions =>
      _resolvedFirestore.collection('hikeSessions');
  CollectionReference<Map<String, dynamic>> get _locationPoints =>
      _resolvedFirestore.collection('localLocationPoints');
  CollectionReference<Map<String, dynamic>> get _checkIns =>
      _resolvedFirestore.collection('checkIns');
  CollectionReference<Map<String, dynamic>> get _hazardReports =>
      _resolvedFirestore.collection('hazardReports');
  CollectionReference<Map<String, dynamic>> get _teams =>
      _resolvedFirestore.collection('teams');
  CollectionReference<Map<String, dynamic>> get _communityPosts =>
      _resolvedFirestore.collection('communityPosts');
  CollectionReference<Map<String, dynamic>> _communityCommentsFor(
    String postId,
  ) {
    return _communityPosts.doc(postId).collection('comments');
  }

  CollectionReference<Map<String, dynamic>> get _achievements =>
      _resolvedFirestore.collection('achievements');
  CollectionReference<Map<String, dynamic>> get _userAchievements =>
      _resolvedFirestore.collection('userAchievements');
  CollectionReference<Map<String, dynamic>> get _networkObservations =>
      _resolvedFirestore.collection('networkObservations');
  CollectionReference<Map<String, dynamic>> get _downloadedMaps =>
      _resolvedFirestore.collection('downloadedMaps');

  Future<List<Trail>> loadTrails() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const TrailRepository().loadTrails();
    }

    try {
      await ensureTrailSeeds();
      final snapshot = await _trails
          .orderBy('isVerifiedTrail', descending: true)
          .orderBy('ratingAverage', descending: true)
          .get();
      final liveTrails = snapshot.docs
          .map((document) => _trailFromFirestore(document.data()))
          .whereType<Trail>()
          .toList();

      return liveTrails.isEmpty
          ? const TrailRepository().loadTrails()
          : liveTrails;
    } catch (_) {
      return const TrailRepository().loadTrails();
    }
  }

  Future<void> ensureTrailSeeds() async {
    _throwIfFirebaseUnavailable();

    final firstTrail = await _trails.limit(1).get();
    if (firstTrail.docs.isNotEmpty) {
      return;
    }

    final batch = _resolvedFirestore.batch();
    for (final trail in const TrailRepository().loadTrails()) {
      batch.set(_trails.doc(trail.trailId), {
        ...trail.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<ActiveHikeSession> createActiveHikeSession({
    required AppSession session,
    required HikeSessionDraft draft,
  }) async {
    final localSession = ActiveHikeSession.fromDraft(draft);
    if (!_firebaseBootstrapResult.isAvailable) {
      return localSession;
    }

    try {
      final document = _hikeSessions.doc();
      final now = DateTime.now().toUtc();
      await document.set({
        'sessionId': document.id,
        'userId': _userIdFor(session),
        'userPhoneNumber': session.phoneNumber,
        'status': 'active',
        'hikeType': draft.hikeType.name,
        'trailId': draft.trail.trailId,
        'trailName': draft.trail.name,
        'trail': draft.trail.toFirestore(),
        'startPointName': draft.startPointName,
        'destinationName': draft.destinationName,
        'plannedStartTimeLocal': draft.departureTime.toUtc().toIso8601String(),
        'expectedArrivalTimeLocal': draft.expectedArrivalTime
            .toUtc()
            .toIso8601String(),
        'expectedReturnTimeLocal': draft.expectedReturnTime
            .toUtc()
            .toIso8601String(),
        'safetyCheckInIntervalMinutes': draft.safetyCheckInInterval.inMinutes,
        'locationRecordingIntervalMinutes':
            draft.locationRecordingInterval.inMinutes,
        'emergencyContactNames': draft.emergencyContactNames,
        'shareLiveLocation': draft.shareLiveLocation,
        'fallDetectionEnabled': draft.fallDetectionEnabled,
        'fallDetectionSensorSensitivity':
            draft.fallDetectionSettings.sensorSensitivity,
        'fallDetectionStillnessDurationSeconds':
            draft.fallDetectionSettings.stillnessDuration.inSeconds,
        'pathDeviationEnabled': draft.pathDeviationEnabled,
        'offlinePhysicalAlertEnabled': draft.offlinePhysicalAlertEnabled,
        'duressEnabled': draft.duressEnabled,
        'completedChecklistItems': draft.completedChecklistItems.toList(),
        'startedAt': FieldValue.serverTimestamp(),
        'startedAtLocal': now.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      });

      await awardAchievement(
        session: session,
        achievementId: 'prepared_adventurer',
        condition: 'Started a hike with offline preparation enabled.',
      );

      return localSession.copyWith(sessionId: document.id);
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<int> recordLocationPoint({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation location,
    required String pointType,
    int? batteryLevel,
  }) async {
    await _localDatabase.insertLocationPoint(
      sessionId: activeHike.sessionId,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracyMeters,
      batteryLevel: batteryLevel ?? activeHike.batteryLevel,
      pointType: pointType,
      isSynced: false,
    );

    if (!_firebaseBootstrapResult.isAvailable) {
      return _localDatabase.countUnsentLocationPoints(activeHike.sessionId);
    }

    try {
      final now = DateTime.now().toUtc();
      await _locationPoints.add({
        'sessionId': activeHike.sessionId,
        'userId': _userIdFor(session),
        'userPhoneNumber': session.phoneNumber,
        'trailId': activeHike.trail.trailId,
        'pointType': pointType,
        'latitude': location.latitude,
        'longitude': location.longitude,
        if (location.accuracyMeters != null)
          'accuracyMeters': location.accuracyMeters,
        'batteryLevel': batteryLevel ?? activeHike.batteryLevel,
        'recordedAt': FieldValue.serverTimestamp(),
        'recordedAtLocal': now.toIso8601String(),
        'isSynced': true,
      });
      await _hikeSessions.doc(activeHike.sessionId).set({
        'latestLocation': location.toFirestore(),
        'latestLocationUpdatedAt': FieldValue.serverTimestamp(),
        'latestLocationUpdatedAtLocal': now.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return _localDatabase.countUnsentLocationPoints(activeHike.sessionId);
    } catch (_) {
      return _localDatabase.countUnsentLocationPoints(activeHike.sessionId);
    }
  }

  Future<void> recordCheckIn({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation? location,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _checkIns.add({
      'sessionId': activeHike.sessionId,
      'userId': _userIdFor(session),
      'userPhoneNumber': session.phoneNumber,
      'trailId': activeHike.trail.trailId,
      'status': 'safe',
      'batteryLevel': activeHike.batteryLevel,
      if (location != null) 'location': location.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
    });
    await _hikeSessions.doc(activeHike.sessionId).set({
      'lastCheckInStatus': 'safe',
      'lastCheckInAt': FieldValue.serverTimestamp(),
      'lastCheckInAtLocal': now.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> endHikeSession({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _hikeSessions.doc(activeHike.sessionId).set({
      'status': 'completed',
      'endedAt': FieldValue.serverTimestamp(),
      'endedAtLocal': now.toIso8601String(),
      'distanceKm': summary?.distanceKm ?? activeHike.recordedDistanceKm,
      'durationMinutes':
          summary?.duration.inMinutes ??
          DateTime.now().difference(activeHike.startedAt).inMinutes,
      'checkIns': activeHike.checkIns,
      'manualPins': activeHike.manualPins,
      'routePointCount': activeHike.routePointCount,
      if (summary != null) 'summaryReport': summary.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await awardAchievement(
      session: session,
      achievementId: 'first_safe_hike',
      condition: 'Completed a hike session.',
    );
  }

  Future<void> submitHazardReport({
    required AppSession session,
    required Trail trail,
    required String hazardType,
    required String description,
    required String severity,
    SosTriggerLocation? location,
  }) async {
    _throwIfFirebaseUnavailable();

    final now = DateTime.now().toUtc();
    final document = _hazardReports.doc();
    await document.set({
      'hazardId': document.id,
      'trailId': trail.trailId,
      'trailName': trail.name,
      'reportedBy': _userIdFor(session),
      'reportedByPhoneNumber': session.phoneNumber,
      'hazardType': hazardType,
      'description': description.trim(),
      'severity': severity.toLowerCase(),
      if (location != null) ...{
        'latitude': location.latitude,
        'longitude': location.longitude,
        'location': location.toFirestore(),
      },
      'status': 'unverified',
      'reportLabel': 'Community Report - Not Officially Verified',
      'reportedAt': FieldValue.serverTimestamp(),
      'reportedAtLocal': now.toIso8601String(),
    });
  }

  Future<void> recordOfflineMapDownloaded({
    required AppSession session,
    required Trail trail,
  }) async {
    await _localDatabase.insertDownloadedMap(
      trailId: trail.trailId,
      trailName: trail.name,
      localFilePath: trail.routeFilePath.isEmpty
          ? 'offline/maps/${trail.trailId}.mbtiles'
          : trail.routeFilePath,
    );

    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    final userId = _userIdFor(session);
    final mapId = '${userId}_${trail.trailId}';
    final now = DateTime.now().toUtc();
    await _downloadedMaps.doc(mapId).set({
      'downloadedMapId': mapId,
      'userId': userId,
      'userPhoneNumber': session.phoneNumber,
      'trailId': trail.trailId,
      'trailName': trail.name,
      'localFilePath': trail.routeFilePath.isEmpty
          ? 'offline/maps/${trail.trailId}.mbtiles'
          : trail.routeFilePath,
      'downloadedAt': FieldValue.serverTimestamp(),
      'downloadedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> createTeamSchedule({required AppSession session}) async {
    _throwIfFirebaseUnavailable();

    final now = DateTime.now().toUtc();
    final document = _teams.doc();
    await document.set({
      'teamId': document.id,
      'teamName': 'Weekend Broga Trip',
      'leaderId': _userIdFor(session),
      'leaderPhoneNumber': session.phoneNumber,
      'trailId': 'trail_broga_001',
      'trailName': 'Broga Hill Trail',
      'plannedStartTimeLocal': DateTime(
        2026,
        6,
        6,
        6,
        30,
      ).toUtc().toIso8601String(),
      'expectedReturnTimeLocal': DateTime(
        2026,
        6,
        6,
        11,
        30,
      ).toUtc().toIso8601String(),
      'memberIds': [_userIdFor(session)],
      'safetyFeatures': {
        'shareTeamLiveLocations': true,
        'warnOnRouteExit': true,
        'allowHazardReporting': true,
        'alertTeamWhenHelpRequested': true,
      },
      'status': 'planned',
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadTeamSchedules({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final snapshot = await _teams
          .where('memberIds', arrayContains: _userIdFor(session))
          .limit(20)
          .get();
      return snapshot.docs.map((document) => document.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> createCompletedHikePost({
    required AppSession session,
    required ActiveHikeSession activeHike,
    HikeSummaryReport? summary,
    String caption = 'Trail completed safely.',
  }) async {
    _throwIfFirebaseUnavailable();

    final now = DateTime.now().toUtc();
    final document = _communityPosts.doc();
    await document.set({
      'postId': document.id,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      'postType': 'completed_hike',
      'trailId': activeHike.trail.trailId,
      'trailName': activeHike.trail.name,
      'sessionId': activeHike.sessionId,
      'caption': caption,
      'imageUrls': <String>[],
      'distanceKm': summary?.distanceKm ?? activeHike.recordedDistanceKm,
      'durationMinutes':
          summary?.duration.inMinutes ??
          DateTime.now().difference(activeHike.startedAt).inMinutes,
      'checkIns': activeHike.checkIns,
      'manualPins': activeHike.manualPins,
      'routePointCount': activeHike.routePointCount,
      if (summary != null) 'summaryReport': summary.toFirestore(),
      'highestAltitudeMeters': null,
      'visibility': 'public',
      'likeCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
    });
  }

  Future<void> createCommunityPost({
    required AppSession session,
    required String caption,
    String postType = 'community_note',
    String? trailId,
    String? trailName,
  }) async {
    _throwIfFirebaseUnavailable();

    final now = DateTime.now().toUtc();
    final document = _communityPosts.doc();
    await document.set({
      'postId': document.id,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      'authorName': 'You',
      'authorHandle': _handleForPhone(session.phoneNumber),
      'postType': postType,
      if (trailId != null) 'trailId': trailId,
      if (trailName != null) 'trailName': trailName,
      'caption': caption.trim(),
      'imageUrls': <String>[],
      'visibility': 'public',
      'likeCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadCommunityPosts() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final snapshot = await _communityPosts
          .orderBy('createdAtLocal', descending: true)
          .limit(20)
          .get();
      return snapshot.docs.map((document) => document.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addCommunityComment({
    required AppSession session,
    required String postId,
    required String body,
  }) async {
    _throwIfFirebaseUnavailable();

    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final comment = _communityCommentsFor(postId).doc();
    final batch = _resolvedFirestore.batch();
    batch.set(comment, {
      'commentId': comment.id,
      'postId': postId,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      'authorName': 'You',
      'authorHandle': _handleForPhone(session.phoneNumber),
      'body': trimmedBody,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
    });
    batch.set(_communityPosts.doc(postId), {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> loadCommunityComments({
    required String postId,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final snapshot = await _communityCommentsFor(
        postId,
      ).orderBy('createdAtLocal', descending: false).limit(100).get();
      return snapshot.docs.map((document) => document.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> loadHazardReports() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final snapshot = await _hazardReports
          .orderBy('reportedAtLocal', descending: true)
          .limit(20)
          .get();
      return snapshot.docs.map((document) => document.data()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> awardAchievement({
    required AppSession session,
    required String achievementId,
    required String condition,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    await ensureAchievementSeeds();
    final userAchievementId = '${_userIdFor(session)}_$achievementId';
    await _userAchievements.doc(userAchievementId).set({
      'userAchievementId': userAchievementId,
      'userId': _userIdFor(session),
      'achievementId': achievementId,
      'condition': condition,
      'awardedAt': FieldValue.serverTimestamp(),
      'awardedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> ensureAchievementSeeds() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    final seeds = {
      'first_safe_hike': {
        'title': 'First Safe Hike',
        'condition': 'Complete first hike session',
      },
      'prepared_adventurer': {
        'title': 'Prepared Adventurer',
        'condition': 'Download offline map before starting',
      },
      'safety_first': {
        'title': 'Safety First',
        'condition': 'Complete gear checklist before departure',
      },
      'reliable_check_in': {
        'title': 'Reliable Check-In',
        'condition': 'Complete scheduled check-ins during a hike',
      },
      'community_helper': {
        'title': 'Community Helper',
        'condition': 'Submit a hazard report later confirmed by others',
      },
      'team_guardian': {
        'title': 'Team Guardian',
        'condition': 'Complete team hikes without separation emergency',
      },
    };

    final batch = _resolvedFirestore.batch();
    for (final entry in seeds.entries) {
      batch.set(_achievements.doc(entry.key), {
        'achievementId': entry.key,
        ...entry.value,
        'rewardsSafeBehaviour': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> recordNetworkObservation({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required SosTriggerLocation location,
    required bool apiRequestSuccess,
  }) async {
    await _localDatabase.insertNetworkObservation(
      sessionId: activeHike.sessionId,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracyMeters,
      networkAvailable: _firebaseBootstrapResult.isAvailable,
      apiRequestSuccess: apiRequestSuccess,
      networkType: 'unknown',
      isSynced: false,
    );

    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    await _networkObservations.add({
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
    });
  }

  Future<void> queueSosPayload({
    required ActiveHikeSession activeHike,
    required SosTriggerLocation triggerLocation,
    required Map<String, dynamic> payload,
  }) async {
    await _localDatabase.insertQueuedAlert(
      sessionId: activeHike.sessionId,
      alertType: payload['alertType'] as String? ?? 'manual_sos',
      triggerLatitude: triggerLocation.latitude,
      triggerLongitude: triggerLocation.longitude,
      payloadJson: jsonEncode(payload),
    );
  }

  Trail? _trailFromFirestore(Map<String, dynamic> data) {
    final checkpoints = _listOfMaps(
      data['checkpoints'],
    ).map(_checkpointFromFirestore).whereType<TrailCheckpoint>().toList();

    if (checkpoints.length < 2) {
      return null;
    }

    return Trail(
      trailId: _stringFrom(data['trailId']),
      name: _stringFrom(data['name']),
      area: _stringFrom(data['area']),
      state: _stringFrom(data['state']),
      latitude: _doubleFrom(data['latitude']),
      longitude: _doubleFrom(data['longitude']),
      distanceKm: _doubleFrom(data['distanceKm']),
      difficulty: _titleCase(_stringFrom(data['difficulty'])),
      estimatedDurationMinutes: _intFrom(data['estimatedDurationMinutes']),
      elevationGainMeters: _intFrom(data['elevationGainMeters']),
      ratingAverage: _doubleFrom(data['ratingAverage']),
      offlineMapAvailable: data['offlineMapAvailable'] == true,
      offlineMapDownloaded: data['offlineMapDownloaded'] == true,
      isVerifiedTrail: data['isVerifiedTrail'] == true,
      routeFilePath: _stringFrom(data['routeFilePath']),
      coverColorValue: _intFrom(data['coverColorValue']),
      coverImageUrl: _stringFrom(data['coverImageUrl']),
      checkpoints: checkpoints,
      weather: _weatherFromFirestore(data['weather']),
      hazards: _listOfMaps(
        data['hazards'],
      ).map(_hazardFromFirestore).whereType<TrailHazard>().toList(),
    );
  }

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

  TrailWeather _weatherFromFirestore(Object? value) {
    final data = value is Map ? Map<String, dynamic>.from(value) : {};
    return TrailWeather(
      summary: _stringFrom(data['summary']),
      temperatureRange: _stringFrom(data['temperatureRange']),
      rainProbability: _intFrom(data['rainProbability']),
      cachedAt: _dateFromValue(data['cachedAtLocal']) ?? DateTime.now().toUtc(),
    );
  }

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

  List<Map<String, dynamic>> _listOfMaps(Object? value) {
    if (value is! Iterable) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _userIdFor(AppSession session) {
    return FirebaseUserRepository.documentIdForPhoneNumber(session.phoneNumber);
  }

  String _handleForPhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) {
      return '@hiker$digits';
    }
    return '@hiker${digits.substring(digits.length - 4)}';
  }

  String _stringFrom(Object? value) {
    return value is String ? value : '';
  }

  double _doubleFrom(Object? value) {
    return value is num ? value.toDouble() : 0;
  }

  int _intFrom(Object? value) {
    return value is num ? value.toInt() : 0;
  }

  DateTime? _dateFromValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

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
