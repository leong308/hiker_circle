part of '../caution_media_feature.dart';

/// Owns the state and non-visual actions of CautionEvidenceEditor.
class CautionEvidenceEditorStateViewModel extends ChangeNotifier {
  /// Creates caution evidence editor state view model.
  CautionEvidenceEditorStateViewModel({required this.readEnabled});
  final bool Function() readEnabled;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final stateFiles = <PendingCautionMedia>[];

  String? stateError;

  bool statePicking = false;

  /// Computes pick.
  Future<void> commandPick() async {
    if (statePicking || !readEnabled()) return;
    _publish(() {
      statePicking = true;
      stateError = null;
    });
    try {
      final selected = await ImagePicker().pickMultipleMedia(
        imageQuality: 85,
        requestFullMetadata: false,
      );
      final additions = <PendingCautionMedia>[];
      for (final file in selected) {
        final contentType =
            cautionMediaTypes[file.name.split('.').last.toLowerCase()];
        if (contentType == null) {
          throw StateError('Choose a supported photo or an MP4/MOV video.');
        }
        additions.add(
          PendingCautionMedia(
            file: file,
            sizeBytes: await file.length(),
            contentType: contentType,
          ),
        );
      }
      final combined = [...stateFiles, ...additions];
      if (combined.length > 6 ||
          combined.fold<int>(0, (a, b) => a + b.sizeBytes) >
              cautionMediaLimit) {
        throw StateError(
          'Choose up to six photos or videos, totaling at most 50 MB.',
        );
      }
      if (mounted) _publish(() => stateFiles.addAll(additions));
    } catch (e) {
      if (mounted) {
        _publish(
          () => stateError = e.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) _publish(() => statePicking = false);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
