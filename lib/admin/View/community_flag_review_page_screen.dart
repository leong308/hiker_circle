part of '../community_flag_review_page_feature.dart';

/// Displays the community flag review page.
class CommunityFlagReviewPage extends StatefulWidget {
  /// Creates community flag review page.
  const CommunityFlagReviewPage({
    super.key,
    required this.flag,
    this.loadSource,
    this.loadParent,
    this.reviewAction,
    this.invalidatePostCache,
  });

  final CommunityFlag flag;
  final Future<Map<String, dynamic>?> Function()? loadSource;
  final Future<Map<String, dynamic>?> Function()? loadParent;
  final Future<String> Function(String action)? reviewAction;
  final Future<void> Function(String postId)? invalidatePostCache;

  /// Creates the presentation state for this widget.
  @override
  State<CommunityFlagReviewPage> createState() =>
      _CommunityFlagReviewPageState();
}

/// Manages the community flag review page presentation and lifecycle.
class _CommunityFlagReviewPageState extends State<CommunityFlagReviewPage> {
  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CommunityFlagReviewPageStateViewModel(
      readFlag: () => widget.flag,
      readLoadParent: () => widget.loadParent,
      readLoadSource: () => widget.loadSource,
    )..addListener(_renderScreenModel);
  }

  late final _CommunityFlagReviewPageStateViewModel _screenModel;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late Future<_ReviewContent> _content = _loadContent();
  bool _saving = false;
  bool _confirming = false;
  String? _saveError;

  /// Delegates load content to the ViewModel.
  Future<_ReviewContent> _loadContent() => _screenModel.commandLoadContent();

  /// Retries content.
  void _retryContent() {
    if (_saving || _confirming) return;
    setState(() {
      _saveError = null;
      _content = _loadContent();
    });
  }

  /// Computes review.
  Future<void> _review(String action) async {
    if (_saving || _confirming) return;
    if (action == 'hide') {
      _confirming = true;
      bool? confirmed;
      try {
        confirmed = await _presentReviewEffect1();
      } finally {
        _confirming = false;
      }
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final status = widget.reviewAction != null
          ? await widget.reviewAction!(action)
          : (await FirebaseFunctions.instance
                    .httpsCallable('reviewCommunityContentFlag')
                    .call<Map<String, dynamic>>({
                      'reviewId': widget.flag.id,
                      'action': action,
                    })
                    .timeout(const Duration(seconds: 30)))
                .data['status']
                ?.toString();
      await _invalidateContentCache(status);
      if (!mounted) return;
      final (message, tone) = switch (status) {
        'dismissed' => (
          'Flag cleared. Content kept.',
          HikerCircleToastTone.success,
        ),
        'actioned' => (
          widget.flag.isComment
              ? 'Comment removed.'
              : 'Post hidden from the community.',
          HikerCircleToastTone.success,
        ),
        'superseded' => (
          'The content changed or is no longer public. No action was applied.',
          HikerCircleToastTone.info,
        ),
        'already-reviewed' => (
          'This flag has already been reviewed. No new action was applied.',
          HikerCircleToastTone.info,
        ),
        _ => throw const FormatException('The review was not confirmed.'),
      };
      HikerCircleToast.show(context, message, tone: tone);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save your decision. Please try again.';
      });
    }
  }

  /// Computes invalidate content cache.
  Future<void> _invalidateContentCache(String? status) async {
    if (!const {
      'actioned',
      'superseded',
      'already-reviewed',
    }.contains(status)) {
      return;
    }
    final source = RegExp(
      r'^communityPosts/([^/]+)(?:/comments/[^/]+)?$',
    ).firstMatch(widget.flag.sourcePath);
    if (source == null) return;
    final invalidate =
        widget.invalidatePostCache ??
        (widget.reviewAction == null
            ? LocalSessionDatabase().removeCachedCommunityPost
            : null);
    if (invalidate == null) return;
    try {
      // Remove the post and its cached thread together. The path is the
      // reviewed record's reference; the flag's denormalized postId may be old.
      await invalidate(source.group(1)!);
    } catch (_) {
      // The cloud decision is committed even if this phone cannot clear cache.
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      backgroundColor: AdminUi.background(context),
      appBar: PageHeaderAppBar(
        title: const Text('Review flag'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _saving ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: FutureBuilder<_ReviewContent>(
        future: _content,
        builder: (context, snapshot) {
          final loaded = snapshot.connectionState == ConnectionState.done;
          final source = snapshot.data?.source;
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('flag-review-scroll'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _detectionCard(context),
                          const SizedBox(height: 16),
                          if (!loaded)
                            const AdminPanel(
                              child: Column(
                                children: [
                                  LinearProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Loading original content…'),
                                ],
                              ),
                            )
                          else if (snapshot.hasError)
                            _unavailableCard(
                              context,
                              title: 'Content could not load',
                              message:
                                  'Load the original content before making a decision.',
                            )
                          else if (source == null)
                            _unavailableCard(
                              context,
                              title: 'Content is no longer available',
                              message:
                                  'You can clear this outdated flag from the review queue. No content will be hidden or removed.',
                            )
                          else ...[
                            _ContentCard(
                              title: widget.flag.isComment
                                  ? 'Flagged comment'
                                  : 'Flagged post',
                              data: source,
                              isComment: widget.flag.isComment,
                            ),
                            if (widget.flag.isComment) ...[
                              const SizedBox(height: 16),
                              if (snapshot.data?.parent != null)
                                _ContentCard(
                                  title: 'Parent post · context',
                                  data: snapshot.data!.parent!,
                                  isComment: false,
                                  compact: true,
                                )
                              else
                                AdminPanel(
                                  child: Text(
                                    snapshot.data?.parentUnavailable == true
                                        ? 'The parent post could not load. The comment is shown above.'
                                        : 'The parent post is unavailable.',
                                    style: TextStyle(
                                      color: AdminUi.muted(context),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _decisionBar(
                context,
                enabled: loaded && !snapshot.hasError && source != null,
                clearMissing: loaded && !snapshot.hasError && source == null,
              ),
            ],
          );
        },
      ),
    ),
  );

  /// Computes detection card.
  Widget _detectionCard(BuildContext context) {
    final flag = widget.flag;
    final color = flag.source == CommunityFlagSource.gemini
        ? AdminUi.blue(context)
        : AdminUi.green(context);
    final severityColor = switch (flag.severity) {
      'critical' || 'high' => Theme.of(context).colorScheme.error,
      'medium' =>
        AdminUi.dark(context)
            ? const Color(0xFFF5C46E)
            : const Color(0xFF916008),
      _ => AdminUi.muted(context),
    };
    final date = flag.flaggedAt?.toLocal();
    final local = MaterialLocalizations.of(context);
    final categories = flag.categoryLabels
        .where((label) => label != flag.title)
        .toList();
    final notes = flag.reasons
        .where((reason) => reason != flag.title && !categories.contains(reason))
        .toList();
    final evidence = flag.evidenceLabels
        .where(
          (label) => !flag.matchedKeywords.any(
            (word) => label == 'Matched phrase “$word”',
          ),
        )
        .toList();
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminTag(
                label: flag.sourceLabel,
                icon: switch (flag.source) {
                  CommunityFlagSource.gemini => Icons.auto_awesome_outlined,
                  CommunityFlagSource.keywords => Icons.find_in_page_outlined,
                  CommunityFlagSource.pattern => Icons.manage_search_rounded,
                  CommunityFlagSource.integrity => Icons.fact_check_outlined,
                  _ => Icons.info_outline_rounded,
                },
                color: color,
              ),
              AdminTag(
                label: flag.contentTypeLabel,
                icon: flag.isComment
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.article_outlined,
                color: AdminUi.muted(context),
              ),
              if (flag.severity != 'unknown')
                AdminTag(
                  label: '${flag.severityLabel} priority',
                  color: severityColor,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            flag.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            flag.sourceDescription,
            style: TextStyle(color: AdminUi.muted(context), height: 1.45),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel('Flag categories'),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final label in categories)
                  AdminTag(label: label, color: AdminUi.muted(context)),
              ],
            ),
          ],
          if (flag.matchedKeywords.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel('Matched keywords'),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final word in flag.matchedKeywords)
                  AdminTag(label: '“$word”', color: color),
              ],
            ),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel('Detection details'),
            const SizedBox(height: 6),
            for (final label in evidence)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• $label', style: const TextStyle(height: 1.4)),
              ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SectionLabel('Review notes'),
            const SizedBox(height: 6),
            for (final reason in notes)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(reason, style: const TextStyle(height: 1.4)),
              ),
          ],
          const Divider(height: 28),
          Text(
            'A flag is a reason to review, not a confirmed violation.',
            style: TextStyle(color: AdminUi.muted(context), height: 1.4),
          ),
          if (date != null || flag.model.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (date != null)
                  '${local.formatMediumDate(date)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                if (flag.model.isNotEmpty) 'Model: ${flag.model}',
              ].join('\n'),
              style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Computes unavailable card.
  Widget _unavailableCard(
    BuildContext context, {
    required String title,
    required String message,
  }) => AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: AdminUi.muted(context))),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('reload-flag-content'),
            onPressed: _retryContent,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reload content'),
          ),
        ),
      ],
    ),
  );

  /// Computes decision bar.
  Widget _decisionBar(
    BuildContext context, {
    required bool enabled,
    required bool clearMissing,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: AdminUi.surface(context),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AdminUi.border(context))),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .45,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_saving) ...[
                        const LinearProgressIndicator(minHeight: 3),
                        const SizedBox(height: 10),
                      ],
                      if (_saveError != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _saveError!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final vertical =
                              constraints.maxWidth < 350 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20;
                          final keep = OutlinedButton.icon(
                            key: const ValueKey('keep-flag-content'),
                            onPressed: (enabled || clearMissing) && !_saving
                                ? () => _review('dismiss')
                                : null,
                            icon: const Icon(Icons.check_rounded, size: 19),
                            label: Text(
                              clearMissing ? 'Clear flag' : 'Keep content',
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          );
                          final hide = FilledButton.icon(
                            key: const ValueKey('hide-flag-content'),
                            onPressed: enabled && !_saving
                                ? () => _review('hide')
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.error,
                              foregroundColor: colors.onError,
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            icon: Icon(
                              widget.flag.isComment
                                  ? Icons.delete_outline_rounded
                                  : Icons.visibility_off_outlined,
                              size: 19,
                            ),
                            label: Text(
                              _saving
                                  ? 'Saving…'
                                  : widget.flag.isComment
                                  ? 'Remove comment'
                                  : 'Hide post',
                            ),
                          );
                          return vertical
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    keep,
                                    const SizedBox(height: 8),
                                    hide,
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: keep),
                                    const SizedBox(width: 10),
                                    Expanded(child: hide),
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
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

  /// Presents the review effect1 UI.
  Future<bool?> _presentReviewEffect1() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        widget.flag.isComment ? 'Remove this comment?' : 'Hide this post?',
      ),
      content: Text(
        widget.flag.isComment
            ? 'The comment will be removed. A copy is kept in the private moderation record.'
            : 'The post will leave the public feed. You can restore it later in Moderate posts.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-flag-action'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(widget.flag.isComment ? 'Remove comment' : 'Hide post'),
        ),
      ],
    ),
  );
}

/// Computes text.
String _text(Object? value) => value is String ? value.trim() : '';
