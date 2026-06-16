import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../home/Model/hike_session_models.dart';
import '../../sos/Model/sos_models.dart';
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
  CollectionReference<Map<String, dynamic>> get _teamHikeSessions =>
      _resolvedFirestore.collection('teamHikeSessions');
  CollectionReference<Map<String, dynamic>> get _fcmOutbox =>
      _resolvedFirestore.collection('fcmOutbox');
  CollectionReference<Map<String, dynamic>> get _communityPosts =>
      _resolvedFirestore.collection('communityPosts');
  CollectionReference<Map<String, dynamic>> get _sosAlerts =>
      _resolvedFirestore.collection('sosAlerts');
  CollectionReference<Map<String, dynamic>> get _whatsAppMessageLogs =>
      _resolvedFirestore.collection('whatsAppMessageLogs');
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
  CollectionReference<Map<String, dynamic>> get _hikeRouteCaptures =>
      _resolvedFirestore.collection('hikeRouteCaptures');

  static const Map<String, Map<String, Object>> _achievementSeeds = {
    'first_safe_hike': {
      'title': 'First Safe Hike',
      'condition': 'Complete first hike session',
      'category': 'Hike milestone',
      'iconName': 'verified_user',
      'rewardPoints': 120,
      'sortOrder': 10,
      'accentColorValue': 0xFF34A853,
    },
    'prepared_adventurer': {
      'title': 'Prepared Adventurer',
      'condition': 'Download offline map before starting',
      'category': 'Preparation',
      'iconName': 'map',
      'rewardPoints': 90,
      'sortOrder': 20,
      'accentColorValue': 0xFF2F80ED,
    },
    'safety_first': {
      'title': 'Safety First',
      'condition': 'Complete gear checklist before departure',
      'category': 'Preparation',
      'iconName': 'health_and_safety',
      'rewardPoints': 100,
      'sortOrder': 30,
      'accentColorValue': 0xFFF2994A,
    },
    'reliable_check_in': {
      'title': 'Reliable Check-In',
      'condition': 'Complete scheduled check-ins during a hike',
      'category': 'Safety habit',
      'iconName': 'task_alt',
      'rewardPoints': 110,
      'sortOrder': 40,
      'accentColorValue': 0xFF9B51E0,
    },
    'community_helper': {
      'title': 'Community Helper',
      'condition': 'Submit a hazard report later confirmed by others',
      'category': 'Community',
      'iconName': 'volunteer_activism',
      'rewardPoints': 140,
      'sortOrder': 50,
      'accentColorValue': 0xFFEB5757,
    },
    'team_guardian': {
      'title': 'Team Guardian',
      'condition': 'Complete team hikes without separation emergency',
      'category': 'Team hike',
      'iconName': 'groups',
      'rewardPoints': 160,
      'sortOrder': 60,
      'accentColorValue': 0xFF00A99D,
    },
  };
  static const Set<String> _legacySeedTrailIds = {
    'trail_broga_001',
    'trail_gasing_001',
    'trail_tabur_001',
    'trail_penang_001',
    'trail_angsi_001',
  };

  Future<List<Trail>> loadTrails() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }

    try {
      final snapshot = await _trails
          .orderBy('isVerifiedTrail', descending: true)
          .orderBy('ratingAverage', descending: true)
          .get();
      final liveTrails = snapshot.docs
          .map(
            (document) => _trailFromFirestore({
              'trailId': document.id,
              ...document.data(),
            }),
          )
          .whereType<Trail>()
          .toList();

      return liveTrails;
    } catch (_) {
      return const [];
    }
  }

  @Deprecated('Firebase trails are no longer seeded from local demo models.')
  Future<void> ensureTrailSeeds() async {
    return;
  }

  Future<void> deleteLegacyFirebaseDummyData({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);

    final dummyPostSnapshots = await Future.wait([
      _communityPosts.where('isDummyData', isEqualTo: true).limit(100).get(),
      _communityPosts.where('isSeedData', isEqualTo: true).limit(100).get(),
      _communityPosts
          .where('postType', isEqualTo: 'demo_post')
          .limit(100)
          .get(),
    ]);
    final batch = _resolvedFirestore.batch();
    for (final trailId in _legacySeedTrailIds) {
      batch.delete(_trails.doc(trailId));
    }
    for (final snapshot in dummyPostSnapshots) {
      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }
    }
    await batch.commit();
  }

  Future<ActiveHikeSession> createActiveHikeSession({
    required AppSession session,
    required HikeSessionDraft draft,
    String teamHikeSessionId = '',
  }) async {
    final localSession = ActiveHikeSession.fromDraft(
      draft,
      teamHikeSessionId: teamHikeSessionId,
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return localSession;
    }

    try {
      final document = _hikeSessions.doc();
      final now = DateTime.now().toUtc();
      await document.set({
        'sessionId': document.id,
        if (teamHikeSessionId.isNotEmpty)
          'teamHikeSessionId': teamHikeSessionId,
        'userId': _userIdFor(session),
        'userPhoneNumber': session.phoneNumber,
        'status': 'active',
        'hikeType': draft.hikeType.name,
        'teamBuddies': draft.teamBuddies
            .map((buddy) => buddy.toFirestore())
            .toList(),
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
        'locationRecordingIntervalSeconds':
            draft.locationRecordingInterval.inSeconds,
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

      if (teamHikeSessionId.isNotEmpty) {
        await attachActiveHikeToTeamSession(
          teamHikeSessionId: teamHikeSessionId,
          activeHikeSessionId: document.id,
        );
      }

      return localSession.copyWith(sessionId: document.id);
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Firestore ${error.code}: ${error.message ?? 'No details provided.'}',
      );
    }
  }

  Future<TeamHikeSession> createTeamHikeSession({
    required AppSession session,
    required HikeSessionDraft draft,
  }) async {
    _throwIfFirebaseUnavailable();
    if (draft.teamBuddies.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Select at least one buddy before starting a team hike.',
      );
    }

    final now = DateTime.now().toUtc();
    final document = _teamHikeSessions.doc();
    final participants = _teamParticipantsFor(
      session: session,
      buddies: draft.teamBuddies,
      now: now,
    );
    final teamSession = TeamHikeSession(
      id: document.id,
      hostPhoneNumber: session.phoneNumber,
      trailId: draft.trail.trailId,
      trailName: draft.trail.name,
      phase: TeamHikePhase.inviting,
      participants: participants,
      createdAt: now,
      updatedAt: now,
    );

    final batch = _resolvedFirestore.batch();
    batch.set(document, {
      ...teamSession.toFirestore(),
      'hostUserId': _userIdFor(session),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'startPointName': draft.startPointName,
      'destinationName': draft.destinationName,
      'plannedStartTimeLocal': draft.departureTime.toUtc().toIso8601String(),
      'expectedArrivalTimeLocal': draft.expectedArrivalTime
          .toUtc()
          .toIso8601String(),
      'expectedReturnTimeLocal': draft.expectedReturnTime
          .toUtc()
          .toIso8601String(),
    });
    for (final participant in participants.where((item) => !item.isHost)) {
      batch.set(
        _fcmOutbox.doc(),
        _fcmOutboxPayload(
          type: 'team_hike_invite',
          recipientPhoneNumber: participant.phoneNumber,
          senderPhoneNumber: session.phoneNumber,
          title: 'Team hike invite',
          body:
              '${_handleForPhone(session.phoneNumber)} invited you to ${draft.trail.name}. Tap to join the readiness check.',
          deepLink: 'hikercircle://team-hike/join?teamSessionId=${document.id}',
          teamHikeSessionId: document.id,
          data: {'trailId': draft.trail.trailId, 'trailName': draft.trail.name},
        ),
      );
    }
    await batch.commit();
    return teamSession;
  }

  Stream<TeamHikeSession?> watchTeamHikeSession(String teamHikeSessionId) {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return Stream<TeamHikeSession?>.value(null);
    }
    return _teamHikeSessions
        .doc(teamHikeSessionId)
        .snapshots()
        .map(_teamHikeSessionFromDocument);
  }

  Future<TeamHikeSession?> loadTeamHikeSession(String teamHikeSessionId) async {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return null;
    }
    final snapshot = await _teamHikeSessions.doc(teamHikeSessionId).get();
    return _teamHikeSessionFromDocument(snapshot);
  }

  Future<TeamHikeSession> acceptTeamHikeInvite({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      final participants = current.participants.map((participant) {
        if (!_samePhone(participant.phoneNumber, session.phoneNumber)) {
          return participant;
        }
        return participant.copyWith(
          status: participant.status == TeamHikeParticipantStatus.invited
              ? TeamHikeParticipantStatus.joined
              : participant.status,
          joinedAt: participant.joinedAt ?? now,
          updatedAt: now,
        );
      }).toList();
      final hasPendingInvite = participants.any(
        (participant) =>
            participant.status == TeamHikeParticipantStatus.invited,
      );
      return current.copyWith(
        phase: hasPendingInvite
            ? TeamHikePhase.inviting
            : TeamHikePhase.readyCheck,
        participants: participants,
        updatedAt: now,
      );
    });
    await _queueFcmOutbox(
      type: 'team_hike_invite_accepted',
      recipientPhoneNumber: updated.hostPhoneNumber,
      senderPhoneNumber: session.phoneNumber,
      title: 'Buddy joined',
      body: '${_handleForPhone(session.phoneNumber)} joined the team hike.',
      deepLink: 'hikercircle://team-hike/join?teamSessionId=$teamHikeSessionId',
      teamHikeSessionId: teamHikeSessionId,
    );
    return updated;
  }

  Future<TeamHikeSession> markTeamParticipantReady({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    var shouldQueueCountdown = false;
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      final participants = current.participants.map((participant) {
        if (!_samePhone(participant.phoneNumber, session.phoneNumber)) {
          return participant;
        }
        return participant.copyWith(
          status: TeamHikeParticipantStatus.ready,
          joinedAt: participant.joinedAt ?? now,
          readyAt: now,
          updatedAt: now,
        );
      }).toList();
      final hasPendingInvite = participants.any(
        (participant) =>
            participant.status == TeamHikeParticipantStatus.invited,
      );
      final everyoneReady =
          participants.isNotEmpty &&
          participants.every(
            (participant) => participant.status.isReadyForStart,
          );
      final nextPhase = everyoneReady
          ? TeamHikePhase.countdown
          : hasPendingInvite
          ? TeamHikePhase.inviting
          : TeamHikePhase.readyCheck;
      shouldQueueCountdown =
          nextPhase == TeamHikePhase.countdown &&
          current.phase != TeamHikePhase.countdown;
      return current.copyWith(
        phase: nextPhase,
        countdownStartedAt: shouldQueueCountdown
            ? now
            : current.countdownStartedAt,
        participants: participants,
        updatedAt: now,
      );
    });
    if (shouldQueueCountdown) {
      await _queueTeamCountdownOutbox(updated);
    }
    return updated;
  }

  Future<TeamHikeSession> activateTeamHikeSession({
    required String teamHikeSessionId,
  }) async {
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      final participants = current.participants.map((participant) {
        if (!participant.status.isReadyForStart) {
          return participant;
        }
        return participant.copyWith(
          status: TeamHikeParticipantStatus.active,
          updatedAt: now,
        );
      }).toList();
      return current.copyWith(
        phase: TeamHikePhase.active,
        startedAt: current.startedAt ?? now,
        participants: participants,
        updatedAt: now,
      );
    });
    await _queueTeamStatusOutbox(
      teamSession: updated,
      type: 'team_hike_started',
      title: 'Team hike started',
      body: '${updated.trailName} is now actively tracking.',
    );
    return updated;
  }

  Future<void> attachActiveHikeToTeamSession({
    required String teamHikeSessionId,
    required String activeHikeSessionId,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return;
    }
    await _teamHikeSessions.doc(teamHikeSessionId).set({
      'activeHikeSessionId': activeHikeSessionId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

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
    return _mutateTeamHikeSession(teamHikeSessionId, (current, now) {
      var participants = current.participants.map((participant) {
        if (!_samePhone(participant.phoneNumber, session.phoneNumber)) {
          return participant;
        }
        return participant.copyWith(
          status: TeamHikeParticipantStatus.active,
          latestLocation: coordinate,
          progressMeters: progressMeters,
          updatedAt: now,
        );
      }).toList();
      final leaderPhoneNumber = _leaderPhoneNumberFor(participants);
      participants = participants.map((participant) {
        return participant.copyWith(
          isLeader: _samePhone(participant.phoneNumber, leaderPhoneNumber),
        );
      }).toList();
      return current.copyWith(
        phase: TeamHikePhase.active,
        participants: participants,
        updatedAt: now,
      );
    });
  }

  Future<TeamHikeSession> pingTeamParticipant({
    required AppSession session,
    required String teamHikeSessionId,
    required String participantPhoneNumber,
  }) async {
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      final participants = current.participants.map((participant) {
        if (!_samePhone(participant.phoneNumber, participantPhoneNumber)) {
          return participant;
        }
        return participant.copyWith(lastPingAt: now, updatedAt: now);
      }).toList();
      return current.copyWith(participants: participants, updatedAt: now);
    });
    await _queueFcmOutbox(
      type: 'team_hike_ping',
      recipientPhoneNumber: participantPhoneNumber,
      senderPhoneNumber: session.phoneNumber,
      title: 'Team check ping',
      body: 'Your hiking team is asking for an OK response.',
      deepLink: 'hikercircle://team-hike/ping?teamSessionId=$teamHikeSessionId',
      teamHikeSessionId: teamHikeSessionId,
    );
    return updated;
  }

  Future<TeamHikeSession> respondToTeamPing({
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      final participants = current.participants.map((participant) {
        if (!_samePhone(participant.phoneNumber, session.phoneNumber)) {
          return participant;
        }
        return participant.copyWith(
          lastOkAt: now,
          status: TeamHikeParticipantStatus.active,
          updatedAt: now,
        );
      }).toList();
      return current.copyWith(participants: participants, updatedAt: now);
    });
    await _queueFcmOutbox(
      type: 'team_hike_ping_ok',
      recipientPhoneNumber: updated.hostPhoneNumber,
      senderPhoneNumber: session.phoneNumber,
      title: 'Buddy responded OK',
      body: '${_handleForPhone(session.phoneNumber)} responded OK.',
      deepLink: 'hikercircle://team-hike/join?teamSessionId=$teamHikeSessionId',
      teamHikeSessionId: teamHikeSessionId,
    );
    return updated;
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
    await _saveActualHikeRouteCapture(
      session: session,
      activeHike: activeHike,
      summary: summary,
      capturedAt: now,
    );
    final teamHikeSessionId = activeHike.teamHikeSessionId;
    if (teamHikeSessionId.isNotEmpty) {
      await _teamHikeSessions.doc(teamHikeSessionId).set({
        'phase': TeamHikePhase.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'completedAtLocal': now.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));
    }
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
    String postType = 'completed_hike',
  }) async {
    _throwIfFirebaseUnavailable();

    final now = DateTime.now().toUtc();
    final document = _communityPosts.doc();
    final routePoints = _actualRoutePointsFor(activeHike);
    final routePreviewPoints = _routePreviewPointsFor(routePoints);
    final routeBounds = _routeBoundsFor(routePoints);
    await _saveActualHikeRouteCapture(
      session: session,
      activeHike: activeHike,
      summary: summary,
      capturedAt: now,
      communityPostId: document.id,
    );
    await document.set({
      'postId': document.id,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      'authorName': 'You',
      'authorHandle': _handleForPhone(session.phoneNumber),
      'postType': postType,
      'trailId': activeHike.trail.trailId,
      'trailName': activeHike.trail.name,
      'sessionId': activeHike.sessionId,
      'routeCaptureId': activeHike.sessionId,
      'thumbnailType': 'recorded_route_map',
      'caption': caption,
      'imageUrls': <String>[],
      'distanceKm': summary?.distanceKm ?? activeHike.recordedDistanceKm,
      'durationMinutes':
          summary?.duration.inMinutes ??
          DateTime.now().difference(activeHike.startedAt).inMinutes,
      'checkIns': activeHike.checkIns,
      'manualPins': activeHike.manualPins,
      'routePointCount': routePoints.length,
      'routePreviewPoints': routePreviewPoints
          .map((point) => point.toFirestore())
          .toList(),
      if (routePoints.isNotEmpty) 'routeStart': routePoints.first.toFirestore(),
      if (routePoints.isNotEmpty) 'routeEnd': routePoints.last.toFirestore(),
      if (routeBounds != null) 'routeBounds': routeBounds,
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

  Future<List<Map<String, dynamic>>> loadAdminHazardReports({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final snapshot = await _hazardReports
          .orderBy('reportedAtLocal', descending: true)
          .limit(50)
          .get();
      return snapshot.docs.map((document) {
        return {'hazardId': document.id, ...document.data()};
      }).toList();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to load hazard reports: ${error.message ?? error.code}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> loadAdminCommunityPosts({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final snapshot = await _communityPosts
          .orderBy('createdAtLocal', descending: true)
          .limit(50)
          .get();
      return snapshot.docs.map((document) {
        return {'postId': document.id, ...document.data()};
      }).toList();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to load community posts: ${error.message ?? error.code}',
      );
    }
  }

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

  Future<void> updateTrailByAdmin({
    required AppSession session,
    required Trail trail,
  }) async {
    _throwIfAdminUnavailable(session);
    await _trails.doc(trail.trailId).set({
      ...trail.toFirestore(),
      'updatedByAdminId': _userIdFor(session),
      'updatedByAdminPhoneNumber': session.phoneNumber,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> createTrailByAdmin({
    required AppSession session,
    required Trail trail,
  }) async {
    _throwIfAdminUnavailable(session);
    final trailId = trail.trailId.isEmpty
        ? _newTrailId(trail.name)
        : trail.trailId;
    final trailToSave = trail.copyWith(trailId: trailId);
    await _trails.doc(trailId).set({
      ...trailToSave.toFirestore(),
      'createdByAdminId': _userIdFor(session),
      'createdByAdminPhoneNumber': session.phoneNumber,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

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

  Future<List<Map<String, dynamic>>> loadAdminWhatsAppMessageLogs({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    try {
      final snapshot = await _whatsAppMessageLogs
          .orderBy('sentAtLocal', descending: true)
          .limit(150)
          .get();
      return snapshot.docs.map((document) {
        return {'messageLogId': document.id, ...document.data()};
      }).toList();
    } on FirebaseException catch (error) {
      throw HikerCircleFirebaseRepositoryException(
        'Failed to load WhatsApp logs: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> reviewHazardReport({
    required AppSession session,
    required Map<String, dynamic> report,
    required bool approved,
    String adminNote = '',
  }) async {
    _throwIfAdminUnavailable(session);
    final hazardId = _stringFrom(report['hazardId']);
    if (hazardId.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Hazard report is missing an id.',
      );
    }

    final now = DateTime.now().toUtc();
    final status = approved ? 'verified' : 'rejected';
    final reportLabel = approved
        ? 'Community Report - Admin Verified'
        : 'Community Report - Rejected';
    await _hazardReports.doc(hazardId).set({
      'status': status,
      'reportLabel': reportLabel,
      'adminNote': adminNote.trim(),
      'reviewedByAdminId': _userIdFor(session),
      'reviewedByAdminPhoneNumber': session.phoneNumber,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));

    if (!approved) {
      return;
    }

    final trailId = _stringFrom(report['trailId']);
    if (trailId.isEmpty) {
      return;
    }
    final hazard = TrailHazard(
      type: _stringFrom(report['hazardType']).isEmpty
          ? 'Hazard'
          : _stringFrom(report['hazardType']),
      description: _stringFrom(report['description']),
      severity: _titleCase(_stringFrom(report['severity'])),
      locationLabel: _locationLabelForHazardReport(report),
      reportedAt: _dateFromValue(report['reportedAtLocal']) ?? now,
    );
    await _trails.doc(trailId).set({
      'hazards': FieldValue.arrayUnion([hazard.toFirestore()]),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> moderateCommunityPost({
    required AppSession session,
    required String postId,
    required String moderationStatus,
    String reason = '',
  }) async {
    _throwIfAdminUnavailable(session);
    if (postId.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Community post is missing an id.',
      );
    }

    final normalizedStatus = moderationStatus.trim().toLowerCase();
    final visibility = switch (normalizedStatus) {
      'approved' => 'public',
      'hidden' => 'hidden',
      'removed' => 'removed',
      _ => 'hidden',
    };
    await _communityPosts.doc(postId).set({
      'moderationStatus': normalizedStatus,
      'visibility': visibility,
      'moderationReason': reason.trim(),
      'moderatedByAdminId': _userIdFor(session),
      'moderatedByAdminPhoneNumber': session.phoneNumber,
      'moderatedAt': FieldValue.serverTimestamp(),
      'moderatedAtLocal': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

  Future<List<Map<String, dynamic>>> loadUserAchievementProgress({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return _achievementProgressFrom(
        achievements: _achievementSeedRows(),
        userAwardsByAchievementId: const <String, Map<String, dynamic>>{},
      );
    }

    try {
      await ensureAchievementSeeds();
      final userId = _userIdFor(session);
      final results = await Future.wait([
        _achievements.orderBy('sortOrder').get(),
        _userAchievements.where('userId', isEqualTo: userId).get(),
      ]);
      final achievementSnapshot = results[0];
      final userAchievementSnapshot = results[1];
      final achievements = achievementSnapshot.docs.map((document) {
        return {...document.data(), 'achievementId': document.id};
      }).toList();
      final awardsByAchievementId = <String, Map<String, dynamic>>{};
      for (final document in userAchievementSnapshot.docs) {
        final data = document.data();
        final achievementId = _stringFrom(data['achievementId']);
        if (achievementId.isEmpty) {
          continue;
        }
        awardsByAchievementId[achievementId] = {
          ...data,
          'userAchievementId': document.id,
        };
      }

      return _achievementProgressFrom(
        achievements: achievements.isEmpty
            ? _achievementSeedRows()
            : achievements,
        userAwardsByAchievementId: awardsByAchievementId,
      );
    } catch (_) {
      return _achievementProgressFrom(
        achievements: _achievementSeedRows(),
        userAwardsByAchievementId: const <String, Map<String, dynamic>>{},
      );
    }
  }

  Future<void> ensureAchievementSeeds() async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return;
    }

    final batch = _resolvedFirestore.batch();
    for (final entry in _achievementSeeds.entries) {
      batch.set(_achievements.doc(entry.key), {
        'achievementId': entry.key,
        ...entry.value,
        'rewardsSafeBehaviour': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  List<Map<String, dynamic>> _achievementSeedRows() {
    return _achievementSeeds.entries.map((entry) {
      return {'achievementId': entry.key, ...entry.value};
    }).toList();
  }

  List<Map<String, dynamic>> _achievementProgressFrom({
    required List<Map<String, dynamic>> achievements,
    required Map<String, Map<String, dynamic>> userAwardsByAchievementId,
  }) {
    final rows = achievements.map((achievement) {
      final achievementId = _stringFrom(achievement['achievementId']);
      final award = userAwardsByAchievementId[achievementId];
      final awardedAt = award == null
          ? null
          : _dateFromValue(award['awardedAt']) ??
                _dateFromValue(award['awardedAtLocal']);
      final title = _stringFrom(achievement['title']);
      final condition = _stringFrom(achievement['condition']);
      final category = _stringFrom(achievement['category']);
      final iconName = _stringFrom(achievement['iconName']);
      final sortOrder = _intFrom(achievement['sortOrder']);

      return <String, dynamic>{
        'achievementId': achievementId,
        'title': title.isEmpty ? 'Achievement' : title,
        'condition': condition.isEmpty
            ? 'Complete a safety milestone'
            : condition,
        'category': category.isEmpty ? 'Safety' : category,
        'iconName': iconName.isEmpty ? 'emoji_events' : iconName,
        'rewardPoints': _intFrom(achievement['rewardPoints']),
        'sortOrder': sortOrder,
        'accentColorValue': _intFrom(achievement['accentColorValue']),
        'isUnlocked': award != null,
        if (award != null)
          'userAchievementId': _stringFrom(award['userAchievementId']),
        if (awardedAt != null) 'awardedAtLocal': awardedAt.toIso8601String(),
      };
    }).toList();

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

  List<TeamHikeParticipant> _teamParticipantsFor({
    required AppSession session,
    required List<TeamHikeBuddy> buddies,
    required DateTime now,
  }) {
    final participants = <TeamHikeParticipant>[];
    final seenKeys = <String>{};

    void addParticipant(TeamHikeBuddy buddy, {required bool isHost}) {
      final key = _participantKeyFor(buddy);
      if (key.isEmpty || seenKeys.contains(key)) {
        return;
      }
      seenKeys.add(key);
      participants.add(
        TeamHikeParticipant(
          buddy: buddy,
          status: isHost
              ? TeamHikeParticipantStatus.joined
              : TeamHikeParticipantStatus.invited,
          isHost: isHost,
          invitedAt: now,
          joinedAt: isHost ? now : null,
          updatedAt: now,
        ),
      );
    }

    addParticipant(
      TeamHikeBuddy(
        name: 'You',
        handle: _handleForPhone(session.phoneNumber),
        phoneNumber: session.phoneNumber,
        role: 'Host',
        avatarColorValue: 0xFF34A853,
      ),
      isHost: true,
    );
    for (final buddy in buddies) {
      addParticipant(buddy, isHost: false);
    }
    return participants;
  }

  Future<TeamHikeSession> _mutateTeamHikeSession(
    String teamHikeSessionId,
    TeamHikeSession Function(TeamHikeSession current, DateTime now) mutate,
  ) async {
    _throwIfFirebaseUnavailable();
    TeamHikeSession? updatedSession;
    final document = _teamHikeSessions.doc(teamHikeSessionId);
    await _resolvedFirestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(document);
      final current = _teamHikeSessionFromDocument(snapshot);
      if (current == null) {
        throw const HikerCircleFirebaseRepositoryException(
          'Team hike session was not found.',
        );
      }
      final now = DateTime.now().toUtc();
      final updated = mutate(current, now);
      updatedSession = updated;
      transaction.set(document, {
        ...updated.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return updatedSession!;
  }

  Future<void> _queueTeamCountdownOutbox(TeamHikeSession teamSession) async {
    await _queueTeamStatusOutbox(
      teamSession: teamSession,
      type: 'team_hike_countdown',
      title: 'Team hike starting',
      body:
          'Everyone is ready. ${teamSession.trailName} starts in ${teamSession.countdownSeconds} seconds.',
    );
  }

  Future<void> _queueTeamStatusOutbox({
    required TeamHikeSession teamSession,
    required String type,
    required String title,
    required String body,
  }) async {
    await Future.wait(
      teamSession.participants.map((participant) {
        return _queueFcmOutbox(
          type: type,
          recipientPhoneNumber: participant.phoneNumber,
          senderPhoneNumber: teamSession.hostPhoneNumber,
          title: title,
          body: body,
          deepLink:
              'hikercircle://team-hike/join?teamSessionId=${teamSession.id}',
          teamHikeSessionId: teamSession.id,
          data: {
            'trailId': teamSession.trailId,
            'trailName': teamSession.trailName,
            'phase': teamSession.phase.name,
          },
        );
      }),
    );
  }

  Future<void> _queueFcmOutbox({
    required String type,
    required String recipientPhoneNumber,
    required String senderPhoneNumber,
    required String title,
    required String body,
    required String deepLink,
    required String teamHikeSessionId,
    Map<String, dynamic> data = const {},
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || recipientPhoneNumber.isEmpty) {
      return;
    }
    await _fcmOutbox.add(
      _fcmOutboxPayload(
        type: type,
        recipientPhoneNumber: recipientPhoneNumber,
        senderPhoneNumber: senderPhoneNumber,
        title: title,
        body: body,
        deepLink: deepLink,
        teamHikeSessionId: teamHikeSessionId,
        data: data,
      ),
    );
  }

  Map<String, dynamic> _fcmOutboxPayload({
    required String type,
    required String recipientPhoneNumber,
    required String senderPhoneNumber,
    required String title,
    required String body,
    required String deepLink,
    required String teamHikeSessionId,
    Map<String, dynamic> data = const {},
  }) {
    final now = DateTime.now().toUtc();
    return {
      'type': type,
      'recipientPhoneNumber': recipientPhoneNumber,
      'senderPhoneNumber': senderPhoneNumber,
      'title': title,
      'body': body,
      'deepLink': deepLink,
      'teamHikeSessionId': teamHikeSessionId,
      'status': 'pending',
      'attemptCount': 0,
      'data': {
        ...data,
        'type': type,
        'teamHikeSessionId': teamHikeSessionId,
        'deepLink': deepLink,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    };
  }

  TeamHikeSession? _teamHikeSessionFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      return null;
    }
    return TeamHikeSession.fromFirestore(data, id: document.id);
  }

  Future<void> _saveActualHikeRouteCapture({
    required AppSession session,
    required ActiveHikeSession activeHike,
    required DateTime capturedAt,
    HikeSummaryReport? summary,
    String? communityPostId,
  }) async {
    final routePoints = _actualRoutePointsFor(activeHike);
    final routeBounds = _routeBoundsFor(routePoints);

    await _hikeRouteCaptures.doc(activeHike.sessionId).set({
      'sessionId': activeHike.sessionId,
      'userId': _userIdFor(session),
      'userPhoneNumber': session.phoneNumber,
      'trailId': activeHike.trail.trailId,
      'trailName': activeHike.trail.name,
      'captureType': 'recorded_actual_trail',
      'anonymousRecommendationEligible': true,
      'routePoints': routePoints.map((point) => point.toFirestore()).toList(),
      'routePointCount': routePoints.length,
      if (routePoints.isNotEmpty) 'routeStart': routePoints.first.toFirestore(),
      if (routePoints.isNotEmpty) 'routeEnd': routePoints.last.toFirestore(),
      if (routeBounds != null) 'routeBounds': routeBounds,
      if (communityPostId != null) 'communityPostId': communityPostId,
      'manualPins': activeHike.manualPinLocations
          .map((pin) => pin.toFirestore())
          .toList(),
      if (summary != null) 'summaryReport': summary.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': capturedAt.toIso8601String(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': capturedAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  List<HikeCoordinate> _actualRoutePointsFor(ActiveHikeSession activeHike) {
    final points = List<HikeCoordinate>.of(activeHike.routePoints);
    final latest = activeHike.latestLocation;
    if (latest != null &&
        (points.isEmpty || points.last.distanceTo(latest) > 2)) {
      points.add(latest);
    }
    points.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return points;
  }

  List<HikeCoordinate> _routePreviewPointsFor(
    List<HikeCoordinate> routePoints, {
    int maxPoints = 120,
  }) {
    if (routePoints.length <= maxPoints) {
      return routePoints;
    }
    final preview = <HikeCoordinate>[];
    final lastIndex = routePoints.length - 1;
    final step = lastIndex / (maxPoints - 1);
    for (var index = 0; index < maxPoints; index++) {
      preview.add(routePoints[(index * step).round()]);
    }
    return preview;
  }

  Map<String, dynamic>? _routeBoundsFor(List<HikeCoordinate> points) {
    if (points.isEmpty) {
      return null;
    }

    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLatitude) {
        minLatitude = point.latitude;
      }
      if (point.latitude > maxLatitude) {
        maxLatitude = point.latitude;
      }
      if (point.longitude < minLongitude) {
        minLongitude = point.longitude;
      }
      if (point.longitude > maxLongitude) {
        maxLongitude = point.longitude;
      }
    }

    return {
      'minLatitude': minLatitude,
      'maxLatitude': maxLatitude,
      'minLongitude': minLongitude,
      'maxLongitude': maxLongitude,
    };
  }

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

  String _leaderPhoneNumberFor(List<TeamHikeParticipant> participants) {
    if (participants.isEmpty) {
      return '';
    }
    final leader = participants.reduce(
      (front, participant) => front.progressMeters >= participant.progressMeters
          ? front
          : participant,
    );
    return leader.phoneNumber;
  }

  String _participantKeyFor(TeamHikeBuddy buddy) {
    final phoneKey = _phoneKeyFor(buddy.phoneNumber);
    if (phoneKey.isNotEmpty) {
      return phoneKey;
    }
    return buddy.handle.trim().toLowerCase();
  }

  bool _samePhone(String first, String second) {
    final firstKey = _phoneKeyFor(first);
    final secondKey = _phoneKeyFor(second);
    return firstKey.isNotEmpty && firstKey == secondKey;
  }

  String _phoneKeyFor(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
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

  String _locationLabelForHazardReport(Map<String, dynamic> report) {
    final locationLabel = _stringFrom(report['locationLabel']);
    if (locationLabel.isNotEmpty) {
      return locationLabel;
    }
    final latitude = report['latitude'];
    final longitude = report['longitude'];
    if (latitude is num && longitude is num) {
      return '${latitude.toDouble().toStringAsFixed(5)}, ${longitude.toDouble().toStringAsFixed(5)}';
    }
    return _stringFrom(report['trailName']);
  }

  String _newTrailId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeSlug = slug.isEmpty ? 'trail' : slug;
    return 'trail_${safeSlug}_${DateTime.now().microsecondsSinceEpoch}';
  }

  void _throwIfAdminUnavailable(AppSession session) {
    _throwIfFirebaseUnavailable();
    if (session.isAdmin) {
      return;
    }
    throw const HikerCircleFirebaseRepositoryException(
      'Admin privilege is required for this action.',
    );
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
