part of '../circle_page_feature.dart';

/// Owns the state and non-visual actions of CirclePage.
class _CirclePageStateViewModel extends ChangeNotifier {
  /// Creates circle page state view model.
  _CirclePageStateViewModel({
    required this.readHikerCircleRepository,
    required this.readSession,
    required this.effectShowCircleMessage,
    required this.effectShowCommunityPersonProfile,
  });
  final HikerCircleFirebaseRepository Function() readHikerCircleRepository;
  final AppSession Function() readSession;
  final void Function(String message) effectShowCircleMessage;
  final Future<void> Function(_CommunityPerson person)
  effectShowCommunityPersonProfile;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final Set<String> stateBuddyPhones = {};

  final Set<String> stateOutgoingBuddyRequestPhones = {};

  final Set<String> stateBusyBuddyRequestPhones = {};

  List<_BuddyRequest> stateBuddyRequests = const [];

  List<_CommunityPerson> statePeople = const [];

  late List<_CommunityPost> statePosts = const [];

  bool stateIsLoadingPosts = false;

  bool stateIsLoadingMorePosts = false;

  bool stateHasMorePosts = true;

  int stateFeedGeneration = 0;

  final Set<String> stateLikingPostIds = {};

  String? statePostsLoadError;

  bool statePostsErrorFromPagination = false;

  List<GroupChat> stateGroupChats = const [];

  bool stateIsLoadingChats = false;

  String? stateChatsLoadError;

  Set<String> statePinnedChatIds = {};

  final Map<String, int> statePinUpdateGeneration = {};

  final Map<String, Future<void>> statePinWriteChains = {};

  Map<String, DateTime> stateLocalLastReadAt = const {};

  String stateCurrentUserPhotoURL = '';

  StreamSubscription<List<GroupChat>>? stateChatsSubscription;

  StreamSubscription<BuddyRelationships>? stateBuddyRequestsSubscription;
  ChatPreferenceCacheObserver? _preferenceCache;
  int _pinReadGeneration = 0;

  void commandWatchCachedPreferences() {
    _preferenceCache?.dispose();
    final owner = readSession().phoneNumber;
    _preferenceCache = ChatPreferenceCacheObserver(
      owner: owner,
      readOwner: () => readSession().phoneNumber,
      changes: readHikerCircleRepository().cachedReadUpdates,
      readCached: () => readHikerCircleRepository().readMobileSnapshot(
        owner: owner,
        resourceType: 'preferences',
        cacheOnly: true,
      ),
      onChanged: (preferences) {
        if (!mounted) return;
        _pinReadGeneration++;
        _publish(() => statePinnedChatIds = Set.of(preferences.pinnedChatIds));
      },
    );
  }

  /// Returns command is admin.
  bool get commandIsAdmin => readSession().isAdmin;

  /// Loads current user photo.
  Future<void> commandLoadCurrentUserPhoto() async {
    try {
      final profile = await readHikerCircleRepository().loadCommunityProfile(
        phoneNumber: readSession().phoneNumber,
      );
      if (!mounted || profile == null) return;
      final photoURL = _stringFrom(profile['photoURL']).trim();
      if (photoURL.isEmpty || photoURL == stateCurrentUserPhotoURL) return;
      _publish(() {
        stateCurrentUserPhotoURL = photoURL;
      });
    } catch (_) {
      // The session avatar remains available if its remote refresh fails.
    }
  }

  /// Loads community people.
  Future<void> commandLoadCommunityPeople({bool force = false}) async {
    try {
      final profiles = await readHikerCircleRepository().loadCommunityProfiles(
        session: readSession(),
        force: force,
      );
      if (!mounted) return;
      _publish(() {
        statePeople = profiles.map(_communityPersonFromProfile).toList();
      });
    } catch (_) {
      // Keep the last successfully loaded community snapshot.
    }
  }

  /// Loads buddy requests.
  Future<void> commandLoadBuddyRequests() async {
    try {
      final relationships = await readHikerCircleRepository()
          .loadBuddyRelationships(session: readSession(), force: true);
      if (!mounted) return;
      _publish(() {
        stateBuddyRequests = relationships.incomingRequests
            .map(_buddyRequestFromFirestore)
            .toList();
        stateBuddyPhones
          ..clear()
          ..addAll(relationships.buddyPhoneNumbers);
        stateOutgoingBuddyRequestPhones
          ..clear()
          ..addAll(relationships.outgoingRequestPhones);
      });
    } catch (_) {}
  }

  /// Listens for to buddy requests.
  void commandListenToBuddyRequests() {
    stateBuddyRequestsSubscription = readHikerCircleRepository()
        .watchBuddyRelationships(session: readSession())
        .listen((relationships) {
          if (!mounted) return;
          _publish(() {
            stateBuddyRequests = relationships.incomingRequests
                .map(_buddyRequestFromFirestore)
                .toList();
            stateBuddyPhones
              ..clear()
              ..addAll(relationships.buddyPhoneNumbers);
            stateOutgoingBuddyRequestPhones
              ..clear()
              ..addAll(relationships.outgoingRequestPhones);
          });
        }, onError: (_) => unawaited(commandLoadBuddyRequests()));
  }

  /// Listens for to group chats.
  void commandListenToGroupChats() {
    final phone = readSession().phoneNumber;
    unawaited(stateChatsSubscription?.cancel());
    stateChatsSubscription = readHikerCircleRepository()
        .userGroupChatsStream(phone)
        .listen(
          (chats) => unawaited(commandApplyGroupChats(chats, phone)),
          onError: (error) {
            if (!mounted) return;
            _publish(() {
              stateIsLoadingChats = false;
              stateChatsLoadError = 'Unable to load chats right now.';
            });
          },
        );
    _publish(() {
      stateIsLoadingChats = true;
      stateChatsLoadError = null;
    });
  }

  /// Applies group chats.
  Future<void> commandApplyGroupChats(
    List<GroupChat> chats,
    String phone,
  ) async {
    if (!mounted) return;
    unawaited(commandSyncReadReceipts(phone));
    var local = Map<String, DateTime>.from(stateLocalLastReadAt);
    try {
      local = await readHikerCircleRepository().loadAllLocalLastReadAt(
        ownerPhoneNumber: readSession().phoneNumber,
      );
    } catch (_) {
      // The remote chat list is still useful without local read timestamps.
    }
    if (!mounted) return;
    _publish(() {
      stateGroupChats = chats;
      stateLocalLastReadAt = local;
      stateIsLoadingChats = false;
      stateChatsLoadError = null;
    });
  }

  /// Synchronizes read receipts.
  Future<void> commandSyncReadReceipts(String phone) async {
    try {
      await readHikerCircleRepository().syncPendingReadReceipts(
        phoneNumber: phone,
      );
    } catch (_) {
      // Pending receipts are retried on the next stream update.
    }
  }

  /// Loads pinned chats.
  Future<void> commandLoadPinnedChats() async {
    final generation = ++_pinReadGeneration;
    final owner = readSession().phoneNumber;
    try {
      final pinned = await readHikerCircleRepository().loadPinnedChats(
        session: readSession(),
      );
      if (!mounted ||
          owner != readSession().phoneNumber ||
          generation != _pinReadGeneration ||
          statePinUpdateGeneration.isNotEmpty) {
        return;
      }
      _publish(() => statePinnedChatIds = pinned);
    } catch (_) {
      // Pin state can be retried by reopening Circle.
    }
  }

  /// Computes pin chat.
  void commandPinChat(GroupChat chat) {
    _pinReadGeneration++;
    _preferenceCache?.beginWrite();
    final isPinned = statePinnedChatIds.contains(chat.id);
    final desiredPinned = !isPinned;
    final generation = (statePinUpdateGeneration[chat.id] ?? 0) + 1;
    statePinUpdateGeneration[chat.id] = generation;
    _publish(() {
      if (isPinned) {
        statePinnedChatIds.remove(chat.id);
      } else {
        statePinnedChatIds.add(chat.id);
      }
    });
    unawaited(commandPersistPinnedChat(chat, desiredPinned, generation));
  }

  /// Serialize pin writes so a slow earlier request cannot undo the user's latest chat pin choice.
  Future<void> commandPersistPinnedChat(
    GroupChat chat,
    bool desiredPinned,
    int generation,
  ) async {
    final previous = statePinWriteChains[chat.id] ?? Future<void>.value();
    final write = previous.then(
      (_) => readHikerCircleRepository().setChatPinned(
        session: readSession(),
        chatId: chat.id,
        pinned: desiredPinned,
      ),
    );
    statePinWriteChains[chat.id] = write.then<void>((_) {}, onError: (_) {});
    try {
      await write;
    } catch (_) {
      if (!mounted || statePinUpdateGeneration[chat.id] != generation) return;
      _publish(() {
        if (desiredPinned) {
          statePinnedChatIds.remove(chat.id);
        } else {
          statePinnedChatIds.add(chat.id);
        }
      });
      effectShowCircleMessage('Unable to update the pinned chat.');
    } finally {
      if (statePinUpdateGeneration[chat.id] == generation) {
        statePinUpdateGeneration.remove(chat.id);
        statePinWriteChains.remove(chat.id);
      }
      _preferenceCache?.endWrite();
    }
  }

  /// Ignore stale refresh responses so an earlier feed request cannot replace a newer result.
  Future<void> commandLoadCommunityPosts({bool force = false}) async {
    final generation = ++stateFeedGeneration;
    _publish(() {
      stateIsLoadingPosts = true;
      stateIsLoadingMorePosts = false;
      statePostsLoadError = null;
      statePostsErrorFromPagination = false;
    });
    try {
      final posts = await readHikerCircleRepository().loadCommunityPosts(
        session: readSession(),
        force: force,
      );
      if (!mounted || generation != stateFeedGeneration) return;
      _publish(() {
        statePosts = posts.map(_communityPostFromFirestore).toList();
        stateHasMorePosts = posts.length >= 20;
        stateIsLoadingPosts = false;
        statePostsLoadError = null;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted || generation != stateFeedGeneration) return;
      _publish(() {
        stateIsLoadingPosts = false;
        statePostsLoadError = error.message;
      });
    } catch (_) {
      if (!mounted || generation != stateFeedGeneration) return;
      _publish(() {
        stateIsLoadingPosts = false;
        statePostsLoadError = 'Unable to load community posts right now.';
      });
    }
  }

  /// Page after the last post ID and discard duplicate IDs when merging the next feed batch.
  Future<void> commandLoadMoreCommunityPosts() async {
    if (stateIsLoadingPosts ||
        stateIsLoadingMorePosts ||
        !stateHasMorePosts ||
        statePosts.isEmpty) {
      return;
    }
    final generation = stateFeedGeneration;
    _publish(() {
      stateIsLoadingMorePosts = true;
      statePostsLoadError = null;
    });
    try {
      final next = await readHikerCircleRepository().loadCommunityPosts(
        session: readSession(),
        afterPostId: statePosts.last.postId,
      );
      if (!mounted || generation != stateFeedGeneration) return;
      final existing = statePosts.map((post) => post.postId).toSet();
      final additions = next
          .map(_communityPostFromFirestore)
          .where((post) => !existing.contains(post.postId))
          .toList();
      _publish(() {
        statePosts = [...statePosts, ...additions];
        stateHasMorePosts = next.length >= 20 && additions.isNotEmpty;
      });
    } catch (_) {
      if (mounted && generation == stateFeedGeneration) {
        _publish(() {
          statePostsLoadError = 'More stories couldn’t be loaded. Try again.';
          statePostsErrorFromPagination = true;
        });
      }
    } finally {
      if (mounted && generation == stateFeedGeneration) {
        _publish(() => stateIsLoadingMorePosts = false);
      }
    }
  }

  /// Update the heart immediately, then apply the canonical count or restore the previous reaction on failure.
  Future<_CommunityPost> commandTogglePostLike(_CommunityPost post) async {
    final id = post.postId;
    if (id == null || id.isEmpty || stateLikingPostIds.contains(id)) {
      return post;
    }
    final current =
        statePosts.where((item) => item.postId == id).firstOrNull ?? post;
    final updated = current.copyWith(
      isLiked: !current.isLiked,
      likes: math.max(0, current.likes + (current.isLiked ? -1 : 1)),
    );

    /// Applies.
    void apply(_CommunityPost value) {
      statePosts = statePosts
          .map((item) => item.postId == id ? value : item)
          .toList();
    }

    _publish(() {
      stateLikingPostIds.add(id);
      apply(updated);
    });
    try {
      final count = await readHikerCircleRepository().setCommunityPostLiked(
        session: readSession(),
        postId: id,
        liked: updated.isLiked,
      );
      final confirmed = updated.copyWith(likes: count);
      if (mounted) _publish(() => apply(confirmed));
      return confirmed;
    } catch (_) {
      if (mounted) {
        _publish(() => apply(current));
        effectShowCircleMessage('Your like couldn’t be saved. Try again.');
      }
      return current;
    } finally {
      if (mounted) _publish(() => stateLikingPostIds.remove(id));
    }
  }

  /// Cancels buddy request.
  Future<void> commandCancelBuddyRequest(_CommunityPerson person) async {
    final key = _phoneKeyFor(person.phoneNumber);
    if (key.isEmpty || stateBusyBuddyRequestPhones.contains(key)) return;
    _publish(() => stateBusyBuddyRequestPhones.add(key));
    try {
      await readHikerCircleRepository().cancelBuddyRequest(
        session: readSession(),
        buddyPhoneNumber: person.phoneNumber,
      );
      if (!mounted) return;
      _publish(() => stateOutgoingBuddyRequestPhones.remove(key));
      effectShowCircleMessage('Friend request cancelled.');
    } on HikerCircleFirebaseRepositoryException catch (error) {
      effectShowCircleMessage(error.message);
    } catch (_) {
      effectShowCircleMessage(
        'Unable to cancel the request. Please try again.',
      );
    } finally {
      if (mounted) _publish(() => stateBusyBuddyRequestPhones.remove(key));
    }
  }

  /// Accepts buddy request.
  Future<void> commandAcceptBuddyRequest(_BuddyRequest request) async {
    try {
      await readHikerCircleRepository().acceptBuddyRequest(
        session: readSession(),
        requesterPhoneNumber: request.phoneNumber,
      );
      if (!mounted) return;
      _publish(() {
        stateBuddyRequests = stateBuddyRequests
            .where((item) => item.phoneNumber != request.phoneNumber)
            .toList();
        stateBuddyPhones.add(request.phoneNumber);
      });
      unawaited(commandLoadCommunityPeople());
    } catch (_) {
      effectShowCircleMessage('Unable to accept the buddy request.');
    }
  }

  /// Declines buddy request.
  Future<void> commandDeclineBuddyRequest(_BuddyRequest request) async {
    try {
      await readHikerCircleRepository().declineBuddyRequest(
        session: readSession(),
        requesterPhoneNumber: request.phoneNumber,
      );
      if (!mounted) return;
      _publish(() {
        stateBuddyRequests = stateBuddyRequests
            .where((item) => item.phoneNumber != request.phoneNumber)
            .toList();
      });
    } catch (_) {
      effectShowCircleMessage('Unable to decline the buddy request.');
    }
  }

  /// Shows buddy request profile.
  Future<void> commandShowBuddyRequestProfile(_BuddyRequest request) async {
    Map<String, dynamic>? profile;
    try {
      profile = await readHikerCircleRepository().loadCommunityProfile(
        phoneNumber: request.phoneNumber,
      );
    } catch (_) {
      // The request snapshot still contains enough information to open the
      // profile overview while the public discovery profile is unavailable.
    }
    if (!mounted) return;
    final person = profile == null
        ? _CommunityPerson(
            phoneNumber: request.phoneNumber,
            name: request.name,
            handle: request.handle,
            subtitle: '',
            trailAffinity: 'HikerCircle',
            color: _colorForPost(request.phoneNumber),
            photoURL: request.photoURL,
          )
        : _communityPersonFromProfile(profile);
    await effectShowCommunityPersonProfile(person);
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _preferenceCache?.dispose();
    super.dispose();
  }

  late final Future<bool?> Function() effectPresentDeleteCommunityPostEffect1;

  late final Future<void> Function() effectPresentOpenBuddyRequestsEffect1;

  late final Future<bool?> Function(bool removing)
  effectPresentModerateCommunityPostEffect1;

  late final Future<void> Function(
    GroupChat chat,
    HikerCircleFirebaseRepository repo,
  )
  effectPresentOpenGroupChatEffect1;

  late final Future<void> Function(bool flags)
  effectPresentOpenCommunityModerationEffect1;

  final Set<String> stateDeletingPostIds = {};

  final Set<String> stateModeratingPostIds = {};

  late final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)
  effectPresentEditPost;

  /// Loads an exact linked post without relying on the currently loaded feed.
  Future<_CommunityPost?> commandLoadLinkedPost(String postId) async {
    try {
      final row = await readHikerCircleRepository().loadCommunityPost(
        session: readSession(),
        postId: postId,
      );
      if (!mounted) return null;
      if (row == null) {
        effectShowCircleMessage('This story is no longer available.');
        return null;
      }
      return _communityPostFromFirestore(row);
    } catch (_) {
      if (mounted) {
        effectShowCircleMessage('Unable to open this story. Please try again.');
      }
      return null;
    }
  }

  /// Opens an author's editor with current media paths and revision checks.
  Future<_CommunityPost?> commandEditCommunityPost(_CommunityPost post) async {
    final id = post.postId;
    if (id == null ||
        id.isEmpty ||
        stateModeratingPostIds.contains(id) ||
        stateDeletingPostIds.contains(id) ||
        stateLikingPostIds.contains(id)) {
      return null;
    }
    _publish(() => stateModeratingPostIds.add(id));
    try {
      final original = await readHikerCircleRepository().loadCommunityPost(
        session: readSession(),
        postId: id,
      );
      if (!mounted) return null;
      if (original == null || original['isOwnPost'] != true) {
        effectShowCircleMessage('This story is no longer available to edit.');
        return null;
      }
      final saved = await effectPresentEditPost(original);
      if (!mounted || saved == null) return null;
      final updated = _communityPostFromFirestore(saved);
      _publish(() {
        // Invalidate any older feed refresh that started before this edit.
        ++stateFeedGeneration;
        stateIsLoadingPosts = false;
        stateIsLoadingMorePosts = false;
        statePosts = statePosts
            .map((item) => item.postId == id ? updated : item)
            .toList();
      });
      effectShowCircleMessage('Your story was updated.');
      return updated;
    } catch (_) {
      if (mounted) {
        effectShowCircleMessage('Unable to open the editor. Please try again.');
      }
      return null;
    } finally {
      if (mounted) _publish(() => stateModeratingPostIds.remove(id));
    }
  }

  /// Queues a linked preview for either a direct or group conversation.
  Future<void> commandSharePost(_CommunityPost post, GroupChat chat) async {
    final id = post.postId;
    if (id == null || id.isEmpty) return;
    final preview = SharedCommunityPost(
      postId: id,
      authorName: post.author.substring(0, math.min(post.author.length, 160)),
      caption: post.body.substring(0, math.min(post.body.length, 600)),
      trailName: post.trail.substring(0, math.min(post.trail.length, 160)),
    );
    final now = DateTime.now();
    final session = readSession();
    try {
      await readHikerCircleRepository().sendGroupChatMessage(
        chatId: chat.id,
        senderPhone: session.phoneNumber,
        senderName: session.username,
        text: preview.summary,
        localId: 'share_${now.microsecondsSinceEpoch}',
        sentAt: now,
        sharedPost: preview,
      );
      if (mounted) {
        effectShowCircleMessage(
          'Post shared to ${chat.displayNameFor(session.phoneNumber)}.',
        );
      }
    } catch (_) {
      if (mounted) {
        effectShowCircleMessage('Unable to share the post right now.');
      }
    }
  }

  bool stateBuddyRequestsSheetOpen = false;

  /// Deletes community post.
  Future<bool> commandDeleteCommunityPost(_CommunityPost post) async {
    final id = post.postId;
    if (id == null || id.isEmpty || stateDeletingPostIds.contains(id)) {
      return false;
    }
    final confirmed = await effectPresentDeleteCommunityPostEffect1();
    if (confirmed != true || !mounted) return false;
    _publish(() => stateDeletingPostIds.add(id));
    try {
      await readHikerCircleRepository().deleteCommunityPost(
        session: readSession(),
        postId: id,
      );
      if (mounted) {
        _publish(() {
          ++stateFeedGeneration;
          stateIsLoadingPosts = false;
          stateIsLoadingMorePosts = false;
          statePosts = statePosts.where((item) => item.postId != id).toList();
        });
        effectShowCircleMessage('Your story was deleted.');
      }
      return true;
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) effectShowCircleMessage(error.message);
      return false;
    } catch (_) {
      if (mounted) {
        effectShowCircleMessage(
          'Your story couldn’t be deleted. Please try again.',
        );
      }
      return false;
    } finally {
      if (mounted) _publish(() => stateDeletingPostIds.remove(id));
    }
  }

  /// Opens community moderation.
  Future<void> commandOpenCommunityModeration({bool flags = false}) async {
    if (!commandIsAdmin) return;
    await effectPresentOpenCommunityModerationEffect1(flags);
    if (mounted) await commandLoadCommunityPosts();
  }

  /// Computes moderate community post.
  Future<bool> commandModerateCommunityPost(
    _CommunityPost post,
    String status,
  ) async {
    final id = post.postId;
    if (!commandIsAdmin ||
        id == null ||
        id.isEmpty ||
        stateModeratingPostIds.contains(id) ||
        stateDeletingPostIds.contains(id)) {
      return false;
    }
    _publish(() => stateModeratingPostIds.add(id));
    final removing = status == 'removed';
    try {
      final confirmed = await effectPresentModerateCommunityPostEffect1(
        removing,
      );
      if (confirmed != true || !mounted) return false;
      await readHikerCircleRepository().moderateCommunityPost(
        session: readSession(),
        postId: id,
        moderationStatus: status,
        expectedUpdatedAtMillis: post.updatedAtMillis,
      );
      if (!mounted) return true;
      _publish(() {
        ++stateFeedGeneration;
        statePosts = statePosts.where((item) => item.postId != id).toList();
      });
      effectShowCircleMessage(removing ? 'Story removed.' : 'Story hidden.');
      await commandLoadCommunityPosts();
      return true;
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) effectShowCircleMessage(error.message);
      return false;
    } catch (_) {
      if (mounted) {
        effectShowCircleMessage(
          'The story couldn’t be updated. Please try again.',
        );
      }
      return false;
    } finally {
      if (mounted) _publish(() => stateModeratingPostIds.remove(id));
    }
  }

  /// Opens buddy requests.
  Future<void> commandOpenBuddyRequests() async {
    if (stateBuddyRequestsSheetOpen) return;
    stateBuddyRequestsSheetOpen = true;
    try {
      await commandLoadBuddyRequests();
      if (!mounted) return;
      await effectPresentOpenBuddyRequestsEffect1();
    } finally {
      stateBuddyRequestsSheetOpen = false;
    }
  }

  /// Opens group chat.
  Future<void> commandOpenGroupChat(GroupChat chat) async {
    final repo = readHikerCircleRepository();
    final now = DateTime.now();
    // Opening the page must not wait for a server acknowledgement. The detail
    // page persists and syncs the read receipt after capturing its unread cutoff.
    _publish(() {
      stateLocalLastReadAt = Map<String, DateTime>.from(stateLocalLastReadAt)
        ..[chat.id] = now;
    });
    await effectPresentOpenGroupChatEffect1(chat, repo);
    if (mounted) _publish(() {});
  }
}

/// Owns the state and non-visual actions of _CommunityPostDetailPage.
class _CommunityPostDetailPageStateViewModel extends ChangeNotifier {
  /// Creates community post detail page state view model.
  _CommunityPostDetailPageStateViewModel({
    required this.readPost,
    required this.readRepository,
  });
  final _CommunityPost Function() readPost;
  final HikerCircleFirebaseRepository Function() readRepository;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<_CommunityComment> stateComments = const [];

  bool stateIsLoadingComments = true;

  bool stateIsLoadingMore = false;

  bool stateHasMoreComments = false;

  String? stateCommentsError;

  bool stateCommentsPaginationError = false;

  int stateCommentsGeneration = 0;

  /// Computes comment changed.
  void commandCommentChanged() {
    if (mounted) _publish(() {});
  }

  /// Loads comments.
  Future<void> commandLoadComments({
    bool more = false,
    bool force = false,
  }) async {
    final postId = readPost().postId;
    if (postId == null || postId.isEmpty) return;
    if (more && (stateIsLoadingMore || !stateHasMoreComments)) return;
    final generation = more
        ? stateCommentsGeneration
        : ++stateCommentsGeneration;
    _publish(() {
      if (more) {
        stateIsLoadingMore = true;
      } else {
        stateIsLoadingComments = true;
      }
      stateCommentsError = null;
    });
    try {
      final comments = await readRepository().loadCommunityComments(
        postId: postId,
        force: force,
        afterCommentId: more && stateComments.isNotEmpty
            ? stateComments.last.commentId
            : null,
      );
      if (!mounted || generation != stateCommentsGeneration) return;
      final known = more
          ? stateComments.map((item) => item.commentId).toSet()
          : <String>{};
      final additions = comments
          .map(_communityCommentFromFirestore)
          .where((item) => !known.contains(item.commentId))
          .toList();
      _publish(() {
        stateComments = more ? [...stateComments, ...additions] : additions;
        stateHasMoreComments = comments.length >= 50 && additions.isNotEmpty;
      });
    } catch (_) {
      if (mounted && generation == stateCommentsGeneration) {
        _publish(() {
          stateCommentsError = 'Comments couldn’t be loaded. Please try again.';
          stateCommentsPaginationError = more;
        });
      }
    } finally {
      if (mounted && generation == stateCommentsGeneration) {
        _publish(() {
          stateIsLoadingComments = false;
          stateIsLoadingMore = false;
        });
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _CircleSettingsPage.
class _CircleSettingsPageStateViewModel extends ChangeNotifier {
  /// Creates circle settings page state view model.
  _CircleSettingsPageStateViewModel({
    required this.readRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  bool stateGroupChatNotificationsEnabled = true;

  bool stateIsLoadingGroupChatSetting = true;
  ChatPreferenceCacheObserver? _preferenceCache;
  int _preferenceReadGeneration = 0;

  void commandWatchCachedPreferences() {
    _preferenceCache?.dispose();
    final owner = readSession().phoneNumber;
    _preferenceCache = ChatPreferenceCacheObserver(
      owner: owner,
      readOwner: () => readSession().phoneNumber,
      changes: readRepository().cachedReadUpdates,
      readCached: () => readRepository().readMobileSnapshot(
        owner: owner,
        resourceType: 'preferences',
        cacheOnly: true,
      ),
      onChanged: (preferences) {
        if (!mounted) return;
        _preferenceReadGeneration++;
        _publish(() {
          stateGroupChatNotificationsEnabled = preferences.notificationsEnabled;
          stateIsLoadingGroupChatSetting = false;
        });
      },
    );
  }

  void commandBeginPreferenceWrite() {
    _preferenceReadGeneration++;
    _preferenceCache?.beginWrite();
  }

  void commandEndPreferenceWrite() => _preferenceCache?.endWrite();

  /// Loads group chat notification setting.
  Future<void> commandLoadGroupChatNotificationSetting() async {
    final generation = ++_preferenceReadGeneration;
    final owner = readSession().phoneNumber;
    try {
      final enabled = await readRepository().loadGroupChatNotificationsEnabled(
        session: readSession(),
      );
      if (!mounted ||
          owner != readSession().phoneNumber ||
          generation != _preferenceReadGeneration) {
        return;
      }
      _publish(() {
        stateGroupChatNotificationsEnabled = enabled;
      });
    } catch (_) {
      // Keep the safe enabled default when the setting cannot be loaded.
    } finally {
      if (mounted && generation == _preferenceReadGeneration) {
        _publish(() {
          stateIsLoadingGroupChatSetting = false;
        });
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _preferenceCache?.dispose();
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _GroupChatTile.
class _GroupChatTileStateViewModel extends ChangeNotifier {
  /// Creates group chat tile state view model.
  _GroupChatTileStateViewModel({
    required this.readChat,
    required this.readLocalLastReadAt,
    required this.readPhoneNumber,
  });
  final GroupChat Function() readChat;
  final DateTime? Function() readLocalLastReadAt;
  final String Function() readPhoneNumber;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes latest of.
  DateTime? commandLatestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Computes unread.
  bool commandComputeUnread(
    GroupChat chat,
    String myPhone,
    DateTime? localReadAt,
  ) {
    if (chat.lastMessageAt == null) return false;
    if (chat.lastMessageSenderPhone == myPhone) return false;
    final cutoff = commandLatestOf(chat.lastReadAtFor(myPhone), localReadAt);
    if (cutoff != null && chat.lastMessageAt!.isBefore(cutoff)) return false;
    return true;
  }

  /// Returns command has unread.
  bool get commandHasUnread {
    final myPhone = readPhoneNumber();
    final chat = readChat();
    if (chat.lastMessageAt == null) return false;
    if (chat.lastMessageSenderPhone == myPhone) return false;
    final cutoff = commandLatestOf(
      chat.lastReadAtFor(myPhone),
      readLocalLastReadAt(),
    );
    if (cutoff != null && chat.lastMessageAt!.isBefore(cutoff)) return false;
    return true;
  }

  /// Returns command unread count.
  int get commandUnreadCount {
    if (!commandHasUnread) return 0;
    final serverCount = readChat().unreadCountFor(readPhoneNumber());
    return serverCount > 0 ? serverCount : 1;
  }

  /// Formats unread.
  String commandFormatUnread(int count) {
    if (count > 99) return '99+';
    return count.toString();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
