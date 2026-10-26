part of '../../circle_page_feature.dart';

/// Displays the header.
class _Header extends StatelessWidget {
  /// Creates header.
  const _Header({
    required this.requestCount,
    required this.onOpenFriendRequests,
    required this.onOpenSettings,
  });

  final int requestCount;
  final VoidCallback onOpenFriendRequests;
  final VoidCallback onOpenSettings;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: PageHeader(
        title: 'Circle',
        subtitle: 'Community, buddies, teams',
        actions: [
          Badge(
            isLabelVisible: requestCount > 0,
            label: Text(requestCount > 9 ? '9+' : '$requestCount'),
            child: PageHeaderAction(
              tooltip: 'Friend requests',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: onOpenFriendRequests,
              color: colors.primary,
              surface: colors.surface,
            ),
          ),
          PageHeaderAction(
            tooltip: 'Circle settings',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: onOpenSettings,
            color: colors.primary,
            surface: colors.surface,
          ),
        ],
      ),
    );
  }
}

/// Displays the community section.
class _CommunitySection extends StatefulWidget {
  /// Creates community section.
  const _CommunitySection({
    required this.activeHike,
    required this.people,
    required this.posts,
    required this.isLoadingPosts,
    required this.postsLoadError,
    required this.onRetryPosts,
    required this.isLoadingMore,
    required this.hasMorePosts,
    required this.onLoadMore,
    required this.likingPostIds,
    required this.deletingPostIds,
    required this.moderatingPostIds,
    required this.isAdmin,
    required this.onModeratePost,
    required this.onDeletePost,
    required this.onLikePost,
    required this.buddyPhones,
    required this.outgoingBuddyRequestPhones,
    required this.busyBuddyRequestPhones,
    required this.currentUserPhone,
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onAddBuddy,
    required this.onCancelRequest,
    required this.onMessageBuddy,
    required this.onOpenPersonProfile,
    required this.onOpenProfile,
    required this.onSharePost,
    required this.onCreatePost,
    required this.onOpenPost,
  });

  final ActiveHikeSession? activeHike;
  final List<_CommunityPerson> people;
  final List<_CommunityPost> posts;
  final bool isLoadingPosts;
  final String? postsLoadError;
  final VoidCallback onRetryPosts;
  final bool isLoadingMore;
  final bool hasMorePosts;
  final VoidCallback onLoadMore;
  final Set<String> likingPostIds;
  final Set<String> deletingPostIds;
  final Set<String> moderatingPostIds;
  final bool isAdmin;
  final void Function(_CommunityPost, String) onModeratePost;
  final ValueChanged<_CommunityPost> onDeletePost;
  final ValueChanged<_CommunityPost> onLikePost;
  final Set<String> buddyPhones;
  final Set<String> outgoingBuddyRequestPhones;
  final Set<String> busyBuddyRequestPhones;
  final String currentUserPhone;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final ValueChanged<_CommunityPerson> onAddBuddy;
  final ValueChanged<_CommunityPerson> onCancelRequest;
  final ValueChanged<_CommunityPerson> onMessageBuddy;
  final ValueChanged<_CommunityPerson> onOpenPersonProfile;
  final ValueChanged<_CommunityPost> onOpenProfile;
  final ValueChanged<_CommunityPost> onSharePost;
  final VoidCallback onCreatePost;
  final ValueChanged<_CommunityPost> onOpenPost;

  /// Creates the presentation state for this widget.
  @override
  State<_CommunitySection> createState() => _CommunitySectionState();
}

/// Manages the community section presentation and lifecycle.
class _CommunitySectionState extends State<_CommunitySection> {
  String _filter = 'Everyone';
  String _query = '';
  bool _showPeople = false;
  bool _onlyBuddies = false;
  bool _showSearch = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final people = widget.people
        .where(
          (person) =>
              (!_onlyBuddies ||
                  widget.buddyPhones.contains(person.phoneNumber)) &&
              '${person.name} ${person.subtitle} ${person.trailAffinity}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    final posts = widget.posts
        .where(
          (post) =>
              (_filter != 'Buddies' ||
                  widget.buddyPhones.contains(post.authorPhoneNumber)) &&
              (_filter != 'Hike stories' || post.kind == 'hike') &&
              '${post.author} ${post.body} ${post.trail}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Stories'),
                    selected: !_showPeople,
                    onSelected: (_) => setState(() {
                      _showPeople = false;
                      _query = '';
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Find hikers'),
                    selected: _showPeople,
                    onSelected: (_) => setState(() {
                      _showPeople = true;
                      _query = '';
                    }),
                  ),
                ],
              ),
            ),
            if (!_showPeople)
              IconButton(
                tooltip: _showSearch ? 'Close search' : 'Search stories',
                onPressed: () => setState(() {
                  _showSearch = !_showSearch;
                  _query = '';
                }),
                icon: Icon(
                  _showSearch ? Icons.close_rounded : CupertinoIcons.search,
                  size: 20,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_showPeople || _showSearch)
          TextField(
            key: ValueKey('community-search-$_showPeople'),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: _showPeople
                  ? 'Search hikers or interests'
                  : 'Search stories, hikers or trails',
              prefixIcon: const Icon(CupertinoIcons.search, size: 20),
              filled: true,
              fillColor: _CircleColors.surfaceFor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_showPeople) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Find your next hiking buddy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilterChip(
                label: const Text('My buddies'),
                selected: _onlyBuddies,
                onSelected: (value) => setState(() => _onlyBuddies = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No hikers match this view. Try another search.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final person in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _CircleColors.surfaceFor(context),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  onTap: () => widget.onOpenPersonProfile(person),
                  leading: _Avatar(
                    label: _circleInitial(person.name),
                    color: person.color,
                    imageUrl: person.photoURL,
                  ),
                  title: Text(
                    person.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    person.trailAffinity.isNotEmpty
                        ? person.trailAffinity
                        : person.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _BuddyDiscoveryAction(
                    isBuddy: widget.buddyPhones.contains(person.phoneNumber),
                    isRequested: widget.outgoingBuddyRequestPhones.contains(
                      _phoneKeyFor(person.phoneNumber),
                    ),
                    isBusy: widget.busyBuddyRequestPhones.contains(
                      _phoneKeyFor(person.phoneNumber),
                    ),
                    onAdd: () => widget.onAddBuddy(person),
                    onCancel: () => widget.onCancelRequest(person),
                    onMessage: () => widget.onMessageBuddy(person),
                  ),
                ),
              ),
            ),
        ] else ...[
          _ComposerCard(
            activeHike: widget.activeHike,
            currentUserPhotoURL: widget.currentUserPhotoURL,
            currentUserPhotoBytes: widget.currentUserPhotoBytes,
            onCreatePost: widget.onCreatePost,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in ['Everyone', 'Buddies', 'Hike stories'])
                ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.isLoadingPosts && widget.posts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: HikerCircleMinorLoadingIndicator(size: 56)),
            ),
          if (widget.postsLoadError != null)
            ListTile(
              leading: const Icon(CupertinoIcons.cloud),
              title: Text(widget.postsLoadError!),
              trailing: TextButton(
                onPressed: widget.onRetryPosts,
                child: const Text('Retry'),
              ),
            ),
          if (!widget.isLoadingPosts &&
              posts.isEmpty &&
              widget.postsLoadError == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.chat_bubble_2,
                    size: 36,
                    color: _CircleColors.green,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.posts.isEmpty
                        ? 'Every circle starts with a story'
                        : 'No stories match this view',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.posts.isEmpty
                        ? 'Share a moment or ask the community a question.'
                        : 'Try Everyone or a different search.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _CircleColors.secondaryTextFor(context),
                    ),
                  ),
                ],
              ),
            ),
          for (final post in posts) ...[
            _CommunityPostCard(
              key: ValueKey(post.postId),
              post: post,
              isOwnPost:
                  post.isOwnPost ||
                  post.authorPhoneNumber == widget.currentUserPhone,
              onOpenPost: () => widget.onOpenPost(post),
              onOpenProfile: () => widget.onOpenProfile(post),
              onShare: () => widget.onSharePost(post),
              onLike: () => widget.onLikePost(post),
              likeBusy:
                  widget.likingPostIds.contains(post.postId) ||
                  widget.deletingPostIds.contains(post.postId) ||
                  widget.moderatingPostIds.contains(post.postId),
              deleteBusy:
                  widget.deletingPostIds.contains(post.postId) ||
                  widget.moderatingPostIds.contains(post.postId),
              isAdmin: widget.isAdmin,
              onModerate: widget.isAdmin
                  ? (status) => widget.onModeratePost(post, status)
                  : null,
              onDelete:
                  post.isOwnPost ||
                      post.authorPhoneNumber == widget.currentUserPhone
                  ? () => widget.onDeletePost(post)
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          if (widget.hasMorePosts && widget.posts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: OutlinedButton.icon(
                onPressed: widget.isLoadingMore ? null : widget.onLoadMore,
                icon: widget.isLoadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  widget.isLoadingMore ? 'Loading stories…' : 'More stories',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Displays the composer card.
class _ComposerCard extends StatelessWidget {
  /// Creates composer card.
  const _ComposerCard({
    required this.activeHike,
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onCreatePost,
  });
  final ActiveHikeSession? activeHike;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final VoidCallback onCreatePost;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Material(
    color: _CircleColors.surfaceFor(context),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: _CircleColors.green.withValues(alpha: .2)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onCreatePost,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _Avatar(
              label: 'Y',
              color: _CircleColors.green,
              imageUrl: currentUserPhotoURL,
              imageBytes: currentUserPhotoBytes,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Write a story',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activeHike == null
                        ? 'A moment, a photo, a question…'
                        : 'Share a moment from your hike',
                    style: TextStyle(
                      color: _CircleColors.secondaryTextFor(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _CircleColors.greenSoftFor(context),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.add_rounded, color: _CircleColors.green),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Displays the community post card.
class _CommunityPostCard extends StatefulWidget {
  /// Creates community post card.
  const _CommunityPostCard({
    super.key,
    required this.post,
    required this.isOwnPost,
    required this.onOpenPost,
    required this.onOpenProfile,
    required this.onShare,
    required this.onLike,
    this.likeBusy = false,
    this.expanded = false,
    this.onDelete,
    this.deleteBusy = false,
    this.isAdmin = false,
    this.onModerate,
  });
  final _CommunityPost post;
  final bool isOwnPost;
  final VoidCallback onOpenPost;
  final VoidCallback onOpenProfile;
  final VoidCallback onShare;
  final VoidCallback onLike;
  final bool likeBusy;
  final bool expanded;
  final VoidCallback? onDelete;
  final bool deleteBusy;
  final bool isAdmin;
  final ValueChanged<String>? onModerate;

  /// Creates the presentation state for this widget.
  @override
  State<_CommunityPostCard> createState() => _CommunityPostCardState();
}

/// Manages the community post card presentation and lifecycle.
class _CommunityPostCardState extends State<_CommunityPostCard> {
  bool _expandedCaption = false;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final quiet = _CircleColors.secondaryTextFor(context);
    final hasLongCaption =
        post.body.length > 240 || '\n'.allMatches(post.body).length > 3;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _CircleColors.separatorFor(context).withValues(alpha: .7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'View ${post.author}’s profile',
                  child: InkWell(
                    onTap: widget.onOpenProfile,
                    borderRadius: BorderRadius.circular(28),
                    child: _Avatar(
                      label: _circleInitial(post.author),
                      color: post.color,
                      imageUrl: post.authorPhotoURL,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: InkWell(
                    onTap: widget.onOpenProfile,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.isOwnPost
                                    ? '${post.author} (You)'
                                    : post.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _LevelBadge(level: post.level),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          post.timeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: quiet,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                CommunityPostOptions(
                  isAdmin: widget.isAdmin,
                  busy: widget.deleteBusy,
                  onDelete: widget.onDelete,
                  onHide: widget.onModerate == null
                      ? null
                      : () => widget.onModerate!('hidden'),
                  onRemove: widget.onModerate == null
                      ? null
                      : () => widget.onModerate!('removed'),
                ),
                if (post.kind == 'hike')
                  Tooltip(
                    message: post.hikeState == 'active'
                        ? 'Hike in progress'
                        : 'Hike story',
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _CircleColors.greenSoftFor(context),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hiking_rounded,
                        color: _CircleColors.green,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (post.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.body,
                    maxLines: widget.expanded || _expandedCaption ? null : 5,
                    overflow: widget.expanded || _expandedCaption
                        ? null
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  if (hasLongCaption && !widget.expanded)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 0),
                        minimumSize: const Size(48, 44),
                      ),
                      onPressed: () =>
                          setState(() => _expandedCaption = !_expandedCaption),
                      child: Text(_expandedCaption ? 'Show less' : 'Read more'),
                    ),
                ],
              ),
            ),
          if (post.imageUrls.isNotEmpty)
            _PostPhotoGallery(
              imageUrls: post.imageUrls,
              postId: post.postId ?? '',
            ),
          if (post.kind == 'hike' || post.hasRouteMap)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Material(
                color: _CircleColors.greenSoftFor(context),
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.expanded ? null : widget.onOpenPost,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (post.hasRouteMap)
                        SizedBox(
                          height: widget.expanded ? 240 : 130,
                          child: widget.expanded
                              ? CommunityRecordedRouteMap(
                                  recordingId:
                                      post.postId ?? post.routeCaptureId,
                                  trailName: post.trail,
                                  points: post.routePreviewPoints,
                                )
                              : CustomPaint(
                                  painter: _FeedRoutePainter(
                                    post.routePreviewPoints,
                                    _CircleColors.green,
                                    _CircleColors.greenSoftFor(context),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.terrain_rounded,
                                  size: 17,
                                  color: _CircleColors.green,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    post.trail,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (!widget.expanded)
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                  ),
                              ],
                            ),
                            if (post.distanceKm != null ||
                                post.durationMinutes != null) ...[
                              const SizedBox(height: 7),
                              Text(
                                [
                                  if (post.distanceKm != null)
                                    '${post.distanceKm!.toStringAsFixed(2)} km',
                                  if (post.durationMinutes != null)
                                    '${post.durationMinutes} min',
                                  if (post.hikeState == 'active') 'In progress',
                                ].join(' · '),
                                style: TextStyle(fontSize: 12, color: quiet),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(
              height: 1,
              color: _CircleColors.separatorFor(context).withValues(alpha: .55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Semantics(
                  toggled: post.isLiked,
                  button: true,
                  label: post.isLiked ? 'Unlike story' : 'Like story',
                  child: TextButton.icon(
                    key: ValueKey('like-${post.postId}'),
                    style: TextButton.styleFrom(
                      foregroundColor: post.isLiked
                          ? _CircleColors.redFor(context)
                          : quiet,
                      minimumSize: const Size(64, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: widget.likeBusy ? null : widget.onLike,
                    icon: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        post.isLiked
                            ? CupertinoIcons.heart_fill
                            : CupertinoIcons.heart,
                        key: ValueKey(post.isLiked),
                        size: 21,
                      ),
                    ),
                    label: Text(
                      '${post.likes}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('comments-${post.postId}'),
                  style: TextButton.styleFrom(
                    foregroundColor: quiet,
                    minimumSize: const Size(64, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: widget.onOpenPost,
                  icon: const Icon(CupertinoIcons.chat_bubble, size: 20),
                  label: Text(
                    '${post.replies}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Share story to chat',
                  onPressed: widget.onShare,
                  icon: Icon(
                    CupertinoIcons.arrowshape_turn_up_right,
                    color: quiet,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the post photo gallery.
class _PostPhotoGallery extends StatefulWidget {
  /// Creates post photo gallery.
  const _PostPhotoGallery({required this.imageUrls, required this.postId});
  final List<String> imageUrls;
  final String postId;

  /// Creates the presentation state for this widget.
  @override
  State<_PostPhotoGallery> createState() => _PostPhotoGalleryState();
}

/// Manages the post photo gallery presentation and lifecycle.
class _PostPhotoGalleryState extends State<_PostPhotoGallery> {
  final _controller = PageController();
  int _index = 0;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Column(
    children: [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => Semantics(
                button: true,
                label: 'Open photo ${index + 1} of ${widget.imageUrls.length}',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => _PhotoViewer(
                        imageUrls: widget.imageUrls,
                        initialIndex: index,
                      ),
                    ),
                  ),
                  child: _CommunityNetworkPhoto(url: widget.imageUrls[index]),
                ),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                top: 12,
                right: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      '${_index + 1}/${widget.imageUrls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (widget.imageUrls.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < widget.imageUrls.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => _controller.animateToPage(
                      index,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    ),
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      width: index == _index ? 18 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: index == _index
                            ? _CircleColors.green
                            : _CircleColors.separatorFor(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

/// Displays the comment row.
class _CommentRow extends StatelessWidget {
  /// Creates comment row.
  const _CommentRow({
    required this.comment,
    this.onRemove,
    this.removing = false,
  });

  final _CommunityComment comment;
  final VoidCallback? onRemove;
  final bool removing;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            label: _circleInitial(comment.author),
            color: _CircleColors.green,
            imageUrl: comment.authorPhotoURL,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.author,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _CircleColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _LevelBadge(level: comment.level),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        comment.handle,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _CircleColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (onRemove != null)
                      PopupMenuButton<String>(
                        tooltip: 'Moderate comment',
                        enabled: !removing,
                        icon: removing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.more_horiz_rounded, size: 20),
                        onSelected: (_) => onRemove?.call(),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove comment'),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.textFor(context),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.timeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the teams section.
class _TeamsSection extends StatelessWidget {
  /// Creates teams section.
  const _TeamsSection({
    required this.buddies,
    required this.teams,
    required this.onCreateTeam,
  });

  final List<_CommunityPerson> buddies;
  final List<_TeamPlan> teams;
  final VoidCallback onCreateTeam;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TeamBuilderCard(buddies: buddies, onCreateTeam: onCreateTeam),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Team Hikes'),
        const SizedBox(height: 8),
        for (final team in teams) ...[
          _TeamPlanCard(team: team),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 10),
        _SectionTitle(label: 'Team Flow'),
        const SizedBox(height: 8),
        const _InsetGroup(
          child: Column(
            children: [
              _TeamFlowRow(
                icon: Icons.route_rounded,
                title: 'Plan route',
                subtitle: 'Pick trail, time, checkpoints, and meetup place.',
              ),
              _HorizontalSeparator(),
              _TeamFlowRow(
                icon: Icons.group_add_rounded,
                title: 'Invite buddies',
                subtitle:
                    'Buddies accept, decline, or request a different time.',
              ),
              _HorizontalSeparator(),
              _TeamFlowRow(
                icon: Icons.location_searching_rounded,
                title: 'Track together',
                subtitle: 'During a hike, compare check-ins and stale updates.',
              ),
              _HorizontalSeparator(),
              _TeamFlowRow(
                icon: Icons.verified_user_rounded,
                title: 'Close safely',
                subtitle: 'Finish with team confirmation and shared recap.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Displays the team builder card.
class _TeamBuilderCard extends StatelessWidget {
  /// Creates team builder card.
  const _TeamBuilderCard({required this.buddies, required this.onCreateTeam});

  final List<_CommunityPerson> buddies;
  final VoidCallback onCreateTeam;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = _CircleColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CircleColors.green.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: _CircleColors.green.withValues(alpha: isDark ? 0.08 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _CircleColors.greenSoftFor(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_2_rounded,
                    color: _CircleColors.green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Build a hiking team',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _CircleColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                      ),
                      Text(
                        '${buddies.length} buddies available for invites',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _CircleColors.secondaryTextFor(context),
                          letterSpacing: 0,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (buddies.isEmpty)
                  const _StatusPill(
                    label: 'Add buddies from Community first',
                    color: _CircleColors.orange,
                  )
                else
                  for (final buddy in buddies.take(5))
                    _StatusPill(label: buddy.name, color: _CircleColors.green),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _CircleColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: onCreateTeam,
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('How to Start'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _CircleColors.green,
                      side: BorderSide(
                        color: _CircleColors.green.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: null,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Join Code Later'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the team plan card.
class _TeamPlanCard extends StatelessWidget {
  /// Creates team plan card.
  const _TeamPlanCard({required this.team});

  final _TeamPlan team;

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
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => _TeamDetailPage(team: team),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _CircleColors.greenSoftFor(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.flag_rounded,
                        color: _CircleColors.green,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _CircleColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            team.trail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _CircleColors.secondaryTextFor(
                                    context,
                                  ),
                                  letterSpacing: 0,
                                  fontSize: 13,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(label: team.status, color: _CircleColors.green),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _CircleColors.isDark(context)
                        ? const Color(0xFF1B261F)
                        : const Color(0xFFF5F7F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _InfoLine(label: 'Start', value: team.dateLabel),
                      ),
                      SizedBox(
                        height: 24,
                        child: VerticalDivider(
                          width: 1,
                          color: _CircleColors.separatorFor(
                            context,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                      Expanded(
                        child: _InfoLine(
                          label: 'Members',
                          value: '${team.members.length} invited',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: team.readiness / 100,
                          minHeight: 8,
                          color: team.readiness >= 80
                              ? _CircleColors.green
                              : team.readiness >= 50
                              ? _CircleColors.orange
                              : _CircleColors.red,
                          backgroundColor: _CircleColors.green.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${team.readiness}%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: _CircleColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to manage roles, invites, and check-ins',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    fontSize: 11,
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

/// Displays the profile info row.
class _ProfileInfoRow extends StatelessWidget {
  /// Creates profile info row.
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: _CircleColors.green, size: 19),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: _CircleColors.secondaryTextFor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _CircleColors.textFor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the settings switch tile.
class _SettingsSwitchTile extends StatelessWidget {
  /// Creates settings switch tile.
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.unavailable = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool unavailable;

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
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _CircleColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _CircleColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (unavailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _CircleColors.greenSoftFor(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Unavailable',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Opacity(
                opacity: onChanged == null ? 0.55 : 1,
                child: _CircleAnimatedToggle(
                  value: value,
                  onChanged: onChanged,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Displays the roster row.
class _RosterRow extends StatelessWidget {
  /// Creates roster row.
  const _RosterRow({required this.name, required this.role});

  final String name;
  final String role;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isLeader = role == 'Leader';
    final isSweep = role == 'Sweep';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _Avatar(
            label: _circleInitial(name),
            color: isLeader ? _CircleColors.green : _CircleColors.blue,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                if (isLeader)
                  Text(
                    'Team leader',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _CircleColors.green,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isLeader
                  ? _CircleColors.green.withValues(alpha: 0.1)
                  : isSweep
                  ? _CircleColors.orange.withValues(alpha: 0.1)
                  : _CircleColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLeader
                      ? Icons.star_rounded
                      : isSweep
                      ? Icons.gps_fixed_rounded
                      : Icons.person_rounded,
                  size: 13,
                  color: isLeader
                      ? _CircleColors.green
                      : isSweep
                      ? _CircleColors.orange
                      : _CircleColors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  role,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isLeader
                        ? _CircleColors.green
                        : isSweep
                        ? _CircleColors.orange
                        : _CircleColors.blue,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the team flow row.
class _TeamFlowRow extends StatelessWidget {
  /// Creates team flow row.
  const _TeamFlowRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _CircleColors.greenSoftFor(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _CircleColors.green, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                    letterSpacing: 0,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: _CircleColors.secondaryTextFor(
              context,
            ).withValues(alpha: 0.5),
            size: 18,
          ),
        ],
      ),
    );
  }
}

/// Displays the buddy request row.
class _BuddyRequestRow extends StatelessWidget {
  /// Creates buddy request row.
  const _BuddyRequestRow({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  final _BuddyRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenProfile;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Semantics(
            key: ValueKey(
              'buddy-request-profile-${_phoneKeyFor(request.phoneNumber)}',
            ),
            button: true,
            label: 'View ${request.name} profile',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenProfile,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _Avatar(
                  label: _circleInitial(request.name),
                  color: _colorForPost(request.phoneNumber),
                  imageUrl: request.photoURL,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    request.handle,
                    if (request.createdAtLabel.isNotEmpty)
                      request.createdAtLabel,
                  ].where((item) => item.isNotEmpty).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Decline',
            onPressed: onDecline,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Accept',
            onPressed: onAccept,
            icon: const Icon(Icons.check_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Displays the detail header.
class _DetailHeader extends StatelessWidget {
  /// Creates detail header.
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

/// Displays the avatar.
class _Avatar extends StatelessWidget {
  /// Creates avatar.
  const _Avatar({
    required this.label,
    required this.color,
    this.size = 42,
    this.imageUrl = '',
    this.imageBytes,
  });

  final String label;
  final Color color;
  final double size;
  final String imageUrl;
  final Uint8List? imageBytes;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final trimmedImageUrl = imageUrl.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: imageBytes != null && imageBytes!.isNotEmpty
          ? Image.memory(
              imageBytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    fontSize: size * 0.42,
                  ),
                ),
              ),
            )
          : trimmedImageUrl.isEmpty
          ? Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                fontSize: size * 0.42,
              ),
            )
          : Image.network(
              trimmedImageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    fontSize: size * 0.42,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Displays the level badge.
class _LevelBadge extends StatelessWidget {
  /// Creates level badge.
  const _LevelBadge({required this.level});

  final int level;

  /// Returns icon.
  IconData get _icon => switch (level) {
    1 => Icons.eco_rounded,
    2 => Icons.explore_rounded,
    3 => Icons.hiking_rounded,
    4 => Icons.landscape_rounded,
    5 => Icons.verified_rounded,
    6 => Icons.shield_rounded,
    _ => Icons.workspace_premium_rounded,
  };

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _CircleColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _CircleColors.green.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _CircleColors.green),
          const SizedBox(width: 3),
          Text(
            'L$level',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _CircleColors.green,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the status pill.
class _StatusPill extends StatelessWidget {
  /// Creates status pill.
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Displays the chats section.
class _ChatsSection extends StatelessWidget {
  /// Creates chats section.
  const _ChatsSection({
    required this.chats,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
    required this.phoneNumber,
    required this.pinnedChatIds,
    required this.currentUserName,
    this.localLastReadAt = const {},
    required this.onOpenChat,
    required this.onChatNotifications,
    required this.onDeleteChat,
    required this.onPinChat,
  });

  final List<GroupChat> chats;
  final bool isLoading;
  final String? loadError;
  final VoidCallback onRetry;
  final String phoneNumber;
  final Set<String> pinnedChatIds;
  final String currentUserName;
  final Map<String, DateTime> localLastReadAt;
  final ValueChanged<GroupChat> onOpenChat;
  final ValueChanged<GroupChat> onChatNotifications;
  final ValueChanged<GroupChat> onDeleteChat;
  final ValueChanged<GroupChat> onPinChat;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: HikerCircleLoadingView(
          message: 'Loading group chats…',
          detail: 'Getting your hike teams and recent messages.',
          compact: true,
        ),
      );
    }

    if (loadError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _CircleColors.greenSoftFor(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: _CircleColors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loadError!,
                style: TextStyle(
                  color: _CircleColors.textFor(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (chats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _CircleColors.greenSoftFor(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_rounded,
                  color: _CircleColors.green,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No group chats yet',
                style: TextStyle(
                  color: _CircleColors.textFor(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start a team hike to create one!',
                style: TextStyle(
                  color: _CircleColors.secondaryTextFor(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = List<GroupChat>.from(chats)
      ..sort(
        (a, b) => (b.lastMessageAt ?? b.createdAt).compareTo(
          a.lastMessageAt ?? a.createdAt,
        ),
      );
    final pinned = sorted.where((c) => pinnedChatIds.contains(c.id)).toList();
    final unpinned = sorted
        .where((c) => !pinnedChatIds.contains(c.id))
        .toList();

    final tiles = <Widget>[];
    if (pinned.isNotEmpty) {
      tiles.add(_SectionTitle(label: 'Pinned chats'));
      tiles.add(const SizedBox(height: 10));
      for (final chat in pinned) {
        tiles.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GroupChatTile(
              chat: chat,
              phoneNumber: phoneNumber,
              isPinned: true,
              localLastReadAt: localLastReadAt[chat.id],
              onTap: () => onOpenChat(chat),
              onChatNotifications: () => onChatNotifications(chat),
              onDeleteChat: () => onDeleteChat(chat),
              onPinChat: () => onPinChat(chat),
            ),
          ),
        );
      }
    }
    if (unpinned.isNotEmpty) {
      tiles.add(_SectionTitle(label: 'Chats'));
      tiles.add(const SizedBox(height: 10));
      for (final chat in unpinned) {
        tiles.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _GroupChatTile(
              chat: chat,
              phoneNumber: phoneNumber,
              isPinned: false,
              localLastReadAt: localLastReadAt[chat.id],
              onTap: () => onOpenChat(chat),
              onChatNotifications: () => onChatNotifications(chat),
              onDeleteChat: () => onDeleteChat(chat),
              onPinChat: () => onPinChat(chat),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: tiles,
    );
  }
}

/// Displays the group chat tile.
class _GroupChatTile extends StatefulWidget {
  /// Creates group chat tile.
  const _GroupChatTile({
    required this.chat,
    required this.phoneNumber,
    required this.isPinned,
    this.localLastReadAt,
    required this.onTap,
    required this.onChatNotifications,
    required this.onDeleteChat,
    required this.onPinChat,
  });

  final GroupChat chat;
  final String phoneNumber;
  final bool isPinned;
  final DateTime? localLastReadAt;
  final VoidCallback onTap;
  final VoidCallback onChatNotifications;
  final VoidCallback onDeleteChat;
  final VoidCallback onPinChat;

  /// Creates the presentation state for this widget.
  @override
  State<_GroupChatTile> createState() => _GroupChatTileState();
}

/// Manages the group chat tile presentation and lifecycle.
class _GroupChatTileState extends State<_GroupChatTile>
    with SingleTickerProviderStateMixin {
  late final _GroupChatTileStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late AnimationController _animController;
  late Animation<double> _borderAnim;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _GroupChatTileStateViewModel(
      readChat: () => widget.chat,
      readLocalLastReadAt: () => widget.localLastReadAt,
      readPhoneNumber: () => widget.phoneNumber,
    )..addListener(_renderScreenModel);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _borderAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.linear));
    _animController.addListener(() => setState(() {}));
    if (_hasUnread) {
      _animController.repeat();
    }
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(_GroupChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasUnread = _computeUnread(
      oldWidget.chat,
      widget.phoneNumber,
      oldWidget.localLastReadAt,
    );
    if (_hasUnread != wasUnread) {
      if (_hasUnread) {
        _animController.repeat();
      } else {
        _animController.stop();
        _animController.reset();
      }
    }
  }

  /// Delegates compute unread to the ViewModel.
  bool _computeUnread(GroupChat chat, String myPhone, DateTime? localReadAt) =>
      _screenModel.commandComputeUnread(chat, myPhone, localReadAt);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _animController.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Returns has unread.
  bool get _hasUnread => _screenModel.commandHasUnread;

  /// Returns unread count.
  int get _unreadCount => _screenModel.commandUnreadCount;

  /// Delegates format unread to the ViewModel.
  String _formatUnread(int count) => _screenModel.commandFormatUnread(count);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final otherCount = widget.chat.participantPhones.length - 1;
    final subtitle = otherCount > 0
        ? '$otherCount ${otherCount == 1 ? 'other' : 'others'}'
        : 'Just you';

    final displayName = widget.chat.displayNameFor(widget.phoneNumber);
    final ownPhoneKey = widget.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final otherPhone = widget.chat.participantPhones.firstWhere(
      (phone) => phone.replaceAll(RegExp(r'[^0-9]'), '') != ownPhoneKey,
      orElse: () => '',
    );
    final directPhotoURL = widget.chat.isDirect
        ? widget.chat.photoURLFor(otherPhone)
        : '';

    /// Shows action sheet.
    Future<void> showActionSheet() async {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _ChatActionSheet(
          displayName: displayName,
          isPinned: widget.isPinned,
        ),
      );
      if (action == null) return;
      switch (action) {
        case 'notifications':
          widget.onChatNotifications();
        case 'delete':
          widget.onDeleteChat();
        case 'pin':
          widget.onPinChat();
      }
    }

    final tileBody = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _CircleColors.greenSoftFor(context),
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: directPhotoURL.isEmpty
                    ? Icon(
                        widget.chat.isDirect
                            ? Icons.person_rounded
                            : Icons.groups_rounded,
                        color: _CircleColors.green,
                        size: 24,
                      )
                    : Image.network(
                        directPhotoURL,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          widget.chat.isDirect
                              ? Icons.person_rounded
                              : Icons.groups_rounded,
                          color: _CircleColors.green,
                          size: 24,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _CircleColors.textFor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.chat.lastMessage ?? subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _hasUnread
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: _CircleColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.chat.lastMessageAt != null)
                    Text(
                      _compactChatTime(widget.chat.lastMessageAt!),
                      style: TextStyle(
                        color: _CircleColors.secondaryTextFor(context),
                        fontSize: 11,
                        fontWeight: _hasUnread
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (_hasUnread)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _CircleColors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _formatUnread(_unreadCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _CircleColors.green,
                      size: 20,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final tile = Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: _hasUnread
            ? null
            : Border.all(
                color: _CircleColors.separatorFor(
                  context,
                ).withValues(alpha: 0.5),
              ),
        boxShadow: [
          BoxShadow(
            color: _CircleColors.shadowFor(context),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: _hasUnread
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  tileBody,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: BorderTravelPainter(
                          progress: _borderAnim.value,
                          color: _CircleColors.green,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : tileBody,
    );

    return Dismissible(
      key: ValueKey('chat_tile_${widget.chat.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      background: Container(
        decoration: BoxDecoration(
          color: _CircleColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _CircleColors.separatorFor(context).withValues(alpha: 0.5),
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _CircleColors.greenSoftFor(context),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.more_horiz_rounded, color: _CircleColors.green),
        ),
      ),
      confirmDismiss: (_) async {
        await showActionSheet();
        return false;
      },
      child: tile,
    );
  }
}
