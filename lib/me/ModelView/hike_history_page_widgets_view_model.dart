part of '../hike_history_page_feature.dart';

/// Coordinates history team tab state view model state and actions.
class _HistoryTeamTabStateViewModel extends ChangeNotifier {
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final HikeHistoryDetail Function() readDetail;

  late final AppSession? Function() readSession;

  late final HikerCircleFirebaseRepository? Function() readRepository;

  late final Future<void> Function(
    GroupChat chat,
    AppSession session,
    HikerCircleFirebaseRepository repository,
  )
  effectPresentOpenChatEffect2;

  late final void Function() effectPresentOpenChatEffect1;

  bool stateOpeningChat = false;

  /// Opens chat.
  Future<void> commandOpenChat() async {
    final repository = readRepository();
    final session = readSession();
    if (repository == null || session == null || stateOpeningChat) return;
    _publish(() => stateOpeningChat = true);
    try {
      final chat = await repository.loadGroupChatById(readDetail().groupChatId);
      if (!mounted) return;
      if (chat == null) {
        effectPresentOpenChatEffect1();
        return;
      }
      await effectPresentOpenChatEffect2(chat, session, repository);
    } finally {
      if (mounted) _publish(() => stateOpeningChat = false);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
