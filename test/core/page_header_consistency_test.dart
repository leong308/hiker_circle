import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:hiker_circle/feedback/feedback_page.dart';

enum HeaderChoice { edit }

ThemeData headerTheme(Brightness brightness) => ThemeData(
  fontFamily: 'Inter',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F8F5E),
    brightness: brightness,
  ),
  appBarTheme: PageHeaderStyle.appBarTheme,
);

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });

  test('all application scaffold headers use the shared app bar', () {
    final exceptions = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('page_header_style.dart')) {
        continue;
      }
      if (RegExp(r'\bAppBar\s*\(').hasMatch(file.readAsStringSync())) {
        exceptions.add(file.path);
      }
    }
    expect(
      exceptions,
      isEmpty,
      reason:
          'Subpages must use PageHeaderAppBar to keep navigation headers consistent.',
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'body and scaffold ${brightness.name} headers have identical typography and action geometry',
      (tester) async {
        final colors = headerTheme(brightness).colorScheme;
        await tester.pumpWidget(
          MaterialApp(
            theme: headerTheme(brightness),
            home: Scaffold(
              appBar: PageHeaderAppBar(
                title: const Text(
                  'Scaffold header',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.red,
                  ),
                ),
                leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back, size: 32),
                  onPressed: () {},
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.all(18),
                child: PageHeader(
                  title: 'Body header',
                  subtitle: 'Subtitle',
                  onBack: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final first = tester.widget<Text>(find.text('Scaffold header')).style!;
        final second = tester.widget<Text>(find.text('Body header')).style!;
        expect(first, second);
        expect(first.fontSize, 26);
        expect(first.fontWeight, FontWeight.w800);
        expect(first.fontStyle, FontStyle.normal);
        expect(first.fontFamily, 'Inter');
        expect(first.color, colors.onSurface);
        for (final action in find.byType(PageHeaderAction).evaluate()) {
          final control = find.descendant(
            of: find.byWidget(action.widget),
            matching: find.byType(CupertinoButton),
          );
          expect(tester.getSize(control), const Size(44, 44));
          final icon = tester.widget<Icon>(
            find.descendant(of: control, matching: find.byType(Icon)),
          );
          expect(icon.size, 19);
          expect(icon.color, colors.primary);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('header preserves typed popup menus, save callbacks and tabs', (
    tester,
  ) async {
    String? selected;
    HeaderChoice? enumSelected;
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: PageHeaderAppBar(
              title: const Text('Details'),
              actions: [
                TextButton(onPressed: () => saved++, child: const Text('Save')),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  onSelected: (value) => selected = value,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit details')),
                  ],
                ),
                PopupMenuButton<HeaderChoice>(
                  tooltip: 'Chat actions',
                  onSelected: (choice) => enumSelected = choice,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: HeaderChoice.edit,
                      child: Text('Edit chat'),
                    ),
                  ],
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'First'),
                  Tab(text: 'Second'),
                ],
              ),
            ),
            body: const TabBarView(
              children: [Text('First content'), Text('Second content')],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    expect(selected, 'edit');
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit chat'));
    await tester.pumpAndSettle();
    expect(enumSelected, HeaderChoice.edit);
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(find.text('Second content').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'automatic back returns to the owning page and disabled controls stay disabled',
    (tester) async {
      var disabledCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: PageHeaderAppBar(
                        title: const Text('Child'),
                        actions: [
                          IconButton(
                            tooltip: 'Disabled',
                            icon: const Icon(Icons.save),
                            onPressed: null,
                          ),
                        ],
                      ),
                      body: TextButton(
                        onPressed: () => disabledCalls++,
                        child: const Text('Body'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Disabled'));
      await tester.pumpAndSettle();
      expect(disabledCalls, 0);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Child'), findsNothing);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'feedback ${brightness.name} page is compact and fits a narrow screen with larger text',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var scale = 1.0;
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: headerTheme(brightness),
            builder: (context, child) => RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: const FeedbackPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Feedback'), findsOneWidget);
        expect(find.byTooltip('My feedback'), findsOneWidget);
        expect(find.text('A better experience, together'), findsNothing);
        expect(find.text('Write feedback'), findsOneWidget);
        expect(find.text('Mark a screenshot'), findsOneWidget);
        await capture(tester, key, 'feedback-${brightness.name}');
        tester.view.physicalSize = const Size(320, 780);
        scale = 1.8;
        await tester.pumpWidget(
          MaterialApp(
            theme: headerTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const FeedbackPage(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Private feedback · Not for emergencies'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Private feedback · Not for emergencies').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_HEADER_PREVIEW')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory('tmp').create(recursive: true);
    await File('tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
