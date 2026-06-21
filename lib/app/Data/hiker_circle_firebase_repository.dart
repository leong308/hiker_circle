import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/hiker_level.dart';
import '../../core/services/open_meteo_service.dart';
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

class AdminTrailImageUpload {
  const AdminTrailImageUpload({
    required this.bytes,
    required this.fileName,
    this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? contentType;
}

class HikerCircleFirebaseRepository {
  HikerCircleFirebaseRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    LocalSessionDatabase? localDatabase,
    FirebaseBootstrapResult firebaseBootstrapResult =
        const FirebaseBootstrapResult.available(),
    OpenMeteoService? openMeteoService,
  }) : _firestore = firestore,
       _storage = storage,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _firebaseBootstrapResult = firebaseBootstrapResult,
       _openMeteoService = openMeteoService ?? const OpenMeteoService(),
       _functions = FirebaseFunctions.instance;

  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;
  final FirebaseFunctions _functions;
  final LocalSessionDatabase _localDatabase;
  final FirebaseBootstrapResult _firebaseBootstrapResult;
  final OpenMeteoService _openMeteoService;

  LocalSessionDatabase get localDatabase => _localDatabase;

  FirebaseFirestore get _resolvedFirestore =>
      _firestore ?? FirebaseFirestore.instance;

  FirebaseFirestore get firestore => _resolvedFirestore;

  FirebaseStorage get _resolvedStorage => _storage ?? FirebaseStorage.instance;

  Future<void> registerFcmToken({
    required AppSession session,
    required String token,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || token.isEmpty) {
      return;
    }
    await _resolvedFirestore.collection('users').doc(_userIdFor(session)).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastFcmToken': token,
      'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'lastFcmTokenUpdatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

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

  CollectionReference<Map<String, dynamic>> get _trails =>
      _resolvedFirestore.collection('trails');
  CollectionReference<Map<String, dynamic>> get _users =>
      _resolvedFirestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _hikeSessions =>
      _resolvedFirestore.collection('hikeSessions');
  CollectionReference<Map<String, dynamic>> get _locationPoints =>
      _resolvedFirestore.collection('localLocationPoints');
  CollectionReference<Map<String, dynamic>> get _checkIns =>
      _resolvedFirestore.collection('checkIns');
  CollectionReference<Map<String, dynamic>> get _hazardReports =>
      _resolvedFirestore.collection('hazardReports');
  CollectionReference<Map<String, dynamic>> get _upcomingHikes =>
      _resolvedFirestore.collection('upcomingHikes');
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
  CollectionReference<Map<String, dynamic>> get _groupChats =>
      _resolvedFirestore.collection('groupChats');
  CollectionReference<Map<String, dynamic>> _groupChatMessagesFor(
    String chatId,
  ) {
    return _groupChats.doc(chatId).collection('messages');
  }

  static const Map<String, Map<String, Object>> _achievementSeeds = {
    'first_safe_hike': {
      'title': 'First Safe Hike',
      'condition': 'Complete first hike session',
      'category': 'Hike milestone',
      'iconName': 'verified_user',
      'rewardPoints': 120,
      'rewardType': 'one_time',
      'metricKey': 'hike_completed',
      'targetCount': 1,
      'isActive': true,
      'sortOrder': 10,
      'accentColorValue': 0xFF34A853,
    },
    'prepared_adventurer': {
      'title': 'Prepared Adventurer',
      'condition': 'Download offline map before starting',
      'category': 'Preparation',
      'iconName': 'map',
      'rewardPoints': 90,
      'rewardType': 'one_time',
      'metricKey': 'hike_started',
      'targetCount': 1,
      'isActive': true,
      'sortOrder': 20,
      'accentColorValue': 0xFF2F80ED,
    },
    'safety_first': {
      'title': 'Safety First',
      'condition': 'Complete gear checklist before departure',
      'category': 'Preparation',
      'iconName': 'health_and_safety',
      'rewardPoints': 100,
      'rewardType': 'one_time',
      'metricKey': 'checklist_completed',
      'targetCount': 1,
      'isActive': true,
      'sortOrder': 30,
      'accentColorValue': 0xFFF2994A,
    },
    'reliable_check_in': {
      'title': 'Reliable Check-In',
      'condition': 'Complete 5 scheduled check-ins during hikes',
      'category': 'Safety habit',
      'iconName': 'task_alt',
      'rewardPoints': 110,
      'rewardType': 'cumulative',
      'metricKey': 'check_in_completed',
      'targetCount': 5,
      'isActive': true,
      'sortOrder': 40,
      'accentColorValue': 0xFF9B51E0,
    },
    'community_helper': {
      'title': 'Community Helper',
      'condition': 'Submit a hazard report later confirmed by others',
      'category': 'Community',
      'iconName': 'volunteer_activism',
      'rewardPoints': 140,
      'rewardType': 'one_time',
      'metricKey': 'hazard_report_approved',
      'targetCount': 1,
      'isActive': true,
      'sortOrder': 50,
      'accentColorValue': 0xFFEB5757,
    },
    'team_guardian': {
      'title': 'Team Guardian',
      'condition': 'Complete 3 team hikes without a separation emergency',
      'category': 'Team hike',
      'iconName': 'groups',
      'rewardPoints': 160,
      'rewardType': 'cumulative',
      'metricKey': 'team_hike_completed',
      'targetCount': 3,
      'isActive': true,
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

      return liveTrails;
    } catch (_) {
      return const [];
    }
  }

  Stream<List<Trail>> watchTrails() {
    if (!_firebaseBootstrapResult.isAvailable) return Stream.value(const []);
    return _trails
        .orderBy('isVerifiedTrail', descending: true)
        .orderBy('ratingAverage', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          var trails = snapshot.docs
              .map(
                (doc) =>
                    _trailFromFirestore({'trailId': doc.id, ...doc.data()}),
              )
              .whereType<Trail>()
              .toList();
          await _enrichWithLiveWeather(trails, snapshot.docs);
          return trails;
        });
  }

  Future<void> _enrichWithLiveWeather(
    List<Trail> liveTrails,
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final fetchIndices = <int>[];
    final batch = _resolvedFirestore.batch();
    var hasChanges = false;

    for (var i = 0; i < liveTrails.length; i++) {
      final docData = i < docs.length ? docs[i].data() : null;
      final hasWeatherField = docData != null && docData.containsKey('weather');
      if (!hasWeatherField || liveTrails[i].weather.isStale) {
        fetchIndices.add(i);
      }
    }

    if (fetchIndices.isEmpty) {
      return;
    }

    final weatherResults = await Future.wait(
      fetchIndices.map(
        (i) => _fetchWeatherOrNull(
          liveTrails[i].latitude,
          liveTrails[i].longitude,
        ),
      ),
    );

    for (var j = 0; j < fetchIndices.length; j++) {
      final weather = weatherResults[j];
      if (weather == null) {
        continue;
      }
      final i = fetchIndices[j];
      liveTrails[i] = liveTrails[i].copyWith(weather: weather);

      if (i < docs.length && docs[i].exists) {
        batch.update(docs[i].reference, {'weather': weather.toFirestore()});
        hasChanges = true;
      }
    }

    if (hasChanges) {
      try {
        await batch.commit();
      } catch (_) {
        // Cache write is best-effort; stale Firestore data is acceptable.
      }
    }
  }

  Future<TrailWeather?> _fetchWeatherOrNull(
    double latitude,
    double longitude,
  ) async {
    try {
      return await _openMeteoService.fetchWeather(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Trail> refreshTrailWeather(Trail trail) async {
    try {
      final weather = await _openMeteoService.fetchWeather(
        latitude: trail.latitude,
        longitude: trail.longitude,
      );
      final updated = trail.copyWith(weather: weather);

      if (_firebaseBootstrapResult.isAvailable) {
        try {
          await _trails.doc(trail.trailId).update({
            'weather': weather.toFirestore(),
          });
        } catch (_) {
          // Cache write is best-effort.
        }
      }

      return updated;
    } catch (_) {
      return trail;
    }
  }

  Future<Trail> refreshTrailWeatherViaCloud(Trail trail) async {
    try {
      final result = await _functions
          .httpsCallable('fetchWeatherForTrail')
          .call({'trailId': trail.trailId});
      final weatherMap = result.data['weather'] as Map<String, dynamic>;
      final weather = weatherFromFirestore(weatherMap);
      final updated = trail.copyWith(weather: weather);
      return updated;
    } catch (_) {
      return trail;
    }
  }

  Future<List<UpcomingHike>> loadUpcomingHikes() async {
    if (!_firebaseBootstrapResult.isAvailable) return const [];
    try {
      final snapshot = await _upcomingHikes.get();
      return snapshot.docs
          .map((doc) => UpcomingHike.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<UpcomingHike?> loadUpcomingHikeById(String hikeId) async {
    if (!_firebaseBootstrapResult.isAvailable || hikeId.trim().isEmpty) {
      return null;
    }
    try {
      final document = await _upcomingHikes.doc(hikeId.trim()).get();
      final data = document.data();
      if (!document.exists || data == null) {
        return null;
      }
      return UpcomingHike.fromFirestore(document.id, data);
    } catch (_) {
      return null;
    }
  }

  Future<List<UpcomingHike>> loadMyUpcomingHikes(String phoneNumber) async {
    if (!_firebaseBootstrapResult.isAvailable) return const [];
    try {
      final createdQuery = await _upcomingHikes
          .where('creatorPhone', isEqualTo: phoneNumber)
          .get();
      final joinedQuery = await _upcomingHikes
          .where('participantPhones', arrayContains: phoneNumber)
          .get();
      final seen = <String>{};
      final results = <UpcomingHike>[];
      for (final doc in [...createdQuery.docs, ...joinedQuery.docs]) {
        if (seen.add(doc.id)) {
          results.add(UpcomingHike.fromFirestore(doc.id, doc.data()));
        }
      }
      results.sort((a, b) => b.departureTime.compareTo(a.departureTime));
      return results;
    } catch (_) {
      return const [];
    }
  }

  Stream<List<UpcomingHike>> watchMyUpcomingHikes(String phoneNumber) {
    if (!_firebaseBootstrapResult.isAvailable) {
      return Stream.value(const []);
    }
    return Stream<List<UpcomingHike>>.multi((controller) {
      List<UpcomingHike>? created;
      List<UpcomingHike>? joined;

      void emit() {
        if (created == null || joined == null) return;
        final seen = <String>{};
        final results = <UpcomingHike>[];
        for (final hike in [...created!, ...joined!]) {
          if (seen.add(hike.id)) results.add(hike);
        }
        results.sort((a, b) => b.departureTime.compareTo(a.departureTime));
        controller.add(results);
      }

      final sub1 = _upcomingHikes
          .where('creatorPhone', isEqualTo: phoneNumber)
          .snapshots()
          .listen((s) {
            created = s.docs
                .map((d) => UpcomingHike.fromFirestore(d.id, d.data()))
                .toList();
            emit();
          }, onError: controller.addError);

      final sub2 = _upcomingHikes
          .where('participantPhones', arrayContains: phoneNumber)
          .snapshots()
          .listen((s) {
            joined = s.docs
                .map((d) => UpcomingHike.fromFirestore(d.id, d.data()))
                .toList();
            emit();
          }, onError: controller.addError);

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };
    });
  }

  Future<bool> joinUpcomingHike({
    required String hikeId,
    required String sessionId,
    required String trailName,
    required String creatorPhone,
    required String phoneNumber,
    String userName = '',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return false;
    try {
      final hikeReference = _upcomingHikes.doc(hikeId);
      await _resolvedFirestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(hikeReference);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          throw const HikerCircleFirebaseRepositoryException(
            'This upcoming hike is no longer available.',
          );
        }
        final currentPhones = data['participantPhones'] is Iterable
            ? (data['participantPhones'] as Iterable)
                  .whereType<String>()
                  .toSet()
            : <String>{};
        final storedCreatorPhone = _stringFrom(data['creatorPhone']);
        if (storedCreatorPhone.isNotEmpty) {
          currentPhones.add(storedCreatorPhone);
        }
        if (currentPhones.contains(phoneNumber)) {
          return;
        }
        currentPhones.add(phoneNumber);
        transaction.set(hikeReference, {
          'participantPhones': currentPhones.toList(),
          'participantCount': currentPhones.length,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
        }, SetOptions(merge: true));
      });

      final snapshot = await _upcomingHikes.doc(hikeId).get();
      final data = snapshot.data();
      if (data == null) return true;

      final raw = data['participantPhones'];
      final allPhones = raw is List
          ? raw.whereType<String>().where((p) => p.isNotEmpty).toList()
          : <String>[creatorPhone, phoneNumber];
      if (allPhones.length < 2) return true;

      await _groupChats.doc(sessionId).set({
        'hikeSessionId': sessionId,
        'trailName': trailName,
        'participantPhones': FieldValue.arrayUnion(allPhones),
        'creatorPhone': creatorPhone,
        'createdAtLocal': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));

      final displayName = userName.isNotEmpty ? userName : phoneNumber;
      await sendSystemMessage(
        chatId: sessionId,
        text: '$displayName joined the hike',
        senderPhone: phoneNumber,
        senderName: displayName,
        participantPhones: allPhones,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> createGroupChat({
    required String hikeSessionId,
    required String trailName,
    required List<String> participantPhones,
    required String creatorPhone,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      final doc = _groupChats.doc();
      final chat = GroupChat(
        id: doc.id,
        hikeSessionId: hikeSessionId,
        trailName: trailName,
        participantPhones: participantPhones,
        creatorPhone: creatorPhone,
        createdAt: DateTime.now(),
        chatType: 'group',
      );
      await doc.set(chat.toFirestore());
    } catch (_) {}
  }

  Future<List<GroupChat>> loadUserGroupChats(String phoneNumber) async {
    if (!_firebaseBootstrapResult.isAvailable) return const [];
    try {
      final snapshot = await _groupChats
          .where('participantPhones', arrayContains: phoneNumber)
          .orderBy('createdAtLocal', descending: true)
          .get();
      final chats = snapshot.docs
          .map((doc) => GroupChat.fromFirestore(doc.id, doc.data()))
          .toList();
      chats.sort(
        (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
          a.lastMessageAt ?? a.createdAt,
        ),
      );
      return chats;
    } catch (_) {
      return const [];
    }
  }

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
      return GroupChat.fromFirestore(snapshot.id, data);
    } catch (_) {
      return null;
    }
  }

  Stream<List<GroupChat>> userGroupChatsStream(String phoneNumber) {
    return _groupChats
        .where('participantPhones', arrayContains: phoneNumber)
        .orderBy('createdAtLocal', descending: true)
        .snapshots()
        .map((snapshot) {
          final chats = snapshot.docs
              .map((doc) => GroupChat.fromFirestore(doc.id, doc.data()))
              .toList();
          chats.sort(
            (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
              a.lastMessageAt ?? a.createdAt,
            ),
          );
          return chats;
        });
  }

  Future<GroupChat> openDirectChat({
    required AppSession session,
    required String otherPhoneNumber,
    required String otherDisplayName,
  }) async {
    _throwIfFirebaseUnavailable();
    final ownPhone = session.phoneNumber.trim();
    final otherPhone = otherPhoneNumber.trim();
    if (otherPhone.isEmpty || _samePhone(ownPhone, otherPhone)) {
      throw const HikerCircleFirebaseRepositoryException(
        'Choose another hiker to start a private conversation.',
      );
    }
    final phoneKeys = [_phoneKeyFor(ownPhone), _phoneKeyFor(otherPhone)]
      ..sort();
    final chatId = 'direct_${phoneKeys.join('_')}';
    final reference = _groupChats.doc(chatId);
    final now = DateTime.now().toUtc();
    final names = <String, String>{
      _phoneKeyFor(ownPhone): session.username.trim().isEmpty
          ? ownPhone
          : session.username.trim(),
      _phoneKeyFor(otherPhone): otherDisplayName.trim().isEmpty
          ? otherPhone
          : otherDisplayName.trim(),
    };
    await reference.set({
      'hikeSessionId': '',
      'trailName': 'Private chat',
      'chatType': 'direct',
      'participantPhones': [ownPhone, otherPhone],
      'participantNames': names,
      'creatorPhone': ownPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': now.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
    }, SetOptions(merge: true));
    final snapshot = await reference.get();
    return GroupChat.fromFirestore(chatId, snapshot.data()!);
  }

  Future<List<Map<String, dynamic>>> loadCommunityProfiles({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const [];
    }
    final snapshot = await _users.limit(80).get();
    final ownId = _userIdFor(session);
    return snapshot.docs
        .where((document) => document.id != ownId)
        .map((document) {
          final data = document.data();
          final profile = data['profile'] is Map
              ? Map<String, dynamic>.from(data['profile'] as Map)
              : const <String, dynamic>{};
          final points = _intFrom(data['achievementPoints']);
          final level = HikerLevel.fromPoints(points);
          final username = _stringFrom(data['username']).trim().isNotEmpty
              ? _stringFrom(data['username']).trim()
              : _stringFrom(profile['username']).trim();
          return <String, dynamic>{
            'userId': document.id,
            'phoneNumber': _stringFrom(data['phoneNumber']),
            'displayName': username.isEmpty ? 'Hiker' : username,
            'handle': _handleForPhone(_stringFrom(data['phoneNumber'])),
            'gender': _stringFrom(profile['gender']),
            'hikerExperience': _stringFrom(profile['hikerExperience']),
            'hikeFrequency': _stringFrom(profile['hikeFrequency']),
            'residentialLocation': _stringFrom(profile['residentialLocation']),
            'achievementPoints': points,
            'level': level.number,
            'levelName': level.name,
          };
        })
        .where((profile) => _stringFrom(profile['phoneNumber']).isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> loadCommunityProfile({
    String userId = '',
    String phoneNumber = '',
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return null;
    }
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    if (userId.trim().isNotEmpty) {
      snapshot = await _users.doc(userId.trim()).get();
    } else if (phoneNumber.trim().isNotEmpty) {
      snapshot = await _users
          .doc(FirebaseUserRepository.documentIdForPhoneNumber(phoneNumber))
          .get();
    } else {
      return null;
    }
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    final profile = data['profile'] is Map
        ? Map<String, dynamic>.from(data['profile'] as Map)
        : const <String, dynamic>{};
    final points = _intFrom(data['achievementPoints']);
    final level = HikerLevel.fromPoints(points);
    final username = _stringFrom(data['username']).trim().isNotEmpty
        ? _stringFrom(data['username']).trim()
        : _stringFrom(profile['username']).trim();
    return {
      'userId': snapshot.id,
      'phoneNumber': _stringFrom(data['phoneNumber']),
      'displayName': username.isEmpty ? 'Hiker' : username,
      'handle': _handleForPhone(_stringFrom(data['phoneNumber'])),
      'gender': _stringFrom(profile['gender']),
      'hikerExperience': _stringFrom(profile['hikerExperience']),
      'hikeFrequency': _stringFrom(profile['hikeFrequency']),
      'residentialLocation': _stringFrom(profile['residentialLocation']),
      'achievementPoints': points,
      'level': level.number,
      'levelName': level.name,
    };
  }

  Future<Set<String>> loadBuddyPhoneNumbers({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return const {};
    }
    final snapshot = await _users.doc(_userIdFor(session)).get();
    final raw = snapshot.data()?['buddyPhoneNumbers'];
    return raw is Iterable ? raw.whereType<String>().toSet() : <String>{};
  }

  Future<void> addBuddy({
    required AppSession session,
    required String buddyPhoneNumber,
  }) async {
    _throwIfFirebaseUnavailable();
    if (buddyPhoneNumber.trim().isEmpty) {
      return;
    }
    await _users.doc(_userIdFor(session)).set({
      'buddyPhoneNumbers': FieldValue.arrayUnion([buddyPhoneNumber.trim()]),
      'buddiesUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> loadGroupChatNotificationsEnabled({
    required AppSession session,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) {
      return true;
    }
    try {
      final snapshot = await _users.doc(_userIdFor(session)).get();
      return snapshot.data()?['groupChatNotificationsEnabled'] != false;
    } catch (_) {
      return true;
    }
  }

  Future<void> setGroupChatNotificationsEnabled({
    required AppSession session,
    required bool enabled,
  }) async {
    _throwIfFirebaseUnavailable();
    await _users.doc(_userIdFor(session)).set({
      'groupChatNotificationsEnabled': enabled,
      'groupChatNotificationSettingsUpdatedAt': FieldValue.serverTimestamp(),
      'groupChatNotificationSettingsUpdatedAtLocal': DateTime.now()
          .toUtc()
          .toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<DateTime?> loadGroupChatMutedUntil({
    required AppSession session,
    required String chatId,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || chatId.trim().isEmpty) {
      return null;
    }
    try {
      final snapshot = await _users.doc(_userIdFor(session)).get();
      final rawMap = snapshot.data()?['groupChatMutedUntil'];
      if (rawMap is! Map) {
        return null;
      }
      final mutedUntil = _dateFromValue(rawMap[chatId.trim()]);
      if (mutedUntil == null || !mutedUntil.isAfter(DateTime.now())) {
        return null;
      }
      return mutedUntil;
    } catch (_) {
      return null;
    }
  }

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
    final userReference = _users.doc(_userIdFor(session));
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
  }

  Future<Set<String>> loadPinnedChats({required AppSession session}) async {
    if (!_firebaseBootstrapResult.isAvailable) return {};
    try {
      final snapshot = await _users.doc(_userIdFor(session)).get();
      final raw = snapshot.data()?['pinnedChats'];
      if (raw is Map) {
        return raw.keys
            .where((k) => raw[k] == true || raw[k] is Timestamp)
            .cast<String>()
            .toSet();
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> setChatPinned({
    required AppSession session,
    required String chatId,
    required bool pinned,
  }) async {
    _throwIfFirebaseUnavailable();
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return;
    await _users.doc(_userIdFor(session)).set({
      'pinnedChats': {
        normalizedChatId:
            pinned ? FieldValue.serverTimestamp() : FieldValue.delete(),
      },
    }, SetOptions(merge: true));
  }

  Future<void> deleteChatForUser({
    required AppSession session,
    required String chatId,
    required String senderName,
    required List<String> participantPhones,
  }) async {
    _throwIfFirebaseUnavailable();
    await sendSystemMessage(
      chatId: chatId,
      text: '$senderName left the conversation',
      senderPhone: session.phoneNumber,
      senderName: senderName,
      participantPhones: participantPhones,
    );
    await _groupChats.doc(chatId).update({
      'participantPhones': FieldValue.arrayRemove([session.phoneNumber]),
    });
  }

  Future<void> sendGroupChatMessage({
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    required String localId,
    required DateTime sentAt,
    ChatAttachment? attachment,
  }) async {
    if (attachment == null) {
      await _localDatabase.insertPendingMessage(
        localId: localId,
        chatId: chatId,
        senderPhone: senderPhone,
        senderName: senderName,
        text: text,
      );
    }

    try {
      final msgDoc = _groupChatMessagesFor(chatId).doc();
      final msg = ChatMessage(
        id: msgDoc.id,
        chatId: chatId,
        senderPhone: senderPhone,
        senderName: senderName,
        text: text,
        sentAt: sentAt,
        seenBy: [senderPhone],
        attachment: attachment,
      );

      await msgDoc.set(msg.toFirestore());
      await _groupChats.doc(chatId).update({
        'lastMessage': text.isNotEmpty ? text : _attachmentSummary(attachment),
        'lastMessageAtLocal': sentAt.toUtc().toIso8601String(),
      });

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

    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
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

  Future<void> sendSystemMessage({
    required String chatId,
    required String text,
    required String senderPhone,
    required String senderName,
    required List<String> participantPhones,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      final msgDoc = _groupChatMessagesFor(chatId).doc();
      final msg = ChatMessage(
        id: msgDoc.id,
        chatId: chatId,
        senderPhone: senderPhone,
        senderName: senderName,
        text: text,
        sentAt: DateTime.now(),
        isSystemMessage: true,
        seenBy: participantPhones,
      );
      await msgDoc.set(msg.toFirestore());
    } catch (_) {}
  }

  String _attachmentSummary(ChatAttachment? attachment) {
    return switch (attachment?.type) {
      ChatAttachmentType.image => 'Photo',
      ChatAttachmentType.video => 'Video',
      ChatAttachmentType.document => 'Document',
      null => '',
    };
  }

  Future<void> markMessageAsSeen({
    required String chatId,
    required String messageId,
    required String phoneNumber,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      await _groupChatMessagesFor(chatId).doc(messageId).update({
        'seenBy': FieldValue.arrayUnion([phoneNumber]),
      });
    } catch (_) {}
  }

  Future<List<ChatMessage>> loadPendingMessagesForChat(String chatId) async {
    final rows = await _localDatabase.loadPendingMessagesForChat(chatId);
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
          ),
        )
        .toList();
  }

  Future<List<ChatMessage>> loadAllLocalMessagesForChat(String chatId) async {
    final rows = await _localDatabase.loadAllLocalMessagesForChat(chatId);
    return rows.map((row) {
      final statusStr = row['send_status'] as String? ?? 'pending';
      final status = switch (statusStr) {
        'sent' => SendStatus.sent,
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
      );
    }).toList();
  }

  Future<void> cacheChatMessages(
    List<ChatMessage> messages,
    String chatId,
  ) async {
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
            'attachment_json': m.attachment == null
                ? ''
                : jsonEncode(m.attachment!.toFirestore()),
          },
        )
        .toList();
    await _localDatabase.upsertChatMessages(rows);
  }

  Future<void> flushPendingMessages() async {
    final rows = await _localDatabase.loadPendingMessages();
    for (final row in rows) {
      final localId = row['local_id'] as String;
      final chatId = row['chat_id'] as String;
      final senderPhone = row['sender_phone'] as String;
      final senderName = row['sender_name'] as String? ?? '';
      final text = row['text'] as String;
      final retryCount = row['retry_count'] as int? ?? 0;
      final firestoreDocId = row['firestore_doc_id'] as String? ?? '';

      if (retryCount > 5) {
        await _localDatabase.deletePendingMessage(localId);
        continue;
      }

      try {
        if (firestoreDocId.isNotEmpty) {
          final existing = await _groupChatMessagesFor(
            chatId,
          ).doc(firestoreDocId).get(const GetOptions(source: Source.server));
          if (existing.exists) {
            await _localDatabase.markPendingMessageSent(localId);
            continue;
          }
        }

        final msgDoc = firestoreDocId.isNotEmpty
            ? _groupChatMessagesFor(chatId).doc(firestoreDocId)
            : _groupChatMessagesFor(chatId).doc();
        final msg = ChatMessage(
          id: msgDoc.id,
          chatId: chatId,
          senderPhone: senderPhone,
          senderName: senderName,
          text: text,
          sentAt: DateTime.now(),
          seenBy: [senderPhone],
        );
        await msgDoc.set(msg.toFirestore());
        await _groupChats.doc(chatId).update({
          'lastMessage': text,
          'lastMessageAtLocal': DateTime.now().toUtc().toIso8601String(),
        });

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
      } catch (_) {
        await _localDatabase.incrementPendingMessageRetry(localId);
      }
    }
  }

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

  Future<UpcomingHike?> loadUpcomingHikeForChat(String hikeSessionId) async {
    if (!_firebaseBootstrapResult.isAvailable) return null;
    try {
      final doc = await _upcomingHikes.doc(hikeSessionId).get();
      if (!doc.exists) return null;
      return UpcomingHike.fromFirestore(doc.id, doc.data()!);
    } catch (_) {
      return null;
    }
  }

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

  Future<void> scheduleUpcomingHike({
    required AppSession session,
    required HikeSessionDraft draft,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable) return;
    try {
      final now = DateTime.now().toUtc();
      final upcomingDoc = _upcomingHikes.doc();
      final participantPhones = [
        session.phoneNumber,
        ...draft.teamBuddies.map((b) => b.phoneNumber),
      ];
      final upcoming = UpcomingHike(
        id: upcomingDoc.id,
        sessionId: upcomingDoc.id,
        trailId: draft.trail.trailId,
        trailName: draft.trail.name,
        latitude: draft.trail.latitude,
        longitude: draft.trail.longitude,
        area: draft.trail.area,
        state: draft.trail.state,
        distanceKm: draft.trail.distanceKm,
        durationMinutes: draft.trail.estimatedDurationMinutes,
        difficulty: draft.trail.difficulty,
        startPointName: draft.startPointName,
        destinationName: draft.destinationName,
        departureTime: draft.departureTime,
        expectedReturnTime: draft.expectedReturnTime,
        hikeType: draft.hikeType.name,
        participantCount: participantPhones.length,
        creatorPhone: session.phoneNumber,
        createdAt: now,
        participantPhones: participantPhones,
      );
      await upcomingDoc.set({
        ...upcoming.toFirestore(),
        'creatorUserId': _userIdFor(session),
        'creatorName': session.username.trim(),
        'notificationRadiusKm': 20,
      });

      if (participantPhones.length > 1) {
        await createGroupChat(
          hikeSessionId: upcomingDoc.id,
          trailName: draft.trail.name,
          participantPhones: participantPhones,
          creatorPhone: session.phoneNumber,
        );
      }
    } catch (_) {
      // Best-effort: scheduling is non-critical.
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
    TeamHikeSession? teamHikeSession,
  }) async {
    final localSession = ActiveHikeSession.fromDraft(
      draft,
      teamHikeSessionId: teamHikeSessionId,
      teamHikeSession: teamHikeSession,
    );
    if (!_firebaseBootstrapResult.isAvailable) {
      return localSession;
    }

    try {
      final document = _hikeSessions.doc();
      final now = DateTime.now().toUtc();
      final effectiveCheckpoints = draft.effectiveCheckpoints;
      final checkpointData = effectiveCheckpoints
          .map((c) => c.toFirestore())
          .toList();

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
        'checkpoints': checkpointData,
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
        'fallDetectionResponseDurationSeconds':
            draft.fallDetectionSettings.fallResponseDuration.inSeconds,
        'fallDetectionLongestRestDurationSeconds':
            draft.fallDetectionSettings.longestRestDuration.inSeconds,
        'fallDetectionStillnessDurationSeconds':
            draft.fallDetectionSettings.fallResponseDuration.inSeconds,
        'pathDeviationEnabled': draft.pathDeviationEnabled,
        'offlinePhysicalAlertEnabled': draft.offlinePhysicalAlertEnabled,
        'duressEnabled': draft.duressEnabled,
        'completedChecklistItems': draft.completedChecklistItems.toList(),
        'startedAt': FieldValue.serverTimestamp(),
        'startedAtLocal': now.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      });

      await recordAchievementMetric(
        session: session,
        metricKey: 'hike_started',
      );
      if (draft.completedChecklistItems.isNotEmpty) {
        await recordAchievementMetric(
          session: session,
          metricKey: 'checklist_completed',
        );
      }

      try {
        final upcomingDoc = _upcomingHikes.doc();
        final participantPhones = [
          session.phoneNumber,
          ...draft.teamBuddies.map((b) => b.phoneNumber),
        ];
        final upcoming = UpcomingHike(
          id: upcomingDoc.id,
          sessionId: document.id,
          trailId: draft.trail.trailId,
          trailName: draft.trail.name,
          latitude: draft.trail.latitude,
          longitude: draft.trail.longitude,
          area: draft.trail.area,
          state: draft.trail.state,
          distanceKm: draft.trail.distanceKm,
          durationMinutes: draft.trail.estimatedDurationMinutes,
          difficulty: draft.trail.difficulty,
          startPointName: draft.startPointName,
          destinationName: draft.destinationName,
          departureTime: draft.departureTime,
          expectedReturnTime: draft.expectedReturnTime,
          hikeType: draft.hikeType.name,
          participantCount: participantPhones.length,
          creatorPhone: session.phoneNumber,
          createdAt: now,
          participantPhones: participantPhones,
        );
        await upcomingDoc.set({
          ...upcoming.toFirestore(),
          'creatorUserId': _userIdFor(session),
          'creatorName': session.username.trim(),
          'notificationRadiusKm': 20,
        });
      } catch (_) {
        // Best-effort: upcoming hike listing is non-critical.
      }

      try {
        final participantPhones = [
          session.phoneNumber,
          ...draft.teamBuddies.map((b) => b.phoneNumber),
        ];
        if (participantPhones.length > 1) {
          await createGroupChat(
            hikeSessionId: document.id,
            trailName: draft.trail.name,
            participantPhones: participantPhones,
            creatorPhone: session.phoneNumber,
          );
        }
      } catch (_) {
        // Best-effort: group chat creation is non-critical.
      }

      if (teamHikeSessionId.isNotEmpty) {
        await attachActiveHikeToTeamSession(
          session: session,
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
          safetySettings: safetySettings,
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
    required AppSession session,
    required String teamHikeSessionId,
  }) async {
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
      if (!_samePhone(current.hostPhoneNumber, session.phoneNumber)) {
        throw const HikerCircleFirebaseRepositoryException(
          'Only the host can start this team hike.',
        );
      }
      if (!current.everyoneReady) {
        throw const HikerCircleFirebaseRepositoryException(
          'Every participant must be ready before the host can start.',
        );
      }
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
    required AppSession session,
    required String teamHikeSessionId,
    required String activeHikeSessionId,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable || teamHikeSessionId.isEmpty) {
      return;
    }
    final reference = _teamHikeSessions.doc(teamHikeSessionId);
    await _resolvedFirestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final sessionIds = data['activeHikeSessionIdsByPhone'] is Map
          ? Map<String, dynamic>.from(
              data['activeHikeSessionIdsByPhone'] as Map,
            )
          : <String, dynamic>{};
      sessionIds[_phoneKeyFor(session.phoneNumber)] = activeHikeSessionId;
      transaction.set(reference, {
        if (_samePhone(
          session.phoneNumber,
          _stringFrom(data['hostPhoneNumber']),
        ))
          'activeHikeSessionId': activeHikeSessionId,
        'activeHikeSessionIdsByPhone': sessionIds,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    });
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
    final newlyIsolated = <TeamHikeParticipant>[];
    final updated = await _mutateTeamHikeSession(teamHikeSessionId, (
      current,
      now,
    ) {
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
      participants = participants.map((participant) {
        final location = participant.latestLocation;
        if (location == null || participants.length < 2) {
          return participant;
        }
        final nearestDistance = participants
            .where(
              (other) =>
                  !_samePhone(other.phoneNumber, participant.phoneNumber) &&
                  other.latestLocation != null,
            )
            .map((other) => location.distanceTo(other.latestLocation!))
            .fold<double>(
              double.infinity,
              (nearest, distance) => distance < nearest ? distance : nearest,
            );
        final threshold =
            (participant.safetySettings['separationDistanceMeters'] as num?)
                ?.toDouble() ??
            150;
        final graceSeconds =
            (participant.safetySettings['isolationGraceSeconds'] as num?)
                ?.toInt() ??
            180;
        if (!nearestDistance.isFinite || nearestDistance <= threshold) {
          return participant.copyWith(
            clearIsolatedSince: true,
            separationAlertActive: false,
          );
        }
        final isolatedSince = participant.isolatedSince ?? now;
        final shouldAlert =
            !participant.separationAlertActive &&
            now.difference(isolatedSince).inSeconds >= graceSeconds;
        final next = participant.copyWith(
          isolatedSince: isolatedSince,
          separationAlertActive:
              participant.separationAlertActive || shouldAlert,
        );
        if (shouldAlert) {
          newlyIsolated.add(next);
        }
        return next;
      }).toList();
      return current.copyWith(
        phase: TeamHikePhase.active,
        participants: participants,
        updatedAt: now,
      );
    });
    for (final participant in newlyIsolated) {
      await _queueTeamStatusOutbox(
        teamSession: updated,
        type: 'team_hike_separation_alert',
        title: 'Teammate separation alert',
        body:
            '${participant.buddy.shortName} may be isolated from the team. Check the team map and send an OK ping.',
      );
    }
    return updated;
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
    await recordAchievementMetric(
      session: session,
      metricKey: 'check_in_completed',
    );
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
      'monitoringExpected': false,
      'monitoringLifecycleState': 'completed',
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
    await recordAchievementMetric(
      session: session,
      metricKey: 'hike_completed',
    );
    if (activeHike.teamHikeSessionId.isNotEmpty) {
      await recordAchievementMetric(
        session: session,
        metricKey: 'team_hike_completed',
      );
    }
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
    final author = await _communityAuthorSnapshot(session);
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
      ...author,
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
    await recordAchievementMetric(
      session: session,
      metricKey: 'community_post_created',
    );
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
    final author = await _communityAuthorSnapshot(session);
    await document.set({
      'postId': document.id,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      ...author,
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
    await recordAchievementMetric(
      session: session,
      metricKey: 'community_post_created',
    );
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
      return _hydrateCommunityAuthorLevels(
        snapshot.docs.map((document) => document.data()).toList(),
      );
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
    final author = await _communityAuthorSnapshot(session);
    final batch = _resolvedFirestore.batch();
    batch.set(comment, {
      'commentId': comment.id,
      'postId': postId,
      'authorId': _userIdFor(session),
      'authorPhoneNumber': session.phoneNumber,
      ...author,
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
      return _hydrateCommunityAuthorLevels(
        snapshot.docs.map((document) => document.data()).toList(),
      );
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

  String newTrailIdForName(String name) => _newTrailId(name);

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
    final reporterUserId = _stringFrom(report['reportedBy']);
    if (reporterUserId.isNotEmpty) {
      await recordAchievementMetricForUserId(
        userId: reporterUserId,
        metricKey: 'hazard_report_approved',
      );
    }
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
    await _applyAchievementProgress(
      userId: _userIdFor(session),
      achievementId: achievementId,
      increment: 1,
      forceUnlock: true,
      condition: condition,
    );
  }

  Future<void> recordAchievementMetric({
    required AppSession session,
    required String metricKey,
    int increment = 1,
  }) {
    return recordAchievementMetricForUserId(
      userId: _userIdFor(session),
      metricKey: metricKey,
      increment: increment,
    );
  }

  Future<void> recordAchievementMetricForUserId({
    required String userId,
    required String metricKey,
    int increment = 1,
  }) async {
    if (!_firebaseBootstrapResult.isAvailable ||
        userId.trim().isEmpty ||
        metricKey.trim().isEmpty ||
        increment <= 0) {
      return;
    }

    await ensureAchievementSeeds();
    final snapshot = await _achievements
        .where('metricKey', isEqualTo: metricKey.trim())
        .get();
    for (final definition in snapshot.docs) {
      if (definition.data()['isActive'] == false) {
        continue;
      }
      await _applyAchievementProgress(
        userId: userId.trim(),
        achievementId: definition.id,
        increment: increment,
      );
    }
  }

  Future<void> _applyAchievementProgress({
    required String userId,
    required String achievementId,
    required int increment,
    bool forceUnlock = false,
    String condition = '',
  }) async {
    final definitionReference = _achievements.doc(achievementId);
    final userAchievementId = '${userId}_$achievementId';
    final progressReference = _userAchievements.doc(userAchievementId);
    final userReference = _users.doc(userId);
    final now = DateTime.now().toUtc();

    await _resolvedFirestore.runTransaction((transaction) async {
      final definitionSnapshot = await transaction.get(definitionReference);
      final definition = definitionSnapshot.data();
      if (!definitionSnapshot.exists ||
          definition == null ||
          definition['isActive'] == false) {
        return;
      }

      final progressSnapshot = await transaction.get(progressReference);
      final existing = progressSnapshot.data() ?? const <String, dynamic>{};
      final wasUnlocked =
          existing['isUnlocked'] == true ||
          existing['awardedAt'] != null ||
          existing['awardedAtLocal'] != null;
      final rewardType = _stringFrom(definition['rewardType']) == 'cumulative'
          ? 'cumulative'
          : 'one_time';
      final targetCount = rewardType == 'one_time'
          ? 1
          : _intFrom(definition['targetCount']).clamp(1, 1000000000);
      final previousProgress = _intFrom(
        existing['progressCount'],
      ).clamp(0, targetCount);
      final nextProgress =
          wasUnlocked || forceUnlock || rewardType == 'one_time'
          ? targetCount
          : (previousProgress + increment).clamp(0, targetCount);
      final isUnlocked = wasUnlocked || nextProgress >= targetCount;
      final rewardPoints = _intFrom(
        definition['rewardPoints'],
      ).clamp(0, 1000000000);
      final newlyUnlocked = !wasUnlocked && isUnlocked;
      final existingPointsAwarded = _intFrom(existing['pointsAwarded']);
      final userSnapshot = newlyUnlocked
          ? await transaction.get(userReference)
          : null;

      transaction.set(progressReference, {
        'userAchievementId': userAchievementId,
        'userId': userId,
        'achievementId': achievementId,
        'achievementTitle': _stringFrom(definition['title']),
        'rewardType': rewardType,
        'metricKey': _stringFrom(definition['metricKey']),
        'targetCount': targetCount,
        'progressCount': nextProgress,
        'isUnlocked': isUnlocked,
        if (condition.trim().isNotEmpty) 'condition': condition.trim(),
        if (newlyUnlocked) ...{
          'pointsAwarded': rewardPoints,
          'awardedAt': FieldValue.serverTimestamp(),
          'awardedAtLocal': now.toIso8601String(),
        } else if (wasUnlocked && existingPointsAwarded > 0)
          'pointsAwarded': existingPointsAwarded,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));

      if (!newlyUnlocked) {
        return;
      }

      final currentPoints = _intFrom(
        userSnapshot?.data()?['achievementPoints'],
      );
      final totalPoints = currentPoints + rewardPoints;
      final level = HikerLevel.fromPoints(totalPoints);
      transaction.set(userReference, {
        'achievementPoints': totalPoints,
        'hikerLevel': level.number,
        'hikerLevelName': level.name,
        'hikerLevelBadge': level.badgeLabel,
        'achievementSummaryUpdatedAt': FieldValue.serverTimestamp(),
        'achievementSummaryUpdatedAtLocal': now.toIso8601String(),
      }, SetOptions(merge: true));
    });
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

      final rows = _achievementProgressFrom(
        achievements: achievements.isEmpty
            ? _achievementSeedRows()
            : achievements,
        userAwardsByAchievementId: awardsByAchievementId,
      );
      unawaited(_syncUserAchievementSummary(userId: userId, rows: rows));
      return rows;
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

    final snapshots = await Future.wait(
      _achievementSeeds.keys.map((id) => _achievements.doc(id).get()),
    );
    final batch = _resolvedFirestore.batch();
    for (var index = 0; index < snapshots.length; index++) {
      final entry = _achievementSeeds.entries.elementAt(index);
      final snapshot = snapshots[index];
      final existing = snapshot.data() ?? const <String, dynamic>{};
      final missingValues = <String, Object>{
        for (final value in entry.value.entries)
          if (!existing.containsKey(value.key)) value.key: value.value,
      };
      if (!snapshot.exists) {
        batch.set(_achievements.doc(entry.key), {
          'achievementId': entry.key,
          ...entry.value,
          'rewardsSafeBehaviour': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (missingValues.isNotEmpty) {
        batch.set(_achievements.doc(entry.key), {
          ...missingValues,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> loadAdminAchievements({
    required AppSession session,
  }) async {
    _throwIfAdminUnavailable(session);
    await ensureAchievementSeeds();
    final snapshot = await _achievements.orderBy('sortOrder').get();
    return snapshot.docs
        .map((document) => {'achievementId': document.id, ...document.data()})
        .toList();
  }

  Future<String> saveAchievementByAdmin({
    required AppSession session,
    required Map<String, dynamic> achievement,
    String achievementId = '',
  }) async {
    _throwIfAdminUnavailable(session);
    final title = _stringFrom(achievement['title']).trim();
    final condition = _stringFrom(achievement['condition']).trim();
    final metricKey = _stringFrom(achievement['metricKey']).trim();
    if (title.isEmpty || condition.isEmpty || metricKey.isEmpty) {
      throw const HikerCircleFirebaseRepositoryException(
        'Title, requirement, and progress metric are required.',
      );
    }
    final rewardType = _stringFrom(achievement['rewardType']) == 'cumulative'
        ? 'cumulative'
        : 'one_time';
    final rewardPoints = _intFrom(
      achievement['rewardPoints'],
    ).clamp(1, 1000000);
    final targetCount = rewardType == 'one_time'
        ? 1
        : _intFrom(achievement['targetCount']).clamp(1, 1000000000);
    var id = achievementId.trim();
    if (id.isEmpty) {
      final slug = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      id = slug.isEmpty ? 'achievement' : slug;
      if ((await _achievements.doc(id).get()).exists) {
        id = '${id}_${DateTime.now().millisecondsSinceEpoch}';
      }
    }
    final now = DateTime.now().toUtc();
    await _achievements.doc(id).set({
      'achievementId': id,
      'title': title,
      'condition': condition,
      'category': _stringFrom(achievement['category']).trim().isEmpty
          ? 'Hiking'
          : _stringFrom(achievement['category']).trim(),
      'iconName': _stringFrom(achievement['iconName']).trim().isEmpty
          ? 'emoji_events'
          : _stringFrom(achievement['iconName']).trim(),
      'rewardPoints': rewardPoints,
      'rewardType': rewardType,
      'metricKey': metricKey,
      'targetCount': targetCount,
      'isActive': achievement['isActive'] != false,
      'sortOrder': _intFrom(achievement['sortOrder']),
      'accentColorValue': _intFrom(achievement['accentColorValue']) == 0
          ? 0xFF34A853
          : _intFrom(achievement['accentColorValue']),
      'rewardsSafeBehaviour': true,
      'updatedByAdminId': _userIdFor(session),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': now.toIso8601String(),
      if (achievementId.trim().isEmpty) ...{
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtLocal': now.toIso8601String(),
      },
    }, SetOptions(merge: true));
    return id;
  }

  Future<void> setAchievementActiveByAdmin({
    required AppSession session,
    required String achievementId,
    required bool isActive,
  }) async {
    _throwIfAdminUnavailable(session);
    if (achievementId.trim().isEmpty) {
      return;
    }
    await _achievements.doc(achievementId.trim()).set({
      'isActive': isActive,
      'updatedByAdminId': _userIdFor(session),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
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
    final rows = achievements
        .map((achievement) {
          final achievementId = _stringFrom(achievement['achievementId']);
          final award = userAwardsByAchievementId[achievementId];
          final isActive = achievement['isActive'] != false;
          if (!isActive && award == null) {
            return <String, dynamic>{};
          }
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

  Future<void> _syncUserAchievementSummary({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    try {
      final points = rows.fold<int>(
        0,
        (total, row) =>
            total +
            (row['isUnlocked'] == true ? _intFrom(row['pointsAwarded']) : 0),
      );
      final level = HikerLevel.fromPoints(points);
      await _users.doc(userId).set({
        'achievementPoints': points,
        'hikerLevel': level.number,
        'hikerLevelName': level.name,
        'hikerLevelBadge': level.badgeLabel,
        'achievementSummaryUpdatedAt': FieldValue.serverTimestamp(),
        'achievementSummaryUpdatedAtLocal': DateTime.now()
            .toUtc()
            .toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // The achievement list is still useful if the profile summary cannot sync.
    }
  }

  Future<Map<String, dynamic>> _communityAuthorSnapshot(
    AppSession session,
  ) async {
    var points = 0;
    var storedUsername = '';
    try {
      final snapshot = await _users.doc(_userIdFor(session)).get();
      final data = snapshot.data();
      points = _intFrom(data?['achievementPoints']);
      storedUsername = _stringFrom(data?['username']).trim();
      final profile = data?['profile'];
      if (storedUsername.isEmpty && profile is Map) {
        storedUsername = _stringFrom(profile['username']).trim();
      }
    } catch (_) {
      // Fall back to the authenticated session snapshot.
    }
    final level = HikerLevel.fromPoints(points);
    final displayName = session.username.trim().isNotEmpty
        ? session.username.trim()
        : storedUsername.isNotEmpty
        ? storedUsername
        : 'Hiker';
    return {
      'authorName': displayName,
      'authorHandle': _handleForPhone(session.phoneNumber),
      'authorAchievementPoints': points,
      'authorLevel': level.number,
      'authorLevelName': level.name,
      'authorLevelBadge': level.badgeLabel,
    };
  }

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
      final snapshots = await Future.wait(
        authorIds.map((id) => _users.doc(id).get()),
      );
      final usersById = <String, Map<String, dynamic>>{
        for (final snapshot in snapshots)
          if (snapshot.data() != null) snapshot.id: snapshot.data()!,
      };
      return rows.map((row) {
        final user = usersById[_stringFrom(row['authorId'])];
        if (user == null) {
          return row;
        }
        final points = _intFrom(user['achievementPoints']);
        final level = HikerLevel.fromPoints(points);
        var username = _stringFrom(user['username']).trim();
        final profile = user['profile'];
        if (username.isEmpty && profile is Map) {
          username = _stringFrom(profile['username']).trim();
        }
        return {
          ...row,
          if (username.isNotEmpty) 'authorName': username,
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
        name: session.username.trim().isEmpty
            ? _handleForPhone(session.phoneNumber)
            : session.username.trim(),
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
      coverImageUrls: _coverImageUrlsFrom(data),
      checkpoints: checkpoints,
      weather: weatherFromFirestore(data['weather']),
      hazards: _listOfMaps(
        data['hazards'],
      ).map(_hazardFromFirestore).whereType<TrailHazard>().toList(),
      routeEncodedPolyline: _nullableStringFrom(data['routeEncodedPolyline']),
      routeCheckpointsHash: _nullableStringFrom(data['routeCheckpointsHash']),
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

  TrailWeather weatherFromFirestore(Object? value) {
    final data = value is Map ? Map<String, dynamic>.from(value) : {};
    final hourlyData = data['hourlyForecast'];
    return TrailWeather(
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

  int? _nullableIntFrom(Object? value) {
    return value is num ? value.toInt() : null;
  }

  double? _nullableDoubleFrom(Object? value) {
    return value is num ? value.toDouble() : null;
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

  List<String> _coverImageUrlsFrom(Map<String, dynamic> data) {
    final raw = data['coverImageUrl'];
    if (raw is List) {
      return raw.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    }
    final legacy = _stringFrom(raw);
    return legacy.isNotEmpty ? [legacy] : const [];
  }

  String? _nullableStringFrom(Object? value) {
    return value is String ? value : null;
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

  String _safeStorageFileName(String fileName, int index) {
    final normalized = fileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'trail_image_$index.jpg' : normalized;
  }

  String _contentTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
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
