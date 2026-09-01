import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/firebase_bootstrap.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/core/services/network_reachability_service.dart';
import 'package:hiker_circle/sos/Data/nearby_sos_event_repository.dart';
import 'package:hiker_circle/sos/Model/nearby_sos_event.dart';
import 'package:hiker_circle/sos/View/sos_page.dart';

void main() {
  testWidgets('shows active nearby SOS first and archives older events', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final repository = _FakeNearbySosEventRepository([
      _event('active', now.subtract(const Duration(minutes: 5))),
      _event('history', now.subtract(const Duration(hours: 2))),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosPage(
            session: AppSession(phoneNumber: '+60111111111', signedInAt: now),
            nearbySosEventRepository: repository,
            firebaseBootstrapResult: const FirebaseBootstrapResult.unavailable(
              'Offline test',
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Nearby SOS needed'), findsOneWidget);
    expect(find.text('1 active nearby event'), findsOneWidget);
    expect(find.text('SOS events'), findsOneWidget);

    final activeEventCard = find.ancestor(
      of: find.text('Approximate nearby area'),
      matching: find.byType(InkWell),
    );
    expect(activeEventCard, findsOneWidget);
    await tester.ensureVisible(activeEventCard);
    await tester.pump();
    tester.widget<InkWell>(activeEventCard).onTap!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nearby SOS route'), findsOneWidget);
    expect(
      find.textContaining('exact direction or walking route cannot be'),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.text('Nearby SOS route'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.ensureVisible(find.text('SOS events'));
    // The compact loading Lottie intentionally loops while reachability is
    // unresolved, so wait for the scroll transition instead of all tickers.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('SOS events'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('NEARBY SOS'), findsOneWidget);
    expect(find.textContaining('Over 1 hour old'), findsOneWidget);
    final historyEventCard = find.ancestor(
      of: find.text('NEARBY SOS'),
      matching: find.byType(InkWell),
    );
    expect(historyEventCard, findsOneWidget);
    tester.widget<InkWell>(historyEventCard).onTap!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nearby SOS route'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(NetworkReachabilityService.instance.stop);
  });
}

NearbySosEvent _event(String key, DateTime receivedAt) {
  return NearbySosEvent(
    ownerPhoneNumber: '+60111111111',
    eventKey: key,
    deviceId: 'button-a',
    receivedAt: receivedAt,
    updatedAt: receivedAt,
  );
}

class _FakeNearbySosEventRepository extends NearbySosEventRepository {
  _FakeNearbySosEventRepository(this.events);

  final List<NearbySosEvent> events;

  @override
  Future<List<NearbySosEvent>> load({
    required String ownerPhoneNumber,
    int limit = 200,
  }) async {
    return events;
  }
}
