// FcmNotificationRouter maps known notification payloads to supported app deep links without
// invoking navigation itself.
/// Represents fcm notification router.
abstract final class FcmNotificationRouter {
  /// Computes deep link for.
  static String? deepLinkFor(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim() ?? '';
    if (type == 'trail_hazard_alert') {
      // Canonical identity is required; neither message text nor a severity
      // supplied in a push can authorize cancellation or bypass a start check.
      Uri? supplied;
      for (final key in const ['deepLink', 'deep_link', 'deeplink']) {
        final candidate = Uri.tryParse(data[key]?.toString().trim() ?? '');
        if (candidate?.scheme == 'hikercircle' &&
            candidate?.host == 'upcoming-hike' &&
            candidate?.path == '/view') {
          supplied = candidate;
          break;
        }
      }
      final hazardId =
          data['hazardId'] ?? supplied?.queryParameters['hazardId'];
      final hikeId =
          data['upcomingHikeId'] ??
          data['hikeId'] ??
          supplied?.queryParameters['upcomingHikeId'];
      final hazard = hazardId?.toString().trim() ?? '';
      final hike = hikeId?.toString().trim() ?? '';
      if (!_validHazardIdentity(hazard) || !_validHazardIdentity(hike)) {
        return null;
      }
      return _link(
        host: 'upcoming-hike',
        path: '/view',
        key: 'upcomingHikeId',
        value: hike,
        queryParameters: {'hazardId': hazard},
      );
    }
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
          // Already-delivered local reminders can contain the previous link
          // format. Upgrade those taps without changing unrelated destinations.
          if (type == 'local_upcoming_hike_reminder' &&
              uri.host == 'upcoming-hike' &&
              uri.path == '/view') {
            return uri
                .replace(
                  queryParameters: {
                    ...uri.queryParametersAll,
                    'chargePhone': ['1'],
                  },
                )
                .toString();
          }
          return uri.toString();
        }
      }
    }

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
      case 'local_upcoming_hike_reminder':
        return _link(
          host: 'upcoming-hike',
          path: '/view',
          key: 'upcomingHikeId',
          value: data['upcomingHikeId'] ?? data['hikeId'],
          queryParameters: const {'chargePhone': '1'},
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

  /// Computes valid hazard identity.
  static bool _validHazardIdentity(String value) =>
      value.isNotEmpty &&
      value.length <= 180 &&
      !value.contains('/') &&
      value != '.' &&
      value != '..';

  /// Computes link.
  static String? _link({
    required String host,
    required String path,
    required String key,
    required Object? value,
    Map<String, String> queryParameters = const {},
  }) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text.length > 240) return null;
    return Uri(
      scheme: 'hikercircle',
      host: host,
      path: path,
      queryParameters: {key: text, ...queryParameters},
    ).toString();
  }
}
