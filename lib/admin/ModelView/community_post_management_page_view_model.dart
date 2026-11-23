part of '../community_post_management_page_feature.dart';

/// Owns the state and non-visual actions of CommunityPostManagementPage.
class _CommunityPostManagementPageStateViewModel extends ChangeNotifier {
  /// Creates community post management page state view model.
  _CommunityPostManagementPageStateViewModel({
    required this.readRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<Map<String, dynamic>> statePosts = [];

  bool stateLoading = false, stateSaving = false, stateHasMore = false;

  String? stateError;

  String? stateNotice;

  /// Append another moderation page or replace the list when refreshing from the first page.
  Future<void> commandLoad({bool more = false}) async {
    if (!readSession().isAdmin ||
        stateLoading ||
        stateSaving ||
        (more && statePosts.isEmpty)) {
      return;
    }
    _publish(() {
      stateLoading = true;
      stateError = null;
    });
    try {
      final page = more
          ? await readRepository().loadMoreAdminCommunityPosts(
              session: readSession(),
              afterPostId: statePosts.last['postId'] as String,
              historyOnly: true,
            )
          : await readRepository().loadAdminCommunityPosts(
              session: readSession(),
              historyOnly: true,
            );
      if (!mounted) return;
      _publish(() {
        final byId = {
          for (final post in [
            ...(more ? statePosts : <Map<String, dynamic>>[]),
            ...page,
          ])
            post['postId']: post,
        };
        statePosts = byId.values.toList();
        stateHasMore = page.length == 50;
      });
    } catch (error) {
      if (mounted) {
        _publish(
          () => stateError = error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'Posts could not load. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) _publish(() => stateLoading = false);
    }
  }

  /// Serialize moderation writes and reload the resulting server state after success.
  Future<void> commandSave(Future<void> Function() action) async {
    if (!readSession().isAdmin || stateSaving || stateLoading) return;
    _publish(() {
      stateSaving = true;
      stateError = null;
      stateNotice = null;
    });
    try {
      await action();
      if (!mounted) return;
      _publish(() {
        stateSaving = false;
        stateNotice = 'Moderation decision saved.';
      });
      await commandLoad();
    } catch (error) {
      if (mounted) {
        _publish(() {
          stateSaving = false;
          stateError = error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'The change could not be saved. Check your connection and retry.';
        });
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<String?> Function(String label, String status)
  effectPresentVisibilityEffect1;

  late final Future<_PostEdit?> Function(Map<String, dynamic> post)
  effectPresentEditEffect1;

  /// Computes visibility.
  Future<void> commandVisibility(
    Map<String, dynamic> post,
    String status,
  ) async {
    final label = switch (status) {
      'approved' => 'Restore',
      'hidden' => 'Hide',
      _ => 'Remove',
    };
    if (!readSession().isAdmin || stateLoading || stateSaving) return;
    final reason = await effectPresentVisibilityEffect1(label, status);
    if (reason != null && mounted) {
      await commandSave(
        () => readRepository().moderateCommunityPost(
          session: readSession(),
          postId: post['postId'] as String,
          moderationStatus: status,
          reason: reason,
          expectedUpdatedAtMillis: (post['updatedAtMillis'] as num?)?.toInt(),
        ),
      );
    }
  }

  /// Computes edit.
  Future<void> commandEdit(Map<String, dynamic> post) async {
    final edited = await effectPresentEditEffect1(post);
    if (edited != null && mounted) await commandLoad();
  }
}
