import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/navigation/View/hiker_bottom_nav_bar.dart';

void main() {
  testWidgets('renders the standard hiker destinations and handles taps', (
    tester,
  ) async {
    var selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              bottomNavigationBar: HikerBottomNavBar(
                currentIndex: selectedIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    selectedIndex = index;
                  });
                },
              ),
            );
          },
        ),
      ),
    );

    for (final destination in HikerBottomNavBar.standardDestinations) {
      expect(find.text(destination.label), findsOneWidget);
    }

    await tester.tap(find.text('SOS'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);
  });
}
