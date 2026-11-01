import 'package:flutter/foundation.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';

/// Keeps an author's edits local until the server confirms the content revision.
class CommunityPostEditorViewModel extends ChangeNotifier {
  /// Initializes the editable caption and existing photos.
  CommunityPostEditorViewModel({
    required this.repository,
    required this.session,
    required this.original,
  }) : caption = original['caption']?.toString() ?? '',
       imageUrls = List<String>.from(
         original['imageUrls'] as List? ?? const [],
       );

  final HikerCircleFirebaseRepository repository;
  final AppSession session;
  final Map<String, dynamic> original;
  final List<String> imageUrls;
  String caption;
  bool saving = false;
  String? error;
  bool _disposed = false;

  /// Removes a photo from this edit while preserving the published version.
  void removePhoto(String url) {
    if (saving || _disposed) return;
    imageUrls.remove(url);
    notifyListeners();
  }

  /// Saves once and retains the user's draft when validation or the server fails.
  Future<Map<String, dynamic>?> save() async {
    if (saving || _disposed) return null;
    final text = caption.trim();
    if (text.length > 5000 ||
        (text.isEmpty && imageUrls.isEmpty && original['kind'] != 'hike')) {
      error = text.length > 5000
          ? 'Keep your story within 5,000 characters.'
          : 'Keep a message, a photo, or a hike in your story.';
      notifyListeners();
      return null;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      return await repository.editOwnCommunityPost(
        session: session,
        original: original,
        caption: text,
        imageUrls: List.of(imageUrls),
      );
    } on HikerCircleFirebaseRepositoryException catch (failure) {
      error = failure.message;
      return null;
    } catch (_) {
      error = 'Your story couldn’t be saved. Please try again.';
      return null;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Stops publishing changes after the editor closes.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
