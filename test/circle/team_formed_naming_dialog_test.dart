import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/circle/View/team_formed_naming_dialog.dart';

void main() {
  testWidgets('shows who joined and submits the selected group name', (
    tester,
  ) async {
    String? submittedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => TeamFormedNamingDialog(
                  joinedHikerName: 'Aina',
                  trailName: 'Bukit Gasing',
                  initialName: 'Bukit Gasing Crew',
                  onSubmit: (name) async => submittedName = name,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Your hiking team is formed'), findsOneWidget);
    expect(find.text('Aina joined Bukit Gasing.'), findsOneWidget);
    expect(find.text('Bukit Gasing Crew'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your hiking team is formed'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('team-group-name-field')),
      '  Gasing   Sunrise Crew  ',
    );
    await tester.tap(find.byKey(const Key('create-team-group-chat-button')));
    await tester.pumpAndSettle();

    expect(submittedName, 'Gasing Sunrise Crew');
    expect(find.text('Your hiking team is formed'), findsNothing);
  });

  testWidgets('keeps the popup open when the name is too short', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TeamFormedNamingDialog(
          joinedHikerName: 'Aina',
          trailName: 'Bukit Gasing',
          initialName: '',
          onSubmit: (_) async => submitted = true,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('team-group-name-field')), 'A');
    await tester.tap(find.byKey(const Key('create-team-group-chat-button')));
    await tester.pump();

    expect(find.text('Enter at least 2 characters.'), findsOneWidget);
    expect(submitted, isFalse);
  });
}
