part of '../community_post_management_page_feature.dart';

/// Defines the post filter choices.
enum _PostFilter { all, public, hidden, removed }

/// Displays the community post management page.
class CommunityPostManagementPage extends StatefulWidget {
  /// Creates community post management page.
  const CommunityPostManagementPage({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<CommunityPostManagementPage> createState() =>
      _CommunityPostManagementPageState();
}

/// Manages the community post management page presentation and lifecycle.
class _CommunityPostManagementPageState
    extends State<CommunityPostManagementPage> {
  late final _CommunityPostManagementPageStateViewModel _screenModel;

  /// Returns posts.
  List<Map<String, dynamic>> get _posts => _screenModel.statePosts;

  /// Returns loading.
  bool get _loading => _screenModel.stateLoading;

  /// Returns saving.
  bool get _saving => _screenModel.stateSaving;

  /// Returns has more.
  bool get _hasMore => _screenModel.stateHasMore;

  /// Returns error.
  String? get _error => _screenModel.stateError;

  /// Returns notice.
  String? get _notice => _screenModel.stateNotice;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  String _search = '';
  _PostFilter _filter = _PostFilter.all;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _CommunityPostManagementPageStateViewModel(
      readRepository: () => widget.repository,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentVisibilityEffect1 = _presentVisibilityEffect1;
    _screenModel.effectPresentEditEffect1 = _presentEditEffect1;

    if (widget.session.isAdmin) _load();
  }

  /// Append another moderation page or replace the list when refreshing from the first page.
  Future<void> _load({bool more = false}) =>
      _screenModel.commandLoad(more: more);

  /// Delegates visibility to the ViewModel.
  Future<void> _visibility(Map<String, dynamic> post, String status) =>
      _screenModel.commandVisibility(post, status);

  /// Delegates edit to the ViewModel.
  Future<void> _edit(Map<String, dynamic> post) =>
      _screenModel.commandEdit(post);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Admin privilege is required.')),
      );
    }
    final visible = _posts
        .where(
          (post) =>
              _filter == _PostFilter.all || post['visibility'] == _filter.name,
        )
        .where(
          (post) => [
            post['caption'],
            post['authorHandle'],
            post['authorName'],
            post['trailName'],
            post['postId'],
          ].join(' ').toLowerCase().contains(_search),
        )
        .toList();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AdminUi.background(context),
        appBar: PageHeaderAppBar(
          title: const Text('Moderate posts'),
          actions: [
            IconButton(
              tooltip: 'Refresh posts',
              onPressed: _loading || _saving ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => _load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Review any community post. Hidden and removed posts stay here for review and can be restored.',
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (text) =>
                    setState(() => _search = text.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Search loaded posts',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final filter in _PostFilter.values)
                    ChoiceChip(
                      key: ValueKey('post-filter-${filter.name}'),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                      label: Text(switch (filter) {
                        _PostFilter.all => 'All',
                        _PostFilter.public => 'Public',
                        _PostFilter.hidden => 'Hidden',
                        _PostFilter.removed => 'Removed',
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${visible.length} shown · ${_posts.length} posts loaded${_hasMore ? ' · more available' : ''}',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
              ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _notice!,
                      style: TextStyle(color: AdminUi.green(context)),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading || _saving ? null : () => _load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              if (_loading || _saving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
              if (!_loading && _error == null && visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _search.isEmpty
                        ? 'No posts available.'
                        : 'No matching posts in the loaded list.',
                  ),
                ),
              for (final post in visible)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AdminPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          (post['authorHandle'] ??
                                  post['authorName'] ??
                                  'Hiker')
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          (post['trailName'] ?? '').toString().trim().isEmpty
                              ? 'Community post'
                              : post['trailName'].toString(),
                          style: TextStyle(color: AdminUi.muted(context)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            AdminTag(
                              label: switch (post['visibility']) {
                                'hidden' => 'Hidden from feed',
                                'removed' => 'Removed from feed',
                                _ => 'Public',
                              },
                              icon: post['visibility'] == 'public'
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: post['visibility'] == 'public'
                                  ? AdminUi.green(context)
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ],
                        ),
                        if ((post['moderationReason'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last decision: ${post['moderationReason']}',
                            style: TextStyle(color: AdminUi.muted(context)),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SelectableText(
                          (post['caption'] ?? '').toString().isEmpty
                              ? 'No caption'
                              : post['caption'].toString(),
                        ),
                        if (post['imageUrls'] is List &&
                            (post['imageUrls'] as List).isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _PostPhotoStrip(
                            urls: (post['imageUrls'] as List)
                                .whereType<String>()
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _loading || _saving
                                  ? null
                                  : () => _edit(post),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit post'),
                            ),
                            if (post['visibility'] != 'public')
                              OutlinedButton.icon(
                                onPressed: _loading || _saving
                                    ? null
                                    : () => _visibility(post, 'approved'),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Restore'),
                              ),
                            if (post['visibility'] == 'public')
                              OutlinedButton.icon(
                                onPressed: _loading || _saving
                                    ? null
                                    : () => _visibility(post, 'hidden'),
                                icon: const Icon(Icons.visibility_off_outlined),
                                label: const Text('Hide'),
                              ),
                            if (post['visibility'] != 'removed')
                              OutlinedButton.icon(
                                onPressed: _loading || _saving
                                    ? null
                                    : () => _visibility(post, 'removed'),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: OutlinedButton(
                    onPressed: _loading || _saving
                        ? null
                        : () => _load(more: true),
                    child: const Text('Load more posts'),
                  ),
                ),
            ],
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

  /// Presents the visibility effect1 UI.
  Future<String?> _presentVisibilityEffect1(String label, String status) =>
      showDialog<String>(
        context: context,
        builder: (_) => _ModerationDecisionDialog(label: label, status: status),
      );

  /// Presents the edit effect1 UI.
  Future<_PostEdit?> _presentEditEffect1(Map<String, dynamic> post) =>
      showDialog<_PostEdit>(
        context: context,
        builder: (_) => _PostEditor(
          post: post,
          session: widget.session,
          repository: widget.repository,
        ),
      );
}

/// Displays the moderation decision dialog.
class _ModerationDecisionDialog extends StatefulWidget {
  /// Creates moderation decision dialog.
  const _ModerationDecisionDialog({required this.label, required this.status});
  final String label, status;

  /// Creates the presentation state for this widget.
  @override
  State<_ModerationDecisionDialog> createState() =>
      _ModerationDecisionDialogState();
}

/// Manages the moderation decision dialog presentation and lifecycle.
class _ModerationDecisionDialogState extends State<_ModerationDecisionDialog> {
  final _reason = TextEditingController();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.label} this post?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.status == 'approved'
                ? 'The post will return to the public community feed.'
                : 'The post will leave the public feed. Its record and this decision will be kept for review.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Add a short note for the moderation record',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _reason.text.trim()),
        child: Text(widget.label),
      ),
    ],
  );
}

/// Displays the post editor.
class _PostEditor extends StatefulWidget {
  /// Creates post editor.
  const _PostEditor({
    required this.post,
    required this.session,
    required this.repository,
  });
  final Map<String, dynamic> post;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<_PostEditor> createState() => _PostEditorState();
}

/// Manages the post editor presentation and lifecycle.
class _PostEditorState extends State<_PostEditor> {
  late final _caption = TextEditingController(
    text: (widget.post['caption'] ?? '').toString(),
  );
  late final _images = List<String>.from(
    widget.post['imageUrls'] as List? ?? const [],
  );
  bool _saving = false;
  String? _error;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Saves.
  Future<void> _save() async {
    if (_saving || _caption.text.length > 5000) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _CommunityPostManagementPageDataActions.editAdminCommunityPost(
        widget.repository,
      )(
        session: widget.session,
        original: widget.post,
        caption: _caption.text,
        imageUrls: List.of(_images),
      );
      if (mounted) Navigator.pop(context, const _PostEdit());
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'Could not save. Your edits are still here; retry when connected.';
        });
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit community post'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _caption,
                enabled: !_saving,
                minLines: 3,
                maxLines: 8,
                maxLength: 5000,
                decoration: const InputDecoration(labelText: 'Caption'),
              ),
              for (final url in List.of(_images))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Image.network(
                          url,
                          height: 100,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const SizedBox(
                            height: 60,
                            child: Center(
                              child: Text('Photo preview unavailable'),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove attached photo',
                        onPressed: _saving
                            ? null
                            : () => setState(() => _images.remove(url)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_saving) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save changes'),
        ),
      ],
    ),
  );
}
