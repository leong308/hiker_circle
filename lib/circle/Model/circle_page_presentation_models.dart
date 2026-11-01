part of '../circle_page_feature.dart';

/// Represents community person.
class _CommunityPerson {
  /// Creates community person.
  const _CommunityPerson({
    this.userId = '',
    this.phoneNumber = '',
    required this.name,
    required this.handle,
    required this.subtitle,
    required this.trailAffinity,
    required this.color,
    this.level = 1,
    this.levelName = 'Trailhead',
    this.gender = '',
    this.photoURL = '',
  });

  final String userId;
  final String phoneNumber;
  final String name;
  final String handle;
  final String subtitle;
  final String trailAffinity;
  final Color color;
  final int level;
  final String levelName;
  final String gender;
  final String photoURL;
}

/// Represents buddy request.
class _BuddyRequest {
  /// Creates buddy request.
  const _BuddyRequest({
    required this.phoneNumber,
    required this.name,
    required this.handle,
    required this.photoURL,
    required this.createdAtLabel,
  });

  final String phoneNumber;
  final String name;
  final String handle;
  final String photoURL;
  final String createdAtLabel;
}

/// Represents community post.
class _CommunityPost {
  /// Creates community post.
  const _CommunityPost({
    this.postId,
    required this.authorId,
    required this.authorPhoneNumber,
    required this.author,
    required this.handle,
    required this.levelBadge,
    required this.level,
    required this.timeLabel,
    required this.trail,
    required this.body,
    required this.likes,
    required this.replies,
    required this.color,
    this.routeCaptureId = '',
    this.routePointCount = 0,
    this.routePreviewPoints = const [],
    this.authorPhotoURL = '',
    this.imageUrls = const [],
    this.isLiked = false,
    this.isOwnPost = false,
    this.authorIsAdmin = false,
    this.kind = 'note',
    this.hikeState = '',
    this.distanceKm,
    this.durationMinutes,
    this.updatedAtMillis,
  });

  final String? postId;
  final int? updatedAtMillis;
  final String authorId;
  final String authorPhoneNumber;
  final String author;
  final String handle;
  final String levelBadge;
  final int level;
  final String timeLabel;
  final String trail;
  final String body;
  final int likes;
  final int replies;
  final Color color;
  final String routeCaptureId;
  final int routePointCount;
  final List<HikeCoordinate> routePreviewPoints;
  final String authorPhotoURL;
  final List<String> imageUrls;
  final bool isLiked;
  final bool isOwnPost;
  final bool authorIsAdmin;
  final String kind;
  final String hikeState;
  final double? distanceKm;
  final int? durationMinutes;

  /// Returns has route map.
  bool get hasRouteMap => routePreviewPoints.length >= 2;

  /// Returns a copy with the supplied fields changed.
  _CommunityPost copyWith({int? likes, bool? isLiked, int? replies}) =>
      _CommunityPost(
        postId: postId,
        authorId: authorId,
        authorPhoneNumber: authorPhoneNumber,
        author: author,
        handle: handle,
        levelBadge: levelBadge,
        level: level,
        timeLabel: timeLabel,
        trail: trail,
        body: body,
        likes: likes ?? this.likes,
        replies: replies ?? this.replies,
        color: color,
        routeCaptureId: routeCaptureId,
        routePointCount: routePointCount,
        routePreviewPoints: routePreviewPoints,
        authorPhotoURL: authorPhotoURL,
        imageUrls: imageUrls,
        isLiked: isLiked ?? this.isLiked,
        isOwnPost: isOwnPost,
        authorIsAdmin: authorIsAdmin,
        kind: kind,
        hikeState: hikeState,
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        updatedAtMillis: updatedAtMillis,
      );
}

/// Represents community comment.
class _CommunityComment {
  /// Creates community comment.
  const _CommunityComment({
    required this.commentId,
    required this.author,
    required this.handle,
    required this.levelBadge,
    required this.level,
    required this.body,
    required this.timeLabel,
    this.authorPhotoURL = '',
  });

  final String author;
  final String commentId;
  final String handle;
  final String levelBadge;
  final int level;
  final String body;
  final String timeLabel;
  final String authorPhotoURL;
}

/// Computes community post from firestore.
_CommunityPost _communityPostFromFirestore(Map<String, dynamic> data) {
  final authorPhone = _stringFrom(data['authorPhoneNumber']);
  final authorName = _stringFrom(data['authorName']).isEmpty
      ? 'Hiker ${authorPhone.length >= 4 ? authorPhone.substring(authorPhone.length - 4) : ''}'
      : _stringFrom(data['authorName']);
  final handle = _stringFrom(data['authorHandle']).isEmpty
      ? _handleForPhone(authorPhone)
      : _stringFrom(data['authorHandle']);
  final trailName = _stringFrom(data['trailName']).isEmpty
      ? 'Community'
      : _stringFrom(data['trailName']);
  final caption = _stringFrom(data['caption']);
  final routePreviewPoints = _listOfMaps(
    data['routePreviewPoints'],
  ).map(HikeCoordinate.tryFromFirestore).nonNulls.toList();

  return _CommunityPost(
    postId: _stringFrom(data['postId']),
    updatedAtMillis: data['updatedAtMillis'] is num
        ? (data['updatedAtMillis'] as num).toInt()
        : null,
    authorId: _stringFrom(data['authorId']),
    authorPhoneNumber: authorPhone,
    author: authorName,
    handle: handle,
    levelBadge: _stringFrom(data['authorLevelBadge']).isEmpty
        ? 'Lv. 1 Trailhead'
        : _stringFrom(data['authorLevelBadge']),
    level: _intFrom(data['authorLevel']) == 0
        ? 1
        : _intFrom(data['authorLevel']),
    timeLabel: _relativeTimeLabel(data['createdAtLocal']),
    trail: trailName,
    body: caption,
    likes: _intFrom(data['likeCount']),
    replies: _intFrom(data['commentCount']),
    color: _colorForPost(_stringFrom(data['postId'])),
    routeCaptureId: _stringFrom(data['routeCaptureId']),
    routePointCount: _intFrom(data['routePointCount']),
    routePreviewPoints: routePreviewPoints,
    authorPhotoURL: _stringFrom(data['authorPhotoURL']),
    imageUrls: data['imageUrls'] is List
        ? (data['imageUrls'] as List)
              .whereType<String>()
              .where((url) => url.isNotEmpty)
              .take(6)
              .toList()
        : const [],
    isLiked: data['isLiked'] == true,
    isOwnPost: data['isOwnPost'] == true,
    authorIsAdmin: data['authorIsAdmin'] == true,
    kind: _stringFrom(data['kind']),
    hikeState: _stringFrom(data['hikeState']),
    distanceKm: data['distanceKm'] is num
        ? (data['distanceKm'] as num).toDouble()
        : null,
    durationMinutes: data['durationMinutes'] is num
        ? (data['durationMinutes'] as num).toInt()
        : null,
  );
}
