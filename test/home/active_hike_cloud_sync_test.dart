import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';

void main() {
  test('only transport-like start failures allow offline fallback', () {
    for (final code in const {
      'aborted',
      'cancelled',
      'data-loss',
      'deadline-exceeded',
      'internal',
      'unavailable',
      'unknown',
    }) {
      expect(
        activeHikeStartAllowsOfflineFallbackForFunctionsCode(code),
        isTrue,
        reason: code,
      );
    }

    for (final code in const {
      'already-exists',
      'failed-precondition',
      'invalid-argument',
      'not-found',
      'permission-denied',
      'resource-exhausted',
      'unauthenticated',
    }) {
      expect(
        activeHikeStartAllowsOfflineFallbackForFunctionsCode(code),
        isFalse,
        reason: code,
      );
    }
  });

  test('restore result retains a canonical remapped session id', () {
    final result = parseActiveHikeCloudRestoreResult({
      'sessionId': 'hike_canonical_123',
      'ensured': true,
      'terminal': false,
      'status': 'active',
    }, requestedSessionId: 'session_1785801600000');

    expect(result.sessionId, 'hike_canonical_123');
    expect(result.ensured, isTrue);
    expect(result.terminal, isFalse);
    expect(result.status, 'active');
  });

  test('restore result rejects a missing canonical session id', () {
    expect(
      () => parseActiveHikeCloudRestoreResult({
        'ensured': true,
        'terminal': false,
        'status': 'active',
      }, requestedSessionId: 'session_1785801600000'),
      throwsA(isA<HikerCircleFirebaseRepositoryException>()),
    );
  });

  test('restore and completion parsers recognize terminal states', () {
    final restore = parseActiveHikeCloudRestoreResult({
      'sessionId': 'hike_terminal',
      'ensured': true,
      'terminal': true,
      'status': 'abandoned',
    }, requestedSessionId: 'session_1785801600000');
    final completion = parseActiveHikeCloudCompletionResult({
      'sessionId': 'hike_terminal',
      'completed': false,
      'terminal': true,
      'status': 'abandoned',
    }, requestedSessionId: 'session_1785801600000');

    expect(restore.ensured, isFalse);
    expect(restore.terminal, isTrue);
    expect(completion.completed, isFalse);
    expect(completion.terminal, isTrue);
  });

  test('team creation key is order-independent but changes with invitees', () {
    final departure = DateTime.parse('2026-08-06T08:00:00+08:00');
    final first = teamHikeCreationKeyFor(
      appInstanceId: 'app-123',
      trailId: 'trail-1',
      departureTime: departure,
      inviteePhoneNumbers: const ['+60122222222', '+60111111111'],
    );
    final reordered = teamHikeCreationKeyFor(
      appInstanceId: 'app-123',
      trailId: 'trail-1',
      departureTime: departure.toUtc(),
      inviteePhoneNumbers: const [
        '+60111111111',
        '+60122222222',
        '+60111111111',
      ],
    );
    final changed = teamHikeCreationKeyFor(
      appInstanceId: 'app-123',
      trailId: 'trail-1',
      departureTime: departure,
      inviteePhoneNumbers: const ['+60133333333'],
    );
    final scheduled = teamHikeCreationKeyFor(
      appInstanceId: 'app-123',
      trailId: 'trail-1',
      departureTime: departure,
      inviteePhoneNumbers: const ['+60122222222', '+60111111111'],
      sourceUpcomingHikeId: 'upcoming-1',
    );

    expect(reordered, first);
    expect(changed, isNot(first));
    expect(scheduled, isNot(first));
    expect(first, matches(RegExp(r'^team_create_[a-f0-9]{64}$')));
  });

  test('scheduled hike creation key includes the canonical team', () {
    final departure = DateTime.parse('2026-08-06T08:00:00+08:00');
    final expectedReturn = departure.add(const Duration(hours: 4));
    String keyFor(Iterable<String> phones) => upcomingHikeCreationKeyFor(
      appInstanceId: 'app-123',
      trailId: 'trail-1',
      departureTime: departure,
      expectedReturnTime: expectedReturn,
      hikeType: HikeType.team,
      startPointName: 'North Gate',
      destinationName: 'Summit',
      inviteePhoneNumbers: phones,
    );

    final first = keyFor(const ['+60122222222', '+60111111111']);
    expect(keyFor(const ['+60111111111', '+60122222222']), first);
    expect(keyFor(const ['+60111111111']), isNot(first));
    expect(first, matches(RegExp(r'^schedule_[a-f0-9]{64}$')));
  });

  test('cloud route downsampling is bounded and preserves endpoints', () {
    final start = DateTime.utc(2026, 8, 4);
    final points = [
      for (var index = 0; index < 1500; index++)
        HikeCoordinate(
          latitude: 3 + index / 100000,
          longitude: 101 + index / 100000,
          capturedAt: start.add(Duration(seconds: index)),
        ),
      HikeCoordinate(latitude: double.nan, longitude: 101, capturedAt: start),
    ];

    final stored = downsampleHikeRouteForCloud(points);

    expect(stored, hasLength(1200));
    expect(stored.first.capturedAt, start);
    expect(stored.last.capturedAt, start.add(const Duration(seconds: 1499)));
    expect(stored.every((point) => point.hasValidPosition), isTrue);
  });
}
