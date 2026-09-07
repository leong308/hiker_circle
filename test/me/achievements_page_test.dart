import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Data/hiker_circle_firebase_repository.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/me/View/me_page.dart';

void main() {
  test('achievement cache hash matches the backend canonical format', () {
    expect(
      achievementProgressContentHash([
        {
          'achievementId': 'state_scout',
          'title': 'State Scout',
          'condition': 'Complete hikes in 3 Malaysian states',
          'category': 'Malaysia exploration',
          'iconName': 'travel_explore',
          'rewardPoints': 250,
          'pointsAwarded': 0,
          'rewardType': 'cumulative',
          'metricKey': 'malaysia_state_hiked',
          'targetCount': 3,
          'progressCount': 1,
          'sortOrder': 140,
          'accentColorValue': 0xFF00A99D,
          'isActive': true,
          'isUnlocked': false,
        },
      ]),
      'ef94fe7f95d49be12e4061d3c032571e17c4f7611673f01a601c8867eeca9549',
    );
  });

  test('offline catalog includes the expanded hiking goals', () async {
    final repository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
        'test',
      ),
    );
    final achievements = await repository.loadUserAchievementProgress(
      session: AppSession(
        phoneNumber: '+60123456789',
        signedInAt: DateTime.utc(2026, 9, 4),
      ),
    );

    expect(achievements, hasLength(22));
    expect(
      achievements.map((achievement) => achievement['achievementId']),
      containsAll([
        'trail_regular',
        'trail_collector',
        'state_scout',
        'malaysia_trailblazer',
        'safety_beacon',
        'trail_crew',
      ]),
    );
  });

  testWidgets('Earned and Locked tabs show only their matching achievements', (
    tester,
  ) async {
    final repository = _AchievementRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 9, 4),
          ),
          repository: repository,
          firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('achievement-status-tabs')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Earned  1'), findsOneWidget);
    expect(find.text('Locked  2'), findsOneWidget);
    expect(find.text('State Scout'), findsOneWidget);
    expect(find.text('First Safe Hike'), findsNothing);
    final thumb = tester.widget<Container>(
      find.byKey(const Key('achievement-tab-thumb')),
    );
    final thumbDecoration = thumb.decoration! as BoxDecoration;
    expect(thumbDecoration.borderRadius, BorderRadius.circular(19));

    await tester.tap(find.byKey(const Key('achievement-tab-earned')));
    await tester.pumpAndSettle();

    expect(find.text('First Safe Hike'), findsOneWidget);
    expect(find.text('State Scout'), findsNothing);

    final tabsRect = tester.getRect(
      find.byKey(const Key('achievement-status-tabs')),
    );
    await tester.dragFrom(
      Offset(tabsRect.left + 30, tabsRect.center.dy),
      Offset(tabsRect.width - 60, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('State Scout'), findsOneWidget);
    expect(find.text('First Safe Hike'), findsNothing);
    expect(repository.achievementLoadCount, 1);
  });

  testWidgets('leaderboard opens from the achievement page header', (
    tester,
  ) async {
    final repository = _AchievementRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 9, 4),
          ),
          repository: repository,
          firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('achievement-leaderboard-button')));
    await tester.pumpAndSettle();

    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Hiker leaderboard'), findsOneWidget);
    expect(repository.leaderboardLoadCount, 1);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Hiker leaderboard'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('Preview · 50 sample hikers'), findsOneWidget);
    expect(find.text('Top 10'), findsOneWidget);
    await tester.ensureVisible(find.text('Your ranking'));
    await tester.pumpAndSettle();
    expect(find.text('37'), findsOneWidget);
    expect(repository.leaderboardLoadCount, 1);
    await tester.ensureVisible(find.text('Leaderboard'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('achievement-leaderboard-button')));
    await tester.pumpAndSettle();
    expect(find.text('Preview · 50 sample hikers'), findsNothing);
    expect(repository.leaderboardLoadCount, 2);
  });

  testWidgets('achievement detail explains purpose, goal and qualifying work', (
    tester,
  ) async {
    final repository = _AchievementRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 9, 4),
          ),
          repository: repository,
          firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('State Scout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State Scout'));
    await tester.pumpAndSettle();

    expect(find.text('Why this achievement exists'), findsOneWidget);
    expect(find.text('Your goal'), findsOneWidget);
    expect(find.text('What counts'), findsOneWidget);
    expect(find.text('Reward and recognition'), findsOneWidget);
    await tester.ensureVisible(find.text('What counts'));
    await tester.tap(find.text('What counts'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 of 3 qualifying activities remain'),
      findsOneWidget,
    );
    expect(find.textContaining('new Malaysian state'), findsOneWidget);
  });

  testWidgets('level badge opens every past and upcoming point threshold', (
    tester,
  ) async {
    final repository = _AchievementRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 9, 4),
          ),
          repository: repository,
          firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('achievement-level-medallion')));
    await tester.pumpAndSettle();

    expect(find.text('Hiker levels'), findsOneWidget);
    expect(find.text('Level 1 · Trailhead'), findsOneWidget);
    final carousel = find.byKey(const Key('hiker-level-carousel'));
    final pages = tester.widget<PageView>(carousel);
    expect(pages.scrollDirection, Axis.horizontal);
    expect(pages.controller!.initialPage, 0);
    final cardSize = tester.getSize(
      find.byKey(const ValueKey('hiker-level-card-1')),
    );
    final reachedOpacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('trail-level-1')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(reachedOpacity.opacity, 1);
    pages.controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('Unlocks at 250 points'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('hiker-level-card-2'))),
      cardSize,
    );
    final lockedOpacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('trail-level-2')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(lockedOpacity.opacity, 0.5);
    pages.controller!.jumpToPage(6);
    await tester.pumpAndSettle();
    expect(find.text('Level 7 · HikerCircle Elite'), findsOneWidget);
    expect(find.text('5,500+ points'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('hiker-level-card-7'))),
      cardSize,
    );
  });

  testWidgets('cached achievements render without a full cloud reload', (
    tester,
  ) async {
    final repository = _AchievementRepository(cacheHit: true);
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime.utc(2026, 9, 4),
          ),
          repository: repository,
          firebaseBootstrapResult: const FirebaseBootstrapResult.available(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('State Scout'), findsOneWidget);
    expect(repository.achievementLoadCount, 0);
    expect(repository.hashLoadCount, 1);
    expect(repository.cacheSaveCount, 0);
  });
}

class _AchievementRepository extends HikerCircleFirebaseRepository {
  _AchievementRepository({this.cacheHit = false})
    : super(
        firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
          'test',
        ),
      );

  final bool cacheHit;
  int achievementLoadCount = 0;
  int leaderboardLoadCount = 0;
  int hashLoadCount = 0;
  int cacheSaveCount = 0;

  @override
  Future<LocalAchievementProgressCache?> loadCachedAchievementProgress({
    required AppSession session,
  }) async {
    if (!cacheHit) return null;
    return LocalAchievementProgressCache(
      contentHash: 'test-hash',
      rows: _testAchievements(),
      cachedAt: DateTime.utc(2026, 9, 4),
    );
  }

  @override
  Future<String> loadAchievementProgressHash({
    required AppSession session,
  }) async {
    hashLoadCount++;
    return 'test-hash';
  }

  @override
  Future<void> saveCachedAchievementProgress({
    required AppSession session,
    required String contentHash,
    required List<Map<String, dynamic>> rows,
  }) async {
    cacheSaveCount++;
  }

  @override
  Future<List<Map<String, dynamic>>> loadUserAchievementProgress({
    required AppSession session,
  }) async {
    achievementLoadCount++;
    return _testAchievements();
  }

  @override
  Future<List<Map<String, dynamic>>> loadAchievementLeaderboard({
    String period = 'month',
  }) async {
    leaderboardLoadCount++;
    return const [];
  }
}

List<Map<String, dynamic>> _testAchievements() => [
  _achievement(
    id: 'first_safe_hike',
    title: 'First Safe Hike',
    unlocked: true,
    progress: 1,
    target: 1,
  ),
  _achievement(
    id: 'state_scout',
    title: 'State Scout',
    unlocked: false,
    progress: 1,
    target: 3,
  ),
  _achievement(
    id: 'trail_collector',
    title: 'Trail Collector',
    unlocked: false,
    progress: 2,
    target: 5,
  ),
];

Map<String, dynamic> _achievement({
  required String id,
  required String title,
  required bool unlocked,
  required int progress,
  required int target,
}) {
  return {
    'achievementId': id,
    'title': title,
    'condition': 'Complete the goal',
    'category': 'Hiking',
    'iconName': 'hiking',
    'rewardPoints': 100,
    'pointsAwarded': unlocked ? 100 : 0,
    'rewardType': 'cumulative',
    'metricKey': id == 'state_scout'
        ? 'malaysia_state_hiked'
        : 'hike_completed',
    'progressCount': progress,
    'targetCount': target,
    'sortOrder': target,
    'accentColorValue': 0xFF34A853,
    'isUnlocked': unlocked,
  };
}
