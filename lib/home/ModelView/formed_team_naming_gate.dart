import '../Model/hike_session_models.dart';

/// Keeps first-time group naming host-only and serializes competing UI events.
class FormedTeamNamingGate {
  String? _activeChatId;
  String? get activeChatId => _activeChatId;
  final Set<String> _handled = {};
  final Set<String> _authorizing = {};

  bool canOffer(GroupChat chat, String viewerPhone) {
    final owner = chat.creatorPhone.replaceAll(RegExp(r'\D'), '');
    final viewer = viewerPhone.replaceAll(RegExp(r'\D'), '');
    return chat.id.trim().isNotEmpty &&
        viewer.isNotEmpty &&
        owner == viewer &&
        !chat.isDirect &&
        !chat.isDeleted &&
        chat.hikeEndedAt == null &&
        chat.participantPhones.length >= 2 &&
        chat.requiresHostNaming &&
        !chat.namingPromptShown &&
        !_handled.contains(chat.id);
  }

  bool reserve(GroupChat chat, String viewerPhone) {
    if (activeChatId != null || !canOffer(chat, viewerPhone)) return false;
    _activeChatId = chat.id;
    return true;
  }

  /// A failed or denied backend check must never open a naming dialog.
  Future<bool> authorize(String chatId, Future<bool> Function() check) async {
    if (activeChatId != chatId ||
        _handled.contains(chatId) ||
        !_authorizing.add(chatId)) {
      return false;
    }
    try {
      final granted = await check();
      _handled.add(chatId);
      if (!granted) release(chatId);
      return granted;
    } catch (_) {
      release(chatId);
      rethrow;
    } finally {
      _authorizing.remove(chatId);
    }
  }

  void release(String chatId) {
    if (activeChatId == chatId) _activeChatId = null;
  }
}
