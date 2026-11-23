part of 'hiker_circle_firebase_repository.dart';

/// Server-owned downloads share the read-hash batch and never enter a write queue.
extension CloudReadRepository on HikerCircleFirebaseRepository {
  // Query named cloud resource
  /// Downloads a named cloud projection or reuses its completed batch validation.
  Future<Map<String, dynamic>> readCloudSnapshot({
    required String resourceType,
    Map<String, Object?> resourceArgs = const {},
    String owner = '',
    String? id,
    Duration freshness = const Duration(minutes: 2),
    bool force = false,
    bool cacheOnly = false,
    bool registerOnly = false,
  }) async => _conditionalCache.read(
    owner:
        ConditionalCloudCache.viewerScopedCloudResources.contains(
              resourceType,
            ) &&
            owner.isEmpty
        ? await _cloudReadOwner()
        : owner,
    type: 'cloud_$resourceType',
    id: id ?? stableContentHash(resourceArgs),
    callable: 'readCloudResource',
    arguments: {'resourceType': resourceType, 'resourceArgs': resourceArgs},
    policy: CacheReadPolicy.cloudFirst,
    freshness: freshness,
    online: _firebaseBootstrapResult.isAvailable && !registerOnly,
    force: force,
    cacheOnly: cacheOnly,
  );

  /// Prevents a rejected cloud read from resurrecting an older normalized cache.
  Future<bool> _cloudSnapshotRevoked(
    String type,
    Map<String, Object?> args,
    String owner,
  ) async {
    final validation = await _localDatabase.loadCachedEntity(
      ownerPhoneNumber: owner,
      entityType: 'cloud_$type:validation',
      entityId: stableContentHash(args),
      includeExpired: true,
    );
    return validation?.payload['revoked'] == true;
  }

  /// Restores downloaded history while retaining every unacknowledged local message.
  Future<List<ChatMessage>> _mergeDownloadedChatMessages(
    String chatId,
    String owner,
    List<ChatMessage> local,
  ) async {
    final args = <String, Object?>{'chatId': chatId};
    // Query local: downloaded chat history
    final snapshot = await readCloudSnapshot(
      resourceType: 'chat_messages',
      resourceArgs: args,
      owner: owner,
      cacheOnly: true,
    );
    final revoked = await _cloudSnapshotRevoked('chat_messages', args, owner);
    if (snapshot['messages'] is! List && !revoked) return local;
    final pendingSnapshots =
        (await _localDatabase.loadAllLocalMessagesForChat(
              chatId,
              ownerPhoneNumber: owner,
            ))
            .where((row) => row['awaiting_cloud_snapshot'] == 1)
            .map((row) => row['local_id'])
            .toSet();
    await _localDatabase.confirmDownloadedChatMessages(
      owner,
      chatId,
      _snapshotRows(
        snapshot,
        'messages',
      ).map((row) => row['messageId'] as String),
    );
    final messages = <String, ChatMessage>{
      if (!revoked)
        for (final row in _snapshotRows(snapshot, 'messages'))
          row['messageId'] as String: ChatMessage.fromFirestore(
            row['messageId'] as String,
            row,
          ),
      for (final row in local.where(
        (message) =>
            message.sendStatus != SendStatus.sent ||
            (!revoked &&
                pendingSnapshots.contains(message.id) &&
                !_snapshotRows(
                  snapshot,
                  'messages',
                ).any((row) => row['messageId'] == message.id)),
      ))
        row.id: row,
    }.values.toList();
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return messages;
  }

  /// Compares message models only to invalidate a stale body, never to forge a server hash.
  String _chatMessagesFingerprint(List<ChatMessage> messages) {
    final ordered = [...messages]..sort((a, b) => a.id.compareTo(b.id));
    return stableContentHash([
      for (final message in ordered)
        {
          'id': message.id,
          ...message.toFirestore(),
          'seenBy': [...message.seenBy]..sort(),
        },
    ]);
  }

  /// Keeps live Firestore delivery and registers its downloaded thread in the shared batch.
  Stream<List<ChatMessage>> _downloadedChatMessagesStream(
    String chatId,
  ) async* {
    final owner = await _cloudReadOwner();
    final args = <String, Object?>{'chatId': chatId};
    // Update local: register chat history for validation
    final initial = await readCloudSnapshot(
      resourceType: 'chat_messages',
      resourceArgs: args,
      owner: owner,
      registerOnly: true,
    );
    if (initial['messages'] is List) {
      final messages =
          _snapshotRows(initial, 'messages')
              .map(
                (row) =>
                    ChatMessage.fromFirestore(row['messageId'] as String, row),
              )
              .toList()
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      yield messages;
    }
    // Query live chat messages
    await for (final snapshot in _groupChatMessagesFor(
      chatId,
    ).orderBy('sentAtLocal', descending: false).snapshots()) {
      if (await _cloudReadOwner() != owner) throw _accountChangedForChat();
      // Query local: downloaded chat messages
      final cached = await readCloudSnapshot(
        resourceType: 'chat_messages',
        resourceArgs: args,
        owner: owner,
        cacheOnly: true,
      );
      if (snapshot.metadata.isFromCache &&
          (cached['messages'] is List ||
              await _cloudSnapshotRevoked('chat_messages', args, owner))) {
        continue;
      }
      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc.id, doc.data()))
          .toList();
      if (!snapshot.metadata.isFromCache && cached['messages'] is List) {
        final previous = _snapshotRows(cached, 'messages')
            .map(
              (row) =>
                  ChatMessage.fromFirestore(row['messageId'] as String, row),
            )
            .toList();
        if (_chatMessagesFingerprint(previous) !=
            _chatMessagesFingerprint(messages)) {
          await _conditionalCache.invalidate(
            owner: owner,
            type: 'cloud_chat_messages',
            id: stableContentHash(args),
          );
        }
      }
      yield messages;
    }
  }

  /// Stops a live subscription from displaying a previous account's conversation.
  FirebaseFunctionsException _accountChangedForChat() =>
      FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'The signed-in account changed.',
      );

  /// Isolates viewer-dependent downloaded state, including community reactions.
  Future<String> _cloudReadOwner() async {
    String? local;
    try {
      local = (await _localDatabase.loadSession())?.phoneNumber.trim();
    } catch (_) {
      // A server read can still succeed when local storage is unavailable.
    }
    String? remote;
    try {
      remote = _authenticatedUid != null
          ? _authenticatedUid()
          : FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // A restored owner can use their downloaded snapshot while offline.
    }
    final owner = remote ?? local;
    if (owner == null || owner.isEmpty || (local != null && local != owner)) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'The signed-in account changed.',
      );
    }
    return owner;
  }

  /// Registers older downloaded snapshots without making individual cloud calls.
  Future<void> _registerDownloadedCloudReads(AppSession session) async {
    if ((await _loadCachedTrails()).isNotEmpty) {
      // Update local: register cached trail catalogue
      await readCloudSnapshot(
        resourceType: 'trail_catalog',
        id: 'all',
        registerOnly: true,
      );
    }
    final profiles = await _loadCachedMapEntities(
      ownerPhoneNumber: session.phoneNumber,
      entityType: 'community_profile',
    );
    if (profiles.isNotEmpty) {
      // Update local: register cached hiker profiles
      await _conditionalCache.read(
        owner: session.phoneNumber,
        type: 'public_profiles',
        id: stableContentHash(const {'limit': 80}),
        callable: 'getPublicProfiles',
        arguments: const {'limit': 80},
        policy: CacheReadPolicy.cloudFirst,
        freshness: const Duration(minutes: 2),
        online: false,
      );
    }
    final posts = await _localDatabase.loadCachedCommunityPosts(
      ownerPhoneNumber: session.phoneNumber,
      limit: 20,
    );
    if (posts.isNotEmpty) {
      // Update local: register cached community content
      await readCloudSnapshot(
        resourceType: 'community_posts',
        resourceArgs: const {'limit': 20},
        owner: session.phoneNumber,
        registerOnly: true,
      );
      // Register individual cached stories as well as the downloaded feed page.
      for (final post in posts.reversed) {
        final id = post['postId'] as String;
        await readCloudSnapshot(
          resourceType: 'community_post',
          resourceArgs: {'postId': id},
          owner: session.phoneNumber,
          registerOnly: true,
        );
        if ((await _localDatabase.loadCachedCommunityComments(
          id,
          limit: 1,
        )).isNotEmpty) {
          await readCloudSnapshot(
            resourceType: 'community_comments',
            resourceArgs: {'postId': id, 'limit': 50},
            owner: session.phoneNumber,
            registerOnly: true,
          );
        }
      }
    }
    final chats = await _localDatabase.loadCachedEntities(
      ownerPhoneNumber: session.phoneNumber,
      entityType: 'group_chat',
      includeExpired: true,
    );
    for (final chat in chats) {
      final id = chat.entityId;
      if (id.isEmpty) continue;
      final messages = await _localDatabase.loadAllLocalMessagesForChat(
        id,
        ownerPhoneNumber: session.phoneNumber,
      );
      if (messages.any((row) => row['send_status'] == 'sent')) {
        // Update local: register downloaded chat history
        await readCloudSnapshot(
          resourceType: 'chat_messages',
          resourceArgs: {'chatId': id},
          owner: session.phoneNumber,
          registerOnly: true,
        );
      }
    }
    final weather = await _localDatabase.loadCachedEntities(
      ownerPhoneNumber: '',
      entityType: 'trail_weather',
      includeExpired: true,
    );
    // Retain the most recently used forecasts within the existing registry bound.
    weather.sort((a, b) => a.cachedAt.compareTo(b.cachedAt));
    for (final row in weather) {
      final descriptor = await _localDatabase.loadCachedEntity(
        ownerPhoneNumber: '',
        entityType: 'conditional_read_descriptor',
        entityId: stableContentHash(['', 'trail_weather', row.entityId]),
        includeExpired: true,
      );
      if (descriptor != null) continue;
      final parts = row.entityId.split(':');
      final coordinateSuffix =
          parts.length >= 3 &&
          double.tryParse(parts[parts.length - 1]) != null &&
          double.tryParse(parts[parts.length - 2]) != null;
      final trailId = coordinateSuffix
          ? parts.take(parts.length - 2).join(':')
          : row.entityId;
      // Update local: register cached trail forecast
      await _conditionalCache.read(
        owner: '',
        type: 'trail_weather',
        id: row.entityId,
        callable: 'fetchWeatherForTrail',
        arguments: {'trailId': trailId},
        policy: CacheReadPolicy.cloudFirst,
        freshness: TrailWeather.cacheFreshness,
        online: false,
      );
    }
  }
}
