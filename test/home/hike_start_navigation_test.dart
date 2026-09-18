import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/View/hike_start_navigation.dart';

void main() {
  for (final flow in [
    ['Trail details', 'Start wizard', 'Preparation', 'Starting'],
    ['Upcoming hikes', 'Preparation', 'Starting'],
    ['Circle', 'Team readiness', 'Safety settings'],
  ]) {
    testWidgets('successful start clears ${flow.join(' / ')}', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Before home')),
        ),
      );
      late BuildContext homeContext;
      final home = MaterialPageRoute<void>(
        builder: (context) {
          homeContext = context;
          return const Scaffold(body: Text('Active hike'));
        },
      );
      navigator.currentState!.push(home);
      await tester.pumpAndSettle();
      final routes = <Route<void>>[];
      for (final label in flow) {
        final route = MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text(label)),
        );
        routes.add(route);
        navigator.currentState!.push(route);
        await tester.pumpAndSettle();
      }

      HikeStartNavigation.revealHome(homeContext);
      // Async wizard/dialog callbacks can arrive before exit animations finish.
      for (final route in routes.reversed) {
        HikeStartNavigation.closeOwnedRoute(route);
      }
      await tester.pumpAndSettle();
      expect(find.text('Active hike'), findsOneWidget);
      expect(home.isCurrent, isTrue);
      expect(routes.every((route) => !route.isActive), isTrue);
      HikeStartNavigation.revealHome(homeContext);
      await tester.pumpAndSettle();
      expect(home.isCurrent, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Before home'), findsOneWidget);
    });
  }

  testWidgets('dialog cleanup preserves a newer page and is idempotent', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    final progress = DialogRoute<void>(
      context: homeContext,
      builder: (_) => const AlertDialog(title: Text('Starting')),
    );
    final closed = navigator.currentState!.push(progress);
    await tester.pumpAndSettle();
    final newer = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Newer page')),
    );
    navigator.currentState!.push(newer);
    await tester.pumpAndSettle();
    HikeStartNavigation.closeOwnedRoute(progress);
    await tester.pumpAndSettle();
    await closed;
    HikeStartNavigation.closeOwnedRoute(progress);
    expect(newer.isCurrent, isTrue);
    expect(find.text('Newer page'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('team completion closes nested safety and delivers one result', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Origin')),
      ),
    );
    final team = MaterialPageRoute<String>(
      builder: (_) => const Scaffold(body: Text('Team readiness')),
    );
    final teamResult = navigator.currentState!.push(team);
    await tester.pumpAndSettle();
    final safety = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Safety')),
    );
    navigator.currentState!.push(safety);
    await tester.pumpAndSettle();
    HikeStartNavigation.completeFlow(team, 'active-team');
    HikeStartNavigation.completeFlow(team, 'duplicate');
    await tester.pumpAndSettle();
    expect(await teamResult, 'active-team');
    expect(find.text('Origin'), findsOneWidget);
    expect(safety.isActive, isFalse);
  });

  testWidgets('cancelling preparation returns to its wizard and trail', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    for (final label in ['Trail', 'Wizard']) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
      );
      await tester.pumpAndSettle();
    }
    final preparation = MaterialPageRoute<String>(
      builder: (_) => const Scaffold(body: Text('Preparation')),
    );
    final result = navigator.currentState!.push(preparation);
    await tester.pumpAndSettle();
    HikeStartNavigation.closeOwnedRoute(preparation);
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(find.text('Wizard'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Trail'), findsOneWidget);
  });
}
