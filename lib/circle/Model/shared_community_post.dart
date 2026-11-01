/// A compact chat preview that links to a canonical Circle post.
class SharedCommunityPost {
  /// Creates a preview without copying private profile or hike information.
  const SharedCommunityPost({
    required this.postId,
    required this.authorName,
    required this.caption,
    required this.trailName,
  });

  final String postId;
  final String authorName;
  final String caption;
  final String trailName;

  /// Provides readable text for chat lists and push notifications.
  String get summary => 'Shared $authorName’s Circle post';

  /// Serializes the preview for both the local queue and Firestore.
  Map<String, dynamic> toMap() => {
    'postId': postId,
    'authorName': authorName,
    'caption': caption,
    'trailName': trailName,
  };

  /// Rejects malformed references while keeping ordinary messages readable.
  static SharedCommunityPost? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['postId'];
    final author = value['authorName'];
    final caption = value['caption'];
    final trail = value['trailName'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 200 ||
        RegExp(r'[/\x00-\x1f]').hasMatch(id) ||
        author is! String ||
        author.trim().isEmpty ||
        author.length > 160 ||
        caption is! String ||
        caption.length > 600 ||
        trail is! String ||
        trail.length > 160) {
      return null;
    }
    return SharedCommunityPost(
      postId: id,
      authorName: author,
      caption: caption,
      trailName: trail,
    );
  }
}
