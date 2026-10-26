part of '../community_integrity_panel_feature.dart';

/// Owns the state and non-visual actions of CommunityIntegrityPanel.
class _CommunityIntegrityPanelStateViewModel extends ChangeNotifier {
  /// Creates community integrity panel state view model.
  _CommunityIntegrityPanelStateViewModel({
    required this.readHealth,
    required this.readLoadReviews,
    required this.readReviews,
  });
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? Function() readHealth;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(int limit)?
  Function()
  readLoadReviews;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? Function() readReviews;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Returns command connected.
  bool get commandConnected => Firebase.apps.isNotEmpty;

  /// Returns command has reviews.
  bool get commandHasReviews =>
      readReviews() != null || readLoadReviews() != null || commandConnected;

  /// Returns command has health.
  bool get commandHasHealth => readHealth() != null || commandConnected;

  /// Computes health stream.
  Stream<DocumentSnapshot<Map<String, dynamic>>> commandHealthStream() =>
      readHealth() ??
      FirebaseFirestore.instance
          .doc('communityModerationStatus/current')
          .snapshots();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<bool?> Function(CommunityFlag flag)? Function()
  readOpenReview;

  late final VoidCallback? Function() readOnReviewed;

  late final Future<bool?> Function(CommunityFlag flag)
  effectPresentOpenEffect1;

  final Set<String> stateOpening = {};

  final Map<String, String> stateResolved = {};

  /// Opens.
  Future<void> commandOpen(CommunityFlag flag) async {
    if (!stateOpening.add(flag.id)) return;
    try {
      final reviewed = readOpenReview() != null
          ? await readOpenReview()!(flag)
          : await effectPresentOpenEffect1(flag);
      if (!mounted || reviewed != true) return;
      _publish(() => stateResolved[flag.id] = flag.fingerprint);
      readOnReviewed()?.call();
    } finally {
      stateOpening.remove(flag.id);
    }
  }
}
