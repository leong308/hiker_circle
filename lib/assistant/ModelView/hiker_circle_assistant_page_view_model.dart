part of '../hiker_circle_assistant_page_feature.dart';

/// Owns the state and non-visual actions of HikerCircleAssistantPage.
class _HikerCircleAssistantPageStateViewModel extends ChangeNotifier {
  /// Creates hiker circle assistant page state view model.
  _HikerCircleAssistantPageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes contextual action for.
  HikerCircleAssistantAction? commandContextualActionFor(
    String question,
    bool isEmergency,
  ) {
    if (isEmergency) {
      return const HikerCircleAssistantAction(
        destinationId: 'sos',
        label: 'Open SOS',
      );
    }
    if (RegExp(
      r'\b(first[ -]?aid|medical|injur(y|ies|ed)|bleed(ing)?|wounds?|nosebleed|fracture|sprain(ed|s)?|burn|scald|bite|sting|choking|cpr|faint(ing)?|heatstroke|heat exhaustion|hypothermia)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return const HikerCircleAssistantAction(
        destinationId: 'first_aid',
        label: 'Open First-Aid Guide',
      );
    }
    if (RegExp(
      r'\b(sos|emergenc(y|ies)|danger|rescue|who (do|should|can) i contact|who to contact)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return const HikerCircleAssistantAction(
        destinationId: 'sos',
        label: 'Open SOS',
      );
    }
    return null;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<bool?> Function() effectPresentConfirmClearHistoryEffect1;

  late final Future<void> Function() effectClearHistory;

  /// Computes confirm clear history.
  Future<void> commandConfirmClearHistory() async {
    final confirmed = await effectPresentConfirmClearHistoryEffect1();
    if (confirmed == true && mounted) await effectClearHistory();
  }
}
