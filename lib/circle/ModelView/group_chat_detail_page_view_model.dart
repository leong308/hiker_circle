part of '../group_chat_detail_page_feature.dart';

/// Owns the state and non-visual actions of GroupChatDetailPage.
class _GroupChatDetailPageStateViewModel extends ChangeNotifier {
  /// Creates group chat detail page state view model.
  _GroupChatDetailPageStateViewModel({
    required this.readChat,
    required this.readRepository,
    required this.readSession,
    required this.effectScrollToBottom,
    required this.effectScrollToInitialPosition,
    required this.effectScrollToMatch,
    required this.effectSendAttachment,
    required this.effectShowAttachmentError,
  });
  final GroupChat Function() readChat;
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  final void Function() effectScrollToBottom;
  final void Function() effectScrollToInitialPosition;
  final void Function() effectScrollToMatch;
  final Future<void> Function({
    required ChatAttachmentType type,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  })
  effectSendAttachment;
  final void Function(String message) effectShowAttachmentError;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<ChatMessage> stateMessages = const [];

  StreamSubscription<List<ChatMessage>>? stateMessagesSubscription;

  StreamSubscription<List<ConnectivityResult>>? stateConnectivitySubscription;

  UpcomingHike? stateUpcomingHike;
  StreamSubscription<List<UpcomingHike>>? _upcomingHikeSubscription;
  int _upcomingHikeGeneration = 0;

  bool stateIsOnline = true;

  bool stateGroupChatNotificationsEnabled = true;

  DateTime? stateMutedUntil;
  ChatPreferenceCacheObserver? _preferenceCache;
  int _preferenceReadGeneration = 0;

  void commandWatchCachedPreferences() {
    _preferenceCache?.dispose();
    final owner = readSession().phoneNumber;
    _preferenceCache = ChatPreferenceCacheObserver(
      owner: owner,
      readOwner: () => readSession().phoneNumber,
      changes: readRepository().cachedReadUpdates,
      // Query local: conversation preferences
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
          // Local mutes are restored independently from downloaded account preferences.
        });
      },
    );
  }

  void commandBeginPreferenceWrite() {
    _preferenceReadGeneration++;
    _preferenceCache?.beginWrite();
  }

  void commandEndPreferenceWrite() => _preferenceCache?.endWrite();

  String stateSearchQuery = '';

  List<int> stateMatchedIndices = const [];

  int stateCurrentMatchIndex = 0;

  bool stateIsSendingMessage = false;

  DateTime? stateUnreadCutoffTime;

  int? stateFirstUnreadIndex;

  int stateUnreadMessagesCount = 0;

  bool stateHasScrolledToInitialPosition = false;

  late final Future<void> stateInitialCutoffLoaded;

  /// Returns command total searchable messages.
  int get commandTotalSearchableMessages =>
      stateMessages.where((m) => !m.isSystemMessage).length;

  /// Returns command is chat muted.
  bool get commandIsChatMuted =>
      stateMutedUntil != null && stateMutedUntil!.isAfter(DateTime.now());

  /// Loads notification settings.
  Future<void> commandLoadNotificationSettings() async {
    final generation = ++_preferenceReadGeneration;
    final owner = readSession().phoneNumber;
    final chatId = readChat().id;
    try {
      final results = await Future.wait<Object?>([
        readRepository().loadGroupChatNotificationsEnabled(
          session: readSession(),
        ),
        readRepository().loadGroupChatMutedUntil(
          session: readSession(),
          chatId: readChat().id,
        ),
      ]);
      if (!mounted ||
          generation != _preferenceReadGeneration ||
          owner != readSession().phoneNumber ||
          chatId != readChat().id) {
        return;
      }
      _publish(() {
        stateGroupChatNotificationsEnabled = results[0] as bool;
        stateMutedUntil = results[1] as DateTime?;
      });
    } catch (_) {
      // Keep safe notification defaults when settings cannot be loaded.
    }
  }

  /// Computes on search changed.
  void commandOnSearchChanged(String query) {
    _publish(() {
      stateSearchQuery = query;
    });
    commandPerformSearch();
  }

  /// Computes perform search.
  void commandPerformSearch() {
    if (stateSearchQuery.isEmpty) {
      _publish(() {
        stateMatchedIndices = const [];
        stateCurrentMatchIndex = 0;
      });
      return;
    }
    final lowerQuery = stateSearchQuery.toLowerCase();
    final indices = <int>[];
    for (var i = 0; i < stateMessages.length; i++) {
      if (stateMessages[i].isSystemMessage) continue;
      final text = stateMessages[i].text.toLowerCase();
      if (text.contains(lowerQuery)) {
        indices.add(i);
      }
    }
    _publish(() {
      stateMatchedIndices = indices;
      stateCurrentMatchIndex = 0;
    });
    if (indices.isNotEmpty) {
      effectScrollToMatch();
    }
  }

  /// Computes next match.
  void commandNextMatch() {
    if (stateMatchedIndices.isEmpty) return;
    _publish(() {
      stateCurrentMatchIndex =
          (stateCurrentMatchIndex + 1) % stateMatchedIndices.length;
    });
    effectScrollToMatch();
  }

  /// Computes previous match.
  void commandPreviousMatch() {
    if (stateMatchedIndices.isEmpty) return;
    _publish(() {
      stateCurrentMatchIndex =
          (stateCurrentMatchIndex - 1 + stateMatchedIndices.length) %
          stateMatchedIndices.length;
    });
    effectScrollToMatch();
  }

  /// Loads pending.
  Future<void> commandLoadPending() async {
    List<ChatMessage> msgs;
    try {
      msgs = await readRepository().loadAllLocalMessagesForChat(
        readChat().id,
        ownerPhoneNumber: readSession().phoneNumber,
      );
    } catch (_) {
      return;
    }
    if (!mounted || msgs.isEmpty) return;
    final toAdd = <ChatMessage>[];
    for (final m in msgs) {
      final exists = stateMessages.any(
        (e) =>
            e.id == m.id ||
            (e.senderPhone == m.senderPhone &&
                e.text == m.text &&
                e.sharedPost?.postId == m.sharedPost?.postId &&
                e.sentAt.difference(m.sentAt).inSeconds.abs() < 5),
      );
      if (exists) continue;
      final dupInToAdd = toAdd.any(
        (e) =>
            e.senderPhone == m.senderPhone &&
            e.text == m.text &&
            e.sharedPost?.postId == m.sharedPost?.postId &&
            e.sentAt.difference(m.sentAt).inSeconds.abs() < 5,
      );
      if (!dupInToAdd) {
        toAdd.add(m);
      }
    }
    if (toAdd.isEmpty) return;
    _publish(() {
      stateMessages = [...stateMessages, ...toAdd]
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    });
    effectScrollToBottom();
  }

  /// Computes monitor connectivity.
  void commandMonitorConnectivity() {
    stateConnectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        if (online && !stateIsOnline) {
          unawaited(
            commandBestEffort(
              readRepository().flushPendingMessages(
                ownerPhoneNumber: readSession().phoneNumber,
              ),
            ),
          );
          unawaited(
            commandBestEffort(
              readRepository().syncPendingReadReceipts(
                phoneNumber: readSession().phoneNumber,
              ),
            ),
          );
        }
        if (mounted) {
          _publish(() => stateIsOnline = online);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) {
          _publish(() => stateIsOnline = false);
        }
      },
    );
  }

  /// Loads upcoming hike.
  Future<void> commandLoadUpcomingHike() async {
    final generation = ++_upcomingHikeGeneration;
    await _upcomingHikeSubscription?.cancel();
    if (!mounted || generation != _upcomingHikeGeneration) return;
    final owner = readSession().phoneNumber;
    final hikeId = readChat().hikeSessionId;
    if (hikeId.trim().isEmpty) {
      _publish(() => stateUpcomingHike = null);
      return;
    }
    _upcomingHikeSubscription = readRepository()
        .watchMyUpcomingHikes(owner)
        .listen(
          (hikes) {
            if (!mounted ||
                generation != _upcomingHikeGeneration ||
                owner != readSession().phoneNumber ||
                hikeId != readChat().hikeSessionId) {
              return;
            }
            UpcomingHike? selected;
            for (final hike in hikes) {
              if (hike.id == hikeId) {
                selected = hike;
                break;
              }
            }
            _publish(() => stateUpcomingHike = selected);
          },
          onError: (_) {
            // Keep the downloaded banner while live plan updates are unavailable.
          },
        );
  }

  /// Listens for to messages.
  void commandListenToMessages() {
    stateMessagesSubscription = readRepository()
        .groupChatMessagesStream(readChat().id)
        .listen(
          (messages) => unawaited(commandOnMessagesUpdated(messages)),
          onError: (_) => effectShowAttachmentError(
            'Message updates are temporarily unavailable.',
          ),
        );
  }

  /// Merge cloud messages with pending local messages before updating unread position and receipts.
  Future<void> commandOnMessagesUpdated(
    List<ChatMessage> firestoreMessages,
  ) async {
    if (!mounted) return;

    final prevLen = stateMessages.length;
    _publish(() {
      stateMessages = firestoreMessages;
      commandComputeUnreadPosition();
    });
    await commandLoadPending();
    if (!mounted) return;
    commandMarkUnseenMessages(firestoreMessages);
    unawaited(commandMarkChatAsRead());

    if (!stateHasScrolledToInitialPosition) {
      effectScrollToInitialPosition();
      stateHasScrolledToInitialPosition = true;
    } else if (firestoreMessages.length > prevLen &&
        firestoreMessages.last.senderPhone == readSession().phoneNumber) {
      effectScrollToBottom();
    }

    if (!stateIsSendingMessage) {
      unawaited(
        commandBestEffort(
          readRepository().cacheChatMessages(
            firestoreMessages,
            readChat().id,
            ownerPhoneNumber: readSession().phoneNumber,
          ),
        ),
      );
    }
  }

  /// Marks unseen messages.
  void commandMarkUnseenMessages(List<ChatMessage> messages) {
    if (!stateIsOnline) return;
    final myPhone = readSession().phoneNumber;
    for (final msg in messages) {
      if (msg.senderPhone == myPhone) continue;
      if (msg.isSystemMessage) continue;
      if (msg.seenBy.contains(myPhone)) continue;
      unawaited(
        commandBestEffort(
          readRepository().markMessageAsSeen(
            chatId: readChat().id,
            messageId: msg.id,
            phoneNumber: myPhone,
          ),
        ),
      );
    }
  }

  /// Marks chat as read.
  Future<void> commandMarkChatAsRead() async {
    final myPhone = readSession().phoneNumber;
    try {
      // Keep the previous receipt available for the unread divider. This local
      // read never blocks navigation or rendering while Firebase syncs below.
      await stateInitialCutoffLoaded;
      if (!mounted) return;
      await readRepository().markGroupChatAsRead(
        chatId: readChat().id,
        phoneNumber: myPhone,
      );
    } catch (_) {
      // Read receipts will be retried by the repository when connectivity returns.
    }
  }

  /// Keep the opening read cutoff stable while incoming messages and local receipts continue to change.
  Future<void> commandLoadInitialCutoff() async {
    final myPhone = readSession().phoneNumber;
    final fromWidget = readChat().lastReadAtFor(myPhone);
    if (fromWidget != null) {
      _publish(() {
        stateUnreadCutoffTime = fromWidget;
        commandComputeUnreadPosition();
      });
      return;
    }
    await commandLoadLocalReadReceipt();
  }

  /// Loads local read receipt.
  Future<void> commandLoadLocalReadReceipt() async {
    DateTime? local;
    try {
      local = await readRepository().loadLocalLastReadAt(
        readChat().id,
        ownerPhoneNumber: readSession().phoneNumber,
      );
    } catch (_) {
      return;
    }
    if (local != null && mounted) {
      _publish(() {
        stateUnreadCutoffTime = local;
        commandComputeUnreadPosition();
      });
    }
  }

  /// Computes best effort.
  Future<void> commandBestEffort(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // Local cache and receipt synchronization retry on later updates.
    }
  }

  /// Computes unread position.
  void commandComputeUnreadPosition() {
    final myPhone = readSession().phoneNumber;
    final cutoff = stateUnreadCutoffTime ?? readChat().lastReadAtFor(myPhone);
    if (cutoff == null) {
      stateFirstUnreadIndex = null;
      stateUnreadMessagesCount = 0;
      return;
    }
    int? firstIdx;
    int count = 0;
    for (int i = 0; i < stateMessages.length; i++) {
      final msg = stateMessages[i];
      if (msg.senderPhone == myPhone || msg.isSystemMessage) continue;
      if (msg.sentAt.isAfter(cutoff)) {
        firstIdx ??= i;
        count++;
      }
    }
    stateFirstUnreadIndex = firstIdx;
    stateUnreadMessagesCount = count;
  }

  /// Sends xfile attachment.
  Future<void> commandSendXFileAttachment(
    ChatAttachmentType type,
    XFile file,
  ) async {
    if (await file.length() > _maxAttachmentBytes) {
      throw const HikerCircleFirebaseRepositoryException(
        'Attachments must be 25 MB or smaller.',
      );
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await effectSendAttachment(
      type: type,
      bytes: bytes,
      fileName: file.name,
      contentType: file.mimeType ?? commandContentTypeFor(file.name, type),
    );
  }

  /// Computes content type for.
  String commandContentTypeFor(String fileName, ChatAttachmentType type) {
    final extension = fileName.split('.').last.toLowerCase();
    const known = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4v': 'video/x-m4v',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
    };
    return known[extension] ??
        switch (type) {
          ChatAttachmentType.image => 'image/*',
          ChatAttachmentType.video => 'video/*',
          ChatAttachmentType.document => 'application/octet-stream',
        };
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _upcomingHikeGeneration++;
    unawaited(_upcomingHikeSubscription?.cancel());
    _preferenceCache?.dispose();
    super.dispose();
  }
}
