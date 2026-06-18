import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/Model/hike_session_models.dart';

const _green = Color(0xFF34A853);
const _greenSoft = Color(0xFFEAF7EE);
const _background = Color(0xFFF2F2F7);
const _darkBackground = Color(0xFF0C120F);
const _darkSurface = Color(0xFF141C17);

Color _surfaceFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _darkSurface : Colors.white;

Color _bgFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _darkBackground : _background;

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

  @override
  void initState() {
    super.initState();
    _listenToMessages();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenToMessages() {
    _messagesSubscription = widget.repository
        .groupChatMessagesStream(widget.chat.id)
        .listen((messages) {
      if (!mounted) return;
      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    });
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
    await widget.repository.sendGroupChatMessage(
      chatId: widget.chat.id,
      senderPhone: widget.session.phoneNumber,
      senderName: widget.session.username,
      text: text,
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
          widget.chat.trailName,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
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
                          child: const Icon(
                            Icons.chat_rounded,
                            color: _green,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFEAF4EE)
                                : const Color(0xFF111111),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Say something to start the conversation!',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFA8B8AE)
                                : const Color(0xFF6E6E73),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe =
                          msg.senderPhone == widget.session.phoneNumber;
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _surfaceFor(context),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF2B3A31).withValues(alpha: 0.5)
                      : const Color(0xFFD9E1DC).withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1B261F)
                              : const Color(0xFFF5F7F5),
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
                        onSubmitted: (_) => _sendMessage(),
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
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final timeText = _formatTime(message.sentAt);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
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
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.text,
                        style: TextStyle(
                          color: isMe
                              ? Colors.white
                              : isDark
                                  ? const Color(0xFFEAF4EE)
                                  : const Color(0xFF111111),
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
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
                    ],
                  ),
                ),
              ),
              if (isMe) const SizedBox(width: 8),
            ],
          ),
        ],
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
