import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../home/Model/hike_session_models.dart';

class ExpiredHikesCursor {
  const ExpiredHikesCursor({
    required this.departureTimeLocal,
    required this.hikeId,
  });
  final String departureTimeLocal;
  final String hikeId;

  Map<String, dynamic> toMap() => {
    'departureTimeLocal': departureTimeLocal,
    'hikeId': hikeId,
  };

  static ExpiredHikesCursor? fromValue(Object? value) {
    if (value is! Map) return null;
    final time = value['departureTimeLocal'];
    final id = value['hikeId'];
    if (time is! String ||
        DateTime.tryParse(time) == null ||
        id is! String ||
        id.isEmpty) {
      return null;
    }
    return ExpiredHikesCursor(departureTimeLocal: time, hikeId: id);
  }
}

class ExpiredHikesPage {
  const ExpiredHikesPage({
    required this.hikes,
    this.nextCursor,
    this.isFromCache = false,
  });
  final List<UpcomingHike> hikes;
  final ExpiredHikesCursor? nextCursor;
  final bool isFromCache;

  factory ExpiredHikesPage.fromMap(
    Map<String, dynamic> data, {
    bool isFromCache = false,
  }) {
    final rawHikes = data['hikes'];
    if (rawHikes is! List) {
      throw const FormatException('Expired hike list is missing.');
    }
    final hikes = <UpcomingHike>[];
    for (final raw in rawHikes.whereType<Map>()) {
      final id = raw['hikeId'];
      if (id is! String || id.trim().isEmpty) continue;
      final departure = raw['departureTimeLocal'];
      if (departure is! String || DateTime.tryParse(departure) == null) {
        continue;
      }
      try {
        hikes.add(
          UpcomingHike.fromFirestore(id, Map<String, dynamic>.from(raw)),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return ExpiredHikesPage(
      hikes: List.unmodifiable(hikes),
      nextCursor: ExpiredHikesCursor.fromValue(data['nextCursor']),
      isFromCache: isFromCache,
    );
  }
}

class ExpiredHikesRepository {
  ExpiredHikesRepository({
    FirebaseFunctions? functions,
    LocalSessionDatabase? localDatabase,
    Duration cloudTimeout = const Duration(seconds: 8),
  }) : _functions = functions,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _cloudTimeout = cloudTimeout;

  final FirebaseFunctions? _functions;
  final LocalSessionDatabase _localDatabase;
  final Duration _cloudTimeout;

  Future<ExpiredHikesPage> loadPage({
    required String ownerPhoneNumber,
    ExpiredHikesCursor? cursor,
    int limit = 30,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return const ExpiredHikesPage(hikes: []);
    final pageKey = jsonEncode({
      'limit': limit.clamp(1, 200),
      'cursor': cursor?.toMap(),
    });
    LocalCachedEntity? cached;
    try {
      cached = await _localDatabase.loadCachedEntity(
        ownerPhoneNumber: owner,
        entityType: 'expired_hike_history_page',
        entityId: pageKey,
        includeExpired: true,
      );
    } catch (_) {
      // An unavailable local cache must not prevent loading cloud history.
    }
    try {
      final data = await fetchCloudPage({
        'limit': limit.clamp(1, 200),
        if (cursor != null) 'cursor': cursor.toMap(),
      }).timeout(_cloudTimeout);
      if (data['ownerPhoneNumber'] != owner) {
        throw const FormatException('The history belongs to another account.');
      }
      final page = ExpiredHikesPage.fromMap(data);
      try {
        await _localDatabase.saveCachedEntity(
          LocalCachedEntity(
            ownerPhoneNumber: owner,
            entityType: 'expired_hike_history_page',
            entityId: pageKey,
            parentId: '',
            payload: data,
            cachedAt: DateTime.now().toUtc(),
          ),
        );
      } catch (_) {
        // Successfully loaded history is still usable if caching fails.
      }
      return page;
    } catch (_) {
      if (cached != null) {
        try {
          return ExpiredHikesPage.fromMap(cached.payload, isFromCache: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  @protected
  Future<Map<String, dynamic>> fetchCloudPage(
    Map<String, dynamic> request,
  ) async {
    final response = await (_functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          'listExpiredScheduledHikes',
          options: HttpsCallableOptions(timeout: _cloudTimeout),
        )
        .call<Map<String, dynamic>>(request);
    return response.data;
  }
}
