// LocalCommunityStorage normalizes public posts/authors while isolating viewer reactions, composer
// drafts and photo bytes by account.
part of 'local_session_database.dart';

// Community data has one canonical cached copy. Viewer reactions and unfinished
// drafts are account scoped; hydrated author/level aliases are never duplicated
// inside every post/comment payload.
/// Creates community tables.
Future<void> _createCommunityTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS community_authors (
    user_id TEXT PRIMARY KEY, name TEXT NOT NULL, photo_url TEXT NOT NULL DEFAULT '',
    phone_number TEXT NOT NULL DEFAULT '', handle TEXT NOT NULL DEFAULT '',
    achievement_points INTEGER NOT NULL DEFAULT 0, cached_at_millis INTEGER NOT NULL
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_posts (
    post_id TEXT PRIMARY KEY, author_id TEXT NOT NULL, caption TEXT NOT NULL,
    kind TEXT NOT NULL, images_json TEXT NOT NULL DEFAULT '[]',
    trail_json TEXT, hike_json TEXT, visibility TEXT NOT NULL DEFAULT 'public',
    like_count INTEGER NOT NULL DEFAULT 0, comment_count INTEGER NOT NULL DEFAULT 0,
    created_at_millis INTEGER NOT NULL, updated_at_millis INTEGER NOT NULL,
    cached_at_millis INTEGER NOT NULL,
    FOREIGN KEY (author_id) REFERENCES community_authors(user_id)
  )''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_community_posts_feed
    ON community_posts(visibility, created_at_millis DESC, post_id DESC)''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_community_posts_author
    ON community_posts(author_id, created_at_millis DESC, post_id DESC)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_comments (
    post_id TEXT NOT NULL, comment_id TEXT NOT NULL, author_id TEXT NOT NULL,
    body TEXT NOT NULL, created_at_millis INTEGER NOT NULL,
    updated_at_millis INTEGER NOT NULL, cached_at_millis INTEGER NOT NULL,
    PRIMARY KEY (post_id, comment_id),
    FOREIGN KEY (post_id) REFERENCES community_posts(post_id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES community_authors(user_id)
  )''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_community_comments_thread
    ON community_comments(post_id, created_at_millis, comment_id)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_reactions (
    owner_phone_number TEXT NOT NULL, post_id TEXT NOT NULL,
    liked INTEGER NOT NULL DEFAULT 0, updated_at_millis INTEGER NOT NULL,
    PRIMARY KEY (owner_phone_number, post_id),
    FOREIGN KEY (post_id) REFERENCES community_posts(post_id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_drafts (
    owner_phone_number TEXT NOT NULL, draft_key TEXT NOT NULL, post_id TEXT NOT NULL,
    caption TEXT NOT NULL DEFAULT '', include_hike INTEGER NOT NULL DEFAULT 0,
    updated_at_millis INTEGER NOT NULL,
    PRIMARY KEY (owner_phone_number, draft_key)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_draft_images (
    owner_phone_number TEXT NOT NULL, draft_key TEXT NOT NULL, image_key TEXT NOT NULL,
    position INTEGER NOT NULL, file_name TEXT NOT NULL, content_type TEXT,
    bytes BLOB NOT NULL,
    PRIMARY KEY (owner_phone_number, draft_key, image_key),
    FOREIGN KEY (owner_phone_number, draft_key)
      REFERENCES community_drafts(owner_phone_number, draft_key) ON DELETE CASCADE
  )''');
}

/// Computes community millis.
int _communityMillis(Object? value) {
  if (value is num) return value.toInt();
  if (value is DateTime) return value.millisecondsSinceEpoch;
  return DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ??
      0;
}

/// Computes community text.
String _communityText(Object? value) => value is String ? value : '';

/// Computes put community row.
Future<void> _putCommunityRow(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> values,
  String where,
  List<Object?> arguments,
) async {
  if (await db.update(table, values, where: where, whereArgs: arguments) == 0) {
    await db.insert(table, values);
  }
}

// _cacheCommunityAuthor merges the freshest profile while distinguishing verified clears from
// missing partial fields.
/// Computes cache community author.
Future<void> _cacheCommunityAuthor(
  DatabaseExecutor db,
  Map<String, dynamic> row,
) async {
  final id = _communityText(row['authorId']);
  if (id.isEmpty) return;
  final previous = await db.query(
    'community_authors',
    where: 'user_id=?',
    whereArgs: [id],
    limit: 1,
  );
  final old = previous.isEmpty ? <String, Object?>{} : previous.single;
  final cachedAt = row['authorCachedAtMillis'] is num
      ? (row['authorCachedAtMillis'] as num).toInt()
      : DateTime.now().millisecondsSinceEpoch;
  if (_communityMillis(old['cached_at_millis']) > cachedAt) return;

  /// Computes text.
  String text(String field, String column, [String fallback = '']) {
    if (row['authorProfileLoaded'] == true && row.containsKey(field)) {
      final value = _communityText(row[field]);
      return field == 'authorName' && value.isEmpty ? 'Hiker' : value;
    }
    if (_communityText(row[field]).isNotEmpty) return row[field] as String;
    return _communityText(old[column]).isNotEmpty
        ? old[column] as String
        : fallback;
  }

  final suppliedPoints = row['authorAchievementPoints'];
  final points =
      suppliedPoints is num &&
          (suppliedPoints > 0 ||
              row['authorProfileLoaded'] == true ||
              old.isEmpty)
      ? suppliedPoints.toInt()
      : _communityMillis(old['achievement_points']);
  await _putCommunityRow(
    db,
    'community_authors',
    {
      'user_id': id,
      'name': text('authorName', 'name', 'Hiker'),
      'photo_url': text('authorPhotoURL', 'photo_url'),
      'phone_number': text('authorPhoneNumber', 'phone_number'),
      'handle': text('authorHandle', 'handle'),
      'achievement_points': points,
      'cached_at_millis': cachedAt,
    },
    'user_id = ?',
    [id],
  );
}

/// Computes cache community post rows.
Future<void> _cacheCommunityPostRows(
  DatabaseExecutor db,
  List<Map<String, dynamic>> rows,
  String owner,
) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  // Process oldest first so the freshest author snapshot wins.
  for (final row in rows.reversed) {
    final id = _communityText(row['postId']);
    final authorId = _communityText(row['authorId']);
    if (id.isEmpty || authorId.isEmpty) continue;
    await _cacheCommunityAuthor(db, row);
    await _putCommunityRow(
      db,
      'community_posts',
      {
        'post_id': id,
        'author_id': authorId,
        'caption': _communityText(row['caption']),
        'kind': _communityText(row['kind']).isEmpty ? 'note' : row['kind'],
        'images_json': jsonEncode(row['images'] ?? []),
        'trail_json': row['trail'] is Map ? jsonEncode(row['trail']) : null,
        'hike_json': row['hike'] is Map ? jsonEncode(row['hike']) : null,
        'visibility': _communityText(row['visibility']).isEmpty
            ? 'public'
            : row['visibility'],
        'like_count': _communityMillis(row['likeCount']),
        'comment_count': _communityMillis(row['commentCount']),
        'created_at_millis': _communityMillis(
          row['createdAtMillis'] ?? row['createdAtLocal'],
        ),
        'updated_at_millis': _communityMillis(
          row['updatedAtMillis'] ??
              row['createdAtMillis'] ??
              row['createdAtLocal'],
        ),
        'cached_at_millis': now,
      },
      'post_id = ?',
      [id],
    );
    if (owner.isNotEmpty && row.containsKey('isLiked')) {
      await _putCommunityRow(
        db,
        'community_reactions',
        {
          'owner_phone_number': owner,
          'post_id': id,
          'liked': row['isLiked'] == true ? 1 : 0,
          'updated_at_millis': now,
        },
        'owner_phone_number = ? AND post_id = ?',
        [owner, id],
      );
    }
  }
}

/// Computes community cached view.
Map<String, dynamic> _communityCachedView(
  Map<String, Object?> row, {
  bool comment = false,
}) {
  final created = _communityMillis(row['created_at_millis']);
  final common = <String, dynamic>{
    'authorId': row['author_id'],
    'authorName': row['author_name'],
    'authorPhotoURL': row['author_photo_url'],
    'authorPhoneNumber': row['author_phone_number'],
    'authorHandle': row['author_handle'],
    'authorAchievementPoints': row['author_points'],
    'createdAtMillis': created,
    'createdAtLocal': DateTime.fromMillisecondsSinceEpoch(
      created,
      isUtc: true,
    ).toIso8601String(),
    'updatedAtMillis': row['updated_at_millis'],
  };
  if (comment) {
    return {
      ...common,
      'commentId': row['comment_id'],
      'postId': row['post_id'],
      'body': row['body'],
    };
  }
  final images = jsonDecode(row['images_json'] as String);
  final trail = row['trail_json'] is String
      ? jsonDecode(row['trail_json'] as String)
      : null;
  final hike = row['hike_json'] is String
      ? jsonDecode(row['hike_json'] as String)
      : null;
  return {
    ...common,
    'postId': row['post_id'],
    'caption': row['caption'],
    'kind': row['kind'],
    'images': images,
    if (trail != null) 'trail': trail,
    if (hike != null) 'hike': hike,
    'visibility': row['visibility'],
    'likeCount': row['like_count'],
    'commentCount': row['comment_count'],
    'isLiked': row['viewer_liked'] == 1,
  };
}

const _communityAuthorColumns =
    '''a.name AS author_name, a.photo_url AS author_photo_url,
  a.phone_number AS author_phone_number, a.handle AS author_handle,
  a.achievement_points AS author_points''';

/// Computes migrate community cache.
Future<void> _migrateCommunityCache(DatabaseExecutor db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='cached_entities'",
  );
  if (tables.isEmpty) return;
  final rows = await db.query(
    'cached_entities',
    where: 'entity_type IN (?, ?)',
    whereArgs: ['community_post', 'community_comment'],
    orderBy: 'cached_at ASC',
  );
  for (final row in rows) {
    Object? payload;
    try {
      payload = jsonDecode(row['payload_json'] as String);
    } on FormatException {
      continue;
    }
    if (payload is! Map) continue;
    final old = Map<String, dynamic>.from(payload);
    old['authorCachedAtMillis'] = _communityMillis(row['cached_at']);
    if (row['entity_type'] == 'community_post') {
      final sessionId = _communityText(old['sessionId']);
      final converted = {
        ...old,
        'postId': old['postId'] ?? row['entity_id'],
        'kind': sessionId.isEmpty ? 'note' : 'hike',
        'images': [
          for (final url in old['imageUrls'] as List? ?? []) {'url': url},
        ],
        if (_communityText(old['trailName']).isNotEmpty)
          'trail': {'id': old['trailId'] ?? '', 'name': old['trailName']},
        if (sessionId.isNotEmpty)
          'hike': {
            'sessionId': sessionId,
            'state': old['postType'] == 'active_hike_update'
                ? 'active'
                : 'completed',
            for (final key in [
              'distanceKm',
              'durationMinutes',
              'checkIns',
              'manualPins',
              'routePointCount',
            ])
              if (old[key] is num) key: old[key],
            if (old['routePreviewPoints'] is List)
              'routePreview': old['routePreviewPoints'],
          },
      };
      await _cacheCommunityPostRows(db, [
        converted,
      ], _communityText(row['owner_phone_number']));
    } else {
      await _cacheCommunityAuthor(db, old);
      final postId = _communityText(old['postId'] ?? row['parent_id']);
      final commentId = _communityText(old['commentId'] ?? row['entity_id']);
      final authorId = _communityText(old['authorId']);
      if (postId.isEmpty || commentId.isEmpty || authorId.isEmpty) continue;
      final created = _communityMillis(old['createdAtLocal']);
      await _putCommunityRow(
        db,
        'community_comments',
        {
          'post_id': postId,
          'comment_id': commentId,
          'author_id': authorId,
          'body': _communityText(old['body']),
          'created_at_millis': created,
          'updated_at_millis': created,
          'cached_at_millis': DateTime.now().millisecondsSinceEpoch,
        },
        'post_id = ? AND comment_id = ?',
        [postId, commentId],
      );
    }
  }
  await db.delete(
    'cached_entities',
    where: 'entity_type IN (?, ?)',
    whereArgs: ['community_post', 'community_comment'],
  );
}

/// Return only absent rows that a successful first-page response covered.
/// Older cached pages remain valid until a complete response proves otherwise.
Future<List<String>> _staleCommunityPageIds(
  DatabaseExecutor db, {
  required String table,
  required String idColumn,
  required String wireId,
  required List<Map<String, dynamic>> rows,
  required String scope,
  required List<Object?> scopeArgs,
  required bool pageComplete,
}) async {
  final ids = rows
      .where((row) => _communityText(row['authorId']).isNotEmpty)
      .map((row) => _communityText(row[wireId]))
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  if (!pageComplete && ids.isEmpty) return [];
  final clauses = <String>[scope];
  final args = <Object?>[...scopeArgs];
  final placeholders = List.filled(ids.length, '?').join(',');
  if (ids.isNotEmpty) {
    clauses.add('$idColumn NOT IN ($placeholders)');
    args.addAll(ids);
  }
  if (!pageComplete) {
    // Use SQLite's own collation, matching the feed/thread cursor queries.
    final oldest = await db.query(
      table,
      columns: [idColumn, 'created_at_millis'],
      where: '$scope AND $idColumn IN ($placeholders)',
      whereArgs: [...scopeArgs, ...ids],
      orderBy: 'created_at_millis ASC, $idColumn ASC',
      limit: 1,
    );
    if (oldest.isEmpty) return [];
    final boundary = oldest.single;
    clauses.add(
      '(created_at_millis > ? OR (created_at_millis = ? AND $idColumn >= ?))',
    );
    args.addAll([
      boundary['created_at_millis'],
      boundary['created_at_millis'],
      boundary[idColumn],
    ]);
  }
  final stale = await db.query(
    table,
    columns: [idColumn],
    where: clauses.join(' AND '),
    whereArgs: args,
  );
  return stale.map((row) => row[idColumn] as String).toList();
}

/// Provides helpers for `LocalSessionDatabase`.
extension LocalCommunityStorage on LocalSessionDatabase {
  /// Reconcile only successful public-feed first pages, never profile/admin lists.
  Future<void> cacheCommunityPosts(
    List<Map<String, dynamic>> rows, {
    String ownerPhoneNumber = '',
    bool reconcileFirstPage = false,
    bool pageComplete = false,
  }) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      await _cacheCommunityPostRows(tx, rows, ownerPhoneNumber.trim());
      if (reconcileFirstPage) {
        final stale = await _staleCommunityPageIds(
          tx,
          table: 'community_posts',
          idColumn: 'post_id',
          wireId: 'postId',
          rows: rows,
          scope: 'visibility = ?',
          scopeArgs: ['public'],
          pageComplete: pageComplete,
        );
        for (final postId in stale) {
          await _removeCommunityPost(tx, postId);
        }
      }
      final expired = await tx.rawQuery(
        '''SELECT post_id FROM community_posts
        ORDER BY cached_at_millis DESC, created_at_millis DESC LIMIT -1 OFFSET 200''',
      );
      for (final row in expired) {
        await _removeCommunityPost(tx, row['post_id'] as String);
      }
    });
  }

  /// Loads cached community posts.
  Future<List<Map<String, dynamic>>> loadCachedCommunityPosts({
    String ownerPhoneNumber = '',
    String? postId,
    String? authorId,
    String? afterPostId,
    int limit = 20,
  }) async {
    final db = await _openDatabase();
    final where = <String>[
      "p.visibility = 'public'",
      if (postId != null) 'p.post_id = ?',
      if (authorId != null) 'p.author_id = ?',
    ];
    final args = <Object?>[
      ownerPhoneNumber.trim(),
      if (postId != null) postId,
      if (authorId != null) authorId,
    ];
    if (afterPostId?.isNotEmpty == true) {
      final cursor = await db.query(
        'community_posts',
        columns: ['created_at_millis'],
        where: 'post_id = ?',
        whereArgs: [afterPostId],
      );
      if (cursor.isEmpty) return [];
      where.add(
        '(p.created_at_millis < ? OR (p.created_at_millis = ? AND p.post_id < ?))',
      );
      args.addAll([
        cursor.single['created_at_millis'],
        cursor.single['created_at_millis'],
        afterPostId,
      ]);
    }
    args.add(limit.clamp(1, 100));
    final rows = await db.rawQuery(
      '''SELECT p.*, $_communityAuthorColumns,
      COALESCE(r.liked, 0) AS viewer_liked FROM community_posts p
      JOIN community_authors a ON a.user_id = p.author_id
      LEFT JOIN community_reactions r ON r.post_id=p.post_id AND r.owner_phone_number=?
      WHERE ${where.join(' AND ')} ORDER BY p.created_at_millis DESC, p.post_id DESC LIMIT ?''',
      args,
    );
    return rows.map(_communityCachedView).toList();
  }

  // cacheCommunityComments reconciles one successful first-page range and preserves older pages
  // and other threads.
  /// Computes cache community comments.
  Future<void> cacheCommunityComments(
    String postId,
    List<Map<String, dynamic>> rows, {
    bool reconcileFirstPage = false,
    bool pageComplete = false,
  }) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      for (final row in rows.reversed) {
        final id = _communityText(row['commentId']);
        if (id.isEmpty || _communityText(row['authorId']).isEmpty) continue;
        await _cacheCommunityAuthor(tx, row);
        await _putCommunityRow(
          tx,
          'community_comments',
          {
            'post_id': postId,
            'comment_id': id,
            'author_id': row['authorId'],
            'body': _communityText(row['body']),
            'created_at_millis': _communityMillis(row['createdAtMillis']),
            'updated_at_millis': _communityMillis(
              row['updatedAtMillis'] ?? row['createdAtMillis'],
            ),
            'cached_at_millis': DateTime.now().millisecondsSinceEpoch,
          },
          'post_id = ? AND comment_id = ?',
          [postId, id],
        );
      }
      if (reconcileFirstPage) {
        final stale = await _staleCommunityPageIds(
          tx,
          table: 'community_comments',
          idColumn: 'comment_id',
          wireId: 'commentId',
          rows: rows,
          scope: 'post_id = ?',
          scopeArgs: [postId],
          pageComplete: pageComplete,
        );
        for (final commentId in stale) {
          await tx.delete(
            'community_comments',
            where: 'post_id = ? AND comment_id = ?',
            whereArgs: [postId, commentId],
          );
        }
      }
      await tx.rawDelete(
        '''DELETE FROM community_comments WHERE post_id=? AND comment_id IN (
        SELECT comment_id FROM community_comments WHERE post_id=?
        ORDER BY cached_at_millis DESC LIMIT -1 OFFSET 200)''',
        [postId, postId],
      );
      await _removeUnusedCommunityAuthors(tx);
    });
  }

  /// Loads cached community comments.
  Future<List<Map<String, dynamic>>> loadCachedCommunityComments(
    String postId, {
    String? afterCommentId,
    int limit = 50,
  }) async {
    final db = await _openDatabase();
    final clauses = ['c.post_id = ?'];
    final args = <Object?>[postId];
    if (afterCommentId != null) {
      final cursor = await db.query(
        'community_comments',
        columns: ['created_at_millis'],
        where: 'post_id=? AND comment_id=?',
        whereArgs: [postId, afterCommentId],
      );
      if (cursor.isEmpty) return [];
      clauses.add(
        '(c.created_at_millis < ? OR (c.created_at_millis = ? AND c.comment_id < ?))',
      );
      args.addAll([
        cursor.single['created_at_millis'],
        cursor.single['created_at_millis'],
        afterCommentId,
      ]);
    }
    args.add(limit.clamp(1, 100));
    final rows = await db.rawQuery(
      '''SELECT c.*, $_communityAuthorColumns
      FROM community_comments c JOIN community_authors a ON a.user_id=c.author_id
      JOIN community_posts p ON p.post_id=c.post_id AND p.visibility='public'
      WHERE ${clauses.join(' AND ')} ORDER BY c.created_at_millis DESC, c.comment_id DESC LIMIT ?''',
      args,
    );
    return rows.map((row) => _communityCachedView(row, comment: true)).toList();
  }

  /// Updates cached community comment count.
  Future<void> updateCachedCommunityCommentCount(
    String postId,
    int count,
  ) async {
    final db = await _openDatabase();
    await db.update(
      'community_posts',
      {'comment_count': count},
      where: 'post_id=?',
      whereArgs: [postId],
    );
  }

  /// Computes cache community reaction.
  Future<void> cacheCommunityReaction({
    required String ownerPhoneNumber,
    required String postId,
    required bool liked,
    required int likeCount,
  }) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      await _putCommunityRow(
        tx,
        'community_reactions',
        {
          'owner_phone_number': ownerPhoneNumber.trim(),
          'post_id': postId,
          'liked': liked ? 1 : 0,
          'updated_at_millis': DateTime.now().millisecondsSinceEpoch,
        },
        'owner_phone_number=? AND post_id=?',
        [ownerPhoneNumber.trim(), postId],
      );
      await tx.update(
        'community_posts',
        {'like_count': likeCount},
        where: 'post_id=?',
        whereArgs: [postId],
      );
    });
  }

  /// Removes cached community post.
  Future<void> removeCachedCommunityPost(String postId) async {
    final db = await _openDatabase();
    await db.transaction((tx) => _removeCommunityPost(tx, postId));
  }

  // saveCommunityDraft writes caption state and ordered photos atomically, reusing
  // content/occurrence photo identities.
  /// Saves community draft.
  Future<void> saveCommunityDraft({
    required String ownerPhoneNumber,
    required String draftKey,
    required String postId,
    required String caption,
    required bool includeHike,
    required List<Map<String, Object?>> images,
  }) async {
    if (ownerPhoneNumber.trim().isEmpty ||
        draftKey.isEmpty ||
        postId.isEmpty ||
        caption.length > 5000 ||
        images.length > 6) {
      throw ArgumentError('Invalid community draft.');
    }
    final occurrences = <String, int>{};
    final prepared = images.indexed.map((entry) {
      final bytes = entry.$2['bytes'];
      if (bytes is! List<int> ||
          bytes.isEmpty ||
          bytes.length > 10 * 1024 * 1024) {
        throw ArgumentError('Invalid draft photo.');
      }
      final hash = crypto.sha256.convert(bytes).toString();
      final occurrence = occurrences.update(
        hash,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      return {
        ...entry.$2,
        'image_key': '${hash}_$occurrence',
        'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        'position': entry.$1,
      };
    }).toList();
    final db = await _openDatabase();
    final owner = ownerPhoneNumber.trim();
    await db.transaction((tx) async {
      await _putCommunityRow(
        tx,
        'community_drafts',
        {
          'owner_phone_number': owner,
          'draft_key': draftKey,
          'post_id': postId,
          'caption': caption,
          'include_hike': includeHike ? 1 : 0,
          'updated_at_millis': DateTime.now().millisecondsSinceEpoch,
        },
        'owner_phone_number=? AND draft_key=?',
        [owner, draftKey],
      );
      final previous = await tx.query(
        'community_draft_images',
        columns: ['image_key'],
        where: 'owner_phone_number=? AND draft_key=?',
        whereArgs: [owner, draftKey],
      );
      final keys = prepared.map((image) => image['image_key']).toSet();
      for (final old in previous) {
        if (!keys.contains(old['image_key'])) {
          await tx.delete(
            'community_draft_images',
            where: 'owner_phone_number=? AND draft_key=? AND image_key=?',
            whereArgs: [owner, draftKey, old['image_key']],
          );
        }
      }
      for (final image in prepared) {
        final identity = [owner, draftKey, image['image_key']];
        final metadata = {
          'position': image['position'],
          'file_name': image['fileName'] ?? 'photo.jpg',
          'content_type': image['contentType'],
        };
        if (await tx.update(
              'community_draft_images',
              metadata,
              where: 'owner_phone_number=? AND draft_key=? AND image_key=?',
              whereArgs: identity,
            ) ==
            0) {
          await tx.insert('community_draft_images', {
            'owner_phone_number': owner,
            'draft_key': draftKey,
            'image_key': image['image_key'],
            ...metadata,
            'bytes': image['bytes'],
          });
        }
      }
    });
  }

  // loadCommunityDraft restores only the requested account/composer key and its selected photo
  // order.
  /// Loads community draft.
  Future<Map<String, dynamic>?> loadCommunityDraft({
    required String ownerPhoneNumber,
    required String draftKey,
  }) async {
    final db = await _openDatabase();
    return db.transaction((tx) async {
      final rows = await tx.query(
        'community_drafts',
        where: 'owner_phone_number=? AND draft_key=?',
        whereArgs: [ownerPhoneNumber.trim(), draftKey],
      );
      if (rows.isEmpty) return null;
      final images = await tx.query(
        'community_draft_images',
        where: 'owner_phone_number=? AND draft_key=?',
        whereArgs: [ownerPhoneNumber.trim(), draftKey],
        orderBy: 'position',
      );
      return {
        'postId': rows.single['post_id'],
        'caption': rows.single['caption'],
        'includeHike': rows.single['include_hike'] == 1,
        'images': images
            .map(
              (image) => {
                'fileName': image['file_name'],
                'contentType': image['content_type'],
                'bytes': image['bytes'],
              },
            )
            .toList(),
      };
    });
  }

  // deleteCommunityDraft removes photo rows and caption state only for the requested
  // account/composer key.
  /// Deletes community draft.
  Future<void> deleteCommunityDraft({
    required String ownerPhoneNumber,
    required String draftKey,
  }) async {
    final db = await _openDatabase();
    await db.transaction((tx) async {
      await tx.delete(
        'community_draft_images',
        where: 'owner_phone_number=? AND draft_key=?',
        whereArgs: [ownerPhoneNumber.trim(), draftKey],
      );
      await tx.delete(
        'community_drafts',
        where: 'owner_phone_number=? AND draft_key=?',
        whereArgs: [ownerPhoneNumber.trim(), draftKey],
      );
    });
  }
}

/// Removes community post.
Future<void> _removeCommunityPost(DatabaseExecutor db, String postId) async {
  await db.delete(
    'community_comments',
    where: 'post_id=?',
    whereArgs: [postId],
  );
  await db.delete(
    'community_reactions',
    where: 'post_id=?',
    whereArgs: [postId],
  );
  await db.delete('community_posts', where: 'post_id=?', whereArgs: [postId]);
  await _removeUnusedCommunityAuthors(db);
}

/// Removes unused community authors.
Future<void> _removeUnusedCommunityAuthors(DatabaseExecutor db) async {
  await db.rawDelete(
    '''DELETE FROM community_authors WHERE user_id NOT IN
    (SELECT author_id FROM community_posts UNION SELECT author_id FROM community_comments)''',
  );
}
