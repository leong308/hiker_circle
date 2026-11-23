part of '../community_integrity_panel_feature.dart';

/// Owns queue subscriptions, filters, paging and review navigation state.
class _CommunityIntegrityPanelStateViewModel extends ChangeNotifier {
  /// Binds live data without subscribing to private chats or changing content.
  _CommunityIntegrityPanelStateViewModel({
    required this.readHealth,
    required this.readLoadReviews,
    required this.readReviews,
    required this.readRunChecks,
  }) {
    _replaceStreams();
  }

  final Stream<DocumentSnapshot<Map<String, dynamic>>>? Function() readHealth;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(int limit)?
  Function()
  readLoadReviews;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? Function() readReviews;
  final Future<Map<String, dynamic>> Function()? Function() readRunChecks;
  CommunityIntegrityStatus? stateManualHealth;
  bool stateRefreshing = false;
  String? stateRefreshError;
  static const pageSize = 50;
  int stateLimit = pageSize;
  String stateQuery = '';
  CommunityFlagFilters stateFilters = const CommunityFlagFilters();
  Stream<QuerySnapshot<Map<String, dynamic>>>? stateReviews;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? stateHealth;
  String? stateError;
  final Set<String> stateOpening = {};
  final Map<String, String> stateResolved = {};
  bool _disposed = false;

  late final Future<bool?> Function(CommunityFlag flag)? Function()
  readOpenReview;
  late final VoidCallback? Function() readOnReviewed;
  late final Future<bool?> Function(CommunityFlag flag)
  effectPresentOpenEffect1;

  /// Whether a Firebase app or an injected source can supply pending flags.
  bool get commandHasReviews => stateReviews != null;

  /// Enables explicit server checks when Firebase or an injected scan action is available.
  bool get commandCanRunChecks =>
      !stateRefreshing && (Firebase.apps.isNotEmpty || readRunChecks() != null);

  /// Runs a manual scan and displays its result.
  Future<void> commandRunChecks() async {
    if (!commandCanRunChecks) return;
    _publish(() {
      stateRefreshing = true;
      stateRefreshError = null;
    });
    try {
      final result =
          await (readRunChecks() ??
              const CommunityIntegrityRepository().runChecks)();
      if (_disposed) return;
      _publish(() {
        stateManualHealth = CommunityIntegrityStatus.fromMap(result);
        stateError = null;
        _replaceStreams();
      });
    } catch (error) {
      if (!_disposed) {
        _publish(
          () => stateRefreshError = error is FirebaseFunctionsException
              ? error.message ?? 'Checks could not finish. Please try again.'
              : 'Checks could not finish. Please try again.',
        );
      }
    } finally {
      if (!_disposed) _publish(() => stateRefreshing = false);
    }
  }

  /// Creates stable streams so rebuilds do not restart database listeners.
  void _replaceStreams() {
    final connected = Firebase.apps.isNotEmpty;
    stateReviews =
        readLoadReviews()?.call(stateLimit) ??
        readReviews() ??
        (connected
            // Query live pending moderation reviews
            ? FirebaseFirestore.instance
                  .collection('communityModerationReviews')
                  .where('status', isEqualTo: 'pending')
                  .limit(stateLimit)
                  .snapshots()
            : null);
    stateHealth =
        readHealth() ??
        (connected
            // Query latest moderation health
            ? FirebaseFirestore.instance
                  .doc('communityModerationStatus/current')
                  .snapshots()
            : null);
  }

  /// Publishes state only while the panel remains on screen.
  void _publish(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  /// Reconnects both data sources while preserving search and applied filters.
  void commandRefresh() => _publish(() {
    stateError = null;
    _replaceStreams();
  });

  /// Adds another page to the loaded subset searched by the controls.
  void commandLoadMore() => _publish(() {
    stateLimit += pageSize;
    _replaceStreams();
  });

  /// Applies search terms to safe displayed reasons and rule evidence.
  void commandSearch(String value) => _publish(() => stateQuery = value);

  /// Applies a complete filter draft after the user chooses Apply.
  void commandFilter(CommunityFlagFilters filters) =>
      _publish(() => stateFilters = filters);

  /// Restores the default queue controls without dropping loaded pages.
  void commandClearFilters() => _publish(() {
    stateQuery = '';
    stateFilters = const CommunityFlagFilters();
  });

  /// Retains revised flags while suppressing the exact version already reviewed.
  List<CommunityFlag> commandFlags(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map((doc) => CommunityFlag(id: doc.id, data: doc.data()))
      .where(
        (flag) =>
            flag.status == 'pending' &&
            stateResolved[flag.id] != flag.fingerprint,
      )
      .toList();

  /// Shows a page control only when more source records may remain.
  bool commandHasMore(int loaded) =>
      readReviews() == null && loaded >= stateLimit;

  /// Opens one review at a time and exposes navigation errors for retry.
  Future<void> commandOpen(CommunityFlag flag) async {
    if (stateOpening.isNotEmpty) return;
    _publish(() {
      stateOpening.add(flag.id);
      stateError = null;
    });
    try {
      final open = readOpenReview();
      final reviewed = open != null
          ? await open(flag)
          : await effectPresentOpenEffect1(flag);
      if (_disposed || reviewed != true) return;
      _publish(() => stateResolved[flag.id] = flag.fingerprint);
      readOnReviewed()?.call();
    } catch (_) {
      if (!_disposed) {
        _publish(
          () => stateError = 'Could not open this flag. Please try again.',
        );
      }
    } finally {
      if (!_disposed) _publish(() => stateOpening.remove(flag.id));
    }
  }

  /// Releases presentation listeners when the queue closes.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
