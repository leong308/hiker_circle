import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/services/fcm_notification_router.dart';

void main() {
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

  test('does not route an arbitrary external URL', () {
    expect(
      FcmNotificationRouter.deepLinkFor({
        'deepLink': 'https://example.com/unsafe',
      }),
      isNull,
    );
  });
}
