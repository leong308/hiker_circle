import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/fcm_notification_router.dart';

void main() {
  test('precaution notification opens the corresponding upcoming hike', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'type': 'upcoming_hike_precaution',
        'upcomingHikeId': 'hike-precaution',
      }),
      'hikercircle://upcoming-hike/view?upcomingHikeId=hike-precaution',
    );
  });
  test('uses a valid explicit HikerCircle deep link', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'deepLink': 'hikercircle://upcoming-hike/view?upcomingHikeId=hike-1',
      }),
      'hikercircle://upcoming-hike/view?upcomingHikeId=hike-1',
    );
  });

  test('reconstructs a route when a legacy payload omitted deepLink', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'type': 'team_hike_invite',
        'teamHikeSessionId': 'team 42',
      }),
      'hikercircle://team-hike/join?teamSessionId=team+42',
    );
  });

  test('routes team countdown and start updates into the live launch', () {
    for (final type in const ['team_hike_countdown', 'team_hike_started']) {
      expect(
        FcmNotificationRouter.deepLinkFor({
          'type': type,
          'teamHikeSessionId': 'team-42',
        }),
        'hikercircle://team-hike/join?teamSessionId=team-42',
      );
    }
  });

  test('routes configurable upcoming hike reminders to that hike', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'type': 'upcoming_hike_reminder',
        'upcomingHikeId': 'hike-99',
      }),
      'hikercircle://upcoming-hike/view?upcomingHikeId=hike-99',
    );
  });

  test('routes a host join-request notification to its confirmation link', () {
    final requestId = 'join_${List.filled(48, 'a').join()}';
    expect(
      FcmNotificationRouter.deepLinkFor({
        'type': 'upcoming_hike_join_request',
        'requestId': requestId,
      }),
      'hikercircle://upcoming-hike/join-request?requestId=$requestId',
    );
  });

  test('does not route an arbitrary external URL', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'deepLink': 'https://example.com/unsafe',
      }),
      isNull,
    );
  });

  test('notification SOS action links only open the existing SOS state', () {
    for (final action in const ['manual', 'instant', 'medical', 'duress']) {
      expect(
        FcmNotificationRouter.deepLinkFor({
          'deepLink': 'hikercircle://sos/$action?source=old-payload',
        }),
        'hikercircle://sos/active?source=notification',
      );
    }
  });
}
