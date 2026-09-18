import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/admin/Model/button_debug_entry.dart';
import 'package:hiker_circle/admin/Model/button_debug_field.dart';
import 'package:hiker_circle/admin/View/button_debug_entry_card.dart';

Map<String, Object?> packet(List<int> bytes, [String characteristic = '']) =>
    ButtonDebugEntry.fromEvent({
      'bytes': bytes,
      'characteristic': characteristic,
      'direction': 'RX',
      'operation': 'advertisement',
      'timestampMillis': DateTime.utc(2026, 9, 14, 8).millisecondsSinceEpoch,
    }).toRow('test', 1);

void main() {
  test('all bytes covered once, including unsupported and partial packets', () {
    for (final characteristic in [
      '',
      '7e2a1d38',
      '7e2a1d39',
      '7e2a1d3d',
      '7e2a1d3f',
    ]) {
      for (var length = 0; length < 70; length++) {
        for (final version in [1, 2, 9]) {
          for (var type = 0; type <= 20; type++) {
            final bytes = Uint8List(length);
            if (length >= 4) bytes.setAll(0, [72, 67, version, type]);
            if (length > 7 && type == 18) bytes.setAll(4, [20, 3, 0, 3]);
            final fields = decodeButtonFields(bytes, characteristic);
            expect([
              for (final field in fields)
                for (var i = field.start; i <= field.end; i++) i,
            ], List.generate(length, (i) => i));
            expect(fields.map((f) => f.hex).join(' '), buttonPayloadHex(bytes));
          }
        }
      }
    }
  });

  test('big-endian coordinates, counters and units match HEX', () {
    final bytes = Uint8List(30)..setAll(0, [72, 67, 2, 5]);
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, 258);
    data.setInt32(8, -51234567);
    data.setInt32(12, 1001234567);
    data.setUint16(16, 123);
    data.setUint32(18, 1700000000);
    final fields = decodeButtonFields(bytes, '');
    ButtonDebugField field(String name) =>
        fields.singleWhere((f) => f.name == name);
    expect(field('Event counter').hex, '00 00 01 02');
    expect(field('Event counter').value, '258');
    expect(field('Latitude').value, '-5.1234567°');
    expect(field('Longitude').value, '100.1234567°');
    expect(field('Location accuracy').value, '12.3 m');
    expect(field('Authentication tag').value, contains('does not verify'));
    expect(
      ButtonDebugEntry.formatRow(packet(bytes)),
      contains('| 4–7 | 00 00 01 02 | Event counter: 258 |'),
    );
  });

  test('pairing secrets are redacted in capture, fields and export', () {
    final bytes = [72, 67, 1, 1, 1, 2, 3, 4, 5, 6, ...List.filled(32, 0xAB)];
    final row = packet(bytes, '7E2A1D38');
    expect((row['payload'] as List).skip(10), everyElement(0));
    final key = decodeButtonFields(bytes, '7E2A1D38').last;
    expect(key.name, 'Permanent pairing key');
    expect(key.value, contains('REDACTED'));
    expect(key.hex, isNot(contains('AB')));
    expect(ButtonDebugEntry.formatRow(row), isNot(contains('AB AB')));
    expect(bytes.last, 0xAB, reason: 'Source packet must not be mutated');
  });

  testWidgets('HEX table remains readable at phone width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final row = packet([72, 67, 1, 6, 1, 20]);
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ButtonDebugEntryCard(row: row),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('48 43 01 06 01 14'), findsOneWidget);
      expect(find.text('Time remaining'), findsOneWidget);
      expect(find.text('20 seconds'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
