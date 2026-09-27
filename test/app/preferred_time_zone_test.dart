import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/preferred_time_zone.dart';

void main() {
  test('Malaysia uses Kuala Lumpur labels and retains UTC+8 formatting', () {
    final instant = DateTime.utc(2026, 9, 25, 4);
    expect(PreferredTimeZone.normalize('Asia/Kuching'), 'Asia/Kuala_Lumpur');
    expect(PreferredTimeZone.allIds, contains('Asia/Kuala_Lumpur'));
    expect(PreferredTimeZone.allIds, isNot(contains('Asia/Kuching')));
    expect(
      PreferredTimeZone.compactLabel('Asia/Kuching', at: instant),
      'Malaysia / Kuala Lumpur (GMT+8)',
    );
    expect(
      PreferredTimeZone.formatInstant(instant, 'Asia/Kuching'),
      '25 Sep 2026, 12:00:00 PM (GMT+8 · Asia/Kuala_Lumpur)',
    );
  });
}
