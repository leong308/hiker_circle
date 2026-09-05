import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/sos/View/emergency_contacts_page.dart';

void main() {
  testWidgets('phone contacts are requested only through the field picker', (
    tester,
  ) async {
    var requests = 0;
    const channel = MethodChannel('hiker_circle/sos_device_alerts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requests++;
      return <Object>[];
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyContactsPage(
          session: AppSession(
            phoneNumber: '+60123456789',
            signedInAt: DateTime(2026),
          ),
          initialContacts: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('From phone contacts'), findsNothing);
    final picker = find.byTooltip('Choose from phone contacts');
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Phone contacts'), findsOneWidget);
    expect(find.textContaining('Check Contacts permission'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Phone contacts'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Phone contacts'), findsNothing);
  });
}
