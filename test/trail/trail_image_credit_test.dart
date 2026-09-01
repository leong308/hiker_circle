import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  test('trail image credits survive persistence round trip', () {
    final trail = Trail.fromPersistence({
      'trailId': 'trail-1',
      'coverImageUrl': ['https://example.com/trail.jpg'],
      'coverImageCredits': [
        {
          'sourceName': 'Wikimedia Commons',
          'sourcePageUrl': 'https://commons.wikimedia.org/wiki/File:Trail.jpg',
          'author': 'Trail photographer',
          'licenseName': 'CC BY-SA 4.0',
          'licenseUrl': 'https://creativecommons.org/licenses/by-sa/4.0/',
          'description': 'A verified trail photograph.',
        },
      ],
    });

    expect(trail.coverImageUrls, ['https://example.com/trail.jpg']);
    expect(trail.coverImageCredits, hasLength(1));
    expect(trail.coverImageCredits.single.author, 'Trail photographer');

    final stored = trail.toPersistence();
    expect(stored['coverImageUrl'], ['https://example.com/trail.jpg']);
    expect(
      (stored['coverImageCredits'] as List).single,
      containsPair('licenseName', 'CC BY-SA 4.0'),
    );
  });

  test('copyWith retains credits unless replacements are supplied', () {
    const credit = TrailImageCredit(
      sourceName: 'OpenStreetMap contributors',
      sourcePageUrl: 'https://www.openstreetmap.org/copyright',
      author: 'OpenStreetMap contributors',
      licenseName: 'Open Database License (ODbL)',
      licenseUrl: 'https://www.openstreetmap.org/copyright',
      description: 'Generated route cover.',
    );
    final trail = Trail.fromPersistence({
      'trailId': 'trail-2',
      'coverImageCredits': [credit.toFirestore()],
    });

    final copiedCredit = trail
        .copyWith(name: 'Updated')
        .coverImageCredits
        .single;
    expect(copiedCredit.sourceName, credit.sourceName);
    expect(copiedCredit.licenseName, credit.licenseName);
  });
}
