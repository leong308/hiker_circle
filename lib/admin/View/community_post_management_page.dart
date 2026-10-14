import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import 'admin_ui.dart';

class CommunityPostManagementPage extends StatefulWidget {
  const CommunityPostManagementPage({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  @override
  State<CommunityPostManagementPage> createState() =>
      _CommunityPostManagementPageState();
}

class _CommunityPostManagementPageState
    extends State<CommunityPostManagementPage> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = false, _saving = false, _hasMore = false;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.session.isAdmin) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = more
          ? await widget.repository.loadMoreAdminCommunityPosts(
              session: widget.session,
              afterPostId: _posts.last['postId'] as String,
            )
          : await widget.repository.loadAdminCommunityPosts(
              session: widget.session,
            );
      if (!mounted) return;
      setState(() {
        final byId = {
          for (final post in [
            ...(more ? _posts : <Map<String, dynamic>>[]),
            ...page,
          ])
            post['postId']: post,
        };
        _posts = byId.values.toList();
        _hasMore = page.length == 50;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Posts could not load. Retry to refresh this list.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    if (_saving || _loading) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'The change could not be saved. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _visibility(Map<String, dynamic> post, String status) async {
    final label = switch (status) {
      'approved' => 'Restore',
      'hidden' => 'Hide',
      _ => 'Remove',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label this post?'),
        content: Text(
          status == 'approved'
              ? 'This post will appear in the public community feed.'
              : 'This post will no longer appear in the public feed. Its record remains available here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(
        () => widget.repository.moderateCommunityPost(
          session: widget.session,
          postId: post['postId'] as String,
          moderationStatus: status,
        ),
      );
    }
  }

  Future<void> _edit(Map<String, dynamic> post) async {
    final edited = await showDialog<_PostEdit>(
      context: context,
      builder: (_) => _PostEditor(
        post: post,
        session: widget.session,
        repository: widget.repository,
      ),
    );
    if (edited != null && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Admin privilege is required.')),
      );
    }
    final visible = _posts
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
          title: const Text('Community posts'),
          actions: [
            IconButton(
              tooltip: 'Refresh posts',
              onPressed: _loading || _saving ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Manage posts directly. Detected flags are reviewed in Community Moderation.',
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
                        (post['authorHandle'] ?? post['authorName'] ?? 'Hiker')
                            .toString(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${post['trailName'] ?? 'General'} · ${post['visibility'] ?? 'public'}',
                        style: TextStyle(color: AdminUi.muted(context)),
                      ),
                      const SizedBox(height: 8),
                      SelectableText((post['caption'] ?? '').toString()),
                      if (post['imageUrls'] is List &&
                          (post['imageUrls'] as List).isNotEmpty)
                        Text(
                          '${(post['imageUrls'] as List).length} attached photos',
                        ),
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
    );
  }
}

class _PostEdit {
  const _PostEdit();
}

class _PostEditor extends StatefulWidget {
  const _PostEditor({
    required this.post,
    required this.session,
    required this.repository,
  });
  final Map<String, dynamic> post;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  @override
  State<_PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<_PostEditor> {
  late final _caption = TextEditingController(
    text: (widget.post['caption'] ?? '').toString(),
  );
  late final _images = List<String>.from(
    widget.post['imageUrls'] as List? ?? const [],
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _caption.text.length > 5000) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.editAdminCommunityPost(
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
