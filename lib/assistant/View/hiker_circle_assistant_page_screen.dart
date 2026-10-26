part of '../hiker_circle_assistant_page_feature.dart';

/// Keep conversation presentation separate from backend answers and account-scoped history persistence.
class HikerCircleAssistantPage extends StatefulWidget {
  /// Creates hiker circle assistant page.
  const HikerCircleAssistantPage({
    super.key,
    this.repository,
    this.onOpenTrail,
    this.onNavigate,
    this.ownerPhoneNumber,
    this.historyStore,
  });

  final HikerCircleAssistantRepository? repository;
  final Future<void> Function(String trailId)? onOpenTrail;
  final void Function(String destinationId)? onNavigate;
  final String? ownerPhoneNumber;
  final HikerCircleAssistantHistoryStore? historyStore;

  /// Creates the presentation state for this widget.
  @override
  State<HikerCircleAssistantPage> createState() =>
      _HikerCircleAssistantPageState();
}

/// Manages the hiker circle assistant page presentation and lifecycle.
class _HikerCircleAssistantPageState extends State<HikerCircleAssistantPage> {
  late final _HikerCircleAssistantPageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _green = Color(0xFF34A853);
  static const _suggestions = <String>[
    'How do I prepare for a group hike?',
    'Where can I manage my passkey?',
    'What do the trail caution icons mean?',
    'How does Hike History work?',
  ];

  late final HikerCircleAssistantRepository _repository;
  HikerCircleAssistantHistoryStore? _historyStore;
  Future<void> _pendingSave = Future<void>.value();
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
  bool _isLoadingHistory = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikerCircleAssistantPageStateViewModel()
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentConfirmClearHistoryEffect1 =
        _presentConfirmClearHistoryEffect1;
    _screenModel.effectClearHistory = _clearHistory;

    _repository = widget.repository ?? HikerCircleAssistantRepository();
    _historyStore =
        widget.historyStore ??
        (widget.ownerPhoneNumber?.trim().isNotEmpty == true
            ? HikerCircleAssistantHistoryStore(
                ownerPhoneNumber: widget.ownerPhoneNumber!.trim(),
                cloud: FirebaseAssistantHistoryCloud(),
              )
            : null);
    if (_historyStore != null) {
      _isLoadingHistory = true;
      unawaited(_restoreHistory());
    }
  }

  /// Restores history.
  Future<void> _restoreHistory() async {
    try {
      final saved = await _historyStore!.load();
      if (!mounted) return;
      setState(() {
        _messages.addAll(saved.map(_AssistantMessage.fromMap));
      });
      _scrollToEnd();
      try {
        final synced = await _historyStore!.synchronize().timeout(
          const Duration(seconds: 8),
        );
        if (!mounted) return;
        setState(() {
          _messages.removeRange(1, _messages.length);
          _messages.addAll(synced.map(_AssistantMessage.fromMap));
        });
        _scrollToEnd();
      } catch (_) {
        // The local copy remains available when Firestore cannot be reached.
      }
      if (mounted) setState(() => _isLoadingHistory = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
      HikerCircleToast.show(context, 'Saved chat could not be loaded.');
    }
  }

  /// Saves history.
  void _saveHistory() {
    final store = _historyStore;
    if (store == null) return;
    final data = _messages.skip(1).map((message) => message.toMap()).toList();
    _pendingSave = _pendingSave.then((_) => store.save(data)).catchError((_) {
      if (mounted) {
        HikerCircleToast.show(context, 'Chat could not be saved.');
      }
    });
  }

  /// Clear persisted history as well as visible messages so reopening does not restore the old conversation.
  Future<void> _clearHistory() async {
    await _pendingSave;
    try {
      await _historyStore?.clear();
      if (mounted) setState(() => _messages.removeRange(1, _messages.length));
    } catch (_) {
      if (!mounted) return;
      HikerCircleToast.show(context, 'Chat could not be cleared.');
    }
  }

  /// Delegates confirm clear history to the ViewModel.
  Future<void> _confirmClearHistory() =>
      _screenModel.commandConfirmClearHistory();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Send bounded recent history and request a location fix only for nearby-trail questions.
  Future<void> _send([String? suggestedQuestion]) async {
    if (_isSending || _isLoadingHistory) return;
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
    final previous = _messages
        .skip(1)
        .where((message) => !message.isError)
        .map(
          (message) => <String, String>{
            'role': message.isUser ? 'user' : 'assistant',
            'text': message.text,
          },
        )
        .toList();
    final history = previous.length > 8
        ? previous.sublist(previous.length - 8)
        : previous;
    setState(() {
      _messages.add(_AssistantMessage.newEntry(text: question, isUser: true));
      _isSending = true;
    });
    _saveHistory();
    _scrollToEnd();
    try {
      final needsLocation =
          RegExp(
            r'\b(near|nearest|nearby|closest|around|to me)\b',
            caseSensitive: false,
          ).hasMatch(question) &&
          RegExp(
            r'\b(trail|hiking route|mountain)\b',
            caseSensitive: false,
          ).hasMatch(question);
      final position = needsLocation
          ? await LocationSnapshotService.instance.refresh()
          : null;
      final validPosition =
          position != null &&
          position.latitude.isFinite &&
          position.longitude.isFinite &&
          position.latitude.abs() <= 90 &&
          position.longitude.abs() <= 180;
      final answer =
          await _HikerCircleAssistantPageDataActions.ask(_repository)(
            question,
            location: validPosition
                ? {
                    'latitude': position.latitude,
                    'longitude': position.longitude,
                  }
                : null,
            history: history,
          ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final action =
          answer.action ?? _contextualActionFor(question, answer.isEmergency);
      setState(() {
        _messages.add(
          _AssistantMessage.newEntry(
            text: answer.answer,
            isUser: false,
            sources: answer.sources,
            isEmergency: answer.isEmergency,
            notice: answer.notice,
            trails: answer.trails,
            action: action,
          ),
        );
      });
      _saveHistory();
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

  /// Delegates contextual action for to the ViewModel.
  HikerCircleAssistantAction? _contextualActionFor(
    String question,
    bool isEmergency,
  ) => _screenModel.commandContextualActionFor(question, isEmergency);

  /// Adds error.
  void _addError(String message) {
    setState(() {
      _messages.add(
        _AssistantMessage.newEntry(text: message, isUser: false, isError: true),
      );
    });
    _saveHistory();
    HikerCircleToast.show(
      context,
      message,
      title: 'Assistant unavailable',
      tone: HikerCircleToastTone.error,
    );
  }

  /// Computes scroll to end.
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

  /// Builds this widget from its current presentation state.
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
                  if (_messages.length > 1)
                    IconButton(
                      key: const Key('assistant-clear-chat'),
                      tooltip: 'Clear chat',
                      onPressed: _isSending || _isLoadingHistory
                          ? null
                          : () => unawaited(_confirmClearHistory()),
                      icon: const Icon(Icons.delete_outline_rounded),
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
                              onPressed: _isSending || _isLoadingHistory
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
                      onOpenTrail: widget.onOpenTrail,
                      onNavigate: widget.onNavigate,
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
              enabled: !_isSending && !_isLoadingHistory,
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

  /// Presents the confirm clear history effect1 UI.
  Future<bool?> _presentConfirmClearHistoryEffect1() => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear assistant chat?'),
      content: const Text(
        'This removes the saved conversation from this device and Firestore.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Clear chat'),
        ),
      ],
    ),
  );
}

/// Displays the ai thinking bubble.
class _AiThinkingBubble extends StatefulWidget {
  /// Creates ai thinking bubble.
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

  /// Creates the presentation state for this widget.
  @override
  State<_AiThinkingBubble> createState() => _AiThinkingBubbleState();
}

/// Manages the ai thinking bubble presentation and lifecycle.
class _AiThinkingBubbleState extends State<_AiThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Finding reviewed guidance',
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

/// Displays the thinking dot.
class _ThinkingDot extends StatelessWidget {
  /// Creates thinking dot.
  const _ThinkingDot({required this.progress, required this.index});

  final double progress;
  final int index;

  /// Builds this widget from its current presentation state.
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

/// Displays the message bubble.
class _MessageBubble extends StatelessWidget {
  /// Creates message bubble.
  const _MessageBubble({
    required this.message,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.separator,
    this.onOpenTrail,
    this.onNavigate,
  });

  final _AssistantMessage message;
  final Color surface;
  final Color text;
  final Color secondary;
  final Color separator;
  final Future<void> Function(String trailId)? onOpenTrail;
  final void Function(String destinationId)? onNavigate;

  /// Builds this widget from its current presentation state.
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
            if (message.action case final action?) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onNavigate == null
                    ? null
                    : () => onNavigate!(action.destinationId),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(action.label),
              ),
            ],
            for (final trail in message.trails) ...[
              const SizedBox(height: 9),
              Card(
                margin: EdgeInsets.zero,
                color: surface,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: Key('assistant-trail-${trail.id}'),
                  onTap: onOpenTrail == null
                      ? null
                      : () => unawaited(onOpenTrail!(trail.id)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trail.coverImageUrl.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          height: 108,
                          child: Image.network(
                            trail.coverImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                ColoredBox(
                                  color: _HikerCircleAssistantPageState._green
                                      .withValues(alpha: 0.1),
                                  child: const Center(
                                    child: Icon(
                                      Icons.landscape_rounded,
                                      color:
                                          _HikerCircleAssistantPageState._green,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trail.name,
                              style: TextStyle(
                                color: text,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              [
                                trail.area,
                                trail.state,
                              ].where((s) => s.isNotEmpty).join(', '),
                              style: TextStyle(color: secondary),
                            ),
                            Text(
                              '${trail.distanceKm.toStringAsFixed(1)} km trail'
                              '${trail.difficulty.isNotEmpty ? ' · ${trail.difficulty}' : ''}'
                              '${trail.estimatedDurationMinutes > 0 ? ' · ${trail.estimatedDurationMinutes} min' : ''}'
                              '${trail.distanceFromUserKm != null ? ' · ${trail.distanceFromUserKm!.toStringAsFixed(1)} km away' : ''}',
                              style: TextStyle(color: secondary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'View trail →',
                              style: TextStyle(color: Color(0xFF34A853)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

/// Displays the question composer.
class _QuestionComposer extends StatelessWidget {
  /// Creates question composer.
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

  /// Builds this widget from its current presentation state.
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
