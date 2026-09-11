abstract final class FcmNotificationRouter {
  static String? deepLinkFor(Map<String, dynamic> data) {
    for (final key in const ['deepLink', 'deep_link', 'deeplink']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        final uri = Uri.tryParse(value);
        if (uri?.scheme == 'hikercircle') {
          // Opening a notification must never create a fresh SOS. Older or
          // misconfigured payloads may still contain an action deep link that
          // was intended for a widget/shortcut. Route those notification taps
          // to the existing SOS state instead.
          if (uri!.host == 'sos' &&
              const {
                '/manual',
                '/instant',
                '/medical',
                '/duress',
              }.contains(uri.path)) {
            return Uri(
              scheme: 'hikercircle',
              host: 'sos',
              path: '/active',
              queryParameters: const {'source': 'notification'},
            ).toString();
          }
          return uri.toString();
        }
      }
    }

    final type = data['type']?.toString().trim() ?? '';
    switch (type) {
      case 'group_chat_message':
        return _link(
          host: 'group-chat',
          path: '/view',
          key: 'chatId',
          value: data['chatId'],
        );
      case 'nearby_upcoming_hike':
      case 'upcoming_hike_reminder':
      case 'upcoming_hike_precaution':
      case 'upcoming_hike_30_minute_reminder':
        return _link(
          host: 'upcoming-hike',
          path: '/view',
          key: 'upcomingHikeId',
          value: data['upcomingHikeId'] ?? data['hikeId'],
        );
      case 'upcoming_hike_join_request':
        return _link(
          host: 'upcoming-hike',
          path: '/join-request',
          key: 'requestId',
          value: data['requestId'],
        );
      case 'team_hike_invite':
      case 'team_hike_ready':
      case 'team_hike_countdown':
      case 'team_hike_started':
      case 'team_hike_start':
        return _link(
          host: 'team-hike',
          path: '/join',
          key: 'teamSessionId',
          value: data['teamHikeSessionId'] ?? data['teamSessionId'],
        );
      case 'team_hike_ping':
        return _link(
          host: 'team-hike',
          path: '/ping',
          key: 'teamSessionId',
          value: data['teamHikeSessionId'] ?? data['teamSessionId'],
        );
      case 'active_hike_scheduled_check_in':
        return _link(
          host: 'hike',
          path: '/check-in',
          key: 'sessionId',
          value: data['sessionId'],
        );
      case 'active_hike_monitoring_stopped':
        return _link(
          host: 'hike',
          path: '/active',
          key: 'sessionId',
          value: data['sessionId'],
        );
      default:
        return null;
    }
  }

  static String? _link({
    required String host,
    required String path,
    required String key,
    required Object? value,
  }) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 240) return null;
    return Uri(
      scheme: 'hikercircle',
      host: host,
      path: path,
      queryParameters: {key: text},
    ).toString();
  }
}
