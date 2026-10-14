import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hiker_circle/admin/View/admin_analytics_dashboard.dart';

Map<String, dynamic> analyticsFixture() => {
  'generatedAtMillis': 1791792000000,
  'totals': {'users': 120, 'trails': 35, 'hikeSessions': 96, 'posts': 50},
  'users': {'recentSignIns': 15, 'activeHikers30Days': 10},
  'trails': {
    'verified': 18,
    'routeStored': 30,
    'byState': [
      for (var i = 0; i < 9; i++) {'label': 'State $i', 'value': 9 - i},
    ],
    'byLength': [
      {'label': 'Under 5 km', 'value': 20},
      {'label': '5–10 km', 'value': 15},
    ],
  },
  'hikes': {
    'completed': 67,
    'byStatus': [
      {'label': 'completed', 'value': 67},
      {'label': 'active', 'value': 5},
    ],
  },
  'community': {
    'byVisibility': [
      {'label': 'public', 'value': 50},
    ],
  },
  'safety': {'pendingHazards': 2, 'pendingReviews': 1, 'openFeedback': 3},
  'daily': [
    for (var i = 1; i <= 30; i++)
      {
        'date': '2026-09-${i.toString().padLeft(2, '0')}',
        'users': i % 5,
        'hikes': i % 3,
        'posts': 1,
      },
  ],
  'monthly': [
    for (var i = 1; i <= 12; i++)
      {
        'date': '2026-${i.toString().padLeft(2, '0')}',
        'users': i,
        'hikes': i * 2,
        'posts': i,
      },
  ],
};
Widget app(
  Map<String, dynamic>? data, {
  double scale = 1,
  Brightness brightness = Brightness.light,
  String? error,
  VoidCallback? retry,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AdminAnalyticsDashboard(
            data: data,
            loading: false,
            error: error,
            onRetry: retry ?? () {},
            onTrails: () {},
            onSafety: () {},
            onCommunity: () {},
            onRewards: () {},
            onTools: () {},
          ),
        ),
      ),
    ),
  ),
);
void main() {
  for (final config in [
    (390.0, 1.0, Brightness.light),
    (1024.0, 1.0, Brightness.dark),
    (320.0, 1.8, Brightness.light),
  ]) {
    testWidgets(
      'charts and review queues fit ${config.$1} at ${config.$2} scale',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(analyticsFixture(), scale: config.$2, brightness: config.$3),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('analytics-period-365')),
        );
        await tester.tap(find.byKey(const ValueKey('analytics-period-365')));
        await tester.pumpAndSettle();
        expect(find.text('78 new users in this period'), findsOneWidget);
        expect(find.byType(LineChart), findsOneWidget);
        await tester.tap(find.text('Hikes'));
        await tester.pumpAndSettle();
        expect(
          find.text('156 completed sessions in this period'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('View all 9 states'));
        await tester.tap(find.text('View all 9 states'));
        await tester.pumpAndSettle();
        expect(find.text('State 8'), findsOneWidget);
        await tester.ensureVisible(find.text('2 safety reports need review'));
        await tester.pumpAndSettle();
        expect(find.byType(PieChart), findsNWidgets(3));
        await tester.ensureVisible(find.text('More system breakdowns'));
        await tester.tap(find.text('More system breakdowns'));
        await tester.pumpAndSettle();
        expect(find.text('Account signals'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'analytics failure offers retry and keeps tools accessible without fabricated totals',
    (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        app(null, error: 'Statistics unavailable', retry: () => retries++),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registered users'), findsNothing);
      expect(find.text('Statistics unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry statistics'));
      expect(retries, 1);
      expect(find.text('Admin tools'), findsOneWidget);
    },
  );
  testWidgets(
    'failed refresh preserves snapshot and declares coverage limits',
    (tester) async {
      final data = analyticsFixture()
        ..['coverage'] = {
          'users': {'complete': false},
        };
      await tester.pumpWidget(app(data, error: 'Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Registered users'), findsOneWidget);
      expect(
        find.textContaining('Showing the previous snapshot'),
        findsOneWidget,
      );
      expect(find.textContaining('first 10,000 records'), findsOneWidget);
    },
  );
}
