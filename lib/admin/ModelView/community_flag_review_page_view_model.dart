part of '../community_flag_review_page_feature.dart';

/// Owns the state and non-visual actions of CommunityFlagReviewPage.
class _CommunityFlagReviewPageStateViewModel extends ChangeNotifier {
  /// Creates community flag review page state view model.
  _CommunityFlagReviewPageStateViewModel({
    required this.readFlag,
    required this.readLoadParent,
    required this.readLoadSource,
  });
  final CommunityFlag Function() readFlag;
  final Future<Map<String, dynamic>?> Function()? Function() readLoadParent;
  final Future<Map<String, dynamic>?> Function()? Function() readLoadSource;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Loads content.
  Future<_ReviewContent> commandLoadContent() async {
    if (!RegExp(
      r'^communityPosts/[^/]+(?:/comments/[^/]+)?$',
    ).hasMatch(readFlag().sourcePath)) {
      throw const FormatException('This flag has no valid content reference.');
    }
    // Query flagged content by path
    final source =
        await (readLoadSource()?.call() ??
                FirebaseFirestore.instance
                    .doc(readFlag().sourcePath)
                    .get(const GetOptions(source: Source.server))
                    .then((snapshot) => snapshot.data()))
            .timeout(const Duration(seconds: 15));
    if (source == null || !readFlag().isComment) {
      return _ReviewContent(source: source);
    }
    // The parent is context only. A failed context read must not conceal a
    // successfully loaded comment or replace the server's final checks.
    try {
      // Query parent post of flagged comment
      final parent = readLoadParent() != null
          ? await readLoadParent()!().timeout(const Duration(seconds: 15))
          : readLoadSource() == null
          ? await FirebaseFirestore.instance
                .doc(readFlag().sourcePath.split('/').take(2).join('/'))
                .get()
                .timeout(const Duration(seconds: 15))
                .then((snapshot) => snapshot.data())
          : null;
      return _ReviewContent(source: source, parent: parent);
    } catch (_) {
      return _ReviewContent(source: source, parentUnavailable: true);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
