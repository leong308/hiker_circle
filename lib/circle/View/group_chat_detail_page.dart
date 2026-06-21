import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/Model/hike_session_models.dart';

const _green = Color(0xFF34A853);
const _greenSoft = Color(0xFFEAF7EE);
const _background = Color(0xFFF2F2F7);
const _darkBackground = Color(0xFF0C120F);
const _darkSurface = Color(0xFF141C17);
const _darkSurface2 = Color(0xFF1B261F);

Color _surfaceFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? _darkSurface
    : Colors.white;

Color _bgFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? _darkBackground
    : _background;

Color _surface2For(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? _darkSurface2
    : const Color(0xFFF5F7F5);

Color _textFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFEAF4EE)
    : const Color(0xFF111111);

Color _secondaryTextFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFA8B8AE)
    : const Color(0xFF6E6E73);

Color _separatorFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF2B3A31).withValues(alpha: 0.5)
    : const Color(0xFFD9E1DC).withValues(alpha: 0.5);

enum _ChatMuteAction { unmute, oneHour, eightHours, oneDay, oneWeek }

class GroupChatDetailPage extends StatefulWidget {
  const GroupChatDetailPage({
    super.key,
    required this.chat,
    required this.session,
    required this.repository,
  });

  final GroupChat chat;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  @override
  State<GroupChatDetailPage> createState() => _GroupChatDetailPageState();
}

class _GroupChatDetailPageState extends State<GroupChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = const [];
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _timeRefreshTimer;
  UpcomingHike? _upcomingHike;
  bool _isOnline = true;
  bool _isUploadingAttachment = false;
  bool _groupChatNotificationsEnabled = true;
  DateTime? _mutedUntil;
  bool _isSavingNotificationSettings = false;
  final ImagePicker _imagePicker = ImagePicker();

  bool get _isChatMuted =>
      _mutedUntil != null && _mutedUntil!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _loadUpcomingHike();
    _listenToMessages();
    _monitorConnectivity();
    _loadPending();
    unawaited(_loadNotificationSettings());
    _timeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadNotificationSettings() async {
    final results = await Future.wait<Object?>([
      widget.repository.loadGroupChatNotificationsEnabled(
        session: widget.session,
      ),
      widget.repository.loadGroupChatMutedUntil(
        session: widget.session,
        chatId: widget.chat.id,
      ),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _groupChatNotificationsEnabled = results[0] as bool;
      _mutedUntil = results[1] as DateTime?;
    });
  }

  Future<void> _openChatSettings() async {
    final action = await showModalBottomSheet<_ChatMuteAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChatNotificationSettingsSheet(
        trailName: widget.chat.displayNameFor(widget.session.phoneNumber),
        globalNotificationsEnabled: _groupChatNotificationsEnabled,
        mutedUntil: _isChatMuted ? _mutedUntil : null,
      ),
    );
    if (action == null || !mounted || _isSavingNotificationSettings) {
      return;
    }
    final now = DateTime.now();
    final mutedUntil = switch (action) {
      _ChatMuteAction.unmute => null,
      _ChatMuteAction.oneHour => now.add(const Duration(hours: 1)),
      _ChatMuteAction.eightHours => now.add(const Duration(hours: 8)),
      _ChatMuteAction.oneDay => now.add(const Duration(days: 1)),
      _ChatMuteAction.oneWeek => now.add(const Duration(days: 7)),
    };
    setState(() {
      _isSavingNotificationSettings = true;
    });
    try {
      await widget.repository.setGroupChatMutedUntil(
        session: widget.session,
        chatId: widget.chat.id,
        mutedUntil: mutedUntil,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _mutedUntil = mutedUntil;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              mutedUntil == null
                  ? 'Notifications turned on for this chat.'
                  : 'Chat muted until ${_formatMuteUntil(mutedUntil)}.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Unable to update this chat notification setting.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingNotificationSettings = false;
        });
      }
    }
  }

  Future<void> _loadPending() async {
    final msgs = await widget.repository.loadAllLocalMessagesForChat(
      widget.chat.id,
    );
    if (!mounted || msgs.isEmpty) return;
    final toAdd = <ChatMessage>[];
    for (final m in msgs) {
      if (m.sendStatus == SendStatus.sent) continue;
      final exists = _messages.any(
        (e) =>
            e.id == m.id ||
            (e.senderPhone == m.senderPhone &&
                e.text == m.text &&
                e.sentAt.difference(m.sentAt).inSeconds.abs() < 5),
      );
      if (exists) continue;
      final dupInToAdd = toAdd.any(
        (e) =>
            e.senderPhone == m.senderPhone &&
            e.text == m.text &&
            e.sentAt.difference(m.sentAt).inSeconds.abs() < 5,
      );
      if (!dupInToAdd) {
        toAdd.add(m);
      }
    }
    if (toAdd.isEmpty) return;
    setState(() {
      _messages = [..._messages, ...toAdd]
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _timeRefreshTimer?.cancel();
    _messagesSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _monitorConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && !_isOnline) {
        widget.repository.flushPendingMessages();
      }
      if (mounted) {
        setState(() => _isOnline = online);
      }
    });
  }

  Future<void> _loadUpcomingHike() async {
    final hike = await widget.repository.loadUpcomingHikeForChat(
      widget.chat.hikeSessionId,
    );
    if (!mounted) return;
    setState(() {
      _upcomingHike = hike;
    });
  }

  void _listenToMessages() {
    _messagesSubscription = widget.repository
        .groupChatMessagesStream(widget.chat.id)
        .listen((messages) {
          _onMessagesUpdated(messages);
        });
  }

  Future<void> _onMessagesUpdated(List<ChatMessage> firestoreMessages) async {
    if (!mounted) return;
    final local = await widget.repository.loadAllLocalMessagesForChat(
      widget.chat.id,
    );
    if (!mounted) return;

    final combined = <ChatMessage>[...firestoreMessages];
    for (final lm in local) {
      final exists = combined.any((m) => m.id == lm.id);
      final matchingIndex = combined.indexWhere(
        (m) =>
            m.senderPhone == lm.senderPhone &&
            m.text == lm.text &&
            m.sentAt.difference(lm.sentAt).inSeconds.abs() < 5,
      );
      if (exists) {
        continue;
      }
      if (matchingIndex >= 0 && lm.sendStatus != SendStatus.sent) {
        combined[matchingIndex] = lm;
      } else if (matchingIndex < 0) {
        combined.add(lm);
      }
    }
    combined.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    setState(() => _messages = combined);
    widget.repository.cacheChatMessages(firestoreMessages, widget.chat.id);
    _markUnseenMessages(firestoreMessages);
    _scrollToBottom();
  }

  void _markUnseenMessages(List<ChatMessage> messages) {
    if (!_isOnline) return;
    final myPhone = widget.session.phoneNumber;
    for (final msg in messages) {
      if (msg.senderPhone == myPhone) continue;
      if (msg.isSystemMessage) continue;
      if (msg.seenBy.contains(myPhone)) continue;
      widget.repository.markMessageAsSeen(
        chatId: widget.chat.id,
        messageId: msg.id,
        phoneNumber: myPhone,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final sentAt = DateTime.now();
    final localId =
        'local_${sentAt.microsecondsSinceEpoch}_${widget.session.phoneNumber.hashCode}';
    final localMsg = ChatMessage(
      id: localId,
      chatId: widget.chat.id,
      senderPhone: widget.session.phoneNumber,
      senderName: widget.session.username,
      text: text,
      sentAt: sentAt,
      sendStatus: SendStatus.sending,
    );

    setState(() {
      _messages = [..._messages, localMsg]
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    });
    _scrollToBottom();

    await widget.repository.sendGroupChatMessage(
      chatId: widget.chat.id,
      senderPhone: widget.session.phoneNumber,
      senderName: widget.session.username,
      text: text,
      localId: localId,
      sentAt: sentAt,
    );

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.any((r) => r != ConnectivityResult.none)) {
      await widget.repository.flushPendingMessages();
    }
    _refreshPendingMessages();
  }

  Future<void> _showAttachmentPicker() async {
    if (_isUploadingAttachment) {
      return;
    }
    final type = await showModalBottomSheet<ChatAttachmentType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_rounded),
                title: const Text('Image'),
                subtitle: const Text('Choose a photo from your gallery'),
                onTap: () =>
                    Navigator.of(context).pop(ChatAttachmentType.image),
              ),
              ListTile(
                leading: const Icon(Icons.video_file_rounded),
                title: const Text('Video'),
                subtitle: const Text('Choose a video from your gallery'),
                onTap: () =>
                    Navigator.of(context).pop(ChatAttachmentType.video),
              ),
              ListTile(
                leading: const Icon(Icons.description_rounded),
                title: const Text('Document'),
                subtitle: const Text('Choose a file up to 25 MB'),
                onTap: () =>
                    Navigator.of(context).pop(ChatAttachmentType.document),
              ),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) {
      return;
    }

    switch (type) {
      case ChatAttachmentType.image:
        final file = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 88,
        );
        if (file != null) {
          await _sendAttachment(
            type: type,
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: file.mimeType ?? _contentTypeFor(file.name, type),
          );
        }
      case ChatAttachmentType.video:
        final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
        if (file != null) {
          await _sendAttachment(
            type: type,
            bytes: await file.readAsBytes(),
            fileName: file.name,
            contentType: file.mimeType ?? _contentTypeFor(file.name, type),
          );
        }
      case ChatAttachmentType.document:
        final result = await FilePicker.pickFiles(
          allowMultiple: false,
          withData: true,
        );
        final file = result?.files.singleOrNull;
        if (file != null) {
          final bytes = file.bytes ?? await file.xFile.readAsBytes();
          await _sendAttachment(
            type: type,
            bytes: bytes,
            fileName: file.name,
            contentType: _contentTypeFor(file.name, type),
          );
        }
    }
  }

  Future<void> _sendAttachment({
    required ChatAttachmentType type,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    if (!_isOnline) {
      _showAttachmentError(
        'Connect to the internet before sending an attachment.',
      );
      return;
    }
    setState(() {
      _isUploadingAttachment = true;
    });
    String? optimisticMessageId;
    try {
      final attachment = await widget.repository.uploadGroupChatAttachment(
        chatId: widget.chat.id,
        senderPhone: widget.session.phoneNumber,
        type: type,
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
      );
      final sentAt = DateTime.now();
      final localId =
          'attachment_${sentAt.microsecondsSinceEpoch}_${widget.session.phoneNumber.hashCode}';
      optimisticMessageId = localId;
      final caption = _messageController.text.trim();
      _messageController.clear();
      final localMessage = ChatMessage(
        id: localId,
        chatId: widget.chat.id,
        senderPhone: widget.session.phoneNumber,
        senderName: widget.session.username,
        text: caption,
        sentAt: sentAt,
        sendStatus: SendStatus.sending,
        attachment: attachment,
      );
      if (mounted) {
        setState(() {
          _messages = [..._messages, localMessage]
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
        });
        _scrollToBottom();
      }
      await widget.repository.sendGroupChatMessage(
        chatId: widget.chat.id,
        senderPhone: widget.session.phoneNumber,
        senderName: widget.session.username,
        text: caption,
        localId: localId,
        sentAt: sentAt,
        attachment: attachment,
      );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (optimisticMessageId != null && mounted) {
        setState(() {
          _messages = _messages
              .where((message) => message.id != optimisticMessageId)
              .toList();
        });
      }
      _showAttachmentError(error.message);
    } catch (_) {
      if (optimisticMessageId != null && mounted) {
        setState(() {
          _messages = _messages
              .where((message) => message.id != optimisticMessageId)
              .toList();
        });
      }
      _showAttachmentError('Unable to send the selected attachment.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAttachment = false;
        });
      }
    }
  }

  void _showAttachmentError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String _contentTypeFor(String fileName, ChatAttachmentType type) {
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
      'zip': 'application/zip',
    };
    return known[extension] ??
        switch (type) {
          ChatAttachmentType.image => 'image/*',
          ChatAttachmentType.video => 'video/*',
          ChatAttachmentType.document => 'application/octet-stream',
        };
  }

  Future<void> _refreshPendingMessages() async {
    if (!mounted) return;
    await _onMessagesUpdated(
      _messages.where((m) => m.sendStatus == SendStatus.sent).toList(),
    );
  }

  void _showReadReceipts(ChatMessage msg) {
    final allPhones = widget.chat.participantPhones;
    final seenPhones = msg.seenBy;
    final senderPhone = msg.senderPhone;
    final unseenPhones = allPhones
        .where((p) => !seenPhones.contains(p))
        .toList();
    final seenOthers = seenPhones.where((p) => p != senderPhone).toList();
    final totalOthers = allPhones.where((p) => p != senderPhone).length;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? _darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _separatorFor(ctx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Read receipts',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: _textFor(ctx),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Seen by ${seenOthers.length} of $totalOthers',
                style: TextStyle(fontSize: 13, color: _secondaryTextFor(ctx)),
              ),
              const SizedBox(height: 14),
              if (seenOthers.isNotEmpty) ...[
                Text(
                  'Seen'.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _green,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...seenOthers.map(
                  (phone) => _ParticipantCard(
                    phone: phone,
                    isYou: phone == widget.session.phoneNumber,
                    username: widget.session.username,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                'Unseen'.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _secondaryTextFor(ctx),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (unseenPhones.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Everyone has seen this',
                    style: TextStyle(
                      color: _secondaryTextFor(ctx),
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...unseenPhones.map(
                  (phone) => _ParticipantCard(
                    phone: phone,
                    isYou: phone == widget.session.phoneNumber,
                    username: widget.session.username,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: _bgFor(context),
      appBar: AppBar(
        backgroundColor: _surfaceFor(context),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.chat.displayNameFor(widget.session.phoneNumber),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Chat settings',
            onPressed: _isSavingNotificationSettings
                ? null
                : () => unawaited(_openChatSettings()),
            icon: _isSavingNotificationSettings
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isChatMuted
                        ? Icons.notifications_off_rounded
                        : Icons.notifications_active_rounded,
                    color: _isChatMuted ? Colors.orange : _green,
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'No connection — messages will send when online',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          if (_upcomingHike != null)
            _HikeInfoCard(
              hike: _upcomingHike!,
              isDark: isDark,
              onTap: () => _showHikeDetails(_upcomingHike!),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(isDark: isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe =
                          msg.senderPhone == widget.session.phoneNumber;

                      if (msg.isSystemMessage) {
                        return _SystemMessagePill(message: msg, isDark: isDark);
                      }

                      final isPending = msg.sendStatus == SendStatus.sending;
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                        isPending: isPending,
                        totalParticipants: widget.chat.participantPhones.length,
                        onTickTap: isMe && !isPending
                            ? () => _showReadReceipts(msg)
                            : null,
                      );
                    },
                  ),
          ),
          _ChatInput(
            controller: _messageController,
            onSend: _sendMessage,
            onAttach: _showAttachmentPicker,
            isUploadingAttachment: _isUploadingAttachment,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  void _showHikeDetails(UpcomingHike hike) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _HikeDetailSheet(hike: hike, chat: widget.chat),
    );
  }
}

String _formatMuteUntil(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final date = DateTime(local.year, local.month, local.day);
  final dayLabel = date == DateTime(now.year, now.month, now.day)
      ? 'today'
      : date == tomorrow
      ? 'tomorrow'
      : '${local.day}/${local.month}/${local.year}';
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$dayLabel at $hour:$minute $period';
}

class _ChatNotificationSettingsSheet extends StatelessWidget {
  const _ChatNotificationSettingsSheet({
    required this.trailName,
    required this.globalNotificationsEnabled,
    required this.mutedUntil,
  });

  final String trailName;
  final bool globalNotificationsEnabled;
  final DateTime? mutedUntil;

  @override
  Widget build(BuildContext context) {
    final isMuted = mutedUntil != null && mutedUntil!.isAfter(DateTime.now());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
        child: Container(
          decoration: BoxDecoration(
            color: _surfaceFor(context),
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
                    color: _separatorFor(context),
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
                        color: _textFor(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trailName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _secondaryTextFor(context),
                      ),
                    ),
                    if (!globalNotificationsEnabled) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.orange,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'All group chat notifications are currently disabled in Circle Settings.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              _ChatMuteOption(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications on',
                subtitle: isMuted
                    ? 'Currently muted until ${_formatMuteUntil(mutedUntil!)}'
                    : 'This chat is not muted',
                selected: !isMuted,
                onTap: () => Navigator.of(context).pop(_ChatMuteAction.unmute),
              ),
              _ChatMuteOption(
                icon: Icons.schedule_rounded,
                title: 'Mute for 1 hour',
                onTap: () => Navigator.of(context).pop(_ChatMuteAction.oneHour),
              ),
              _ChatMuteOption(
                icon: Icons.bedtime_rounded,
                title: 'Mute for 8 hours',
                onTap: () =>
                    Navigator.of(context).pop(_ChatMuteAction.eightHours),
              ),
              _ChatMuteOption(
                icon: Icons.today_rounded,
                title: 'Mute for 1 day',
                onTap: () => Navigator.of(context).pop(_ChatMuteAction.oneDay),
              ),
              _ChatMuteOption(
                icon: Icons.date_range_rounded,
                title: 'Mute for 1 week',
                onTap: () => Navigator.of(context).pop(_ChatMuteAction.oneWeek),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMuteOption extends StatelessWidget {
  const _ChatMuteOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _green, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(color: _textFor(context), fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: _secondaryTextFor(context)),
            ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: _green)
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _HikeInfoCard extends StatelessWidget {
  const _HikeInfoCard({
    required this.hike,
    required this.isDark,
    required this.onTap,
  });

  final UpcomingHike hike;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = '${hike.departureTime.day}/${hike.departureTime.month}';
    final timeStr =
        '${hike.departureTime.hour.toString().padLeft(2, '0')}:${hike.departureTime.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: _surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: _green.withValues(alpha: isDark ? 0.08 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _greenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.hiking_rounded,
                    color: _green,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hike.trailName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _textFor(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: _secondaryTextFor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$dateStr · $timeStr',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryTextFor(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.people_rounded,
                            size: 12,
                            color: _secondaryTextFor(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${hike.participantCount}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondaryTextFor(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _secondaryTextFor(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _greenSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_rounded, color: _green, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              color: isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Say something to start the conversation!',
            style: TextStyle(
              color: isDark ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemMessagePill extends StatelessWidget {
  const _SystemMessagePill({required this.message, required this.isDark});
  final ChatMessage message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_rounded, size: 14, color: _green),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${message.senderName} just joined!',
                  style: TextStyle(
                    color: _green,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isPending,
    required this.totalParticipants,
    this.onTickTap,
  });

  final ChatMessage message;
  final bool isMe;
  final bool isPending;
  final int totalParticipants;
  final VoidCallback? onTickTap;

  @override
  Widget build(BuildContext context) {
    final timeText = isPending ? 'now' : _formatTime(message.sentAt);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final othersSeen = message.seenBy.length - 1;
    final allSeen = message.seenBy.length >= totalParticipants;

    Widget statusIndicator;
    if (isPending) {
      statusIndicator = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: isMe
              ? Colors.white.withValues(alpha: 0.7)
              : _secondaryTextFor(context),
        ),
      );
    } else if (isMe) {
      final tickColor = Colors.white.withValues(alpha: 0.7);
      final seenColor = Colors.white.withValues(alpha: 0.85);
      if (othersSeen == 0) {
        statusIndicator = Icon(Icons.done_rounded, size: 14, color: tickColor);
      } else if (allSeen) {
        statusIndicator = Icon(
          Icons.done_all_rounded,
          size: 14,
          color: seenColor,
        );
      } else {
        statusIndicator = Icon(
          Icons.done_all_rounded,
          size: 14,
          color: tickColor,
        );
      }
    } else {
      statusIndicator = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GestureDetector(
        onTap: onTickTap,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _green,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 11, 10, 8),
                    decoration: BoxDecoration(
                      color: isMe
                          ? _green
                          : isDark
                          ? const Color(0xFF1B261F)
                          : const Color(0xFFEEF1EF),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (message.attachment != null) ...[
                          _MessageAttachmentView(
                            attachment: message.attachment!,
                            isMe: isMe,
                          ),
                          if (message.text.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        if (message.text.isNotEmpty)
                          _LinkedMessageText(
                            text: message.text,
                            textColor: isMe
                                ? Colors.white
                                : isDark
                                ? const Color(0xFFEAF4EE)
                                : const Color(0xFF111111),
                            linkColor: isMe
                                ? const Color(0xFFD8F3E2)
                                : const Color(0xFF0A66C2),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeText,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : isDark
                                    ? const Color(0xFFA8B8AE)
                                    : const Color(0xFF6E6E73),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            statusIndicator,
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isMe) const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }
}

class _MessageAttachmentView extends StatelessWidget {
  const _MessageAttachmentView({required this.attachment, required this.isMe});

  final ChatAttachment attachment;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    switch (attachment.type) {
      case ChatAttachmentType.image:
        return GestureDetector(
          onTap: () => unawaited(_openExternalUrl(attachment.url)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              attachment.url,
              width: 230,
              height: 170,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  return child;
                }
                return const SizedBox(
                  width: 230,
                  height: 170,
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stackTrace) => _AttachmentFileTile(
                attachment: attachment,
                icon: Icons.broken_image_rounded,
                isMe: isMe,
              ),
            ),
          ),
        );
      case ChatAttachmentType.video:
        return _AttachmentFileTile(
          attachment: attachment,
          icon: Icons.play_circle_fill_rounded,
          isMe: isMe,
          label: 'Open video',
        );
      case ChatAttachmentType.document:
        return _AttachmentFileTile(
          attachment: attachment,
          icon: Icons.description_rounded,
          isMe: isMe,
          label: _fileSizeLabel(attachment.sizeBytes),
        );
    }
  }
}

class _AttachmentFileTile extends StatelessWidget {
  const _AttachmentFileTile({
    required this.attachment,
    required this.icon,
    required this.isMe,
    this.label,
  });

  final ChatAttachment attachment;
  final IconData icon;
  final bool isMe;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isMe
          ? Colors.white.withValues(alpha: 0.14)
          : Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(_openExternalUrl(attachment.url)),
        child: SizedBox(
          width: 230,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: isMe ? Colors.white : _green, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? Colors.white : _textFor(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label ?? _fileSizeLabel(attachment.sizeBytes),
                        style: TextStyle(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.7)
                              : _secondaryTextFor(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.8)
                      : _secondaryTextFor(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedMessageText extends StatelessWidget {
  const _LinkedMessageText({
    required this.text,
    required this.textColor,
    required this.linkColor,
  });

  static final RegExp _linkPattern = RegExp(
    r'((?:https?://|www\.)[^\s<]+)',
    caseSensitive: false,
  );

  final String text;
  final Color textColor;
  final Color linkColor;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _linkPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final rawLink = match.group(0)!;
      final trailingMatch = RegExp(r'[.,!?;:)\]]+$').firstMatch(rawLink);
      final trailing = trailingMatch?.group(0) ?? '';
      final cleanLink = trailing.isEmpty
          ? rawLink
          : rawLink.substring(0, rawLink.length - trailing.length);
      spans.add(
        TextSpan(
          text: cleanLink,
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
            fontWeight: FontWeight.w600,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => unawaited(_openExternalUrl(cleanLink)),
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return RichText(
      text: TextSpan(
        children: spans,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
      ),
    );
  }
}

Future<void> _openExternalUrl(String rawUrl) async {
  final normalized = rawUrl.startsWith('www.') ? 'https://$rawUrl' : rawUrl;
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _fileSizeLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.isUploadingAttachment,
    required this.isDark,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final bool isUploadingAttachment;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceFor(context),
        border: Border(top: BorderSide(color: _separatorFor(context))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 42,
                child: IconButton(
                  tooltip: 'Add attachment',
                  onPressed: isUploadingAttachment ? null : onAttach,
                  icon: isUploadingAttachment
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_circle_outline_rounded),
                  color: _green,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    filled: true,
                    fillColor: _surface2For(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HikeDetailSheet extends StatelessWidget {
  const _HikeDetailSheet({required this.hike, required this.chat});
  final UpcomingHike hike;
  final GroupChat chat;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr =
        '${hike.departureTime.day}/${hike.departureTime.month}/${hike.departureTime.year}';
    final timeStr =
        '${hike.departureTime.hour.toString().padLeft(2, '0')}:${hike.departureTime.minute.toString().padLeft(2, '0')}';
    final returnStr =
        '${hike.expectedReturnTime.hour.toString().padLeft(2, '0')}:${hike.expectedReturnTime.minute.toString().padLeft(2, '0')}';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: _surfaceFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _separatorFor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _greenSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.hiking_rounded,
                    color: _green,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hike.trailName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: _textFor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${hike.area}${hike.state.isNotEmpty ? ', ${hike.state}' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: _secondaryTextFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface2For(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: dateStr,
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.schedule_rounded,
                    label: 'Departure',
                    value: timeStr,
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.timer_rounded,
                    label: 'Expected return',
                    value: returnStr,
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.straighten_rounded,
                    label: 'Distance',
                    value: '${hike.distanceKm.toStringAsFixed(1)} km',
                  ),
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: '${hike.durationMinutes} min',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hike.difficulty,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _green,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.people_rounded,
                  size: 14,
                  color: _secondaryTextFor(context),
                ),
                const SizedBox(width: 4),
                Text(
                  '${hike.participantCount} ${hike.participantCount == 1 ? 'participant' : 'participants'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: _secondaryTextFor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Participants',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _textFor(context),
              ),
            ),
            const SizedBox(height: 8),
            ...chat.participantPhones.map(
              (phone) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _greenSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: _green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        phone == hike.creatorPhone ? '$phone (Host)' : phone,
                        style: TextStyle(
                          fontSize: 14,
                          color: _textFor(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.phone,
    required this.isYou,
    required this.username,
  });

  final String phone;
  final bool isYou;
  final String username;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = isYou && username.isNotEmpty ? username : phone;
    final subtitle = isYou && username.isNotEmpty ? phone : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B261F) : const Color(0xFFF5F7F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _greenSoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: _textFor(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: _secondaryTextFor(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isYou)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _green),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: _secondaryTextFor(context)),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textFor(context),
          ),
        ),
      ],
    );
  }
}
