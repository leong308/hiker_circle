import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/Model/hike_session_models.dart';

class CirclePage extends StatefulWidget {
  const CirclePage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    this.activeHike,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final ActiveHikeSession? activeHike;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<CirclePage> createState() => _CirclePageState();
}

class _CirclePageState extends State<CirclePage> {
  int _selectedSection = 0;
  final Set<String> _buddyHandles = {'@ainatrails', '@jasonridge'};
  late final List<_CommunityPerson> _people = _seedPeople();
  late List<_CommunityPost> _posts = _seedPosts();
  late final List<_TeamPlan> _teams = _seedTeams();
  bool _isLoadingPosts = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCommunityPosts());
  }

  Future<void> _loadCommunityPosts() async {
    setState(() {
      _isLoadingPosts = true;
    });
    final posts = await widget.hikerCircleRepository.loadCommunityPosts();
    if (!mounted) {
      return;
    }
    setState(() {
      if (posts.isNotEmpty) {
        _posts = posts.map(_communityPostFromFirestore).toList();
      }
      _isLoadingPosts = false;
    });
  }

  void _addBuddy(_CommunityPerson person) {
    if (_buddyHandles.contains(person.handle)) {
      return;
    }

    setState(() {
      _buddyHandles.add(person.handle);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${person.name} added as a buddy.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _createCommunityPost(String caption) async {
    try {
      await widget.hikerCircleRepository.createCommunityPost(
        session: widget.session,
        caption: caption,
      );
      await _loadCommunityPosts();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Community post shared.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _shareActiveHikeUpdate() async {
    final hike = widget.activeHike;
    if (hike == null) {
      return;
    }
    await _createCommunityPost(
      'Live update from ${hike.trail.name}: ${hike.checkIns} check-ins, ${hike.manualPins} pins, ${hike.recordedDistanceKm.toStringAsFixed(2)} km tracked so far.',
    );
  }

  void _openPostDetail(_CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return _CommunityPostDetailPage(
            session: widget.session,
            repository: widget.hikerCircleRepository,
            post: post,
          );
        },
      ),
    );
  }

  void _createTeam() {
    final buddies = _people
        .where((person) => _buddyHandles.contains(person.handle))
        .take(4)
        .map((person) => person.name)
        .toList();

    setState(() {
      _teams.insert(
        0,
        _TeamPlan(
          name: 'Morning Ridge Crew',
          trail: 'Broga Hill Trail',
          dateLabel: 'Saturday, 6:30 AM',
          status: 'Draft invites',
          members: ['You', ...buddies],
          readiness: 68,
        ),
      );
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Dummy hiking team created.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _CircleSettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buddies = _people
        .where((person) => _buddyHandles.contains(person.handle))
        .toList();

    return ColoredBox(
      color: _CircleColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(onOpenSettings: _openSettings),
                  const SizedBox(height: 16),
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: _selectedSection,
                    children: const {
                      0: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Community'),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Teams'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSection = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_selectedSection),
                      child: _selectedSection == 0
                          ? _CommunitySection(
                              activeHike: widget.activeHike,
                              people: _people,
                              posts: _posts,
                              isLoadingPosts: _isLoadingPosts,
                              buddyHandles: _buddyHandles,
                              onAddBuddy: _addBuddy,
                              onCreatePost: _createCommunityPost,
                              onShareHike: _shareActiveHikeUpdate,
                              onOpenPost: _openPostDetail,
                            )
                          : _TeamsSection(
                              buddies: buddies,
                              teams: _teams,
                              onCreateTeam: _createTeam,
                            ),
                    ),
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

class _CommunityPerson {
  const _CommunityPerson({
    required this.name,
    required this.handle,
    required this.subtitle,
    required this.trailAffinity,
    required this.color,
  });

  final String name;
  final String handle;
  final String subtitle;
  final String trailAffinity;
  final Color color;
}

class _CommunityPost {
  const _CommunityPost({
    this.postId,
    required this.author,
    required this.handle,
    required this.timeLabel,
    required this.trail,
    required this.body,
    required this.likes,
    required this.replies,
    required this.color,
  });

  final String? postId;
  final String author;
  final String handle;
  final String timeLabel;
  final String trail;
  final String body;
  final int likes;
  final int replies;
  final Color color;
}

class _CommunityComment {
  const _CommunityComment({
    required this.author,
    required this.handle,
    required this.body,
    required this.timeLabel,
  });

  final String author;
  final String handle;
  final String body;
  final String timeLabel;
}

class _TeamPlan {
  const _TeamPlan({
    required this.name,
    required this.trail,
    required this.dateLabel,
    required this.status,
    required this.members,
    required this.readiness,
  });

  final String name;
  final String trail;
  final String dateLabel;
  final String status;
  final List<String> members;
  final int readiness;
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circle',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _CircleColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Community posts, buddies, and hiking teams',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryText,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Circle settings',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(36),
              onPressed: onOpenSettings,
              child: const _CircleIcon(icon: CupertinoIcons.gear_alt_fill),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunitySection extends StatelessWidget {
  const _CommunitySection({
    required this.activeHike,
    required this.people,
    required this.posts,
    required this.isLoadingPosts,
    required this.buddyHandles,
    required this.onAddBuddy,
    required this.onCreatePost,
    required this.onShareHike,
    required this.onOpenPost,
  });

  final ActiveHikeSession? activeHike;
  final List<_CommunityPerson> people;
  final List<_CommunityPost> posts;
  final bool isLoadingPosts;
  final Set<String> buddyHandles;
  final ValueChanged<_CommunityPerson> onAddBuddy;
  final Future<void> Function(String caption) onCreatePost;
  final Future<void> Function() onShareHike;
  final ValueChanged<_CommunityPost> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final suggestions = people
        .where((person) => !buddyHandles.contains(person.handle))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComposerCard(
          activeHike: activeHike,
          onCreatePost: onCreatePost,
          onShareHike: onShareHike,
        ),
        const SizedBox(height: 18),
        _SectionTitle(label: 'Add Buddies'),
        const SizedBox(height: 8),
        if (suggestions.isEmpty)
          const _InsetGroup(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No new buddy suggestions right now.'),
            ),
          )
        else
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final person = suggestions[index];
                return _BuddySuggestionCard(
                  person: person,
                  isBuddy: false,
                  onAddBuddy: () => onAddBuddy(person),
                );
              },
            ),
          ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Community Feed'),
        const SizedBox(height: 8),
        if (isLoadingPosts)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        for (final post in posts) ...[
          _CommunityPostCard(
            post: post,
            isBuddy: buddyHandles.contains(post.handle),
            onOpenPost: () => onOpenPost(post),
            onAddBuddy: () {
              final person = people.firstWhere(
                (person) => person.handle == post.handle,
                orElse: () => _CommunityPerson(
                  name: post.author,
                  handle: post.handle,
                  subtitle: 'Community hiker',
                  trailAffinity: post.trail,
                  color: post.color,
                ),
              );
              onAddBuddy(person);
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.activeHike,
    required this.onCreatePost,
    required this.onShareHike,
  });

  final ActiveHikeSession? activeHike;
  final Future<void> Function(String caption) onCreatePost;
  final Future<void> Function() onShareHike;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Avatar(label: 'Y', color: _CircleColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    activeHike == null
                        ? 'Share a trail note, photo, or question...'
                        : 'Share live progress from ${activeHike!.trail.name}...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _CircleColors.secondaryText,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_openComposer(context)),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Post'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: activeHike == null
                        ? null
                        : () => unawaited(onShareHike()),
                    icon: const Icon(Icons.hiking_rounded),
                    label: const Text('Share Hike'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openComposer(BuildContext context) async {
    final controller = TextEditingController();
    final caption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New community post',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _CircleColors.text,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                maxLength: 280,
                decoration: const InputDecoration(
                  hintText: 'Share a trail note, question, or safety update.',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Post'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    if (caption == null || caption.trim().isEmpty) {
      return;
    }
    await onCreatePost(caption.trim());
  }
}

class _BuddySuggestionCard extends StatelessWidget {
  const _BuddySuggestionCard({
    required this.person,
    required this.isBuddy,
    required this.onAddBuddy,
  });

  final _CommunityPerson person;
  final bool isBuddy;
  final VoidCallback onAddBuddy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(
                    label: person.name.substring(0, 1),
                    color: person.color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: _CircleColors.text,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                        Text(
                          person.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _CircleColors.secondaryText,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                person.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _CircleColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: isBuddy
                    ? const _StatusPill(
                        label: 'Buddy',
                        color: _CircleColors.green,
                      )
                    : FilledButton.icon(
                        onPressed: onAddBuddy,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add Buddy'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.isBuddy,
    required this.onOpenPost,
    required this.onAddBuddy,
  });

  final _CommunityPost post;
  final bool isBuddy;
  final VoidCallback onOpenPost;
  final VoidCallback onAddBuddy;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenPost,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(
                      label: post.author.substring(0, 1),
                      color: post.color,
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
                                  post.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: _CircleColors.text,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  post.handle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: _CircleColors.secondaryText,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${post.timeLabel} - ${post.trail}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _CircleColors.secondaryText,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    isBuddy
                        ? const _StatusPill(
                            label: 'Buddy',
                            color: _CircleColors.green,
                          )
                        : OutlinedButton(
                            onPressed: onAddBuddy,
                            child: const Text('Add'),
                          ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  post.body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _CircleColors.text,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    painter: _CommunityImagePainter(color: post.color),
                    child: const SizedBox(height: 152, width: double.infinity),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PostAction(
                      icon: CupertinoIcons.heart,
                      label: '${post.likes}',
                      onTap: () => _showDummySnack(context, 'Liked post.'),
                    ),
                    const SizedBox(width: 18),
                    _PostAction(
                      icon: CupertinoIcons.chat_bubble,
                      label: '${post.replies}',
                      onTap: onOpenPost,
                    ),
                    const SizedBox(width: 18),
                    _PostAction(
                      icon: CupertinoIcons.arrowshape_turn_up_right,
                      label: 'Share',
                      onTap: () =>
                          _showDummySnack(context, 'Share sheet opened.'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityPostDetailPage extends StatefulWidget {
  const _CommunityPostDetailPage({
    required this.session,
    required this.repository,
    required this.post,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final _CommunityPost post;

  @override
  State<_CommunityPostDetailPage> createState() =>
      _CommunityPostDetailPageState();
}

class _CommunityPostDetailPageState extends State<_CommunityPostDetailPage> {
  final _commentController = TextEditingController();
  List<_CommunityComment> _comments = const [];
  bool _isLoadingComments = false;
  bool _isPostingComment = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadComments());
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    final postId = widget.post.postId;
    if (postId == null || postId.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingComments = true;
    });
    final comments = await widget.repository.loadCommunityComments(
      postId: postId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _comments = comments.map(_communityCommentFromFirestore).toList();
      _isLoadingComments = false;
    });
  }

  Future<void> _postComment() async {
    final postId = widget.post.postId;
    final body = _commentController.text.trim();
    if (_isPostingComment || body.isEmpty) {
      return;
    }
    if (postId == null || postId.isEmpty) {
      _showDetailSnack('Only Firebase community posts support comments.');
      return;
    }

    setState(() {
      _isPostingComment = true;
    });
    try {
      await widget.repository.addCommunityComment(
        session: widget.session,
        postId: postId,
        body: body,
      );
      _commentController.clear();
      await _loadComments();
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showDetailSnack(error.message);
    } catch (_) {
      _showDetailSnack('Unable to add comment right now.');
    } finally {
      if (mounted) {
        setState(() {
          _isPostingComment = false;
        });
      }
    }
  }

  void _showDetailSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Scaffold(
      backgroundColor: _CircleColors.background,
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
                    title: post.author,
                    subtitle: '${post.timeLabel} - ${post.trail}',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _CommunityPostCard(
                    post: post,
                    isBuddy: true,
                    onOpenPost: () {},
                    onAddBuddy: () {},
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Comments'),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              minLines: 1,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Write a comment...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: _isPostingComment
                                ? null
                                : () => unawaited(_postComment()),
                            icon: _isPostingComment
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoadingComments)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (_comments.isEmpty)
                    const _InsetGroup(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No comments yet.'),
                      ),
                    )
                  else
                    _InsetGroup(
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < _comments.length;
                            index++
                          ) ...[
                            _CommentRow(comment: _comments[index]),
                            if (index != _comments.length - 1)
                              const _HorizontalSeparator(),
                          ],
                        ],
                      ),
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

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final _CommunityComment comment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            label: comment.author.isEmpty
                ? '?'
                : comment.author.substring(0, 1),
            color: _CircleColors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comment.author} ${comment.handle}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _CircleColors.text,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.text,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  comment.timeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _CircleColors.secondaryText,
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

class _TeamsSection extends StatelessWidget {
  const _TeamsSection({
    required this.buddies,
    required this.teams,
    required this.onCreateTeam,
  });

  final List<_CommunityPerson> buddies;
  final List<_TeamPlan> teams;
  final VoidCallback onCreateTeam;

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

class _TeamBuilderCard extends StatelessWidget {
  const _TeamBuilderCard({required this.buddies, required this.onCreateTeam});

  final List<_CommunityPerson> buddies;
  final VoidCallback onCreateTeam;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.groups_2_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Build a hiking team',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _CircleColors.text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        '${buddies.length} buddies available for invites',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _CircleColors.secondaryText,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCreateTeam,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Team'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showDummySnack(context, 'Join code scanner opened.'),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Join Code'),
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

class _TeamPlanCard extends StatelessWidget {
  const _TeamPlanCard({required this.team});

  final _TeamPlan team;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => _TeamDetailPage(team: team),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const _Glyph(icon: Icons.flag_rounded),
                    const SizedBox(width: 12),
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
                                  color: _CircleColors.text,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          Text(
                            team.trail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _CircleColors.secondaryText,
                                  letterSpacing: 0,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(label: team.status, color: _CircleColors.green),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoLine(label: 'Start', value: team.dateLabel),
                _InfoLine(
                  label: 'Members',
                  value: '${team.members.length} invited',
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: team.readiness / 100,
                    minHeight: 6,
                    color: _CircleColors.green,
                    backgroundColor: _CircleColors.green.withValues(
                      alpha: 0.14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${team.readiness}% team readiness - tap to manage roles, invites, and check-ins',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _CircleColors.secondaryText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
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

class _TeamDetailPage extends StatelessWidget {
  const _TeamDetailPage({required this.team});

  final _TeamPlan team;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CircleColors.background,
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
                    title: team.name,
                    subtitle: team.trail,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InfoLine(label: 'Start', value: team.dateLabel),
                          _InfoLine(label: 'Status', value: team.status),
                          _InfoLine(
                            label: 'Team readiness',
                            value: '${team.readiness}%',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _showDummySnack(
                                    context,
                                    'Team check-in schedule opened.',
                                  ),
                                  icon: const Icon(Icons.check_circle_rounded),
                                  label: const Text('Check-ins'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showDummySnack(
                                    context,
                                    'Invite manager opened.',
                                  ),
                                  icon: const Icon(Icons.group_add_rounded),
                                  label: const Text('Invite'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Roster'),
                  const SizedBox(height: 8),
                  _InsetGroup(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < team.members.length;
                          index++
                        ) ...[
                          _RosterRow(
                            name: team.members[index],
                            role: index == 0
                                ? 'Leader'
                                : index == team.members.length - 1
                                ? 'Sweep'
                                : 'Member',
                          ),
                          if (index != team.members.length - 1)
                            const _HorizontalSeparator(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Team Safety Logic'),
                  const SizedBox(height: 8),
                  const _InsetGroup(
                    child: Column(
                      children: [
                        _TeamFlowRow(
                          icon: Icons.social_distance_rounded,
                          title: 'Separation watch',
                          subtitle:
                              'Warn when a member is too far ahead or behind.',
                        ),
                        _HorizontalSeparator(),
                        _TeamFlowRow(
                          icon: Icons.timer_rounded,
                          title: 'Stale update watch',
                          subtitle:
                              'Flag members who miss expected location updates.',
                        ),
                        _HorizontalSeparator(),
                        _TeamFlowRow(
                          icon: Icons.route_rounded,
                          title: 'Route boundary watch',
                          subtitle:
                              'Compare team progress with planned checkpoints.',
                        ),
                      ],
                    ),
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

class _CircleSettingsPage extends StatefulWidget {
  const _CircleSettingsPage();

  @override
  State<_CircleSettingsPage> createState() => _CircleSettingsPageState();
}

class _CircleSettingsPageState extends State<_CircleSettingsPage> {
  bool _autoAcceptBuddies = false;
  bool _nearbyTrailPosts = true;
  bool _teamInviteAlerts = true;
  bool _showHikeHistory = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CircleColors.background,
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
                    subtitle: 'Community and team controls',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSwitchTile(
                    title: 'Auto-accept buddy requests',
                    subtitle: 'Only for people with two mutual buddies.',
                    value: _autoAcceptBuddies,
                    onChanged: (value) {
                      setState(() {
                        _autoAcceptBuddies = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Nearby trail posts',
                    subtitle:
                        'Prioritize posts from trails you saved or hiked.',
                    value: _nearbyTrailPosts,
                    onChanged: (value) {
                      setState(() {
                        _nearbyTrailPosts = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Team invite alerts',
                    subtitle: 'Notify when buddies invite you to a hike.',
                    value: _teamInviteAlerts,
                    onChanged: (value) {
                      setState(() {
                        _teamInviteAlerts = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _SettingsSwitchTile(
                    title: 'Show hike history on profile',
                    subtitle: 'Buddies can see completed public hikes.',
                    value: _showHikeHistory,
                    onChanged: (value) {
                      setState(() {
                        _showHikeHistory = value;
                      });
                    },
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Moderation'),
                  const SizedBox(height: 8),
                  const _InsetGroup(
                    child: Column(
                      children: [
                        _TeamFlowRow(
                          icon: Icons.visibility_off_rounded,
                          title: 'Muted topics',
                          subtitle: 'Hide route spam, gear sales, or events.',
                        ),
                        _HorizontalSeparator(),
                        _TeamFlowRow(
                          icon: Icons.block_rounded,
                          title: 'Blocked hikers',
                          subtitle: 'Manage people who cannot message you.',
                        ),
                      ],
                    ),
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

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          activeThumbColor: _CircleColors.green,
          activeTrackColor: _CircleColors.green.withValues(alpha: 0.24),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _CircleColors.text,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _CircleColors.secondaryText,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.name, required this.role});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _Avatar(label: name.substring(0, 1), color: _CircleColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _CircleColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          _StatusPill(label: role, color: _CircleColors.green),
        ],
      ),
    );
  }
}

class _TeamFlowRow extends StatelessWidget {
  const _TeamFlowRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _CircleColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryText,
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

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _CircleColors.secondaryText),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _CircleColors.secondaryText,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _CircleColors.secondaryText,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _CircleColors.text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _CircleColors.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _CircleColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _CircleColors.secondaryText,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _CircleColors.green, size: 19),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

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

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _CircleColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _CircleColors.separator,
    );
  }
}

class _CommunityImagePainter extends CustomPainter {
  const _CommunityImagePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = color.withValues(alpha: 0.72);
    final hillBack = Paint()
      ..color = _CircleColors.green.withValues(alpha: 0.58);
    final hillFront = Paint()..color = _CircleColors.green;
    final pathPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Offset.zero & size, sky);

    final back = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width * 0.24, size.height * 0.38)
      ..lineTo(size.width * 0.48, size.height * 0.68)
      ..lineTo(size.width * 0.70, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.70)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, hillBack);

    final front = Path()
      ..moveTo(0, size.height * 0.86)
      ..lineTo(size.width * 0.30, size.height * 0.54)
      ..lineTo(size.width * 0.58, size.height * 0.78)
      ..lineTo(size.width * 0.84, size.height * 0.50)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, hillFront);

    final trail = Path()
      ..moveTo(size.width * 0.16, size.height * 0.90)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.74,
        size.width * 0.46,
        size.height * 0.82,
        size.width * 0.56,
        size.height * 0.64,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.48,
        size.width * 0.78,
        size.height * 0.56,
        size.width * 0.88,
        size.height * 0.42,
      );
    canvas.drawPath(trail, pathPaint);
  }

  @override
  bool shouldRepaint(covariant _CommunityImagePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

List<_CommunityPerson> _seedPeople() {
  return const [
    _CommunityPerson(
      name: 'Aina',
      handle: '@ainatrails',
      subtitle: 'Weekend ridge hiker. Shares weather notes and route timing.',
      trailAffinity: 'Broga Hill',
      color: _CircleColors.green,
    ),
    _CommunityPerson(
      name: 'Jason',
      handle: '@jasonridge',
      subtitle: 'Team lead for beginner-friendly morning hikes.',
      trailAffinity: 'Bukit Gasing',
      color: _CircleColors.blue,
    ),
    _CommunityPerson(
      name: 'Mei Lin',
      handle: '@meiclimbs',
      subtitle: 'Likes technical climbs and careful checkpoint planning.',
      trailAffinity: 'Bukit Tabur',
      color: _CircleColors.orange,
    ),
    _CommunityPerson(
      name: 'Farid',
      handle: '@faridforest',
      subtitle: 'Photographer, sweep role, and rain-route planner.',
      trailAffinity: 'Penang Hill',
      color: _CircleColors.purple,
    ),
  ];
}

List<_CommunityPost> _seedPosts() {
  return const [
    _CommunityPost(
      author: 'Aina',
      handle: '@ainatrails',
      timeLabel: '12 min',
      trail: 'Broga Hill Trail',
      body:
          'Started before sunrise and the upper section dried faster than expected. Bring a headlamp and avoid the muddy right fork.',
      likes: 42,
      replies: 8,
      color: _CircleColors.green,
    ),
    _CommunityPost(
      author: 'Mei Lin',
      handle: '@meiclimbs',
      timeLabel: '48 min',
      trail: 'Bukit Tabur Trail',
      body:
          'Loose stones near the ridge are still a problem. Smaller groups moved better today. I would not bring first-timers this week.',
      likes: 31,
      replies: 12,
      color: _CircleColors.orange,
    ),
    _CommunityPost(
      author: 'Farid',
      handle: '@faridforest',
      timeLabel: '2 hr',
      trail: 'Penang Hill Heritage Trail',
      body:
          'Misty but calm. The middle station checkpoint is a good regroup spot before the climb gets steeper.',
      likes: 64,
      replies: 15,
      color: _CircleColors.purple,
    ),
  ];
}

List<_TeamPlan> _seedTeams() {
  return const [
    _TeamPlan(
      name: 'Gasing Easy Loop',
      trail: 'Bukit Gasing Trail',
      dateLabel: 'Sunday, 7:00 AM',
      status: 'Ready',
      members: ['You', 'Aina', 'Jason', 'Farid'],
      readiness: 92,
    ),
    _TeamPlan(
      name: 'Penang Mist Walk',
      trail: 'Penang Hill Heritage Trail',
      dateLabel: 'Next Friday, 6:45 AM',
      status: 'Inviting',
      members: ['You', 'Mei Lin', 'Farid'],
      readiness: 74,
    ),
  ];
}

_CommunityPost _communityPostFromFirestore(Map<String, dynamic> data) {
  final authorPhone = _stringFrom(data['authorPhoneNumber']);
  final authorName = _stringFrom(data['authorName']).isEmpty
      ? 'Hiker ${authorPhone.length >= 4 ? authorPhone.substring(authorPhone.length - 4) : ''}'
      : _stringFrom(data['authorName']);
  final handle = _stringFrom(data['authorHandle']).isEmpty
      ? _handleForPhone(authorPhone)
      : _stringFrom(data['authorHandle']);
  final trailName = _stringFrom(data['trailName']).isEmpty
      ? 'Community'
      : _stringFrom(data['trailName']);
  final caption = _stringFrom(data['caption']).isEmpty
      ? 'Shared a trail update.'
      : _stringFrom(data['caption']);

  return _CommunityPost(
    postId: _stringFrom(data['postId']),
    author: authorName,
    handle: handle,
    timeLabel: _relativeTimeLabel(data['createdAtLocal']),
    trail: trailName,
    body: caption,
    likes: _intFrom(data['likeCount']),
    replies: _intFrom(data['commentCount']),
    color: _colorForPost(_stringFrom(data['postId'])),
  );
}

_CommunityComment _communityCommentFromFirestore(Map<String, dynamic> data) {
  final authorPhone = _stringFrom(data['authorPhoneNumber']);
  final authorName = _stringFrom(data['authorName']).isEmpty
      ? 'Hiker ${authorPhone.length >= 4 ? authorPhone.substring(authorPhone.length - 4) : ''}'
      : _stringFrom(data['authorName']);

  return _CommunityComment(
    author: authorName,
    handle: _stringFrom(data['authorHandle']).isEmpty
        ? _handleForPhone(authorPhone)
        : _stringFrom(data['authorHandle']),
    body: _stringFrom(data['body']),
    timeLabel: _relativeTimeLabel(data['createdAtLocal']),
  );
}

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

String _handleForPhone(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 4) {
    return '@hiker$digits';
  }
  return '@hiker${digits.substring(digits.length - 4)}';
}

String _stringFrom(Object? value) {
  if (value is String) {
    return value;
  }
  return '';
}

int _intFrom(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

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

void _showDummySnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

abstract final class _CircleColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF7C3AED);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
}
