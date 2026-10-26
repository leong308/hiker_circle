// ExpiredHikesRepository pages through expired hike records and their server-provided details.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../home/Model/hike_session_models.dart';
import '../Model/expired_hike_eligibility.dart';

/// Carry the paging cursor separately from the expired-hike result rows.
class ExpiredHikesCursor {
  /// Creates expired hikes cursor.
  const ExpiredHikesCursor({
    required this.departureTimeLocal,
    required this.hikeId,
  });
  final String departureTimeLocal;
  final String hikeId;

  /// Serializes this value as a map.
  Map<String, dynamic> toMap() => {
    'departureTimeLocal': departureTimeLocal,
    'hikeId': hikeId,
  };

  /// Creates from value.
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

/// Represents expired hikes page.
class ExpiredHikesPage {
  /// Creates expired hikes page.
  const ExpiredHikesPage({
    required this.hikes,
    this.nextCursor,
    this.isFromCache = false,
  });
  final List<UpcomingHike> hikes;
  final ExpiredHikesCursor? nextCursor;
  final bool isFromCache;

  /// Creates expired hikes page from stored map data.
  factory ExpiredHikesPage.fromMap(
    Map<String, dynamic> data, {
    bool isFromCache = false,
    DateTime? now,
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
      if (!isExpiredScheduledHikeData(
        Map<String, dynamic>.from(raw),
        ownerPhoneNumber: '${data['ownerPhoneNumber'] ?? ''}',
        now: now ?? DateTime.now(),
      )) {
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

/// Represents expired hikes repository.
class ExpiredHikesRepository {
  /// Creates expired hikes repository.
  ExpiredHikesRepository({
    FirebaseFunctions? functions,
    LocalSessionDatabase? localDatabase,
    Duration cloudTimeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _functions = functions,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _cloudTimeout = cloudTimeout,
       _now = now ?? DateTime.now;

  final FirebaseFunctions? _functions;
  final LocalSessionDatabase _localDatabase;
  final Duration _cloudTimeout;
  final DateTime Function() _now;

  /// Loads page.
  Future<ExpiredHikesPage> loadPage({
    required String ownerPhoneNumber,
    ExpiredHikesCursor? cursor,
    int limit = 30,
  }) async {
    final owner = ownerPhoneNumber.trim();
    if (owner.isEmpty) return const ExpiredHikesPage(hikes: []);
    final localExpired = <UpcomingHike>[];
    final consumedIds = <String>{};
    try {
      final states = await _localDatabase.loadPlannedHikeStates(
        ownerPhoneNumber: owner,
      );
      for (final state in states) {
        if (state.ownerPhoneNumber != owner) continue;
        final hike = state.upcomingHike;
        if (state.isConsumed) {
          consumedIds.add(hike.id);
        } else if (!hike.visibleUntil.isAfter(_now().toUtc()) &&
            (!hike.isDeleted ||
                hike.deletedReason == 'departure_time_expired')) {
          localExpired.add(hike);
        }
      }
    } catch (_) {
      // Cloud history remains usable when the local planning store is unavailable.
    }

    /// Computes merge local.
    ExpiredHikesPage mergeLocal(ExpiredHikesPage page) {
      final byId = {
        for (final hike in page.hikes)
          if (!consumedIds.contains(hike.id)) hike.id: hike,
      };
      if (cursor == null) {
        for (final hike in localExpired) {
          final remote = byId[hike.id];
          byId[hike.id] = remote == null
              ? hike
              : remote.draft == null && hike.draft != null
              ? remote.withDraft(hike.draft!)
              : remote;
        }
      }
      final rows = byId.values.toList()
        ..sort((a, b) {
          final time = b.departureTime.compareTo(a.departureTime);
          return time != 0 ? time : b.id.compareTo(a.id);
        });
      return ExpiredHikesPage(
        hikes: List.unmodifiable(rows),
        nextCursor: page.nextCursor,
        isFromCache: page.isFromCache,
      );
    }

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
      final page = ExpiredHikesPage.fromMap(data, now: _now());
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
      return mergeLocal(page);
    } catch (_) {
      if (cached != null) {
        try {
          return mergeLocal(
            ExpiredHikesPage.fromMap(
              cached.payload,
              isFromCache: true,
              now: _now(),
            ),
          );
        } catch (_) {}
      }
      if (cursor == null && localExpired.isNotEmpty) {
        return mergeLocal(const ExpiredHikesPage(hikes: [], isFromCache: true));
      }
      rethrow;
    }
  }

  /// Fetches cloud page.
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
