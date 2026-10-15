import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/sos/View/emergency_contacts_page.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:hiker_circle/sos/Data/emergency_contacts_repository.dart';

void main() {
  final session = AppSession(
    phoneNumber: '+60123456789',
    signedInAt: DateTime.utc(2026),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'onboarding tick is right-aligned and gated by contacts in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Future<void> show(List<EmergencyContact> contacts) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: EmergencyContactsPage(
              session: session,
              initialContacts: contacts,
              onboardingRequired: true,
              onOnboardingCompleted: (_) async {},
            ),
          ),
        );
        await show([]);
        final action = find.byTooltip('Continue');
        expect(
          tester.getCenter(action).dx,
          greaterThan(tester.getCenter(find.text('Emergency Contacts')).dx),
        );
        expect(
          tester
              .widget<CupertinoButton>(
                find.descendant(
                  of: action,
                  matching: find.byType(CupertinoButton),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.pumpWidget(const SizedBox());
        await show([
          const EmergencyContact(
            name: 'Friend',
            phoneNumber: '+60122222222',
            relationship: 'Friend',
          ),
        ]);
        expect(
          tester
              .widget<CupertinoButton>(
                find.descendant(
                  of: find.byTooltip('Continue'),
                  matching: find.byType(CupertinoButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(find.byTooltip('Back'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual entry shows own-number validation inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyContactsPage(
          session: session,
          initialContacts: const [],
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(1), '0123456789');
    await tester.ensureVisible(find.text('Add contact'));
    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    expect(
      find.text(EmergencyContactsRepository.ownNumberMessage),
      findsOneWidget,
    );
    expect(find.text('0/3 contacts added'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('editing a contact to own number keeps the editor open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyContactsPage(
          session: session,
          initialContacts: const [
            EmergencyContact(
              name: 'Friend',
              phoneNumber: '+60122222222',
              relationship: 'Friend',
            ),
          ],
        ),
      ),
    );
    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Edit contact'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '+60 12-3456789');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
      find.text(EmergencyContactsRepository.ownNumberMessage),
      findsOneWidget,
    );
    expect(find.text('Edit contact'), findsOneWidget);
  });

  testWidgets('device contacts mark own number as non-selectable', (
    tester,
  ) async {
    const channel = MethodChannel('hiker_circle/sos_device_alerts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => [
        {
          'fullName': 'My phone',
          'phoneNumbers': ['0123456789'],
        },
        {
          'fullName': 'Friend',
          'phoneNumbers': ['0122222222'],
        },
      ],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EmergencyContactsPage(
          session: session,
          initialContacts: const [],
        ),
      ),
    );
    await tester.ensureVisible(find.byTooltip('Choose from phone contacts'));
    await tester.tap(find.byTooltip('Choose from phone contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Your number'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    final ownRow = find.ancestor(
      of: find.text('My phone'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: ownRow, matching: find.byType(FilledButton)),
      findsNothing,
    );
  });

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
