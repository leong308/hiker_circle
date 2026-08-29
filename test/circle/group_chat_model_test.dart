import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  test('formed group chat uses its host-selected name', () {
    final chat = GroupChat.fromFirestore('hike_123', {
      'hikeSessionId': '123',
      'trailName': 'Bukit Gasing',
      'participantPhones': ['+60111111111', '+60222222222'],
      'creatorPhone': '+60111111111',
      'createdAtLocal': '2026-08-26T01:00:00.000Z',
      'departureTimeLocal': '2026-08-27T01:00:00.000Z',
      'customName': 'Gasing Sunrise Crew',
      'requiresHostNaming': false,
      'latestJoinedName': 'Aina',
    });

    expect(chat.customName, 'Gasing Sunrise Crew');
    expect(chat.displayNameFor('+60111111111'), 'Gasing Sunrise Crew');
    expect(chat.requiresHostNaming, isFalse);
    expect(chat.latestJoinedName, 'Aina');
  });

  test('newly formed group carries the host naming prompt state', () {
    final chat = GroupChat.fromFirestore('team_123', {
      'hikeSessionId': '123',
      'trailName': 'Broga Hill',
      'participantPhones': ['+60111111111', '+60222222222'],
      'creatorPhone': '+60111111111',
      'createdAtLocal': '2026-08-26T01:00:00.000Z',
      'requiresHostNaming': true,
      'latestJoinedName': 'Wei Ming',
    });

    expect(chat.requiresHostNaming, isTrue);
    expect(chat.customName, isEmpty);
    expect(chat.latestJoinedName, 'Wei Ming');
  });

  test('automatic group name follows the required departure format', () {
    expect(
      GroupChat.defaultGroupName('HikeLocation', DateTime(2026, 8, 29, 5)),
      '29Aug 05:00 HikeLocation Group',
    );
  });
}
