import 'dart:async';

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../../home/Model/hike_session_models.dart';
import 'group_chat_detail_page.dart';

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

  bool get _isAdmin => widget.session.isAdmin;
  final Set<String> _buddyHandles = {'@ainatrails', '@jasonridge'};
  late final List<_CommunityPerson> _people = _seedPeople();
  late List<_CommunityPost> _posts = const [];
  late final List<_TeamPlan> _teams = _seedTeams();
  bool _isLoadingPosts = false;
  List<GroupChat> _groupChats = const [];
  bool _isLoadingChats = false;
  StreamSubscription<List<GroupChat>>? _chatsSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCommunityPosts());
    _listenToGroupChats();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _listenToGroupChats() {
    final phone = widget.session.phoneNumber;
    _chatsSubscription = widget.hikerCircleRepository
        .userGroupChatsStream(phone)
        .listen((chats) {
      if (!mounted) return;
      setState(() {
        _groupChats = chats;
        _isLoadingChats = false;
      });
    }, onError: (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingChats = false;
      });
    });
    setState(() {
      _isLoadingChats = true;
    });
  }

  Future<void> _loadCommunityPosts() async {
    setState(() {
      _isLoadingPosts = true;
    });
    try {
      final posts = await widget.hikerCircleRepository.loadCommunityPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts.map(_communityPostFromFirestore).toList();
        _isLoadingPosts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
      });
    }
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
    try {
      await widget.hikerCircleRepository.createCompletedHikePost(
        session: widget.session,
        activeHike: hike,
        postType: 'active_hike_update',
        caption:
            'Live update from ${hike.trail.name}: ${hike.checkIns} check-ins, ${hike.manualPins} pins, ${hike.recordedDistanceKm.toStringAsFixed(2)} km tracked so far.',
      );
      await _loadCommunityPosts();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Hike route shared to community.'),
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

  void _openGroupChat(GroupChat chat) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupChatDetailPage(
          chat: chat,
          session: widget.session,
          repository: widget.hikerCircleRepository,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CircleSettingsPage(
          session: widget.session,
        ),
      ),
    );
  }

  Widget _buildSegment(int value, String label, IconData icon) {
    final isSelected = _selectedSection == value;
    return Expanded(
      child: GestureDetector(
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
            color: isSelected
                ? _CircleColors.green
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.white
                    : _CircleColors.secondaryTextFor(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : _CircleColors.secondaryTextFor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buddies = _people
        .where((person) => _buddyHandles.contains(person.handle))
        .toList();

    return ColoredBox(
      color: _CircleColors.backgroundFor(context),
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
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _CircleColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildSegment(0, 'Community', Icons.people_rounded),
                        if (_isAdmin)
                          _buildSegment(1, 'Teams', Icons.groups_2_rounded),
                        _buildSegment(
                          _isAdmin ? 2 : 1,
                          'Chats',
                          Icons.chat_rounded,
                        ),
                      ],
                    ),
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
                          : _isAdmin && _selectedSection == 1
                              ? _TeamsSection(
                                  buddies: buddies,
                                  teams: _teams,
                                  onCreateTeam: _createTeam,
                                )
                              : _ChatsSection(
                                  chats: _groupChats,
                                  isLoading: _isLoadingChats,
                                  phoneNumber: widget.session.phoneNumber,
                                  onOpenChat: _openGroupChat,
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
    this.routeCaptureId = '',
    this.routePointCount = 0,
    this.routePreviewPoints = const [],
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
  final String routeCaptureId;
  final int routePointCount;
  final List<HikeCoordinate> routePreviewPoints;

  bool get hasRouteMap => routePreviewPoints.length >= 2;
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
                    color: _CircleColors.textFor(context),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Community posts, buddies, and hiking teams',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryTextFor(context),
                    letterSpacing: 0,
                    fontSize: 13,
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
            height: 210,
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
        if (!isLoadingPosts && posts.isEmpty)
          const _InsetGroup(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No Firebase community posts yet. Shared hikes will appear here with their recorded route map.',
              ),
            ),
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
    final isDark = _CircleColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _CircleColors.green.withValues(alpha: 0.15),
        ),
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
                const _Avatar(label: 'Y', color: _CircleColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => unawaited(_openComposer(context)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1B261F)
                            : const Color(0xFFF5F7F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _CircleColors.separatorFor(context)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        activeHike == null
                            ? 'Share a trail note, photo, or question...'
                            : 'Share live progress from ${activeHike!.trail.name}...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _CircleColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => unawaited(_openComposer(context)),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Post'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _CircleColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: activeHike == null
                        ? null
                        : () => unawaited(onShareHike()),
                    icon: const Icon(Icons.hiking_rounded, size: 18),
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
      backgroundColor: _CircleColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _Avatar(label: 'Y', color: _CircleColors.green, size: 36),
                  const SizedBox(width: 10),
                  Text(
                    'Create a post',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _CircleColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                minLines: 4,
                maxLines: 6,
                maxLength: 280,
                decoration: InputDecoration(
                  hintText: 'Share a trail note, question, or safety update.',
                  hintStyle: TextStyle(
                    color: _CircleColors.secondaryTextFor(context),
                  ),
                  filled: true,
                  fillColor: _CircleColors.isDark(context)
                      ? const Color(0xFF1B261F)
                      : const Color(0xFFF5F7F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: _CircleColors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  counterStyle: TextStyle(
                    color: _CircleColors.secondaryTextFor(context),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _CircleColors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                icon: const Icon(Icons.send_rounded, size: 18),
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
      width: 220,
      child: Container(
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
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                                color: _CircleColors.textFor(context),
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
                                color: _CircleColors.secondaryTextFor(context),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: person.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  person.trailAffinity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: person.color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                person.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _CircleColors.secondaryTextFor(context),
                  letterSpacing: 0,
                  fontSize: 12,
                  height: 1.35,
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
                        style: FilledButton.styleFrom(
                          backgroundColor: _CircleColors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: onAddBuddy,
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 16,
                        ),
                        label: const Text('Add Buddy', style: TextStyle(fontSize: 13)),
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
          onTap: onOpenPost,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
                                        color: _CircleColors.textFor(context),
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
                                        color: _CircleColors.secondaryTextFor(
                                          context,
                                        ),
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
                                  color: _CircleColors.secondaryTextFor(
                                    context,
                                  ),
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
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _CircleColors.green,
                              side: BorderSide(
                                color: _CircleColors.green.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                            ),
                            onPressed: onAddBuddy,
                            child: const Text('Add',
                                style: TextStyle(fontSize: 12)),
                          ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  post.body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                if (post.hasRouteMap) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: _CommunityRouteThumbnail(post: post),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Row(
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
                      const Spacer(),
                      _PostAction(
                        icon: CupertinoIcons.arrowshape_turn_up_right,
                        label: 'Share',
                        onTap: () =>
                            _showDummySnack(context, 'Share sheet opened.'),
                      ),
                    ],
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
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: _CircleColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const _Avatar(
                            label: 'Y',
                            color: _CircleColors.green,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              minLines: 1,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: 'Write a comment...',
                                hintStyle: TextStyle(
                                  color: _CircleColors.secondaryTextFor(context),
                                ),
                                filled: true,
                                fillColor: _CircleColors.isDark(context)
                                    ? const Color(0xFF1B261F)
                                    : const Color(0xFFF5F7F5),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _CircleColors.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: _isPostingComment
                                  ? null
                                  : () => unawaited(_postComment()),
                              icon: _isPostingComment
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingComments)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_comments.isEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: _CircleColors.surfaceFor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _CircleColors.separatorFor(context)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No comments yet.\nBe the first to share your thoughts!',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: _CircleColors.surfaceFor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _CircleColors.separatorFor(context)
                              .withValues(alpha: 0.5),
                        ),
                      ),
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
                    color: _CircleColors.textFor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
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
    final isDark = _CircleColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _CircleColors.green.withValues(alpha: 0.15),
        ),
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
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Team'),
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
                    onPressed: () =>
                        _showDummySnack(context, 'Join code scanner opened.'),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
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
                          color: _CircleColors.separatorFor(context)
                              .withValues(alpha: 0.5),
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

class _TeamDetailPage extends StatelessWidget {
  const _TeamDetailPage({required this.team});

  final _TeamPlan team;

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
                    title: team.name,
                    subtitle: team.trail,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _CircleColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _CircleColors.shadowFor(context),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _InfoLine(
                                  label: 'Start', value: team.dateLabel),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: team.readiness >= 80
                                    ? _CircleColors.green.withValues(alpha: 0.1)
                                    : _CircleColors.orange
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                team.status,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: team.readiness >= 80
                                          ? _CircleColors.green
                                          : _CircleColors.orange,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
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
                        const SizedBox(height: 8),
                        Text(
                          '${team.readiness}% team readiness',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: _CircleColors.secondaryTextFor(context),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                                onPressed: () => _showDummySnack(
                                  context,
                                  'Team check-in schedule opened.',
                                ),
                                icon: const Icon(
                                    Icons.check_circle_rounded, size: 18),
                                label: const Text('Check-ins'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _CircleColors.green,
                                  side: BorderSide(
                                    color: _CircleColors.green
                                        .withValues(alpha: 0.3),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                                onPressed: () => _showDummySnack(
                                  context,
                                  'Invite manager opened.',
                                ),
                                icon: const Icon(
                                    Icons.group_add_rounded, size: 18),
                                label: const Text('Invite'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Roster'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _CircleColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _CircleColors.shadowFor(context),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
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
                  Container(
                    decoration: BoxDecoration(
                      color: _CircleColors.surfaceFor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _CircleColors.separatorFor(context)
                            .withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _CircleColors.shadowFor(context),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Column(
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
  const _CircleSettingsPage({required this.session});

  final AppSession session;

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
                  if (widget.session.isAdmin) ...[
                    const SizedBox(height: 22),
                    _SectionTitle(label: 'Moderation'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: _CircleColors.surfaceFor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _CircleColors.separatorFor(context)
                              .withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _CircleColors.shadowFor(context),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Column(
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
            _CircleAnimatedToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _CircleAnimatedToggle extends StatelessWidget {
  const _CircleAnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

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

class _RosterRow extends StatelessWidget {
  const _RosterRow({required this.name, required this.role});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    final isLeader = role == 'Leader';
    final isSweep = role == 'Sweep';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _Avatar(
            label: name.substring(0, 1),
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
            color: _CircleColors.secondaryTextFor(context).withValues(alpha: 0.5),
            size: 18,
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: _CircleColors.secondaryTextFor(context),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _CircleColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
                fontSize: 12,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _CircleColors.secondaryTextFor(context),
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _CircleColors.textFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: _CircleColors.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _CircleColors.secondaryTextFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
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
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _CircleColors.surfaceFor(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _CircleColors.separatorFor(context).withValues(alpha: 0.5),
            ),
          ),
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onBack,
            child: Icon(
              CupertinoIcons.chevron_back,
              color: _CircleColors.green,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _CircleColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.color, this.size = 42});

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
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
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          fontSize: size * 0.42,
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
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
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

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

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

class _CommunityRouteThumbnail extends StatefulWidget {
  const _CommunityRouteThumbnail({required this.post});

  final _CommunityPost post;

  @override
  State<_CommunityRouteThumbnail> createState() =>
      _CommunityRouteThumbnailState();
}

class _CommunityRouteThumbnailState extends State<_CommunityRouteThumbnail> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.CircleAnnotationManager? _circleManager;
  var _styleLoaded = false;
  var _routeRendered = false;
  late double _currentZoom = 13.5;
  late double _scaleLatitude;

  List<mapbox.Point> get _routePoints {
    return widget.post.routePreviewPoints
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final pts = _routePoints;
    if (pts.isNotEmpty) {
      _scaleLatitude = pts.first.coordinates[1]!.toDouble();
    }
  }

  @override
  void didUpdateWidget(covariant _CommunityRouteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.postId != widget.post.postId ||
        oldWidget.post.routePointCount != widget.post.routePointCount) {
      _routeRendered = false;
      unawaited(_renderRoute());
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await mapboxMap.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        rotateEnabled: true,
        pitchEnabled: true,
      ),
    );
    _polylineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    await _renderRoute();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    await enableTerrain3D(_mapboxMap!);
    schedulePitch(_mapboxMap!);
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRoute();
  }

  Future<void> _renderRoute() async {
    final points = _routePoints;
    if (_mapboxMap == null || !_styleLoaded || _routeRendered || points.length < 2) {
      return;
    }

    await _polylineManager?.deleteAll();
    await _circleManager?.deleteAll();

    await _polylineManager?.create(
      mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: [
          for (final pt in points)
            mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
        ]),
        lineColor: const Color(0xFF34A853).toARGB32(),
        lineOpacity: 0.94,
        lineWidth: 4.0,
        lineJoin: mapbox.LineJoin.ROUND,
      ),
    );
    await _circleManager?.createMulti([
      mapbox.CircleAnnotationOptions(
        geometry: points.first,
        circleColor: const Color(0xFF7BC90E).toARGB32(),
        circleRadius: 6,
        circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        circleStrokeWidth: 2,
      ),
      mapbox.CircleAnnotationOptions(
        geometry: points.last,
        circleColor: const Color(0xFF0A84FF).toARGB32(),
        circleRadius: 7,
        circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        circleStrokeWidth: 2,
      ),
    ]);

    _routeRendered = true;
    await _fitRoute();
  }

  Future<void> _fitRoute() async {
    final map = _mapboxMap;
    final points = _routePoints;
    if (map == null || points.length < 2) {
      return;
    }
    try {
      await map.flyTo(
        mapbox.CameraOptions(center: centerFor(points), zoom: _currentZoom),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {}
    await _syncScaleFromCamera();
  }

  Future<void> _zoomBy(double amount) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
    await _syncScaleFromCamera();
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
  }

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    if (map == null) return;
    final state = await map.getCameraState();
    if (!mounted) return;
    setState(() {
      _currentZoom = state.zoom;
      _scaleLatitude = state.center.coordinates[1]!.toDouble();
    });
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final nextLatitude = data.cameraState.center.coordinates[1]!.toDouble();
    if (!mounted ||
        ((nextZoom - _currentZoom).abs() < 0.005 &&
            (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = _routePoints;
    if (points.length < 2) {
      return CustomPaint(
        painter: _CommunityImagePainter(color: widget.post.color),
        child: const SizedBox.expand(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DeferredMap(
          child: mapbox.MapWidget(
            key: ValueKey('${widget.post.postId}:${widget.post.routePointCount}'),
            styleUri: mapStyleUrls[0],
            gestureRecognizers: mapGestureRecognizers,
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: (_) => _onStyleLoaded(),
            onCameraChangeListener: _onCameraChange,
            onMapIdleListener: (_) => unawaited(_syncScaleFromCamera()),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x11000000), Color(0x00000000), Color(0x77000000)],
            ),
          ),
        ),
        Positioned(
          left: 10,
          bottom: 9,
          child: _StatusPill(
            label: '${widget.post.routePointCount} GPS points',
            color: _CircleColors.green,
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: MapZoomControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
              onReset: _fitRoute,
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: MapScaleBar(
              zoom: _currentZoom,
              latitude: _scaleLatitude,
            ),
          ),
        ),
      ],
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
  final routePreviewPoints = _listOfMaps(
    data['routePreviewPoints'],
  ).map(HikeCoordinate.fromFirestore).toList();

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
    routeCaptureId: _stringFrom(data['routeCaptureId']),
    routePointCount: _intFrom(data['routePointCount']),
    routePreviewPoints: routePreviewPoints,
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

class _ChatsSection extends StatelessWidget {
  const _ChatsSection({
    required this.chats,
    required this.isLoading,
    required this.phoneNumber,
    required this.onOpenChat,
  });

  final List<GroupChat> chats;
  final bool isLoading;
  final String phoneNumber;
  final ValueChanged<GroupChat> onOpenChat;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Group Chats'),
        const SizedBox(height: 10),
        ...chats.map((chat) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GroupChatTile(
                chat: chat,
                phoneNumber: phoneNumber,
                onTap: () => onOpenChat(chat),
              ),
            )),
      ],
    );
  }
}

class _GroupChatTile extends StatelessWidget {
  const _GroupChatTile({
    required this.chat,
    required this.phoneNumber,
    required this.onTap,
  });

  final GroupChat chat;
  final String phoneNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherCount = chat.participantPhones.length - 1;
    final subtitle = otherCount > 0
        ? '$otherCount ${otherCount == 1 ? 'other' : 'others'}'
        : 'Just you';

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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _CircleColors.greenSoftFor(context),
                  radius: 26,
                  child: const Icon(
                    Icons.chat_rounded,
                    color: _CircleColors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.trailName,
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
                        chat.lastMessage ?? subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: _CircleColors.secondaryTextFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _CircleColors.greenSoftFor(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _CircleColors.green,
                    size: 18,
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

int _intFrom(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return 0;
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
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color red = Color(0xFFE11D48);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF7C3AED);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color shadow = Color(0x1A000000);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;

  static Color shadowFor(BuildContext context) =>
      isDark(context) ? const Color(0x4D000000) : shadow;
}
