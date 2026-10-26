part of '../community_post_composer_feature.dart';

/// Owns the state and non-visual actions of CommunityPostEditor.
class CommunityPostEditorStateViewModel extends ChangeNotifier {
  /// Creates community post editor state view model.
  CommunityPostEditorStateViewModel({
    required this.readEnabled,
    required this.readOnBusyChanged,
    required this.effectNotifyChanged,
  });
  final bool Function() readEnabled;
  final ValueChanged<bool>? Function() readOnBusyChanged;
  final void Function() effectNotifyChanged;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final List<CommunityPostImageUpload> stateImages = [];

  bool stateIsPosting = false;

  bool stateIsPicking = false;

  String? stateError;

  /// Returns command is busy.
  bool get commandIsBusy => !readEnabled() || stateIsPosting || stateIsPicking;

  /// Use the single-photo picker for the last slot because pickMultiImage requires a limit of at least two.
  Future<void> commandPickPhotos() async {
    if (commandIsBusy || stateImages.length >= communityPostPhotoLimit) return;
    _publish(() {
      stateIsPicking = true;
      stateError = null;
    });
    readOnBusyChanged()?.call(true);
    try {
      final remaining = communityPostPhotoLimit - stateImages.length;
      final picker = ImagePicker();
      final picked = remaining == 1
          ? [
              await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 85,
              ),
            ].nonNulls.toList()
          : await picker.pickMultiImage(
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 85,
              limit: remaining,
            );
      final additions = <CommunityPostImageUpload>[];
      var rejected = false;
      for (final file in picked.take(
        communityPostPhotoLimit - stateImages.length,
      )) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
          rejected = true;
          continue;
        }
        additions.add(
          CommunityPostImageUpload(
            bytes: bytes,
            fileName: file.name,
            contentType: file.mimeType,
          ),
        );
      }
      if (!mounted) return;
      _publish(() {
        stateImages.addAll(additions);
        if (rejected) {
          stateError =
              'Some photos were too large. Choose photos under 10 MB each.';
        }
      });
      if (additions.isNotEmpty) effectNotifyChanged();
    } catch (_) {
      if (mounted) {
        _publish(
          () => stateError = 'Unable to open your photos. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        _publish(() => stateIsPicking = false);
        readOnBusyChanged()?.call(false);
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
