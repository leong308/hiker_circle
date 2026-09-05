import '../../core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/loading_toast.dart';
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
  final Set<String> _buddyPhones = {};
  final Set<String> _outgoingBuddyRequestPhones = {};
  List<_BuddyRequest> _buddyRequests = const [];
  List<_CommunityPerson> _people = const [];
  late List<_CommunityPost> _posts = const [];
  final List<_TeamPlan> _teams = const [];
  bool _isLoadingPosts = false;
  String? _postsLoadError;
  List<GroupChat> _groupChats = const [];
  bool _isLoadingChats = false;
  String? _chatsLoadError;
  Set<String> _pinnedChatIds = {};
  final Map<String, int> _pinUpdateGeneration = {};
  final Map<String, Future<void>> _pinWriteChains = {};
  Map<String, DateTime> _localLastReadAt = const {};
  String _currentUserPhotoURL = '';
  StreamSubscription<List<GroupChat>>? _chatsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _buddyRequestsSubscription;

  @override
  void initState() {
    super.initState();
    _currentUserPhotoURL = widget.session.photoURL ?? '';
    unawaited(_loadCommunityPosts());
    unawaited(_loadCommunityPeople());
    unawaited(_loadCurrentUserPhoto());
    unawaited(_loadPinnedChats());
    _listenToBuddyRequests();
    _listenToGroupChats();
  }

  Future<void> _loadCurrentUserPhoto() async {
    try {
      final profile = await widget.hikerCircleRepository.loadCommunityProfile(
        phoneNumber: widget.session.phoneNumber,
      );
      if (!mounted || profile == null) return;
      final photoURL = _stringFrom(profile['photoURL']).trim();
      if (photoURL.isEmpty || photoURL == _currentUserPhotoURL) return;
      setState(() {
        _currentUserPhotoURL = photoURL;
      });
    } catch (_) {
      // The session avatar remains available if its remote refresh fails.
    }
  }

  Future<void> _loadCommunityPeople() async {
    try {
      final results = await Future.wait<Object>([
        widget.hikerCircleRepository.loadCommunityProfiles(
          session: widget.session,
        ),
        widget.hikerCircleRepository.loadBuddyPhoneNumbers(
          session: widget.session,
        ),
        widget.hikerCircleRepository.loadOutgoingBuddyRequestPhoneNumbers(
          session: widget.session,
        ),
      ]);
      if (!mounted) return;
      final profiles = results[0] as List<Map<String, dynamic>>;
      setState(() {
        _people = profiles.map(_communityPersonFromProfile).toList();
        _buddyPhones
          ..clear()
          ..addAll(results[1] as Set<String>);
        _outgoingBuddyRequestPhones
          ..clear()
          ..addAll(results[2] as Set<String>);
      });
    } catch (_) {
      // Keep the last successfully loaded community snapshot.
    }
  }

  Future<void> _loadBuddyRequests() async {
    try {
      final requests = await widget.hikerCircleRepository.loadBuddyRequests(
        session: widget.session,
      );
      if (!mounted) return;
      setState(() {
        _buddyRequests = requests.map(_buddyRequestFromFirestore).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _buddyRequestsSubscription?.cancel();
    super.dispose();
  }

  void _listenToBuddyRequests() {
    _buddyRequestsSubscription = widget.hikerCircleRepository
        .watchBuddyRequests(session: widget.session)
        .listen((requests) {
          if (!mounted) return;
          setState(() {
            _buddyRequests = requests.map(_buddyRequestFromFirestore).toList();
          });
        }, onError: (_) => unawaited(_loadBuddyRequests()));
  }

  void _listenToGroupChats() {
    final phone = widget.session.phoneNumber;
    unawaited(_chatsSubscription?.cancel());
    _chatsSubscription = widget.hikerCircleRepository
        .userGroupChatsStream(phone)
        .listen(
          (chats) => unawaited(_applyGroupChats(chats, phone)),
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoadingChats = false;
              _chatsLoadError = 'Unable to load chats right now.';
            });
          },
        );
    setState(() {
      _isLoadingChats = true;
      _chatsLoadError = null;
    });
  }

  Future<void> _applyGroupChats(List<GroupChat> chats, String phone) async {
    if (!mounted) return;
    unawaited(_syncReadReceipts(phone));
    var local = Map<String, DateTime>.from(_localLastReadAt);
    try {
      local = await widget.hikerCircleRepository.loadAllLocalLastReadAt();
    } catch (_) {
      // The remote chat list is still useful without local read timestamps.
    }
    if (!mounted) return;
    setState(() {
      _groupChats = chats;
      _localLastReadAt = local;
      _isLoadingChats = false;
      _chatsLoadError = null;
    });
  }

  Future<void> _syncReadReceipts(String phone) async {
    try {
      await widget.hikerCircleRepository.syncPendingReadReceipts(
        phoneNumber: phone,
      );
    } catch (_) {
      // Pending receipts are retried on the next stream update.
    }
  }

  Future<void> _loadPinnedChats() async {
    try {
      final pinned = await widget.hikerCircleRepository.loadPinnedChats(
        session: widget.session,
      );
      if (!mounted) return;
      setState(() => _pinnedChatIds = pinned);
    } catch (_) {
      // Pin state can be retried by reopening Circle.
    }
  }

  Future<void> _showChatNotifications(GroupChat chat) async {
    DateTime? mutedUntil;
    try {
      mutedUntil = await widget.hikerCircleRepository.loadGroupChatMutedUntil(
        session: widget.session,
        chatId: chat.id,
      );
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
      await widget.hikerCircleRepository.setGroupChatMutedUntil(
        session: widget.session,
        chatId: chat.id,
        mutedUntil: newMutedUntil,
      );
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

  void _pinChat(GroupChat chat) {
    final isPinned = _pinnedChatIds.contains(chat.id);
    final desiredPinned = !isPinned;
    final generation = (_pinUpdateGeneration[chat.id] ?? 0) + 1;
    _pinUpdateGeneration[chat.id] = generation;
    setState(() {
      if (isPinned) {
        _pinnedChatIds.remove(chat.id);
      } else {
        _pinnedChatIds.add(chat.id);
      }
    });
    unawaited(_persistPinnedChat(chat, desiredPinned, generation));
  }

  Future<void> _persistPinnedChat(
    GroupChat chat,
    bool desiredPinned,
    int generation,
  ) async {
    final previous = _pinWriteChains[chat.id] ?? Future<void>.value();
    final write = previous.then(
      (_) => widget.hikerCircleRepository.setChatPinned(
        session: widget.session,
        chatId: chat.id,
        pinned: desiredPinned,
      ),
    );
    _pinWriteChains[chat.id] = write.then<void>((_) {}, onError: (_) {});
    try {
      await write;
    } catch (_) {
      if (!mounted || _pinUpdateGeneration[chat.id] != generation) return;
      setState(() {
        if (desiredPinned) {
          _pinnedChatIds.remove(chat.id);
        } else {
          _pinnedChatIds.add(chat.id);
        }
      });
      _showCircleMessage('Unable to update the pinned chat.');
    } finally {
      if (_pinUpdateGeneration[chat.id] == generation) {
        _pinUpdateGeneration.remove(chat.id);
        _pinWriteChains.remove(chat.id);
      }
    }
  }

  void _showCircleMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _deleteChat(GroupChat chat) async {
    final confirm = await showDialog<bool>(
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
    if (confirm != true || !mounted) return;
    try {
      await widget.hikerCircleRepository.deleteChatForUser(
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

  Future<void> _loadCommunityPosts() async {
    setState(() {
      _isLoadingPosts = true;
      _postsLoadError = null;
    });
    try {
      final posts = await widget.hikerCircleRepository.loadCommunityPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts.map(_communityPostFromFirestore).toList();
        _isLoadingPosts = false;
        _postsLoadError = null;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
        _postsLoadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPosts = false;
        _postsLoadError = 'Unable to load community posts right now.';
      });
    }
  }

  Future<void> _addBuddy(_CommunityPerson person) async {
    if (person.phoneNumber == widget.session.phoneNumber) return;
    if (_buddyPhones.contains(person.phoneNumber) ||
        _outgoingBuddyRequestPhones.contains(
          _phoneKeyFor(person.phoneNumber),
        ) ||
        person.phoneNumber.isEmpty) {
      return;
    }

    try {
      await widget.hikerCircleRepository.sendBuddyRequest(
        session: widget.session,
        buddyPhoneNumber: person.phoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _outgoingBuddyRequestPhones.add(_phoneKeyFor(person.phoneNumber));
      });
      _showCircleMessage('Friend request sent to ${person.name}.');
    } catch (_) {
      _showCircleMessage('Unable to send the buddy request.');
    }
  }

  Future<void> _acceptBuddyRequest(_BuddyRequest request) async {
    try {
      await widget.hikerCircleRepository.acceptBuddyRequest(
        session: widget.session,
        requesterPhoneNumber: request.phoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _buddyRequests = _buddyRequests
            .where((item) => item.phoneNumber != request.phoneNumber)
            .toList();
        _buddyPhones.add(request.phoneNumber);
      });
      unawaited(_loadCommunityPeople());
    } catch (_) {
      _showCircleMessage('Unable to accept the buddy request.');
    }
  }

  Future<void> _declineBuddyRequest(_BuddyRequest request) async {
    try {
      await widget.hikerCircleRepository.declineBuddyRequest(
        session: widget.session,
        requesterPhoneNumber: request.phoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _buddyRequests = _buddyRequests
            .where((item) => item.phoneNumber != request.phoneNumber)
            .toList();
      });
    } catch (_) {
      _showCircleMessage('Unable to decline the buddy request.');
    }
  }

  Future<void> _openBuddyRequests() async {
    await _loadBuddyRequests();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BuddyRequestsSheet(
        requests: _buddyRequests,
        onAccept: (request) => unawaited(_acceptBuddyRequest(request)),
        onDecline: (request) => unawaited(_declineBuddyRequest(request)),
      ),
    );
  }

  Future<void> _openDirectChat(_CommunityPerson person) async {
    if (person.phoneNumber == widget.session.phoneNumber) return;
    try {
      final chat = await widget.hikerCircleRepository.openDirectChat(
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

  Future<void> _showCommunityProfile(_CommunityPost post) async {
    Map<String, dynamic>? profile;
    try {
      profile = await widget.hikerCircleRepository.loadCommunityProfile(
        userId: post.authorId,
        phoneNumber: post.authorPhoneNumber,
      );
    } catch (_) {
      _showCircleMessage('Unable to load this hiker profile.');
      return;
    }
    if (!mounted || profile == null) return;
    final person = _communityPersonFromProfile(profile);
    await _showCommunityPersonProfile(person);
  }

  Future<void> _showCommunityPersonProfile(_CommunityPerson person) async {
    Map<String, dynamic> details = const <String, dynamic>{};
    try {
      details = await widget.hikerCircleRepository.loadPublicHikerProfile(
        userId: person.userId,
        phoneNumber: person.phoneNumber,
      );
    } catch (_) {
      // The basic allow-listed profile remains useful if extended history is
      // temporarily unavailable.
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CommunityProfileSheet(
        person: person,
        details: details,
        isBuddy: _buddyPhones.contains(person.phoneNumber),
        isRequested: _outgoingBuddyRequestPhones.contains(
          _phoneKeyFor(person.phoneNumber),
        ),
        isOwnProfile: person.phoneNumber == widget.session.phoneNumber,
        onAddBuddy: () {
          Navigator.of(sheetContext).pop();
          unawaited(_addBuddy(person));
        },
        onMessage: () {
          Navigator.of(sheetContext).pop();
          if (person.phoneNumber == widget.session.phoneNumber) {
            _showCircleMessage(
              'You cannot start a conversation with yourself.',
            );
          } else {
            unawaited(_openDirectChat(person));
          }
        },
      ),
    );
  }

  Future<void> _sharePostToGroupChat(_CommunityPost post) async {
    final groupChats = _groupChats.where((chat) => !chat.isDirect).toList();
    if (groupChats.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Join or create a group chat before sharing.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final chat = await showModalBottomSheet<GroupChat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SharePostToChatSheet(chats: groupChats),
    );
    if (chat == null || !mounted) return;
    try {
      await widget.hikerCircleRepository.sendGroupChatMessage(
        chatId: chat.id,
        senderPhone: widget.session.phoneNumber,
        senderName: widget.session.username,
        text:
            'Shared ${post.author}’s community post:\n${post.body}\nTrail: ${post.trail}',
        localId: 'share_${DateTime.now().microsecondsSinceEpoch}',
        sentAt: DateTime.now(),
      );
      _showCircleMessage('Post shared to ${chat.trailName}.');
    } catch (_) {
      _showCircleMessage('Unable to share the post right now.');
    }
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
    } catch (_) {
      _showCircleMessage('Unable to share the community post right now.');
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
    } catch (_) {
      _showCircleMessage('Unable to share this hike update right now.');
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
            currentUserPhotoURL: _currentUserPhotoURL,
            currentUserPhotoBytes:
                _currentUserPhotoURL == (widget.session.photoURL ?? '')
                ? widget.session.photoBytes
                : null,
            onOpenProfile: () => _showCommunityProfile(post),
            onShare: () => _sharePostToGroupChat(post),
          );
        },
      ),
    );
  }

  void _createTeam() {
    _showCircleMessage(
      'Create a real team session from Home > Start Hike > Team Hike.',
    );
  }

  Future<void> _openGroupChat(GroupChat chat) async {
    final repo = widget.hikerCircleRepository;
    final phone = widget.session.phoneNumber;
    final now = DateTime.now();
    try {
      await repo.markGroupChatAsRead(chatId: chat.id, phoneNumber: phone);
    } catch (_) {
      // Receipt sync should not prevent opening a locally cached chat.
    }
    if (!mounted) return;
    setState(() {
      _localLastReadAt = Map<String, DateTime>.from(_localLastReadAt)
        ..[chat.id] = now;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GroupChatDetailPage(
          chat: chat,
          session: widget.session,
          repository: repo,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

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
            color: isSelected ? _CircleColors.green : Colors.transparent,
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
        .where((person) => _buddyPhones.contains(person.phoneNumber))
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
                  _Header(
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
                              postsLoadError: _postsLoadError,
                              onRetryPosts: _loadCommunityPosts,
                              buddyPhones: _buddyPhones,
                              outgoingBuddyRequestPhones:
                                  _outgoingBuddyRequestPhones,
                              currentUserPhone: widget.session.phoneNumber,
                              currentUserPhotoURL: _currentUserPhotoURL,
                              currentUserPhotoBytes:
                                  _currentUserPhotoURL ==
                                      (widget.session.photoURL ?? '')
                                  ? widget.session.photoBytes
                                  : null,
                              onAddBuddy: (person) =>
                                  unawaited(_addBuddy(person)),
                              onMessageBuddy: (person) =>
                                  unawaited(_openDirectChat(person)),
                              onOpenPersonProfile: (person) => unawaited(
                                _showCommunityPersonProfile(person),
                              ),
                              onOpenProfile: _showCommunityProfile,
                              onSharePost: _sharePostToGroupChat,
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
    );
  }
}

class _CommunityPerson {
  const _CommunityPerson({
    this.userId = '',
    this.phoneNumber = '',
    required this.name,
    required this.handle,
    required this.subtitle,
    required this.trailAffinity,
    required this.color,
    this.level = 1,
    this.levelName = 'Trailhead',
    this.gender = '',
    this.photoURL = '',
  });

  final String userId;
  final String phoneNumber;
  final String name;
  final String handle;
  final String subtitle;
  final String trailAffinity;
  final Color color;
  final int level;
  final String levelName;
  final String gender;
  final String photoURL;
}

class _BuddyRequest {
  const _BuddyRequest({
    required this.phoneNumber,
    required this.name,
    required this.handle,
    required this.photoURL,
    required this.createdAtLabel,
  });

  final String phoneNumber;
  final String name;
  final String handle;
  final String photoURL;
  final String createdAtLabel;
}

class _CommunityPost {
  const _CommunityPost({
    this.postId,
    required this.authorId,
    required this.authorPhoneNumber,
    required this.author,
    required this.handle,
    required this.levelBadge,
    required this.level,
    required this.timeLabel,
    required this.trail,
    required this.body,
    required this.likes,
    required this.replies,
    required this.color,
    this.routeCaptureId = '',
    this.routePointCount = 0,
    this.routePreviewPoints = const [],
    this.authorPhotoURL = '',
  });

  final String? postId;
  final String authorId;
  final String authorPhoneNumber;
  final String author;
  final String handle;
  final String levelBadge;
  final int level;
  final String timeLabel;
  final String trail;
  final String body;
  final int likes;
  final int replies;
  final Color color;
  final String routeCaptureId;
  final int routePointCount;
  final List<HikeCoordinate> routePreviewPoints;
  final String authorPhotoURL;

  bool get hasRouteMap => routePreviewPoints.length >= 2;
}

class _CommunityComment {
  const _CommunityComment({
    required this.author,
    required this.handle,
    required this.levelBadge,
    required this.level,
    required this.body,
    required this.timeLabel,
    this.authorPhotoURL = '',
  });

  final String author;
  final String handle;
  final String levelBadge;
  final int level;
  final String body;
  final String timeLabel;
  final String authorPhotoURL;
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
  const _Header({
    required this.requestCount,
    required this.onOpenFriendRequests,
    required this.onOpenSettings,
  });

  final int requestCount;
  final VoidCallback onOpenFriendRequests;
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
                  style: PageHeaderStyle.title(
                    context,
                    _CircleColors.textFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Community, buddies, teams',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    _CircleColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Friend requests',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(44),
              onPressed: onOpenFriendRequests,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const _CircleIcon(icon: Icons.person_add_alt_1_rounded),
                  if (requestCount > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: _RequestBadge(count: requestCount),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Circle settings',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size.square(44),
              onPressed: onOpenSettings,
              child: const _CircleIcon(icon: CupertinoIcons.gear_alt_fill),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunitySection extends StatefulWidget {
  const _CommunitySection({
    required this.activeHike,
    required this.people,
    required this.posts,
    required this.isLoadingPosts,
    required this.postsLoadError,
    required this.onRetryPosts,
    required this.buddyPhones,
    required this.outgoingBuddyRequestPhones,
    required this.currentUserPhone,
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onAddBuddy,
    required this.onMessageBuddy,
    required this.onOpenPersonProfile,
    required this.onOpenProfile,
    required this.onSharePost,
    required this.onCreatePost,
    required this.onShareHike,
    required this.onOpenPost,
  });

  final ActiveHikeSession? activeHike;
  final List<_CommunityPerson> people;
  final List<_CommunityPost> posts;
  final bool isLoadingPosts;
  final String? postsLoadError;
  final VoidCallback onRetryPosts;
  final Set<String> buddyPhones;
  final Set<String> outgoingBuddyRequestPhones;
  final String currentUserPhone;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final ValueChanged<_CommunityPerson> onAddBuddy;
  final ValueChanged<_CommunityPerson> onMessageBuddy;
  final ValueChanged<_CommunityPerson> onOpenPersonProfile;
  final ValueChanged<_CommunityPost> onOpenProfile;
  final ValueChanged<_CommunityPost> onSharePost;
  final Future<void> Function(String caption) onCreatePost;
  final Future<void> Function() onShareHike;
  final ValueChanged<_CommunityPost> onOpenPost;

  @override
  State<_CommunitySection> createState() => _CommunitySectionState();
}

class _CommunitySectionState extends State<_CommunitySection> {
  String _filter = 'Everyone';
  String _query = '';
  bool _showPeople = false;
  bool _onlyBuddies = false;

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
              (_filter != 'Hike stories' || post.hasRouteMap) &&
              '${post.author} ${post.body} ${post.trail}'
                  .toLowerCase()
                  .contains(_query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _CircleColors.green.withValues(alpha: 0.16),
                _CircleColors.surfaceFor(context),
              ],
            ),
            border: Border.all(
              color: _CircleColors.green.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Better together',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _CircleColors.textFor(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Find your hiking people. Share the moments along the way.',
                style: TextStyle(
                  color: _CircleColors.secondaryTextFor(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    avatar: const Icon(CupertinoIcons.chat_bubble_2, size: 18),
                    label: const Text('Stories'),
                    selected: !_showPeople,
                    onSelected: (_) => setState(() {
                      _showPeople = false;
                    }),
                  ),
                  ChoiceChip(
                    avatar: const Icon(CupertinoIcons.person_2, size: 18),
                    label: const Text('Find hikers'),
                    selected: _showPeople,
                    onSelected: (_) => setState(() {
                      _showPeople = true;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
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
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _CircleColors.surfaceFor(context),
                borderRadius: BorderRadius.circular(22),
              ),
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
                trailing: IconButton(
                  tooltip: widget.buddyPhones.contains(person.phoneNumber)
                      ? 'Message hiker'
                      : widget.outgoingBuddyRequestPhones.contains(
                          _phoneKeyFor(person.phoneNumber),
                        )
                      ? 'Request sent'
                      : 'Add buddy',
                  icon: Icon(
                    widget.buddyPhones.contains(person.phoneNumber)
                        ? CupertinoIcons.chat_bubble
                        : widget.outgoingBuddyRequestPhones.contains(
                            _phoneKeyFor(person.phoneNumber),
                          )
                        ? CupertinoIcons.checkmark
                        : CupertinoIcons.person_add,
                    color: _CircleColors.green,
                  ),
                  onPressed: widget.buddyPhones.contains(person.phoneNumber)
                      ? () => widget.onMessageBuddy(person)
                      : widget.outgoingBuddyRequestPhones.contains(
                          _phoneKeyFor(person.phoneNumber),
                        )
                      ? null
                      : () => widget.onAddBuddy(person),
                ),
              ),
            ),
        ] else ...[
          _ComposerCard(
            activeHike: widget.activeHike,
            currentUserPhotoURL: widget.currentUserPhotoURL,
            currentUserPhotoBytes: widget.currentUserPhotoBytes,
            onCreatePost: widget.onCreatePost,
            onShareHike: widget.onShareHike,
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
          if (widget.isLoadingPosts)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: HikerCircleMinorLoadingIndicator(size: 56)),
            )
          else if (widget.postsLoadError != null)
            ListTile(
              leading: const Icon(CupertinoIcons.cloud),
              title: Text(widget.postsLoadError!),
              trailing: TextButton(
                onPressed: widget.onRetryPosts,
                child: const Text('Retry'),
              ),
            )
          else if (posts.isEmpty)
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
              post: post,
              isOwnPost: post.authorPhoneNumber == widget.currentUserPhone,
              onOpenPost: () => widget.onOpenPost(post),
              onOpenProfile: () => widget.onOpenProfile(post),
              onShare: () => widget.onSharePost(post),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ],
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.activeHike,
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onCreatePost,
    required this.onShareHike,
  });

  final ActiveHikeSession? activeHike;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final Future<void> Function(String caption) onCreatePost;
  final Future<void> Function() onShareHike;

  @override
  Widget build(BuildContext context) {
    final isDark = _CircleColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _CircleColors.green.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Avatar(
                  label: 'Y',
                  color: _CircleColors.green,
                  imageUrl: currentUserPhotoURL,
                  imageBytes: currentUserPhotoBytes,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
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
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _CircleColors.separatorFor(
                            context,
                          ).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        activeHike == null
                            ? 'What did you discover today?'
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
                        borderRadius: BorderRadius.circular(22),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => unawaited(_openComposer(context)),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Write a story'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _CircleColors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
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
                  _Avatar(
                    label: 'Y',
                    color: _CircleColors.green,
                    size: 36,
                    imageUrl: currentUserPhotoURL,
                    imageBytes: currentUserPhotoBytes,
                  ),
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
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
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
                    borderRadius: BorderRadius.circular(22),
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

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({
    required this.post,
    required this.isOwnPost,
    required this.onOpenPost,
    required this.onOpenProfile,
    required this.onShare,
  });

  final _CommunityPost post;
  final bool isOwnPost;
  final VoidCallback onOpenPost;
  final VoidCallback onOpenProfile;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _CircleColors.surfaceFor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _CircleColors.separatorFor(context).withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onOpenPost,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onOpenProfile,
                      child: _Avatar(
                        label: _circleInitial(post.author),
                        color: post.color,
                        imageUrl: post.authorPhotoURL,
                      ),
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
                                  isOwnPost
                                      ? '${post.author} (You)'
                                      : post.author,
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
                              _LevelBadge(level: post.level),
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
                        color: _CircleColors.separatorFor(
                          context,
                        ).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _PostAction(
                        icon: CupertinoIcons.heart,
                        label: '${post.likes}',
                        onTap: onOpenPost,
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
                        onTap: onShare,
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
    required this.currentUserPhotoURL,
    required this.currentUserPhotoBytes,
    required this.onOpenProfile,
    required this.onShare,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final _CommunityPost post;
  final String currentUserPhotoURL;
  final Uint8List? currentUserPhotoBytes;
  final VoidCallback onOpenProfile;
  final VoidCallback onShare;

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
    try {
      final comments = await widget.repository.loadCommunityComments(
        postId: postId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = comments.map(_communityCommentFromFirestore).toList();
      });
    } catch (_) {
      _showDetailSnack('Unable to load comments right now.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
      }
    }
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
        child: Stack(
          children: [
            SingleChildScrollView(
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
                        isOwnPost:
                            post.authorPhoneNumber ==
                            widget.session.phoneNumber,
                        onOpenPost: () {},
                        onOpenProfile: widget.onOpenProfile,
                        onShare: widget.onShare,
                      ),
                      const SizedBox(height: 22),
                      _SectionTitle(label: 'Comments'),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: _CircleColors.surfaceFor(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _CircleColors.separatorFor(
                              context,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              _Avatar(
                                label: 'Y',
                                color: _CircleColors.green,
                                size: 36,
                                imageUrl: widget.currentUserPhotoURL,
                                imageBytes: widget.currentUserPhotoBytes,
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
                                      color: _CircleColors.secondaryTextFor(
                                        context,
                                      ),
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
                                  icon: const Icon(
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
                        const HikerCircleLoadingView(
                          message: 'Loading comments…',
                          detail: 'Getting the latest trail discussion.',
                          compact: true,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        )
                      else if (_comments.isEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: _CircleColors.surfaceFor(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _CircleColors.separatorFor(
                                context,
                              ).withValues(alpha: 0.5),
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
                              color: _CircleColors.separatorFor(
                                context,
                              ).withValues(alpha: 0.5),
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
            if (_isPostingComment)
              HikerCircleLoadingToastOverlay(
                compact: true,
                message: 'Posting comment…',
                detail: 'Adding your comment to this community hike.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  if (mounted) setState(() => _isPostingComment = false);
                },
              ),
          ],
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
                        color: _CircleColors.separatorFor(
                          context,
                        ).withValues(alpha: 0.5),
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
                                label: 'Start',
                                value: team.dateLabel,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: team.readiness >= 80
                                    ? _CircleColors.green.withValues(alpha: 0.1)
                                    : _CircleColors.orange.withValues(
                                        alpha: 0.1,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                team.status,
                                style: Theme.of(context).textTheme.labelSmall
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
                          style: Theme.of(context).textTheme.labelSmall
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                onPressed: null,
                                icon: const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                ),
                                label: const Text('Check-ins'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _CircleColors.green,
                                  side: BorderSide(
                                    color: _CircleColors.green.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                onPressed: null,
                                icon: const Icon(
                                  Icons.group_add_rounded,
                                  size: 18,
                                ),
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
                        color: _CircleColors.separatorFor(
                          context,
                        ).withValues(alpha: 0.5),
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
                        color: _CircleColors.separatorFor(
                          context,
                        ).withValues(alpha: 0.5),
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

class _CommunityProfileSheet extends StatelessWidget {
  const _CommunityProfileSheet({
    required this.person,
    required this.details,
    required this.isBuddy,
    required this.isRequested,
    required this.isOwnProfile,
    required this.onAddBuddy,
    required this.onMessage,
  });

  final _CommunityPerson person;
  final Map<String, dynamic> details;
  final bool isBuddy;
  final bool isRequested;
  final bool isOwnProfile;
  final VoidCallback onAddBuddy;
  final VoidCallback onMessage;

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
                      else if (isRequested)
                        const _StatusPill(
                          label: 'Requested',
                          color: _CircleColors.orange,
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

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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

class _SharePostToChatSheet extends StatelessWidget {
  const _SharePostToChatSheet({required this.chats});

  final List<GroupChat> chats;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: _InsetGroup(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'Share to group chat',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _CircleColors.textFor(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                for (final chat in chats)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _CircleColors.greenSoftFor(context),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: _CircleColors.green,
                      ),
                    ),
                    title: Text(chat.trailName),
                    subtitle: Text(
                      '${chat.participantPhones.length} participants',
                    ),
                    trailing: const Icon(Icons.send_rounded),
                    onTap: () => Navigator.of(context).pop(chat),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleSettingsPage extends StatefulWidget {
  const _CircleSettingsPage({required this.session, required this.repository});

  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  @override
  State<_CircleSettingsPage> createState() => _CircleSettingsPageState();
}

class _CircleSettingsPageState extends State<_CircleSettingsPage> {
  bool _groupChatNotificationsEnabled = true;
  bool _isLoadingGroupChatSetting = true;
  bool _isSavingGroupChatSetting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGroupChatNotificationSetting());
  }

  Future<void> _loadGroupChatNotificationSetting() async {
    try {
      final enabled = await widget.repository.loadGroupChatNotificationsEnabled(
        session: widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _groupChatNotificationsEnabled = enabled;
      });
    } catch (_) {
      // Keep the safe enabled default when the setting cannot be loaded.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGroupChatSetting = false;
        });
      }
    }
  }

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
      await widget.repository.setGroupChatNotificationsEnabled(
        session: widget.session,
        enabled: enabled,
      );
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
                    title: 'Team invite alerts',
                    subtitle: 'Managed by the mobile notification permission.',
                    value: true,
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
}

class _SettingsSwitchTile extends StatelessWidget {
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

class _CircleAnimatedToggle extends StatelessWidget {
  const _CircleAnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

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

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: onTap == null ? 'This action is not available yet.' : label,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: InkWell(
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

class _BuddyRequestsSheet extends StatelessWidget {
  const _BuddyRequestsSheet({
    required this.requests,
    required this.onAccept,
    required this.onDecline,
  });

  final List<_BuddyRequest> requests;
  final ValueChanged<_BuddyRequest> onAccept;
  final ValueChanged<_BuddyRequest> onDecline;

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

class _BuddyRequestRow extends StatelessWidget {
  const _BuddyRequestRow({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final _BuddyRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _Avatar(
            label: _circleInitial(request.name),
            color: _colorForPost(request.phoneNumber),
            imageUrl: request.photoURL,
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
                style: PageHeaderStyle.title(
                  context,
                  _CircleColors.textFor(context),
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PageHeaderStyle.subtitle(
                  context,
                  _CircleColors.secondaryTextFor(context),
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

class _RequestBadge extends StatelessWidget {
  const _RequestBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _CircleColors.red,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _CircleColors.surfaceFor(context), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  IconData get _icon => switch (level) {
    1 => Icons.eco_rounded,
    2 => Icons.explore_rounded,
    3 => Icons.hiking_rounded,
    4 => Icons.landscape_rounded,
    5 => Icons.verified_rounded,
    6 => Icons.shield_rounded,
    _ => Icons.workspace_premium_rounded,
  };

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
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
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
  double _currentZoom = 13.5;
  double _scaleLatitude = 0;

  List<mapbox.Point> get _routePoints {
    return widget.post.routePreviewPoints
        .map(
          (point) => mapbox.Point(
            coordinates: mapbox.Position(point.longitude, point.latitude),
          ),
        )
        .where((point) => mapPointCoordinatesOrNull(point) != null)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _resetScaleLatitude();
  }

  @override
  void didUpdateWidget(covariant _CommunityRouteThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.postId != widget.post.postId ||
        !_sameRouteGeometry(
          oldWidget.post.routePreviewPoints,
          widget.post.routePreviewPoints,
        )) {
      _routeRendered = false;
      _resetScaleLatitude();
      unawaited(_renderRoute());
    }
  }

  @override
  void dispose() {
    _mapboxMap = null;
    _polylineManager = null;
    _circleManager = null;
    super.dispose();
  }

  void _resetScaleLatitude() {
    final points = _routePoints;
    _scaleLatitude = points.isEmpty
        ? 0
        : mapPointCoordinatesOrNull(points.first)?.latitude ?? 0;
  }

  static bool _sameRouteGeometry(
    List<HikeCoordinate> first,
    List<HikeCoordinate> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].latitude != second[index].latitude ||
          first[index].longitude != second[index].longitude) {
        return false;
      }
    }
    return true;
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    _mapboxMap = mapboxMap;
    try {
      await mapboxMap.compass.updateSettings(
        mapbox.CompassSettings(enabled: false),
      );
      await mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
      await mapboxMap.gestures.updateSettings(
        mapbox.GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: true,
          pitchEnabled: true,
        ),
      );
      final polylineManager = await mapboxMap.annotations
          .createPolylineAnnotationManager();
      if (!mounted || !identical(mapboxMap, _mapboxMap)) return;
      final circleManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      if (!mounted || !identical(mapboxMap, _mapboxMap)) return;
      _polylineManager = polylineManager;
      _circleManager = circleManager;
      await _renderRoute();
      await _syncScaleFromCamera();
    } catch (_) {}
  }

  Future<void> _onStyleLoaded() async {
    final map = _mapboxMap;
    if (map == null || !mounted) return;
    try {
      await enableTerrain3D(map);
      if (!mounted || !identical(map, _mapboxMap)) return;
      schedulePitch(map);
      _styleLoaded = true;
      _routeRendered = false;
      await _renderRoute();
    } catch (_) {
      // The native style can be replaced while its callback is in flight.
    }
  }

  Future<void> _renderRoute() async {
    final map = _mapboxMap;
    final polylineManager = _polylineManager;
    final circleManager = _circleManager;
    final points = _routePoints;
    if (map == null ||
        polylineManager == null ||
        circleManager == null ||
        !_styleLoaded ||
        _routeRendered ||
        points.length < 2) {
      return;
    }

    try {
      await polylineManager.deleteAll();
      await circleManager.deleteAll();
      if (!mounted ||
          !identical(map, _mapboxMap) ||
          !identical(polylineManager, _polylineManager) ||
          !identical(circleManager, _circleManager)) {
        return;
      }

      await polylineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(
            coordinates: [
              for (final pt in points)
                mapbox.Position(pt.coordinates[0]!, pt.coordinates[1]!),
            ],
          ),
          lineColor: const Color(0xFF34A853).toARGB32(),
          lineOpacity: 0.94,
          lineWidth: 4.0,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
      await circleManager.createMulti([
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
      if (!mounted || !identical(map, _mapboxMap)) return;
      _routeRendered = true;
      await _fitRoute();
    } catch (_) {
      if (mounted && identical(map, _mapboxMap)) {
        _routeRendered = false;
      }
    }
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
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.flyTo(
        mapbox.CameraOptions(
          zoom: (_currentZoom + amount)
              .clamp(kMapMinZoom, kMapMaxZoom)
              .toDouble(),
        ),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } catch (_) {
      return;
    }
    await _syncScaleFromCamera();
  }

  void _onCameraChange(mapbox.CameraChangedEventData data) {
    _updateScale(data);
  }

  Future<void> _syncScaleFromCamera() async {
    final map = _mapboxMap;
    if (map == null) return;
    if (!mounted) return;
    try {
      final state = await map.getCameraState();
      if (!mounted || !identical(map, _mapboxMap)) return;
      final coordinates = mapPointCoordinatesOrNull(state.center);
      if (!state.zoom.isFinite || coordinates == null) return;
      setState(() {
        _currentZoom = state.zoom;
        _scaleLatitude = coordinates.latitude;
      });
    } catch (_) {}
  }

  void _updateScale(mapbox.CameraChangedEventData data) {
    final nextZoom = data.cameraState.zoom;
    final coordinates = mapPointCoordinatesOrNull(data.cameraState.center);
    if (!mounted || !nextZoom.isFinite || coordinates == null) return;
    final nextLatitude = coordinates.latitude;
    if (((nextZoom - _currentZoom).abs() < 0.005 &&
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
            key: ValueKey(
              '${widget.post.postId}:${widget.post.routePointCount}',
            ),
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
            child: MapScaleBar(zoom: _currentZoom, latitude: _scaleLatitude),
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
  ).map(HikeCoordinate.tryFromFirestore).nonNulls.toList();

  return _CommunityPost(
    postId: _stringFrom(data['postId']),
    authorId: _stringFrom(data['authorId']),
    authorPhoneNumber: authorPhone,
    author: authorName,
    handle: handle,
    levelBadge: _stringFrom(data['authorLevelBadge']).isEmpty
        ? 'Lv. 1 Trailhead'
        : _stringFrom(data['authorLevelBadge']),
    level: _intFrom(data['authorLevel']) == 0
        ? 1
        : _intFrom(data['authorLevel']),
    timeLabel: _relativeTimeLabel(data['createdAtLocal']),
    trail: trailName,
    body: caption,
    likes: _intFrom(data['likeCount']),
    replies: _intFrom(data['commentCount']),
    color: _colorForPost(_stringFrom(data['postId'])),
    routeCaptureId: _stringFrom(data['routeCaptureId']),
    routePointCount: _intFrom(data['routePointCount']),
    routePreviewPoints: routePreviewPoints,
    authorPhotoURL: _stringFrom(data['authorPhotoURL']),
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

String _phoneKeyFor(String phoneNumber) {
  return phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
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

class _GroupChatTile extends StatefulWidget {
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

  @override
  State<_GroupChatTile> createState() => _GroupChatTileState();
}

class _GroupChatTileState extends State<_GroupChatTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _borderAnim;

  @override
  void initState() {
    super.initState();
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

  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  bool _computeUnread(GroupChat chat, String myPhone, DateTime? localReadAt) {
    if (chat.lastMessageAt == null) return false;
    if (chat.lastMessageSenderPhone == myPhone) return false;
    final cutoff = _latestOf(chat.lastReadAtFor(myPhone), localReadAt);
    if (cutoff != null && chat.lastMessageAt!.isBefore(cutoff)) return false;
    return true;
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  bool get _hasUnread {
    final myPhone = widget.phoneNumber;
    final chat = widget.chat;
    if (chat.lastMessageAt == null) return false;
    if (chat.lastMessageSenderPhone == myPhone) return false;
    final cutoff = _latestOf(
      chat.lastReadAtFor(myPhone),
      widget.localLastReadAt,
    );
    if (cutoff != null && chat.lastMessageAt!.isBefore(cutoff)) return false;
    return true;
  }

  int get _unreadCount {
    if (!_hasUnread) return 0;
    final serverCount = widget.chat.unreadCountFor(widget.phoneNumber);
    return serverCount > 0 ? serverCount : 1;
  }

  String _formatUnread(int count) {
    if (count > 99) return '99+';
    return count.toString();
  }

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
                        painter: _BorderTravelPainter(
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

class _BorderTravelPainter extends CustomPainter {
  _BorderTravelPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const radius = 14.0;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(radius));

    final dimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: 0.15);
    canvas.drawRRect(rrect, dimPaint);

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final totalLength = metrics.fold<double>(0.0, (s, m) => s + m.length);
    if (totalLength <= 0) return;

    const segmentFraction = 0.1;
    final segmentLength = totalLength * segmentFraction;

    final anticlockwisePos = 1.0 - progress;
    final start = anticlockwisePos * totalLength;
    final end = start + segmentLength;

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;

    double processed = 0;
    for (final metric in metrics) {
      final metricStart = processed;
      final metricEnd = processed + metric.length;

      if (end <= totalLength) {
        final overlapStart = start.clamp(metricStart, metricEnd);
        final overlapEnd = end.clamp(metricStart, metricEnd);
        if (overlapEnd > overlapStart) {
          final segment = metric.extractPath(
            overlapStart - metricStart,
            overlapEnd - metricStart,
          );
          canvas.drawPath(segment, highlightPaint);
        }
      } else {
        final wrapStart = 0.0;
        final wrapEnd = end - totalLength;
        if (wrapEnd > 0) {
          final overlapStart = wrapStart.clamp(metricStart, metricEnd);
          final overlapEnd = wrapEnd.clamp(metricStart, metricEnd);
          if (overlapEnd > overlapStart) {
            final segment = metric.extractPath(
              overlapStart - metricStart,
              overlapEnd - metricStart,
            );
            canvas.drawPath(segment, highlightPaint);
          }
        }
        final normalStart = start.clamp(metricStart, metricEnd);
        final normalEnd = totalLength.clamp(metricStart, metricEnd);
        if (normalEnd > normalStart) {
          final segment = metric.extractPath(
            normalStart - metricStart,
            normalEnd - metricStart,
          );
          canvas.drawPath(segment, highlightPaint);
        }
      }
      processed = metricEnd;
    }
  }

  @override
  bool shouldRepaint(_BorderTravelPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _ChatActionSheet extends StatelessWidget {
  const _ChatActionSheet({required this.displayName, required this.isPinned});

  final String displayName;
  final bool isPinned;

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

class _ActionOption extends StatelessWidget {
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

class _ChatNotificationSettingsSheet extends StatelessWidget {
  const _ChatNotificationSettingsSheet({
    required this.chatName,
    required this.isMuted,
  });

  final String chatName;
  final bool isMuted;

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

class _NotificationOption extends StatelessWidget {
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

String _circleInitial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

int _intFrom(Object? value) {
  if (value is num && value.isFinite) {
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
