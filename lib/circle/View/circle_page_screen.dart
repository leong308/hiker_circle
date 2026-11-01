part of '../circle_page_feature.dart';

/// Circle offers community discovery and existing conversations for every role.
enum _CircleSection { community, chats }

/// Displays the circle page.
class CirclePage extends StatefulWidget {
  /// Creates circle page.
  const CirclePage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    this.activeHike,
    this.initialPostId,
    this.buddyRequestsOpenId = 0,
    this.onBuddyRequestsOpenHandled,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final ActiveHikeSession? activeHike;
  final String? initialPostId;
  final int buddyRequestsOpenId;
  final VoidCallback? onBuddyRequestsOpenHandled;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  /// Creates the presentation state for this widget.
  @override
  State<CirclePage> createState() => _CirclePageState();
}

/// Manages the circle page presentation and lifecycle.
class _CirclePageState extends State<CirclePage> {
  /// Returns deleting post ids.
  Set<String> get _deletingPostIds => _screenModel.stateDeletingPostIds;

  /// Returns moderating post ids.
  Set<String> get _moderatingPostIds => _screenModel.stateModeratingPostIds;

  late final _CirclePageStateViewModel _screenModel;

  /// Returns buddy phones.
  Set<String> get _buddyPhones => _screenModel.stateBuddyPhones;

  /// Returns outgoing buddy request phones.
  Set<String> get _outgoingBuddyRequestPhones =>
      _screenModel.stateOutgoingBuddyRequestPhones;

  /// Returns busy buddy request phones.
  Set<String> get _busyBuddyRequestPhones =>
      _screenModel.stateBusyBuddyRequestPhones;

  /// Returns buddy requests.
  List<_BuddyRequest> get _buddyRequests => _screenModel.stateBuddyRequests;

  /// Returns people.
  List<_CommunityPerson> get _people => _screenModel.statePeople;

  /// Returns posts.
  List<_CommunityPost> get _posts => _screenModel.statePosts;

  /// Updates posts.
  set _posts(List<_CommunityPost> value) => _screenModel.statePosts = value;

  /// Returns is loading posts.
  bool get _isLoadingPosts => _screenModel.stateIsLoadingPosts;

  /// Returns is loading more posts.
  bool get _isLoadingMorePosts => _screenModel.stateIsLoadingMorePosts;

  /// Returns has more posts.
  bool get _hasMorePosts => _screenModel.stateHasMorePosts;

  /// Returns liking post ids.
  Set<String> get _likingPostIds => _screenModel.stateLikingPostIds;

  /// Returns posts load error.
  String? get _postsLoadError => _screenModel.statePostsLoadError;

  /// Returns posts error from pagination.
  bool get _postsErrorFromPagination =>
      _screenModel.statePostsErrorFromPagination;

  /// Returns group chats.
  List<GroupChat> get _groupChats => _screenModel.stateGroupChats;

  /// Returns is loading chats.
  bool get _isLoadingChats => _screenModel.stateIsLoadingChats;

  /// Returns chats load error.
  String? get _chatsLoadError => _screenModel.stateChatsLoadError;

  /// Returns pinned chat ids.
  Set<String> get _pinnedChatIds => _screenModel.statePinnedChatIds;

  /// Returns local last read at.
  Map<String, DateTime> get _localLastReadAt =>
      _screenModel.stateLocalLastReadAt;

  /// Returns current user photo url.
  String get _currentUserPhotoURL => _screenModel.stateCurrentUserPhotoURL;

  /// Updates current user photo url.
  set _currentUserPhotoURL(String value) =>
      _screenModel.stateCurrentUserPhotoURL = value;

  /// Returns chats subscription.
  StreamSubscription<List<GroupChat>>? get _chatsSubscription =>
      _screenModel.stateChatsSubscription;

  /// Returns buddy requests subscription.
  StreamSubscription<BuddyRelationships>? get _buddyRequestsSubscription =>
      _screenModel.stateBuddyRequestsSubscription;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  _CircleSection _selectedSection = _CircleSection.community;

  /// Returns is admin.
  bool get _isAdmin => _screenModel.commandIsAdmin;

  bool _composerOpen = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CirclePageStateViewModel(
      readHikerCircleRepository: () => widget.hikerCircleRepository,
      readSession: () => widget.session,
      effectShowCircleMessage: _showCircleMessage,
      effectShowCommunityPersonProfile: _showCommunityPersonProfile,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentDeleteCommunityPostEffect1 =
        _presentDeleteCommunityPostEffect1;
    _screenModel.effectPresentOpenBuddyRequestsEffect1 =
        _presentOpenBuddyRequestsEffect1;
    _screenModel.effectPresentModerateCommunityPostEffect1 =
        _presentModerateCommunityPostEffect1;
    _screenModel.effectPresentOpenGroupChatEffect1 =
        _presentOpenGroupChatEffect1;
    _screenModel.effectPresentOpenCommunityModerationEffect1 =
        _presentOpenCommunityModerationEffect1;

    _screenModel.effectPresentEditPost = (original) =>
        showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          isDismissible: false,
          enableDrag: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => CommunityPostEditorSheet(
            repository: widget.hikerCircleRepository,
            session: widget.session,
            original: original,
          ),
        );
    if (widget.initialPostId case final postId?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final post = await _screenModel.commandLoadLinkedPost(postId);
        if (mounted && post != null) _openPostDetail(post);
      });
    }
    _currentUserPhotoURL = widget.session.photoURL ?? '';
    unawaited(_loadCommunityPosts());
    unawaited(_loadCommunityPeople());
    unawaited(_loadCurrentUserPhoto());
    unawaited(_loadPinnedChats());
    _listenToBuddyRequests();
    _listenToGroupChats();
    if (widget.buddyRequestsOpenId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onBuddyRequestsOpenHandled?.call();
        unawaited(_openBuddyRequests());
      });
    }
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant CirclePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.buddyRequestsOpenId > 0 &&
        widget.buddyRequestsOpenId != oldWidget.buddyRequestsOpenId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onBuddyRequestsOpenHandled?.call();
        unawaited(_openBuddyRequests());
      });
    }
  }

  /// Delegates load current user photo to the ViewModel.
  Future<void> _loadCurrentUserPhoto() =>
      _screenModel.commandLoadCurrentUserPhoto();

  /// Delegates load community people to the ViewModel.
  Future<void> _loadCommunityPeople() =>
      _screenModel.commandLoadCommunityPeople();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _buddyRequestsSubscription?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates listen to buddy requests to the ViewModel.
  void _listenToBuddyRequests() => _screenModel.commandListenToBuddyRequests();

  /// Delegates listen to group chats to the ViewModel.
  void _listenToGroupChats() => _screenModel.commandListenToGroupChats();

  /// Delegates load pinned chats to the ViewModel.
  Future<void> _loadPinnedChats() => _screenModel.commandLoadPinnedChats();

  /// Shows chat notifications.
  Future<void> _showChatNotifications(GroupChat chat) async {
    DateTime? mutedUntil;
    try {
      mutedUntil = await _CirclePageDataActions.loadGroupChatMutedUntil(
        widget.hikerCircleRepository,
      )(session: widget.session, chatId: chat.id);
    } catch (_) {
      _showCircleMessage('Unable to load notification settings.');
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChatNotificationSettingsSheet(
        chatName: chat.displayNameFor(widget.session.phoneNumber),
        isMuted: mutedUntil != null && mutedUntil.isAfter(DateTime.now()),
      ),
    );
    if (action == null || !mounted) return;
    final now = DateTime.now();
    final muteDuration = switch (action) {
      'unmute' => null,
      '1h' => const Duration(hours: 1),
      '8h' => const Duration(hours: 8),
      '1d' => const Duration(days: 1),
      '1w' => const Duration(days: 7),
      _ => null,
    };
    final newMutedUntil = muteDuration == null ? null : now.add(muteDuration);
    try {
      await _CirclePageDataActions.setGroupChatMutedUntil(
        widget.hikerCircleRepository,
      )(session: widget.session, chatId: chat.id, mutedUntil: newMutedUntil);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newMutedUntil == null
                  ? 'Notifications turned on for this chat.'
                  : 'Chat muted.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to update notification setting.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Delegates pin chat to the ViewModel.
  void _pinChat(GroupChat chat) => _screenModel.commandPinChat(chat);

  /// Shows circle message.
  void _showCircleMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// Deletes chat.
  Future<void> _deleteChat(GroupChat chat) async {
    final confirm = await _presentDeleteChatEffect1(chat);
    if (confirm != true || !mounted) return;
    try {
      await _CirclePageDataActions.deleteChatForUser(
        widget.hikerCircleRepository,
      )(
        session: widget.session,
        chatId: chat.id,
        senderName: widget.session.username,
        participantPhones: chat.participantPhones,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to delete conversation.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Ignore stale refresh responses so an earlier feed request cannot replace a newer result.
  Future<void> _loadCommunityPosts() =>
      _screenModel.commandLoadCommunityPosts();

  /// Page after the last post ID and discard duplicate IDs when merging the next feed batch.
  Future<void> _loadMoreCommunityPosts() =>
      _screenModel.commandLoadMoreCommunityPosts();

  /// Update the heart immediately, then apply the canonical count or restore the previous reaction on failure.
  Future<_CommunityPost> _togglePostLike(_CommunityPost post) =>
      _screenModel.commandTogglePostLike(post);

  /// Delegates delete community post to the ViewModel.
  Future<bool> _deleteCommunityPost(_CommunityPost post) =>
      _screenModel.commandDeleteCommunityPost(post);

  /// Delegates open community moderation to the ViewModel.
  Future<void> _openCommunityModeration({bool flags = false}) =>
      _screenModel.commandOpenCommunityModeration(flags: flags);

  /// Delegates moderate community post to the ViewModel.
  Future<bool> _moderateCommunityPost(_CommunityPost post, String status) =>
      _screenModel.commandModerateCommunityPost(post, status);

  /// Adds buddy.
  Future<void> _addBuddy(_CommunityPerson person) async {
    final key = _phoneKeyFor(person.phoneNumber);
    if (key.isEmpty ||
        key == _phoneKeyFor(widget.session.phoneNumber) ||
        _buddyPhones.any((phone) => _phoneKeyFor(phone) == key) ||
        _outgoingBuddyRequestPhones.contains(key) ||
        _busyBuddyRequestPhones.contains(key)) {
      return;
    }
    setState(() => _busyBuddyRequestPhones.add(key));
    try {
      await _CirclePageDataActions.sendBuddyRequest(
        widget.hikerCircleRepository,
      )(session: widget.session, buddyPhoneNumber: person.phoneNumber);
      if (!mounted) return;
      setState(() => _outgoingBuddyRequestPhones.add(key));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Friend request sent to ${person.name}.'),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Cancel request',
              onPressed: () => unawaited(_cancelBuddyRequest(person)),
            ),
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showCircleMessage(error.message);
    } catch (_) {
      _showCircleMessage('Unable to send the buddy request. Please try again.');
    } finally {
      if (mounted) setState(() => _busyBuddyRequestPhones.remove(key));
    }
  }

  /// Delegates cancel buddy request to the ViewModel.
  Future<void> _cancelBuddyRequest(_CommunityPerson person) =>
      _screenModel.commandCancelBuddyRequest(person);

  /// Delegates accept buddy request to the ViewModel.
  Future<void> _acceptBuddyRequest(_BuddyRequest request) =>
      _screenModel.commandAcceptBuddyRequest(request);

  /// Delegates decline buddy request to the ViewModel.
  Future<void> _declineBuddyRequest(_BuddyRequest request) =>
      _screenModel.commandDeclineBuddyRequest(request);

  /// Delegates open buddy requests to the ViewModel.
  Future<void> _openBuddyRequests() => _screenModel.commandOpenBuddyRequests();

  /// Delegates show buddy request profile to the ViewModel.
  Future<void> _showBuddyRequestProfile(_BuddyRequest request) =>
      _screenModel.commandShowBuddyRequestProfile(request);

  /// Opens direct chat.
  Future<void> _openDirectChat(_CommunityPerson person) async {
    if (person.phoneNumber == widget.session.phoneNumber) return;
    try {
      final chat =
          await _CirclePageDataActions.openDirectChat(
            widget.hikerCircleRepository,
          )(
            session: widget.session,
            otherPhoneNumber: person.phoneNumber,
            otherDisplayName: person.name,
          );
      if (!mounted) return;
      unawaited(_openGroupChat(chat));
    } catch (_) {
      _showCircleMessage('Unable to open this conversation.');
    }
  }

  /// Shows community profile.
  Future<void> _showCommunityProfile(_CommunityPost post) async {
    Map<String, dynamic>? profile;
    try {
      profile = await _CirclePageDataActions.loadCommunityProfile(
        widget.hikerCircleRepository,
      )(userId: post.authorId, phoneNumber: post.authorPhoneNumber);
    } catch (_) {
      _showCircleMessage('Unable to load this hiker profile.');
      return;
    }
    if (!mounted || profile == null) return;
    final person = _communityPersonFromProfile(profile);
    await _showCommunityPersonProfile(person);
  }

  /// Shows community person profile.
  Future<void> _showCommunityPersonProfile(_CommunityPerson person) async {
    Map<String, dynamic> details = const <String, dynamic>{};
    try {
      details = await _CirclePageDataActions.loadPublicHikerProfile(
        widget.hikerCircleRepository,
      )(userId: person.userId, phoneNumber: person.phoneNumber);
    } catch (_) {
      // The basic allow-listed profile remains useful if extended history is
      // temporarily unavailable.
    }
    if (!mounted) return;
    final isIncomingRequest = _buddyRequests.any(
      (request) =>
          _phoneKeyFor(request.phoneNumber) == _phoneKeyFor(person.phoneNumber),
    );
    await _presentShowCommunityPersonProfileEffect1(
      person,
      details,
      isIncomingRequest,
    );
  }

  /// Presents chat selection and delegates durable sharing to the ViewModel.
  Future<void> _sharePostToChat(_CommunityPost post) async {
    if (_groupChats.isEmpty) {
      _showCircleMessage('Start a conversation before sharing.');
      return;
    }
    final chat = await _presentSharePostToChatEffect1(_groupChats);
    if (chat != null && mounted) {
      await _screenModel.commandSharePost(post, chat);
    }
  }

  /// Persist one postId before publishing and serialize draft saves across retries and navigation.
  Future<void> _openCommunityComposer() async {
    if (_composerOpen) return;
    _composerOpen = true;
    CommunityPostDraftData? saved;
    try {
      saved = await _CirclePageDataActions.loadCommunityPostDraft(
        widget.hikerCircleRepository,
      )(session: widget.session, draftKey: 'community');
    } catch (_) {
      _composerOpen = false;
      if (mounted) {
        _showCircleMessage(
          'Your saved draft couldn’t be opened. Please try again.',
        );
      }
      return;
    }
    if (!mounted) {
      _composerOpen = false;
      return;
    }
    final postId =
        saved?.postId ??
        'post_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final hike = widget.activeHike;
    Timer? debounce;
    CommunityPostDraft? pending;
    Future<void> writes = Future.value();
    var published = false;
    var cloudPublished = false;

    /// Saves pending.
    Future<void> savePending() {
      if (cloudPublished) return Future.value();
      debounce?.cancel();
      final draft = pending;
      pending = null;
      if (draft == null) return writes;
      writes = writes
          .catchError((_) {})
          .then(
            (_) =>
                _CirclePageDataActions.saveCommunityPostDraft(
                  widget.hikerCircleRepository,
                )(
                  session: widget.session,
                  draftKey: 'community',
                  postId: postId,
                  caption: draft.caption,
                  images: draft.images,
                  includeHike: draft.includeHike,
                ),
          );
      return writes;
    }

    /// Computes discard.
    Future<void> discard() async {
      debounce?.cancel();
      pending = null;
      await writes.catchError((_) {});
      await _CirclePageDataActions.deleteCommunityPostDraft(
        widget.hikerCircleRepository,
      )(session: widget.session, draftKey: 'community');
    }

    try {
      published = await showCommunityPostComposer(
        context,
        authorName: widget.session.username,
        photoURL: _currentUserPhotoURL,
        photoBytes: _currentUserPhotoURL == (widget.session.photoURL ?? '')
            ? widget.session.photoBytes
            : null,
        hikeAttachment: hike == null ? null : _LiveHikeAttachment(hike: hike),
        hikeLabel: hike == null ? null : 'Attach current hike',
        initialCaption: saved?.caption ?? '',
        initialImages: saved?.images ?? const [],
        includeHikeInitially: saved?.includeHike ?? false,
        onDraftChanged: (draft) {
          if (cloudPublished) return;
          pending = draft;
          debounce?.cancel();
          debounce = Timer(
            const Duration(milliseconds: 400),
            () => unawaited(savePending().catchError((_) {})),
          );
        },
        onDiscard: discard,
        onSaveDraft: (draft) {
          pending = draft;
          return savePending();
        },
        onPublish: (draft) async {
          pending = draft;
          try {
            await savePending();
          } catch (_) {
            throw const HikerCircleFirebaseRepositoryException(
              'Your draft couldn’t be saved. Please try again before posting.',
            );
          }
          await _CirclePageDataActions.createCommunityPost(
            widget.hikerCircleRepository,
          )(
            session: widget.session,
            postId: postId,
            caption: draft.caption,
            images: draft.images,
            activeHike: draft.includeHike ? hike : null,
          );
          cloudPublished = true;
          pending = null;
          debounce?.cancel();
          try {
            await discard();
          } catch (_) {
            // The confirmed cloud post remains successful if local cleanup fails.
          }
        },
      );
    } finally {
      await savePending().catchError((_) {
        if (mounted) {
          _showCircleMessage('Your draft couldn’t be saved on this device.');
        }
      });
      _composerOpen = false;
    }
    if (!mounted || !published) return;
    _showCircleMessage('Your story is shared with the community.');
    await _loadCommunityPosts();
  }

  /// Opens post detail.
  void _openPostDetail(_CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return _CommunityPostDetailPage(
            session: widget.session,
            repository: widget.hikerCircleRepository,
            post: post,
            currentUserPhotoURL: _currentUserPhotoURL,
            currentUserPhotoBytes:
                _currentUserPhotoURL == (widget.session.photoURL ?? '')
                ? widget.session.photoBytes
                : null,
            onOpenProfile: () => _showCommunityProfile(post),
            onShare: _sharePostToChat,
            onToggleLike: _togglePostLike,
            onDeletePost: _deleteCommunityPost,
            onEditPost: _screenModel.commandEditCommunityPost,
            onModeratePost: _moderateCommunityPost,
            onCommentCountChanged: (count) {
              if (!mounted) return;
              setState(() {
                _posts = _posts
                    .map(
                      (item) => item.postId == post.postId
                          ? item.copyWith(replies: count)
                          : item,
                    )
                    .toList();
              });
              if (_isAdmin) unawaited(_loadCommunityPosts());
            },
          );
        },
      ),
    );
  }

  /// Delegates open group chat to the ViewModel.
  Future<void> _openGroupChat(GroupChat chat) =>
      _screenModel.commandOpenGroupChat(chat);

  /// Opens settings.
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CircleSettingsPage(
          session: widget.session,
          repository: widget.hikerCircleRepository,
        ),
      ),
    );
  }

  /// Builds segment.
  Widget _buildSegment(_CircleSection value, String label, IconData icon) {
    final isSelected = _selectedSection == value;
    final stacked = MediaQuery.textScalerOf(context).scale(13) > 18;
    return Expanded(
      child: GestureDetector(
        key: ValueKey('circle-tab-${value.name}'),
        onTap: () {
          setState(() {
            _selectedSection = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? _CircleColors.green : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : _CircleColors.secondaryTextFor(context),
              ),
              SizedBox(width: stacked ? 0 : 6, height: stacked ? 6 : 0),
              if (stacked)
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : _CircleColors.secondaryTextFor(context),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : _CircleColors.secondaryTextFor(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _CircleColors.backgroundFor(context),
      child: SafeArea(
        child: RefreshIndicator(
          color: _CircleColors.green,
          onRefresh: _selectedSection == _CircleSection.community
              ? () async {
                  await Future.wait([
                    _loadCommunityPosts(),
                    _loadCommunityPeople(),
                  ]);
                }
              : () async => _loadPinnedChats(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      onBack: widget.initialPostId == null
                          ? null
                          : () => Navigator.of(context).pop(),
                      requestCount: _buddyRequests.length,
                      onOpenFriendRequests: _openBuddyRequests,
                      onOpenSettings: _openSettings,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _CircleColors.surfaceFor(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _CircleColors.separatorFor(
                            context,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildSegment(
                            _CircleSection.community,
                            'Community',
                            Icons.people_rounded,
                          ),
                          _buildSegment(
                            _CircleSection.chats,
                            'Chats',
                            Icons.chat_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_isAdmin &&
                        _selectedSection == _CircleSection.community) ...[
                      CommunityModerationToolbar(
                        isAdmin: _isAdmin,
                        onManagePosts: () =>
                            unawaited(_openCommunityModeration()),
                        onReviewFlags: () =>
                            unawaited(_openCommunityModeration(flags: true)),
                      ),
                      const SizedBox(height: 18),
                    ],
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(_selectedSection),
                        child: _selectedSection == _CircleSection.community
                            ? _CommunitySection(
                                activeHike: widget.activeHike,
                                people: _people,
                                posts: _posts,
                                isLoadingPosts: _isLoadingPosts,
                                postsLoadError: _postsLoadError,
                                onRetryPosts: _postsErrorFromPagination
                                    ? _loadMoreCommunityPosts
                                    : _loadCommunityPosts,
                                isLoadingMore: _isLoadingMorePosts,
                                hasMorePosts: _hasMorePosts,
                                onLoadMore: _loadMoreCommunityPosts,
                                likingPostIds: _likingPostIds,
                                deletingPostIds: _deletingPostIds,
                                moderatingPostIds: _moderatingPostIds,
                                isAdmin: _isAdmin,
                                onModeratePost: (post, status) => unawaited(
                                  _moderateCommunityPost(post, status),
                                ),
                                onEditPost: (post) => unawaited(
                                  _screenModel.commandEditCommunityPost(post),
                                ),
                                onDeletePost: (post) =>
                                    unawaited(_deleteCommunityPost(post)),
                                onLikePost: (post) =>
                                    unawaited(_togglePostLike(post)),
                                buddyPhones: _buddyPhones,
                                outgoingBuddyRequestPhones:
                                    _outgoingBuddyRequestPhones,
                                busyBuddyRequestPhones: _busyBuddyRequestPhones,
                                currentUserPhone: widget.session.phoneNumber,
                                currentUserPhotoURL: _currentUserPhotoURL,
                                currentUserPhotoBytes:
                                    _currentUserPhotoURL ==
                                        (widget.session.photoURL ?? '')
                                    ? widget.session.photoBytes
                                    : null,
                                onAddBuddy: (person) =>
                                    unawaited(_addBuddy(person)),
                                onCancelRequest: (person) =>
                                    unawaited(_cancelBuddyRequest(person)),
                                onMessageBuddy: (person) =>
                                    unawaited(_openDirectChat(person)),
                                onOpenPersonProfile: (person) => unawaited(
                                  _showCommunityPersonProfile(person),
                                ),
                                onOpenProfile: _showCommunityProfile,
                                onSharePost: _sharePostToChat,
                                onCreatePost: () =>
                                    unawaited(_openCommunityComposer()),
                                onOpenPost: _openPostDetail,
                              )
                            : _ChatsSection(
                                chats: _groupChats,
                                isLoading: _isLoadingChats,
                                loadError: _chatsLoadError,
                                onRetry: _listenToGroupChats,
                                phoneNumber: widget.session.phoneNumber,
                                pinnedChatIds: _pinnedChatIds,
                                currentUserName: widget.session.username,
                                localLastReadAt: _localLastReadAt,
                                onOpenChat: _openGroupChat,
                                onChatNotifications: _showChatNotifications,
                                onDeleteChat: _deleteChat,
                                onPinChat: _pinChat,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the delete chat effect1 UI.
  Future<bool?> _presentDeleteChatEffect1(GroupChat chat) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this conversation?'),
      content: Text(
        chat.isDirect
            ? 'This will delete the conversation on your end. '
                  'The other person will see that you left.'
            : 'This will delete the conversation on your end. '
                  'Other members will see that you left.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(
            'Delete',
            style: TextStyle(color: _CircleColors.red),
          ),
        ),
      ],
    ),
  );

  /// Presents the delete community post effect1 UI.
  Future<bool?> _presentDeleteCommunityPostEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this story?'),
      content: const Text('This removes your post from the community.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep story'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete story'),
        ),
      ],
    ),
  );

  /// Presents the open community moderation effect1 UI.
  Future<void> _presentOpenCommunityModerationEffect1(bool flags) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => flags
              ? _CommunityFlagReviewPage(session: widget.session)
              : CommunityPostManagementPage(
                  session: widget.session,
                  repository: widget.hikerCircleRepository,
                ),
        ),
      );

  /// Presents the moderate community post effect1 UI.
  Future<bool?> _presentModerateCommunityPostEffect1(
    bool removing,
  ) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(removing ? 'Remove this story?' : 'Hide this story?'),
      content: Text(
        removing
            ? 'This story will be removed from the community. Its record stays in Manage posts for review or restoration.'
            : 'This story will be hidden from the community. You can restore it from Manage posts.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(removing ? 'Remove story' : 'Hide story'),
        ),
      ],
    ),
  );

  /// Presents the open buddy requests effect1 UI.
  Future<void> _presentOpenBuddyRequestsEffect1() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StreamBuilder<BuddyRelationships>(
      stream: _CirclePageDataActions.watchBuddyRelationships(
        widget.hikerCircleRepository,
      )(session: widget.session),
      builder: (context, snapshot) => _BuddyRequestsSheet(
        requests: snapshot.hasData
            ? snapshot.data!.incomingRequests
                  .map(_buddyRequestFromFirestore)
                  .toList()
            : _buddyRequests,
        onAccept: (request) => unawaited(_acceptBuddyRequest(request)),
        onDecline: (request) => unawaited(_declineBuddyRequest(request)),
        onOpenProfile: (request) =>
            unawaited(_showBuddyRequestProfile(request)),
      ),
    ),
  );

  /// Presents the show community person profile effect1 UI.
  Future<void> _presentShowCommunityPersonProfileEffect1(
    _CommunityPerson person,
    Map<String, dynamic> details,
    bool isIncomingRequest,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _CommunityProfileSheet(
      person: person,
      details: details,
      isBuddy: _buddyPhones.contains(person.phoneNumber),
      isIncomingRequest: isIncomingRequest,
      isRequested: _outgoingBuddyRequestPhones.contains(
        _phoneKeyFor(person.phoneNumber),
      ),
      isOwnProfile: person.phoneNumber == widget.session.phoneNumber,
      onAddBuddy: () {
        Navigator.of(sheetContext).pop();
        unawaited(_addBuddy(person));
      },
      onCancelRequest: () {
        Navigator.of(sheetContext).pop();
        unawaited(_cancelBuddyRequest(person));
      },
      onMessage: () {
        Navigator.of(sheetContext).pop();
        if (person.phoneNumber == widget.session.phoneNumber) {
          _showCircleMessage('You cannot start a conversation with yourself.');
        } else {
          unawaited(_openDirectChat(person));
        }
      },
    ),
  );

  /// Presents the share post to group chat effect1 UI.
  Future<GroupChat?> _presentSharePostToChatEffect1(
    List<GroupChat> groupChats,
  ) => showModalBottomSheet<GroupChat>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => _SharePostToChatSheet(
      chats: groupChats,
      currentPhone: widget.session.phoneNumber,
    ),
  );

  /// Presents the open group chat effect1 UI.
  Future<void> _presentOpenGroupChatEffect1(
    GroupChat chat,
    HikerCircleFirebaseRepository repo,
  ) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => GroupChatDetailPage(
        chat: chat,
        session: widget.session,
        repository: repo,
      ),
    ),
  );
}

/// Displays the community flag review page.
class _CommunityFlagReviewPage extends StatelessWidget {
  /// Creates community flag review page.
  const _CommunityFlagReviewPage({required this.session});
  final AppSession session;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      CommunityFlaggedContentPage(isAdmin: session.isAdmin);
}

/// Displays the buddy discovery action.
class _BuddyDiscoveryAction extends StatelessWidget {
  /// Creates buddy discovery action.
  const _BuddyDiscoveryAction({
    required this.isBuddy,
    required this.isRequested,
    required this.isBusy,
    required this.onAdd,
    required this.onCancel,
    required this.onMessage,
  });
  final bool isBuddy, isRequested, isBusy;
  final VoidCallback onAdd, onCancel, onMessage;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox.square(
        dimension: 44,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (isRequested && !isBuddy) {
      return TextButton.icon(
        onPressed: onCancel,
        icon: const Icon(Icons.close_rounded, size: 17),
        label: const Text('Cancel'),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      );
    }
    final label = isBuddy ? 'Message hiker' : 'Add buddy';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: CupertinoButton(
          minimumSize: const Size.square(44),
          padding: const EdgeInsets.all(10),
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          onPressed: isBuddy ? onMessage : onAdd,
          child: Icon(
            isBuddy ? CupertinoIcons.chat_bubble : CupertinoIcons.person_add,
            color: Theme.of(context).colorScheme.primary,
            size: 21,
          ),
        ),
      ),
    );
  }
}

/// Displays the live hike attachment.
class _LiveHikeAttachment extends StatelessWidget {
  /// Creates live hike attachment.
  const _LiveHikeAttachment({required this.hike});
  final ActiveHikeSession hike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _CircleColors.greenSoftFor(context),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(Icons.route_rounded, color: _CircleColors.green, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hike.trail.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                '${hike.recordedDistanceKm.toStringAsFixed(2)} km · ${hike.elapsedDuration.inMinutes} min · In progress',
                style: TextStyle(
                  fontSize: 12,
                  color: _CircleColors.secondaryTextFor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Draw lightweight feed geometry without creating a native map for every story card.
class _FeedRoutePainter extends CustomPainter {
  /// Creates feed route painter.
  const _FeedRoutePainter(this.points, this.color, this.background);
  final List<HikeCoordinate> points;
  final Color color;
  final Color background;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final grid = Paint()
      ..color = color.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;
    final minLat = points.map((p) => p.latitude).reduce(math.min);
    final maxLat = points.map((p) => p.latitude).reduce(math.max);
    final minLng = points.map((p) => p.longitude).reduce(math.min);
    final maxLng = points.map((p) => p.longitude).reduce(math.max);
    final aspect = math
        .cos((minLat + maxLat) / 2 * math.pi / 180)
        .abs()
        .clamp(.1, 1);
    final width = math.max((maxLng - minLng) * aspect, .00001);
    final height = math.max(maxLat - minLat, .00001);
    final scale = math.min(
      (size.width - 50) / width,
      (size.height - 40) / height,
    );

    /// Computes project.
    Offset project(HikeCoordinate point) => Offset(
      size.width / 2 +
          (point.longitude - (minLng + maxLng) / 2) * aspect * scale,
      size.height / 2 - (point.latitude - (minLat + maxLat) / 2) * scale,
    );
    final path = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final point in points.skip(1)) {
      final p = project(point);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in [points.first, points.last]) {
      canvas.drawCircle(project(point), 6, Paint()..color = Colors.white);
      canvas.drawCircle(project(point), 3.5, Paint()..color = color);
    }
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _FeedRoutePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}

/// Displays the community network photo.
class _CommunityNetworkPhoto extends StatelessWidget {
  /// Creates community network photo.
  const _CommunityNetworkPhoto({required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Icon(
                CupertinoIcons.photo,
                size: 32,
                color: _CircleColors.secondaryTextFor(context),
              ),
            ),
          ),
    errorBuilder: (context, _, _) => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.photo,
              color: _CircleColors.secondaryTextFor(context),
            ),
            const SizedBox(height: 8),
            const Text('Photo unavailable', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

/// Displays the photo viewer.
class _PhotoViewer extends StatefulWidget {
  /// Creates photo viewer.
  const _PhotoViewer({required this.imageUrls, required this.initialIndex});
  final List<String> imageUrls;
  final int initialIndex;

  /// Creates the presentation state for this widget.
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

/// Manages the photo viewer presentation and lifecycle.
class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${_index + 1} of ${widget.imageUrls.length}'),
    ),
    body: SafeArea(
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.imageUrls.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (_, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: _CommunityNetworkPhoto(
            url: widget.imageUrls[index],
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}

/// Displays the community post detail page.
class _CommunityPostDetailPage extends StatefulWidget {
  /// Creates community post detail page.
  const _CommunityPostDetailPage({
    required this.session,
    required this.repository,
    required this.post,
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onOpenProfile,
    required this.onShare,
    required this.onToggleLike,
    required this.onDeletePost,
    required this.onEditPost,
    required this.onModeratePost,
    required this.onCommentCountChanged,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final _CommunityPost post;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final VoidCallback onOpenProfile;
  final ValueChanged<_CommunityPost> onShare;
  final Future<_CommunityPost> Function(_CommunityPost post) onToggleLike;
  final ValueChanged<int> onCommentCountChanged;
  final Future<bool> Function(_CommunityPost post) onDeletePost;
  final Future<_CommunityPost?> Function(_CommunityPost post) onEditPost;
  final Future<bool> Function(_CommunityPost post, String status)
  onModeratePost;

  /// Creates the presentation state for this widget.
  @override
  State<_CommunityPostDetailPage> createState() =>
      _CommunityPostDetailPageState();
}

/// Manages the community post detail page presentation and lifecycle.
class _CommunityPostDetailPageState extends State<_CommunityPostDetailPage> {
  late final _CommunityPostDetailPageStateViewModel _screenModel;

  /// Returns comments.
  List<_CommunityComment> get _comments => _screenModel.stateComments;

  /// Updates comments.
  set _comments(List<_CommunityComment> value) =>
      _screenModel.stateComments = value;

  /// Returns is loading comments.
  bool get _isLoadingComments => _screenModel.stateIsLoadingComments;

  /// Returns is loading more.
  bool get _isLoadingMore => _screenModel.stateIsLoadingMore;

  /// Returns has more comments.
  bool get _hasMoreComments => _screenModel.stateHasMoreComments;

  /// Returns comments error.
  String? get _commentsError => _screenModel.stateCommentsError;

  /// Returns comments pagination error.
  bool get _commentsPaginationError =>
      _screenModel.stateCommentsPaginationError;

  /// Returns comments generation.
  int get _commentsGeneration => _screenModel.stateCommentsGeneration;

  /// Updates comments generation.
  set _commentsGeneration(int value) =>
      _screenModel.stateCommentsGeneration = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  final _scroll = ScrollController();
  late _CommunityPost _post = widget.post;

  bool _isPostingComment = false;
  bool _likeBusy = false;
  bool _deleting = false;
  bool _moderating = false;
  final Set<String> _removingCommentIds = {};

  String? _pendingCommentId;
  String? _pendingCommentBody;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CommunityPostDetailPageStateViewModel(
      readPost: () => widget.post,
      readRepository: () => widget.repository,
    )..addListener(_renderScreenModel);

    _commentController.addListener(_commentChanged);
    unawaited(_loadComments());
  }

  /// Delegates comment changed to the ViewModel.
  void _commentChanged() => _screenModel.commandCommentChanged();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _scroll.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates load comments to the ViewModel.
  Future<void> _loadComments({bool more = false}) =>
      _screenModel.commandLoadComments(more: more);

  /// Reuse the comment ID when retrying the same text after an uncertain network result.
  Future<void> _postComment() async {
    final postId = _post.postId;
    final body = _commentController.text.trim();
    if (_isPostingComment || body.isEmpty || postId == null || postId.isEmpty) {
      return;
    }
    if (_pendingCommentBody != body) {
      _pendingCommentId =
          'comment_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
      _pendingCommentBody = body;
    }
    setState(() => _isPostingComment = true);
    try {
      await _CirclePageDataActions.addCommunityComment(widget.repository)(
        session: widget.session,
        postId: postId,
        body: body,
        commentId: _pendingCommentId,
      );
      if (!mounted) return;
      _commentController.clear();
      _pendingCommentId = null;
      _pendingCommentBody = null;
      setState(() => _post = _post.copyWith(replies: _post.replies + 1));
      widget.onCommentCountChanged(_post.replies);
      await _loadComments();
      if (mounted) _showDetailSnack('Comment added.');
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showDetailSnack(error.message);
    } catch (_) {
      _showDetailSnack(
        'Your comment couldn’t be sent. Your text is still here.',
      );
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  /// Toggles like.
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final previous = _post;
    setState(() {
      _likeBusy = true;
      _post = _post.copyWith(
        isLiked: !_post.isLiked,
        likes: math.max(0, _post.likes + (_post.isLiked ? -1 : 1)),
      );
    });
    final confirmed = await widget.onToggleLike(previous);
    if (mounted) {
      setState(() {
        _post = confirmed.copyWith(replies: _post.replies);
        _likeBusy = false;
      });
    }
  }

  /// Replaces detail content only after the author confirms an edit.
  Future<void> _editStory() async {
    if (_deleting || _moderating || _likeBusy) return;
    setState(() => _moderating = true);
    final updated = await widget.onEditPost(_post);
    if (mounted) {
      setState(() {
        if (updated != null) _post = updated;
        _moderating = false;
      });
    }
  }

  /// Deletes story.
  Future<void> _deleteStory() async {
    if (_deleting || _moderating) return;
    setState(() => _deleting = true);
    final deleted = await widget.onDeletePost(_post);
    if (!mounted) return;
    if (deleted) {
      _presentDeleteStoryEffect1();
    } else {
      setState(() => _deleting = false);
    }
  }

  /// Computes moderate story.
  Future<void> _moderateStory(String status) async {
    if (!widget.session.isAdmin || _moderating || _deleting) return;
    setState(() => _moderating = true);
    final updated = await widget.onModeratePost(_post, status);
    if (!mounted) return;
    if (updated) {
      _presentModerateStoryEffect1();
    } else {
      setState(() => _moderating = false);
    }
  }

  /// Removes comment.
  Future<void> _removeComment(_CommunityComment comment) async {
    final postId = _post.postId;
    final commentId = comment.commentId;
    if (!widget.session.isAdmin ||
        postId == null ||
        postId.isEmpty ||
        commentId.isEmpty ||
        !_removingCommentIds.add(commentId)) {
      return;
    }
    setState(() {});
    try {
      final confirmed = await _presentRemoveCommentEffect1();
      if (confirmed != true || !mounted) return;
      await _CirclePageDataActions.removeAdminCommunityComment(
        widget.repository,
      )(session: widget.session, postId: postId, commentId: commentId);
      final remaining = math.max(0, _post.replies - 1);
      widget.onCommentCountChanged(remaining);
      if (!mounted) return;
      setState(() {
        ++_commentsGeneration;
        _comments = _comments
            .where((item) => item.commentId != commentId)
            .toList();
        _post = _post.copyWith(replies: remaining);
      });
      _showDetailSnack('Comment removed.');
      await _loadComments();
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showDetailSnack(error.message);
    } catch (_) {
      _showDetailSnack('The comment couldn’t be removed. Please try again.');
    } finally {
      if (mounted) setState(() => _removingCommentIds.remove(commentId));
    }
  }

  /// Shows detail snack.
  void _showDetailSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final quiet = _CircleColors.secondaryTextFor(context);
    return Scaffold(
      backgroundColor: _CircleColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: _CircleColors.backgroundFor(context),
        title: const Text('Story'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Refresh comments',
            onPressed: _isLoadingComments ? null : () => _loadComments(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _CircleColors.green,
        onRefresh: _loadComments,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CommunityPostCard(
                    post: _post,
                    isOwnPost:
                        _post.isOwnPost ||
                        _post.authorPhoneNumber == widget.session.phoneNumber,
                    onOpenPost: () => _commentFocus.requestFocus(),
                    onOpenProfile: widget.onOpenProfile,
                    onShare: () => widget.onShare(_post),
                    onLike: _toggleLike,
                    likeBusy: _likeBusy || _moderating || _deleting,
                    expanded: true,
                    deleteBusy: _deleting || _moderating,
                    isAdmin: widget.session.isAdmin,
                    onModerate: widget.session.isAdmin ? _moderateStory : null,
                    onEdit:
                        _post.isOwnPost ||
                            _post.authorPhoneNumber ==
                                widget.session.phoneNumber
                        ? _editStory
                        : null,
                    onDelete:
                        _post.isOwnPost ||
                            _post.authorPhoneNumber ==
                                widget.session.phoneNumber
                        ? _deleteStory
                        : null,
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        const Text(
                          'Conversation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_post.replies}',
                          style: TextStyle(color: quiet),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isLoadingComments && _comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_comments.isEmpty && _commentsError == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            CupertinoIcons.chat_bubble_2,
                            color: quiet,
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Start the conversation',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ask a question or leave a little encouragement.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: quiet, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  if (_commentsError != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _CircleColors.surfaceFor(context),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_commentsError!),
                          TextButton(
                            onPressed: () =>
                                _loadComments(more: _commentsPaginationError),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  for (final comment in _comments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _CircleColors.surfaceFor(context),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _CommentRow(
                          comment: comment,
                          onRemove:
                              widget.session.isAdmin &&
                                  comment.commentId.isNotEmpty
                              ? () => unawaited(_removeComment(comment))
                              : null,
                          removing: _removingCommentIds.contains(
                            comment.commentId,
                          ),
                        ),
                      ),
                    ),
                  if (_hasMoreComments)
                    TextButton.icon(
                      onPressed: _isLoadingMore
                          ? null
                          : () => _loadComments(more: true),
                      icon: _isLoadingMore
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: const Text('More comments'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _CircleColors.surfaceFor(context),
              border: Border(
                top: BorderSide(
                  color: _CircleColors.separatorFor(
                    context,
                  ).withValues(alpha: .6),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('community-comment'),
                        controller: _commentController,
                        focusNode: _commentFocus,
                        enabled: !_isPostingComment,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Add to the conversation…',
                          counterText: '',
                          filled: true,
                          fillColor: _CircleColors.backgroundFor(context),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send comment',
                      style: IconButton.styleFrom(
                        backgroundColor: _CircleColors.green,
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed:
                          _isPostingComment ||
                              _commentController.text.trim().isEmpty
                          ? null
                          : _postComment,
                      icon: _isPostingComment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Presents the delete story effect1 UI.
  void _presentDeleteStoryEffect1() => Navigator.of(context).pop();

  /// Presents the moderate story effect1 UI.
  void _presentModerateStoryEffect1() => Navigator.of(context).pop();

  /// Presents the remove comment effect1 UI.
  Future<bool?> _presentRemoveCommentEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove this comment?'),
      content: const Text(
        'This comment will be removed from the conversation. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove comment'),
        ),
      ],
    ),
  );
}

/// Displays the community profile sheet.
class _CommunityProfileSheet extends StatelessWidget {
  /// Creates community profile sheet.
  const _CommunityProfileSheet({
    required this.person,
    required this.details,
    required this.isBuddy,
    required this.isIncomingRequest,
    required this.isRequested,
    required this.isOwnProfile,
    required this.onAddBuddy,
    required this.onCancelRequest,
    required this.onMessage,
  });

  final _CommunityPerson person;
  final Map<String, dynamic> details;
  final bool isBuddy;
  final bool isIncomingRequest;
  final bool isRequested;
  final bool isOwnProfile;
  final VoidCallback onAddBuddy;
  final VoidCallback onCancelRequest;
  final VoidCallback onMessage;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final profile = details['profile'] is Map
        ? Map<String, dynamic>.from(details['profile'] as Map)
        : const <String, dynamic>{};
    final achievements = details['achievements'] is List
        ? (details['achievements'] as List).whereType<Map>().toList()
        : const <Map>[];
    final history = details['hikeHistory'] is List
        ? (details['hikeHistory'] as List).whereType<Map>().toList()
        : const <Map>[];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: _InsetGroup(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Avatar(
                        label: _circleInitial(person.name),
                        color: person.color,
                        size: 58,
                        imageUrl: person.photoURL,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: _CircleColors.textFor(context),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                _LevelBadge(level: person.level),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    person.levelName,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: _CircleColors.secondaryTextFor(
                                            context,
                                          ),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (isOwnProfile)
                        const _StatusPill(
                          label: 'You',
                          color: _CircleColors.green,
                        )
                      else if (isIncomingRequest)
                        const _StatusPill(
                          label: 'Requested you',
                          color: _CircleColors.orange,
                        )
                      else if (isRequested)
                        IconButton(
                          tooltip: 'Cancel friend request',
                          onPressed: onCancelRequest,
                          icon: const Icon(Icons.person_remove_outlined),
                        )
                      else if (!isBuddy)
                        IconButton.filled(
                          tooltip: 'Send friend request',
                          onPressed: onAddBuddy,
                          icon: const Icon(Icons.person_add_rounded),
                        )
                      else
                        const _StatusPill(
                          label: 'Buddy',
                          color: _CircleColors.green,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileInfoRow(
                    icon: Icons.terrain_rounded,
                    label: 'Experience',
                    value: person.subtitle.isEmpty
                        ? 'Not provided'
                        : person.subtitle,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.location_city_rounded,
                    label: 'Area',
                    value: person.trailAffinity,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Frequency',
                    value:
                        (profile['hikeFrequency']
                                ?.toString()
                                .trim()
                                .isNotEmpty ??
                            false)
                        ? profile['hikeFrequency'].toString()
                        : 'Not provided',
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: Theme.of(context).brightness == Brightness.dark
                            ? const [Color(0xFF173526), Color(0xFF202C24)]
                            : const [Color(0xFFE9F8EE), Color(0xFFFFF8E7)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFF59E0B),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile['levelName']?.toString() ??
                                        person.levelName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    '${profile['achievementPoints'] ?? 0} points · ${achievements.length} badges unlocked',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (achievements.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final achievement in achievements.take(8))
                                Chip(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.82),
                                  avatar: const Icon(
                                    Icons.emoji_events_rounded,
                                    size: 16,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  label: Text(
                                    achievement['title']?.toString() ??
                                        'Achievement',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Recent hikes',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final hike in history)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.route_rounded,
                          color: _CircleColors.green,
                        ),
                        title: Text(hike['trailName']?.toString() ?? 'Hike'),
                        subtitle: Text(
                          '${((hike['recordedDistanceKm'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} km · ${hike['hikeType'] == 'team' ? 'Group' : 'Solo'}',
                        ),
                      ),
                  ],
                  Text(
                    'Phone number and private route details are hidden.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _CircleColors.secondaryTextFor(context),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (isRequested && !isBuddy && !isOwnProfile) ...[
                    OutlinedButton.icon(
                      onPressed: onCancelRequest,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel friend request'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (!isOwnProfile)
                    FilledButton.icon(
                      onPressed: onMessage,
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Start conversation'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the share post to chat sheet.
class _SharePostToChatSheet extends StatelessWidget {
  /// Creates share post to chat sheet.
  const _SharePostToChatSheet({
    required this.chats,
    required this.currentPhone,
  });

  final List<GroupChat> chats;
  final String currentPhone;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: Material(
          color: _CircleColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'Share to Chat',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _CircleColors.textFor(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Flexible(
                  child: Scrollbar(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _CircleColors.greenSoftFor(
                              context,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _CircleColors.green,
                            ),
                          ),
                          title: Text(chat.displayNameFor(currentPhone)),
                          subtitle: Text(
                            chat.isDirect
                                ? 'Direct chat'
                                : '${chat.participantPhones.length} participants',
                          ),
                          trailing: const Icon(Icons.send_rounded),
                          onTap: () => Navigator.of(context).pop(chat),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the circle settings page.
class _CircleSettingsPage extends StatefulWidget {
  /// Creates circle settings page.
  const _CircleSettingsPage({required this.session, required this.repository});

  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<_CircleSettingsPage> createState() => _CircleSettingsPageState();
}

/// Manages the circle settings page presentation and lifecycle.
class _CircleSettingsPageState extends State<_CircleSettingsPage> {
  late final _CircleSettingsPageStateViewModel _screenModel;

  /// Returns group chat notifications enabled.
  bool get _groupChatNotificationsEnabled =>
      _screenModel.stateGroupChatNotificationsEnabled;

  /// Updates group chat notifications enabled.
  set _groupChatNotificationsEnabled(bool value) =>
      _screenModel.stateGroupChatNotificationsEnabled = value;

  /// Returns is loading group chat setting.
  bool get _isLoadingGroupChatSetting =>
      _screenModel.stateIsLoadingGroupChatSetting;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  bool _isSavingGroupChatSetting = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CircleSettingsPageStateViewModel(
      readRepository: () => widget.repository,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);

    unawaited(_loadGroupChatNotificationSetting());
  }

  /// Delegates load group chat notification setting to the ViewModel.
  Future<void> _loadGroupChatNotificationSetting() =>
      _screenModel.commandLoadGroupChatNotificationSetting();

  /// Sets group chat notifications enabled.
  Future<void> _setGroupChatNotificationsEnabled(bool enabled) async {
    if (_isSavingGroupChatSetting) {
      return;
    }
    final previous = _groupChatNotificationsEnabled;
    setState(() {
      _groupChatNotificationsEnabled = enabled;
      _isSavingGroupChatSetting = true;
    });
    try {
      await _CirclePageDataActions.setGroupChatNotificationsEnabled(
        widget.repository,
      )(session: widget.session, enabled: enabled);
    } catch (_) {
      if (mounted) {
        setState(() {
          _groupChatNotificationsEnabled = previous;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to update group chat notifications right now.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingGroupChatSetting = false;
        });
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CircleColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Circle Settings',
                    subtitle: 'Community and chat controls',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSwitchTile(
                    title: 'Auto-accept buddy requests',
                    subtitle:
                        'Not available yet. Buddy requests require confirmation.',
                    value: false,
                    onChanged: null,
                    unavailable: true,
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Nearby trail posts',
                    subtitle: 'Coming later with personalized community feeds.',
                    value: false,
                    onChanged: null,
                    unavailable: true,
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Group chat notifications',
                    subtitle: _groupChatNotificationsEnabled
                        ? 'Receive new-message alerts except for chats you muted individually.'
                        : 'All group chat message notifications are muted.',
                    value: _groupChatNotificationsEnabled,
                    onChanged:
                        _isLoadingGroupChatSetting || _isSavingGroupChatSetting
                        ? null
                        : (value) => unawaited(
                            _setGroupChatNotificationsEnabled(value),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Show hike history on profile',
                    subtitle: 'Profile privacy controls are not available yet.',
                    value: false,
                    onChanged: null,
                    unavailable: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}

/// Displays the circle animated toggle.
class _CircleAnimatedToggle extends StatelessWidget {
  /// Creates circle animated toggle.
  const _CircleAnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return AnimatedToggleSwitch<bool>.size(
      current: value,
      values: const [false, true],
      height: 38,
      spacing: 2,
      indicatorSize: const Size.square(32),
      borderWidth: 2,
      style: ToggleStyle(
        backgroundColor: _CircleColors.greenSoftFor(context),
        borderColor: _CircleColors.separatorFor(context),
        borderRadius: BorderRadius.circular(999),
        indicatorBorderRadius: BorderRadius.circular(999),
      ),
      styleBuilder: (enabled) => ToggleStyle(
        indicatorColor: enabled
            ? _CircleColors.green
            : _CircleColors.redFor(context),
      ),
      iconBuilder: (enabled) => Icon(
        enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled ? _CircleColors.green : _CircleColors.redFor(context),
        size: 17,
      ),
      foregroundIndicatorIconBuilder: (context, global) {
        final enabled = global.current;
        return Icon(
          enabled ? Icons.check_rounded : Icons.close_rounded,
          color: Colors.white,
          size: 18,
        );
      },
      iconOpacity: 0.72,
      selectedIconOpacity: 0,
      selectedIconScale: 1,
      animationDuration: const Duration(milliseconds: 260),
      animationCurve: Curves.easeOutCubic,
      onChanged: onChanged,
    );
  }
}

/// Displays the buddy requests sheet.
class _BuddyRequestsSheet extends StatelessWidget {
  /// Creates buddy requests sheet.
  const _BuddyRequestsSheet({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  final List<_BuddyRequest> requests;
  final ValueChanged<_BuddyRequest> onAccept;
  final ValueChanged<_BuddyRequest> onDecline;
  final ValueChanged<_BuddyRequest> onOpenProfile;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: _InsetGroup(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Friend Requests',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accept hikers before they become buddies.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 14),
                if (requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No pending friend requests.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _CircleColors.secondaryTextFor(context),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: requests.length,
                      separatorBuilder: (_, __) => const _HorizontalSeparator(),
                      itemBuilder: (context, index) {
                        final request = requests[index];
                        return _BuddyRequestRow(
                          request: request,
                          onAccept: () {
                            Navigator.of(context).pop();
                            onAccept(request);
                          },
                          onDecline: () {
                            Navigator.of(context).pop();
                            onDecline(request);
                          },
                          onOpenProfile: () => onOpenProfile(request),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _CircleColors.separatorFor(context).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: _CircleColors.shadowFor(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );
  }
}

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: _CircleColors.separatorFor(context).withValues(alpha: 0.5),
      ),
    );
  }
}

/// Computes community comment from firestore.
_CommunityComment _communityCommentFromFirestore(Map<String, dynamic> data) {
  final authorPhone = _stringFrom(data['authorPhoneNumber']);
  final authorName = _stringFrom(data['authorName']).isEmpty
      ? 'Hiker ${authorPhone.length >= 4 ? authorPhone.substring(authorPhone.length - 4) : ''}'
      : _stringFrom(data['authorName']);

  return _CommunityComment(
    commentId: _stringFrom(data['commentId']),
    author: authorName,
    handle: _stringFrom(data['authorHandle']).isEmpty
        ? _handleForPhone(authorPhone)
        : _stringFrom(data['authorHandle']),
    levelBadge: _stringFrom(data['authorLevelBadge']).isEmpty
        ? 'Lv. 1 Trailhead'
        : _stringFrom(data['authorLevelBadge']),
    level: _intFrom(data['authorLevel']) == 0
        ? 1
        : _intFrom(data['authorLevel']),
    body: _stringFrom(data['body']),
    timeLabel: _relativeTimeLabel(data['createdAtLocal']),
    authorPhotoURL: _stringFrom(data['authorPhotoURL']),
  );
}

/// Computes community person from profile.
_CommunityPerson _communityPersonFromProfile(Map<String, dynamic> data) {
  final name = _stringFrom(data['displayName']).isEmpty
      ? 'Hiker'
      : _stringFrom(data['displayName']);
  final experience = _stringFrom(data['hikerExperience']);
  final frequency = _stringFrom(data['hikeFrequency']);
  return _CommunityPerson(
    userId: _stringFrom(data['userId']),
    phoneNumber: _stringFrom(data['phoneNumber']),
    name: name,
    handle: _stringFrom(data['handle']),
    subtitle: [
      if (experience.isNotEmpty) experience,
      if (frequency.isNotEmpty) frequency,
    ].join(' · '),
    trailAffinity: _stringFrom(data['residentialLocation']).isEmpty
        ? 'HikerCircle'
        : _stringFrom(data['residentialLocation']),
    color: _colorForPost(_stringFrom(data['userId'])),
    level: _intFrom(data['level']) == 0 ? 1 : _intFrom(data['level']),
    levelName: _stringFrom(data['levelName']).isEmpty
        ? 'Trailhead'
        : _stringFrom(data['levelName']),
    gender: _stringFrom(data['gender']),
    photoURL: _stringFrom(data['photoURL']),
  );
}

/// Computes buddy request from firestore.
_BuddyRequest _buddyRequestFromFirestore(Map<String, dynamic> data) {
  final phoneNumber = _stringFrom(data['phoneNumber']);
  final name = _stringFrom(data['displayName']).isEmpty
      ? 'Hiker ${phoneNumber.length >= 4 ? phoneNumber.substring(phoneNumber.length - 4) : ''}'
      : _stringFrom(data['displayName']);
  return _BuddyRequest(
    phoneNumber: phoneNumber,
    name: name,
    handle: _stringFrom(data['handle']).isEmpty
        ? _handleForPhone(phoneNumber)
        : _stringFrom(data['handle']),
    photoURL: _stringFrom(data['photoURL']),
    createdAtLabel: _relativeTimeLabel(data['createdAtLocal']),
  );
}

/// Computes relative time label.
String _relativeTimeLabel(Object? rawValue) {
  final value = rawValue is String ? DateTime.tryParse(rawValue) : null;
  if (value == null) {
    return 'Just now';
  }
  final elapsed = DateTime.now().toUtc().difference(value.toUtc());
  if (elapsed.inMinutes < 1) {
    return 'Just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes}m ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours}h ago';
  }
  return '${elapsed.inDays}d ago';
}

/// Computes phone key for.
String _phoneKeyFor(String phoneNumber) {
  return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Handles for phone.
String _handleForPhone(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 4) {
    return '@hiker$digits';
  }
  return '@hiker${digits.substring(digits.length - 4)}';
}

/// Computes string from.
String _stringFrom(Object? value) {
  if (value is String) {
    return value;
  }
  return '';
}

/// Displays the chat action sheet.
class _ChatActionSheet extends StatelessWidget {
  /// Creates chat action sheet.
  const _ChatActionSheet({required this.displayName, required this.isPinned});

  final String displayName;
  final bool isPinned;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: Container(
          decoration: BoxDecoration(
            color: _CircleColors.surfaceFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _CircleColors.separatorFor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ActionOption(
                icon: isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                title: isPinned ? 'Unpin' : 'Pin',
                onTap: () => Navigator.of(context).pop('pin'),
              ),
              _ActionOption(
                icon: Icons.notifications_outlined,
                title: 'Chat notifications',
                onTap: () => Navigator.of(context).pop('notifications'),
              ),
              _ActionOption(
                icon: Icons.delete_outline_rounded,
                title: 'Delete',
                titleColor: _CircleColors.red,
                onTap: () => Navigator.of(context).pop('delete'),
              ),
              _ActionOption(
                icon: Icons.close_rounded,
                title: 'Cancel',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the action option.
class _ActionOption extends StatelessWidget {
  /// Creates action option.
  const _ActionOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? titleColor;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: _CircleColors.green, size: 22),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: titleColor ?? _CircleColors.textFor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Displays the chat notification settings sheet.
class _ChatNotificationSettingsSheet extends StatelessWidget {
  /// Creates chat notification settings sheet.
  const _ChatNotificationSettingsSheet({
    required this.chatName,
    required this.isMuted,
  });

  final String chatName;
  final bool isMuted;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: Container(
          decoration: BoxDecoration(
            color: _CircleColors.surfaceFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _CircleColors.separatorFor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat notifications',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _CircleColors.textFor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chatName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _CircleColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _NotificationOption(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications on',
                subtitle: isMuted
                    ? 'Currently muted'
                    : 'This chat is not muted',
                selected: !isMuted,
                onTap: () => Navigator.of(context).pop('unmute'),
              ),
              _NotificationOption(
                icon: Icons.schedule_rounded,
                title: 'Mute for 1 hour',
                onTap: () => Navigator.of(context).pop('1h'),
              ),
              _NotificationOption(
                icon: Icons.bedtime_rounded,
                title: 'Mute for 8 hours',
                onTap: () => Navigator.of(context).pop('8h'),
              ),
              _NotificationOption(
                icon: Icons.today_rounded,
                title: 'Mute for 1 day',
                onTap: () => Navigator.of(context).pop('1d'),
              ),
              _NotificationOption(
                icon: Icons.date_range_rounded,
                title: 'Mute for 1 week',
                onTap: () => Navigator.of(context).pop('1w'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the notification option.
class _NotificationOption extends StatelessWidget {
  /// Creates notification option.
  const _NotificationOption({
    required this.icon,
    required this.title,
    this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? _CircleColors.green
                      : _CircleColors.secondaryTextFor(context),
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _CircleColors.textFor(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _CircleColors.secondaryTextFor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_rounded,
                    color: _CircleColors.green,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Computes compact chat time.
String _compactChatTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    return '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  }
  return '${local.day}/${local.month}';
}

/// Computes circle initial.
String _circleInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// Computes int from.
int _intFrom(Object? value) {
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return 0;
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

/// Computes color for post.
Color _colorForPost(String postId) {
  const colors = [
    _CircleColors.green,
    _CircleColors.orange,
    _CircleColors.blue,
    _CircleColors.purple,
  ];
  if (postId.isEmpty) {
    return colors.first;
  }
  return colors[postId.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
      colors.length];
}

/// Represents circle colors.
abstract final class _CircleColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color red = Color(0xFFE11D48);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF7C3AED);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color shadow = Color(0x1A000000);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes red for.
  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;

  /// Computes shadow for.
  static Color shadowFor(BuildContext context) =>
      isDark(context) ? const Color(0x4D000000) : shadow;
}
