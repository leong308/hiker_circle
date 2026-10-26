part of '../hike_share_preview_page_feature.dart';

/// Owns the state and non-visual actions of HikeSharePreviewPage.
class _HikeSharePreviewPageStateViewModel extends ChangeNotifier {
  /// Creates hike share preview page state view model.
  _HikeSharePreviewPageStateViewModel({
    required this.readActiveHike,
    required this.readOnPostToCommunity,
    required this.readRepository,
    required this.readSession,
    required this.effectSaveInBackground,
  });
  final ActiveHikeSession Function() readActiveHike;
  final Future<void> Function(
    String caption,
    List<CommunityPostImageUpload> images,
  )
  Function()
  readOnPostToCommunity;
  final HikerCircleFirebaseRepository? Function() readRepository;
  final AppSession Function() readSession;
  final void Function() effectSaveInBackground;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late CommunityPostDraft stateInitialDraft;

  late CommunityPostDraft stateCurrentDraft;

  late String statePostId;

  bool stateIsEditingBusy = false;

  bool stateIsSharingExternally = false;

  bool stateIsClosing = false;

  bool stateIsLoading = false;

  bool statePublished = false;

  String? stateLoadError;

  Timer? stateSaveTimer;

  Future<void> stateSaveChain = Future<void>.value();

  /// Returns command is busy.
  bool get commandIsBusy =>
      stateIsEditingBusy || stateIsSharingExternally || stateIsClosing;

  /// Returns command draft key.
  String get commandDraftKey => 'hike:${readActiveHike().sessionId}';

  /// Loads draft.
  Future<void> commandLoadDraft() async {
    _publish(() {
      stateIsLoading = true;
      stateLoadError = null;
    });
    try {
      final saved = await readRepository()!.loadCommunityPostDraft(
        session: readSession(),
        draftKey: commandDraftKey,
      );
      if (!mounted) return;
      if (saved != null) {
        statePostId = saved.postId;
        stateInitialDraft = CommunityPostDraft(
          caption: saved.caption,
          images: saved.images,
          includeHike: true,
        );
        stateCurrentDraft = stateInitialDraft;
      }
      _publish(() => stateIsLoading = false);
    } catch (_) {
      if (mounted) {
        _publish(() {
          stateIsLoading = false;
          stateLoadError =
              'Your saved post could not be opened. Try again to keep your draft safe.';
        });
      }
    }
  }

  /// Computes draft changed.
  void commandDraftChanged(CommunityPostDraft draft) {
    stateCurrentDraft = draft;
    stateSaveTimer?.cancel();
    if (readRepository() == null) return;
    stateSaveTimer = Timer(
      const Duration(milliseconds: 350),
      effectSaveInBackground,
    );
  }

  /// Serialize end-hike draft writes so a late autosave cannot overwrite a newer caption or photo selection.
  Future<void> commandSaveDraft() {
    final repository = readRepository();
    if (repository == null ||
        statePublished ||
        stateIsLoading ||
        stateLoadError != null) {
      return Future<void>.value();
    }
    final draft = stateCurrentDraft;
    final pending = stateSaveChain.then(
      (_) => repository.saveCommunityPostDraft(
        session: readSession(),
        draftKey: commandDraftKey,
        postId: statePostId,
        caption: draft.caption,
        images: draft.images,
        includeHike: true,
      ),
    );
    stateSaveChain = pending.catchError((Object _) {});
    return pending;
  }

  /// Save the stable post identity before publishing; local cleanup cannot turn a confirmed post into failure.
  Future<void> commandPublish(CommunityPostDraft draft) async {
    stateCurrentDraft = draft;
    stateSaveTimer?.cancel();
    try {
      await commandSaveDraft();
    } catch (_) {
      throw const HikerCircleFirebaseRepositoryException(
        'Your draft could not be saved. Please try posting again.',
      );
    }
    await readOnPostToCommunity()(draft.caption, draft.images);
    statePublished = true;
    // A cleanup failure must not turn a successful, idempotent post into an error.
    try {
      await readRepository()?.deleteCommunityPostDraft(
        session: readSession(),
        draftKey: commandDraftKey,
      );
    } catch (_) {}
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
