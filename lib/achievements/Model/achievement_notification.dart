import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Represents achievement notification.
class AchievementNotification {
  /// Creates achievement notification.
  AchievementNotification({required this.owner, required this.row});
  final String owner;
  final Map<String, dynamic> row;

  /// Returns achievement id.
  String get achievementId => row['achievementId'] as String;

  /// Returns message id.
  String get messageId => 'achievement:$achievementId';

  /// Returns title.
  String get title => 'Achievement unlocked';

  /// Returns body.
  String get body =>
      '${row['title']} · +${row['pointsAwarded'] ?? row['rewardPoints'] ?? 0} points';

  /// Returns id.
  int get id {
    final bytes = sha256.convert(utf8.encode('$owner:$achievementId')).bytes;
    return 0x60000000 |
        (((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
            0x1fffffff);
  }

  /// Returns deep link.
  String get deepLink => Uri(
    scheme: 'hikercircle',
    host: 'achievement',
    path: '/earned',
    queryParameters: {
      'achievementId': achievementId,
      'ownerPhoneNumber': owner,
    },
  ).toString();

  /// Returns data.
  Map<String, String> get data => {
    'messageId': messageId,
    'type': 'local_achievement_unlocked',
    'ownerPhoneNumber': owner,
    'achievementId': achievementId,
    'deepLink': deepLink,
    'title': title,
    'body': body,
  };

  /// Returns payload.
  String get payload => jsonEncode(data);

  /// Computes achievement id from link.
  static String? achievementIdFromLink(Uri uri, String owner) {
    final id = uri.queryParameters['achievementId'] ?? '';
    return uri.scheme == 'hikercircle' &&
            uri.host == 'achievement' &&
            uri.path == '/earned' &&
            uri.queryParameters['ownerPhoneNumber'] == owner &&
            RegExp(r'^[A-Za-z0-9_-]{1,240}$').hasMatch(id)
        ? id
        : null;
  }
}
