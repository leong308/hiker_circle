/// Carries only identities; a fresh report determines the displayed hazard and risk.
class ActiveTrailHazardNotice {
  /// Binds a reported hazard to one trail and one active tracking session.
  const ActiveTrailHazardNotice({
    required this.sessionId,
    required this.trailId,
    required this.hazardId,
  });

  final String sessionId;
  final String trailId;
  final String hazardId;

  /// Prevents duplicate dialogs for the same report while it is already open.
  String get key => '$sessionId|$trailId|$hazardId';

  /// Builds a notification-only link that cannot start, stop or reschedule a hike.
  String get deepLink => Uri(
    scheme: 'hikercircle',
    host: 'hike',
    path: '/hazard',
    queryParameters: {
      'sessionId': sessionId,
      'trailId': trailId,
      'hazardId': hazardId,
    },
  ).toString();

  /// Recognizes active-hike payloads including locally displayed notification copies.
  static bool isActiveFcm(Map<String, dynamic> data) =>
      data['audience'] == 'active' || _suppliedLink(data) != null;

  /// Reads identities from a push or its canonical link without trusting display text.
  static ActiveTrailHazardNotice? fromFcm(Map<String, dynamic> data) {
    if (data['type'] != 'trail_hazard_alert' || !isActiveFcm(data)) return null;
    final supplied = _suppliedLink(data);
    return _validated(
      data['sessionId'] ?? supplied?.queryParameters['sessionId'],
      data['trailId'] ?? supplied?.queryParameters['trailId'],
      data['hazardId'] ?? supplied?.queryParameters['hazardId'],
    );
  }

  /// Validates custom links again, since they can also arrive outside FCM.
  static ActiveTrailHazardNotice? fromUri(Uri uri) =>
      uri.scheme == 'hikercircle' && uri.host == 'hike' && uri.path == '/hazard'
      ? _validated(
          uri.queryParameters['sessionId'],
          uri.queryParameters['trailId'],
          uri.queryParameters['hazardId'],
        )
      : null;

  /// Accepts document identities without allowing path traversal or arbitrary queries.
  static ActiveTrailHazardNotice? _validated(
    Object? session,
    Object? trail,
    Object? hazard,
  ) {
    final values = [
      session,
      trail,
      hazard,
    ].map((value) => value?.toString().trim() ?? '').toList();
    if (values.any(
      (value) => !RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(value),
    )) {
      return null;
    }
    return ActiveTrailHazardNotice(
      sessionId: values[0],
      trailId: values[1],
      hazardId: values[2],
    );
  }

  /// Limits fallback links to the active hazard destination.
  static Uri? _suppliedLink(Map<String, dynamic> data) {
    for (final key in const ['deepLink', 'deep_link', 'deeplink']) {
      final uri = Uri.tryParse(data[key]?.toString() ?? '');
      if (uri?.scheme == 'hikercircle' &&
          uri?.host == 'hike' &&
          uri?.path == '/hazard') {
        return uri;
      }
    }
    return null;
  }
}
