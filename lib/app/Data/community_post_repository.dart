// Community post repository converts compact cloud documents into UI views and coordinates account-
// scoped cache, drafts, uploads and reactions.
part of 'hiker_circle_firebase_repository.dart';

/// Computes post map.
Map<String, dynamic> _postMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

/// Computes post millis.
int _postMillis(Object? value) => value is Timestamp
    ? value.millisecondsSinceEpoch
    : value is num
    ? value.toInt()
    : value is DateTime
    ? value.millisecondsSinceEpoch
    : DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;

/// Presentation aliases are derived here, never stored back into Firestore.
@visibleForTesting
Map<String, dynamic> communityPostViewData(
  Map<String, dynamic> data, {
  required String postId,
  String viewerId = '',
  bool liked = false,
}) {
  final author = _postMap(data['author']);
  final trail = _postMap(data['trail']);
  final hike = _postMap(data['hike']);
  final images = data['images'] is List
      ? (data['images'] as List).map(_postMap).toList()
      : <Map<String, dynamic>>[];
  final created = _postMillis(data['createdAt'] ?? data['createdAtMillis']);
  final points = data['authorAchievementPoints'] is num
      ? (data['authorAchievementPoints'] as num).toInt()
      : 0;
  final level = HikerLevel.fromPoints(points);
  return {
    ...data,
    'postId': postId,
    'authorName': author['name'] ?? data['authorName'] ?? 'Hiker',
    'authorPhotoURL': author['photoURL'] ?? data['authorPhotoURL'] ?? '',
    'authorPhoneNumber': data['authorPhoneNumber'] ?? '',
    'authorHandle': data['authorHandle'] ?? '',
    'authorAchievementPoints': points,
    'authorLevel': level.number,
    'authorLevelName': level.name,
    'authorLevelBadge': level.badgeLabel,
    'images': images,
    'imageUrls': images
        .map((image) => image['url'])
        .whereType<String>()
        .toList(),
    'trailId': trail['id'] ?? '',
    'trailName': trail['name'] ?? '',
    'sessionId': hike['sessionId'] ?? '',
    'routeCaptureId': hike['sessionId'] ?? '',
    'postType': data['kind'] == 'hike'
        ? (hike['state'] == 'active' ? 'active_hike_update' : 'completed_hike')
        : 'community_note',
    'hikeState': hike['state'] ?? '',
    for (final key in [
      'distanceKm',
      'durationMinutes',
      'checkIns',
      'manualPins',
      'routePointCount',
      'highestAltitudeMeters',
    ])
      if (hike.containsKey(key)) key: hike[key],
    'routePreviewPoints': hike['routePreview'] ?? [],
    'createdAtMillis': created,
    'updatedAtMillis': _postMillis(
      data['updatedAt'] ?? data['updatedAtMillis'] ?? created,
    ),
    'createdAtLocal': DateTime.fromMillisecondsSinceEpoch(
      created,
      isUtc: true,
    ).toIso8601String(),
    'isLiked': liked,
    'isOwnPost': viewerId.isNotEmpty && data['authorId'] == viewerId,
    if (data['moderation'] is Map) ...{
      'moderationStatus': (data['moderation'] as Map)['status'],
      'moderationReason': (data['moderation'] as Map)['reason'],
    },
  };
}

/// Computes community comment view.
Map<String, dynamic> _communityCommentView(
  Map<String, dynamic> data,
  String id,
  String postId,
) {
  final author = _postMap(data['author']);
  final created = _postMillis(data['createdAt'] ?? data['createdAtMillis']);
  final points = data['authorAchievementPoints'] is num
      ? (data['authorAchievementPoints'] as num).toInt()
      : 0;
  final level = HikerLevel.fromPoints(points);
  return {
    ...data,
    'postId': postId,
    'commentId': id,
    'authorName': author['name'] ?? data['authorName'] ?? 'Hiker',
    'authorPhotoURL': author['photoURL'] ?? data['authorPhotoURL'] ?? '',
    'authorPhoneNumber': data['authorPhoneNumber'] ?? '',
    'authorHandle': data['authorHandle'] ?? '',
    'authorAchievementPoints': points,
    'authorLevel': level.number,
    'authorLevelName': level.name,
    'authorLevelBadge': level.badgeLabel,
    'createdAtMillis': created,
    'createdAtLocal': DateTime.fromMillisecondsSinceEpoch(
      created,
      isUtc: true,
    ).toIso8601String(),
    'updatedAtMillis': _postMillis(
      data['updatedAt'] ?? data['updatedAtMillis'] ?? created,
    ),
  };
}

/// Computes community call.
Future<Map<String, dynamic>> _communityCall(
  HikerCircleFirebaseRepository r,
  String name,
  Map<String, dynamic> payload,
) async {
  r._throwIfFirebaseUnavailable();
  try {
    final response = await r._resolvedFunctions
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call(payload);
    if (response.data is! Map) {
      throw const HikerCircleFirebaseRepositoryException(
        'The community server returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  } on FirebaseFunctionsException catch (error) {
    throw HikerCircleFirebaseRepositoryException(
      error.message ??
          'Unable to update this community post. Please try again.',
    );
  }
}

/// Computes community account.
String _communityAccount(HikerCircleFirebaseRepository r, AppSession session) {
  final uid = r._captureAccountUid(session);
  if (uid == null) {
    throw const HikerCircleFirebaseRepositoryException(
      'Sign in again to publish or react. Your draft is saved on this phone.',
    );
  }
  return uid;
}

// _publishCommunity reuses a stable post ID and content-addressed uploads so uncertain submissions
// can be retried safely.
/// Computes publish community.
Future<void> _publishCommunity(
  HikerCircleFirebaseRepository r, {
  required AppSession session,
  required String caption,
  required List<CommunityPostImageUpload> images,
  ActiveHikeSession? activeHike,
  HikeSummaryReport? summary,
  String? postId,
  String? trailId,
}) async {
  r._throwIfFirebaseUnavailable();
  final uid = _communityAccount(r, session);
  if (caption.length > 5000 ||
      images.length > 6 ||
      images.any(
        (image) => image.bytes.isEmpty || image.bytes.length > 10 * 1024 * 1024,
      )) {
    throw const HikerCircleFirebaseRepositoryException(
      'Use up to 5,000 characters and six photos, each up to 10 MB.',
    );
  }
  if (caption.trim().isEmpty && images.isEmpty && activeHike == null) {
    throw const HikerCircleFirebaseRepositoryException(
      'Add a message, a photo, or a hike.',
    );
  }
  final id = postId ?? r._communityPosts.doc().id;
  var hike = activeHike;
  if (hike != null) {
    if (summary == null) {
      final cloud = await r.ensureActiveHikeSessionInCloud(
        session: session,
        activeHike: hike,
      );
      if (!cloud.ensured && !cloud.terminal) {
        throw const HikerCircleFirebaseRepositoryException(
          'Sync this hike before sharing it. Your post is still saved.',
        );
      }
      if (cloud.status == 'abandoned') {
        throw const HikerCircleFirebaseRepositoryException(
          'An abandoned hike cannot be shared as a completed hike.',
        );
      }
      if (cloud.sessionId != hike.sessionId) {
        hike = hike.copyWith(sessionId: cloud.sessionId);
      }
    }
    r._requireSameAccount(session, uid);
    final capturedAt = DateTime.now().toUtc();
    await r._saveActualHikeRouteCapture(
      session: session,
      activeHike: hike,
      capturedAt: capturedAt,
      summary:
          summary ??
          HikeSummaryReport.fromActiveHike(
            activeHike: hike,
            endedAt: capturedAt,
          ),
    );
  }
  final paths = <String>[];
  try {
    for (final entry in images.indexed) {
      r._requireSameAccount(session, uid);
      final image = entry.$2;
      final name = r._safeStorageFileName(image.fileName, entry.$1);
      final digest = crypto.sha256.convert(image.bytes).toString();
      final reference = r._resolvedStorage.ref(
        'community_posts/$uid/$id/${entry.$1}_${digest}_$name',
      );
      var exists = false;
      try {
        final old = await reference.getMetadata();
        exists =
            old.size == image.bytes.length &&
            old.customMetadata?['ownerUserId'] == uid &&
            old.customMetadata?['postId'] == id;
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
      if (!exists) {
        await reference.putData(
          image.bytes,
          SettableMetadata(
            contentType: image.contentType ?? r._contentTypeForFileName(name),
            customMetadata: {'ownerUserId': uid, 'postId': id},
          ),
        );
      }
      paths.add(reference.fullPath);
    }
    r._requireSameAccount(session, uid);
    await _communityCall(r, 'publishCommunityPost', {
      'postId': id,
      'caption': caption.trim(),
      'imagePaths': paths,
      if (hike != null) 'sessionId': hike.sessionId,
      if (hike == null && trailId?.trim().isNotEmpty == true)
        'trailId': trailId!.trim(),
    });
    r._requireSameAccount(session, uid);
  } on FirebaseException catch (error) {
    // An uncertain publish must retain uploads: a retry uses the same ID/path.
    throw HikerCircleFirebaseRepositoryException(
      error.message ??
          'Unable to upload these photos. Your draft is saved; try again.',
    );
  }
}

// _readCommunityPosts hydrates viewer state and reconciles successful public feed refreshes before
// offline fallback.
/// Computes community posts.
Future<List<Map<String, dynamic>>> _readCommunityPosts(
  HikerCircleFirebaseRepository r, {
  AppSession? session,
  int limit = 20,
  String? afterPostId,
  String? authorId,
  bool admin = false,
}) async {
  final owner = session?.phoneNumber ?? '';
  final viewer = session == null ? '' : r._userIdFor(session);

  /// Computes same account.
  bool sameAccount() =>
      session == null ||
      !r._firebaseBootstrapResult.isAvailable ||
      r._accountStillMatches(session, viewer);

  /// Computes cached.
  Future<List<Map<String, dynamic>>> cached() async {
    if (!sameAccount()) return [];
    try {
      final rows = await r._localDatabase.loadCachedCommunityPosts(
        ownerPhoneNumber: owner,
        authorId: authorId,
        limit: limit,
        afterPostId: afterPostId,
      );
      if (!sameAccount()) return [];
      return rows
          .map(
            (row) => communityPostViewData(
              row,
              postId: row['postId'] as String,
              viewerId: viewer,
              liked: row['isLiked'] == true,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  if (!r._firebaseBootstrapResult.isAvailable) return cached();
  if (!sameAccount()) return [];
  try {
    Query<Map<String, dynamic>> query = r._communityPosts;
    if (authorId != null) {
      query = query.where('authorId', isEqualTo: authorId);
    } else if (!admin) {
      query = query.where('visibility', isEqualTo: 'public');
    }
    query = query
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (afterPostId != null) {
      final cursor = await r._communityPosts
          .doc(afterPostId)
          .get()
          .timeout(HikerCircleFirebaseRepository._firebaseReadTimeout);
      if (!cursor.exists) return [];
      query = query.startAfterDocument(cursor);
    }
    final result = await query
        .limit(limit.clamp(1, 100))
        .get()
        .timeout(HikerCircleFirebaseRepository._firebaseReadTimeout);
    final liked = <String>{};
    if (viewer.isNotEmpty) {
      final publicPosts = result.docs
          .where((post) => post.data()['visibility'] == 'public')
          .toList();
      final reactions = await Future.wait(
        publicPosts.map((post) async {
          try {
            return (await post.reference
                    .collection('reactions')
                    .doc(viewer)
                    .get())
                .exists;
          } on FirebaseException catch (error) {
            if (error.code == 'permission-denied' ||
                error.code == 'not-found') {
              return false;
            }
            rethrow;
          }
        }),
      );
      for (var i = 0; i < reactions.length; i++) {
        if (reactions[i]) liked.add(publicPosts[i].id);
      }
    }
    if (!sameAccount()) return [];
    final rows = await r._hydrateCommunityAuthorLevels(
      result.docs
          .map(
            (doc) => communityPostViewData(
              doc.data(),
              postId: doc.id,
              viewerId: viewer,
              liked: liked.contains(doc.id),
            ),
          )
          .toList(),
    );
    // JSON-safe canonical fields + a single normalized author record in SQLite.
    if (!sameAccount()) return [];
    try {
      for (final post in rows.where((post) => post['visibility'] != 'public')) {
        await r._localDatabase.removeCachedCommunityPost(
          post['postId'] as String,
        );
      }
      if (!sameAccount()) return [];
      await r._localDatabase.cacheCommunityPosts(
        rows
            .where((row) => row['visibility'] == 'public')
            .map(r._jsonSafeMap)
            .toList(),
        ownerPhoneNumber: owner,
        reconcileFirstPage: afterPostId == null && authorId == null && !admin,
        pageComplete: result.docs.length < limit.clamp(1, 100),
      );
    } catch (_) {
      /* A cache failure does not invalidate a successful online read. */
    }
    if (!sameAccount()) return [];
    return rows;
  } on FirebaseException catch (error) {
    if (!sameAccount()) return [];
    if (admin ||
        !{
          'unavailable',
          'deadline-exceeded',
          'network-request-failed',
          'unknown',
          'cancelled',
        }.contains(error.code)) {
      throw HikerCircleFirebaseRepositoryException(
        error.message ?? 'Unable to load community posts.',
      );
    }
    final fallback = await cached();
    if (fallback.isNotEmpty) return fallback;
    throw const HikerCircleFirebaseRepositoryException(
      'Unable to load posts. Check your connection and try again.',
    );
  } on TimeoutException {
    if (admin) {
      throw const HikerCircleFirebaseRepositoryException(
        'Moderation records could not load. Check your connection and retry.',
      );
    }
    final fallback = await cached();
    if (fallback.isNotEmpty || !sameAccount()) return fallback;
    throw const HikerCircleFirebaseRepositoryException(
      'Unable to load posts. Check your connection and try again.',
    );
  }
}

// _readCommunityComments paginates one thread and reconciles only the range confirmed by a
// successful refresh.
/// Computes community comments.
Future<List<Map<String, dynamic>>> _readCommunityComments(
  HikerCircleFirebaseRepository r,
  String postId, {
  String? afterCommentId,
  int limit = 50,
}) async {
  final uid = _communityCurrentUid(r);

  /// Computes same account.
  bool sameAccount() =>
      !r._firebaseBootstrapResult.isAvailable || _communityCurrentUid(r) == uid;

  /// Computes cached.
  Future<List<Map<String, dynamic>>> cached() async {
    if (!sameAccount()) return [];
    try {
      final rows = await r._localDatabase.loadCachedCommunityComments(
        postId,
        afterCommentId: afterCommentId,
        limit: limit,
      );
      return sameAccount()
          ? rows
                .map(
                  (row) => _communityCommentView(
                    row,
                    row['commentId'] as String,
                    postId,
                  ),
                )
                .toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  if (!r._firebaseBootstrapResult.isAvailable) return cached();
  try {
    final post = await r._communityPosts
        .doc(postId)
        .get()
        .timeout(HikerCircleFirebaseRepository._firebaseReadTimeout);
    if (!post.exists) {
      throw const HikerCircleFirebaseRepositoryException(
        'This post is no longer available.',
      );
    }
    Query<Map<String, dynamic>> query = r
        ._communityCommentsFor(postId)
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (afterCommentId != null) {
      final cursor = await r
          ._communityCommentsFor(postId)
          .doc(afterCommentId)
          .get();
      if (!cursor.exists) return [];
      query = query.startAfterDocument(cursor);
    }
    final result = await query
        .limit(limit.clamp(1, 100))
        .get()
        .timeout(HikerCircleFirebaseRepository._firebaseReadTimeout);
    final rows = await r._hydrateCommunityAuthorLevels(
      result.docs
          .map((doc) => _communityCommentView(doc.data(), doc.id, postId))
          .toList(),
    );
    if (!sameAccount()) return [];
    if (post.data()?['visibility'] == 'public') {
      try {
        await r._localDatabase.cacheCommunityComments(
          postId,
          rows.map(r._jsonSafeMap).toList(),
          reconcileFirstPage: afterCommentId == null,
          pageComplete: result.docs.length < limit.clamp(1, 100),
        );
      } catch (_) {
        /* Online replies remain available if the cache cannot be saved. */
      }
    }
    if (!sameAccount()) return [];
    return rows;
  } on FirebaseException catch (error) {
    if (!sameAccount()) return [];
    if (!{
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
      'unknown',
      'cancelled',
    }.contains(error.code)) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        try {
          await r._localDatabase.removeCachedCommunityPost(postId);
        } catch (_) {}
      }
      throw const HikerCircleFirebaseRepositoryException(
        'This post or its replies are no longer available.',
      );
    }
    final fallback = await cached();
    if (fallback.isNotEmpty) return fallback;
    throw const HikerCircleFirebaseRepositoryException(
      'Unable to load replies. Please try again.',
    );
  } on TimeoutException {
    final fallback = await cached();
    if (fallback.isNotEmpty || !sameAccount()) return fallback;
    throw const HikerCircleFirebaseRepositoryException(
      'Unable to load replies. Please try again.',
    );
  }
}

/// Computes community current uid.
String _communityCurrentUid(HikerCircleFirebaseRepository r) {
  try {
    return r._authenticatedUid?.call() ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
  } catch (_) {
    return '';
  }
}

/// Loads community draft.
Future<CommunityPostDraftData?> _loadCommunityDraft(
  HikerCircleFirebaseRepository r,
  AppSession session,
  String key,
) async {
  final data = await r._localDatabase.loadCommunityDraft(
    ownerPhoneNumber: session.phoneNumber,
    draftKey: key,
  );
  if (data == null) return null;
  return CommunityPostDraftData(
    postId: data['postId'] as String,
    caption: data['caption'] as String,
    includeHike: data['includeHike'] == true,
    images: [
      for (final raw in data['images'] as List)
        CommunityPostImageUpload(
          bytes: (raw['bytes'] is Uint8List)
              ? raw['bytes'] as Uint8List
              : Uint8List.fromList(List<int>.from(raw['bytes'] as List)),
          fileName: raw['fileName'] as String,
          contentType: raw['contentType'] as String?,
        ),
    ],
  );
}
