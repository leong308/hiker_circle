import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/app_toast.dart';
import '../../core/widgets/page_header_style.dart';
import '../Data/hiker_circle_assistant_repository.dart';

class HikerCircleAssistantPage extends StatefulWidget {
  const HikerCircleAssistantPage({super.key, this.repository});

  final HikerCircleAssistantRepository? repository;

  @override
  State<HikerCircleAssistantPage> createState() =>
      _HikerCircleAssistantPageState();
}

class _HikerCircleAssistantPageState extends State<HikerCircleAssistantPage> {
  static const _green = Color(0xFF34A853);
  static const _suggestions = <String>[
    'How do I prepare for a group hike?',
    'Where can I manage my passkey?',
    'What do the trail caution icons mean?',
    'How does Hike History work?',
  ];

  late final HikerCircleAssistantRepository _repository;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<_AssistantMessage> _messages = [
    const _AssistantMessage(
      text:
          'Hi, I can explain HikerCircle features using the app’s reviewed guides. What would you like to know?',
      isUser: false,
    ),
  ];
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? HikerCircleAssistantRepository();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    if (_isSending) return;
    final question = (suggestedQuestion ?? _controller.text).trim();
    if (question.length < 3) {
      HikerCircleToast.show(
        context,
        'Enter a little more detail in your question.',
        tone: HikerCircleToastTone.warning,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() {
      _messages.add(_AssistantMessage(text: question, isUser: true));
      _isSending = true;
    });
    _scrollToEnd();
    try {
      final answer = await _repository
          .ask(question)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AssistantMessage(
            text: answer.answer,
            isUser: false,
            sources: answer.sources,
            isEmergency: answer.isEmergency,
            notice: answer.notice,
          ),
        );
      });
    } on TimeoutException {
      if (!mounted) return;
      _addError(
        'The assistant took too long to respond. The loading window has been closed; please try again.',
      );
    } on HikerCircleAssistantException catch (error) {
      if (!mounted) return;
      _addError(error.message);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToEnd();
      }
    }
  }

  void _addError(String message) {
    setState(() {
      _messages.add(
        _AssistantMessage(text: message, isUser: false, isError: true),
      );
    });
    HikerCircleToast.show(
      context,
      message,
      title: 'Assistant unavailable',
      tone: HikerCircleToastTone.error,
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF0C120F)
        : const Color(0xFFF2F2F7);
    final surface = isDark ? const Color(0xFF141C17) : Colors.white;
    final text = isDark ? const Color(0xFFEAF4EE) : const Color(0xFF111111);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF6E6E73);
    final separator = isDark
        ? const Color(0xFF2B3A31)
        : const Color(0xFFD9E1DC);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeaderAction(
                    tooltip: 'Back',
                    icon: CupertinoIcons.back,
                    onPressed: () => Navigator.of(context).pop(),
                    color: text,
                    surface: surface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HikerCircle Assistant',
                          style: PageHeaderStyle.title(context, text),
                        ),
                        Text(
                          'Quick help from reviewed app guides',
                          style: PageHeaderStyle.subtitle(context, secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  _AssistantIntroCard(
                    surface: surface,
                    text: text,
                    secondary: secondary,
                    separator: separator,
                  ),
                  const SizedBox(height: 14),
                  if (_messages.length == 1) ...[
                    Text(
                      'Try asking',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _suggestions
                          .map(
                            (suggestion) => ActionChip(
                              label: Text(suggestion),
                              avatar: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 16,
                              ),
                              onPressed: _isSending
                                  ? null
                                  : () => _send(suggestion),
                              backgroundColor: surface,
                              side: BorderSide(color: separator),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (final message in _messages)
                    _MessageBubble(
                      message: message,
                      surface: surface,
                      text: text,
                      secondary: secondary,
                      separator: separator,
                    ),
                  if (_isSending)
                    _AiThinkingBubble(
                      surface: surface,
                      text: text,
                      secondary: secondary,
                      separator: separator,
                    ),
                ],
              ),
            ),
            _QuestionComposer(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !_isSending,
              surface: surface,
              text: text,
              secondary: secondary,
              separator: separator,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessage {
  const _AssistantMessage({
    required this.text,
    required this.isUser,
    this.sources = const [],
    this.isEmergency = false,
    this.isError = false,
    this.notice,
  });

  final String text;
  final bool isUser;
  final List<HikerCircleAssistantSource> sources;
  final bool isEmergency;
  final bool isError;
  final String? notice;
}

class _AiThinkingBubble extends StatefulWidget {
  const _AiThinkingBubble({
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
  });

  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;

  @override
  State<_AiThinkingBubble> createState() => _AiThinkingBubbleState();
}

class _AiThinkingBubbleState extends State<_AiThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'HikerCircle AI is thinking',
      liveRegion: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const Key('ai-thinking-indicator'),
          constraints: const BoxConstraints(maxWidth: 250),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          decoration: BoxDecoration(
            color: widget.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: widget.separator),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final progress = reduceMotion ? 0.25 : _controller.value;
              final pulse =
                  0.9 + (0.1 * (math.sin(progress * math.pi * 2) + 1) / 2);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: pulse,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const SweepGradient(
                          colors: [
                            Color(0xFF4C8BF5),
                            Color(0xFF8B5CF6),
                            Color(0xFFE0529C),
                            Color(0xFF34A853),
                            Color(0xFF4C8BF5),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF7C5CE7,
                            ).withValues(alpha: 0.24 + (pulse - 0.9)),
                            blurRadius: 13,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Text(
                    'Thinking',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: widget.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 7),
                  for (var index = 0; index < 3; index++) ...[
                    _ThinkingDot(progress: progress, index: index),
                    if (index < 2) const SizedBox(width: 4),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThinkingDot extends StatelessWidget {
  const _ThinkingDot({required this.progress, required this.index});

  final double progress;
  final int index;

  @override
  Widget build(BuildContext context) {
    final wave = (math.sin((progress * math.pi * 2) - (index * 0.9)) + 1) / 2;
    return Transform.translate(
      offset: Offset(0, -2.5 * wave),
      child: Opacity(
        opacity: 0.28 + (0.72 * wave),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF7C5CE7),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 6),
        ),
      ),
    );
  }
}

class _AssistantIntroCard extends StatelessWidget {
  const _AssistantIntroCard({
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
  });

  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _HikerCircleAssistantPageState._green.withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: _HikerCircleAssistantPageState._green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App help, not an open chatbot',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gemini free tier · no app chat history stored',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _HikerCircleAssistantPageState._green.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'UNPAID',
                  style: TextStyle(
                    color: _HikerCircleAssistantPageState._green,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Free-tier questions may be reviewed by Google. Do not enter names, phone numbers, email addresses, verification codes, precise coordinates, or medical details. For an active emergency, call 999 or 112.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: secondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
  });

  final _AssistantMessage message;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;

  @override
  Widget build(BuildContext context) {
    final accent = message.isError
        ? Theme.of(context).colorScheme.error
        : message.isEmergency
        ? const Color(0xFFE14949)
        : _HikerCircleAssistantPageState._green;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          color: message.isUser
              ? _HikerCircleAssistantPageState._green
              : message.isError || message.isEmergency
              ? accent.withValues(alpha: 0.1)
              : surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 5),
            bottomRight: Radius.circular(message.isUser ? 5 : 18),
          ),
          border: Border.all(
            color: message.isUser
                ? _HikerCircleAssistantPageState._green
                : message.isError || message.isEmergency
                ? accent.withValues(alpha: 0.45)
                : separator,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: message.isUser ? Colors.white : text,
                height: 1.42,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (message.notice case final notice?) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CE7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF7C5CE7),
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        notice,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: secondary,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (message.sources.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.sources
                    .map(
                      (source) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          source.title,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionComposer extends StatelessWidget {
  const _QuestionComposer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;
  final Future<void> Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.viewInsetsOf(context).bottom * 0,
      ),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: separator)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('hiker-circle-assistant-question'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 480,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(onSend()),
              style: TextStyle(color: text),
              decoration: InputDecoration(
                hintText: 'Ask about HikerCircle…',
                hintStyle: TextStyle(color: secondary),
                counterText: '',
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0D1611)
                    : const Color(0xFFF3F7F4),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: separator),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: _HikerCircleAssistantPageState._green,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            key: const Key('hiker-circle-assistant-send'),
            tooltip: 'Send question',
            onPressed: enabled ? () => unawaited(onSend()) : null,
            style: IconButton.styleFrom(
              backgroundColor: _HikerCircleAssistantPageState._green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: separator,
              minimumSize: const Size.square(48),
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
