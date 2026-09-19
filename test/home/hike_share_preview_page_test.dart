import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/home/Model/hike_session_models.dart';
import 'package:hiker_circle/home/View/hike_share_preview_page.dart';

void main() {
  final report = HikeSummaryReport(
    sessionId: 'session-1',
    trailName: 'Pine Ridge Trail',
    startedAt: DateTime(2026, 8, 26, 8),
    endedAt: DateTime(2026, 8, 26, 10, 15),
    duration: Duration(hours: 2, minutes: 15),
    distanceKm: 7.42,
    checkIns: 3,
    manualPins: 1,
    routePointCount: 24,
    batteryStartPercent: 92,
    batteryEndPercent: 71,
    insights: ['A steady and safe hike.'],
  );

  test('default share caption is concise and social-ready', () {
    expect(
      defaultHikeShareCaption(report),
      'Completed Pine Ridge Trail — 7.42 km in 2h 15m. '
      '24 GPS points recorded along the way.',
    );
  });

  test('external share contains the edited caption and full report', () {
    final text = buildExternalHikeShareText(
      report: report,
      caption: 'A brilliant morning on the ridge.',
    );

    expect(text, startsWith('A brilliant morning on the ridge.'));
    expect(text, contains('Hike summary: Pine Ridge Trail'));
    expect(text, contains('Distance: 7.42 km'));
    expect(text, contains('Battery: 92% to 71%'));
  });
}
