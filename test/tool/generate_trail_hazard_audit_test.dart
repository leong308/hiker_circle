import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Data/local_session_database.dart';
import 'package:hiker_circle/core/services/static_hazard_dataset_service.dart';
import 'package:hiker_circle/core/widgets/static_hazard_marker.dart';
import 'package:hiker_circle/trail/Model/trail_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generate live trail hazard audit',
    () async {
      const enabled = bool.fromEnvironment('GENERATE_HAZARD_AUDIT');
      if (!enabled) return;

      // Flutter's widget-test binding replaces HttpClient with a 400-only
      // implementation. This opt-in audit deliberately exercises the live
      // providers, so restore the platform client for this process only.
      HttpOverrides.global = null;

      final root = Directory.current;
      final raw =
          jsonDecode(
                File(
                  '${root.path}/tmp/trail_hazard_audit_input.json',
                ).readAsStringSync(),
              )
              as List;
      final trails = raw
          .whereType<Map>()
          .map(
            (value) => Trail.fromPersistence(Map<String, dynamic>.from(value)),
          )
          .where((trail) => trail.name.trim().isNotEmpty)
          .toList(growable: false);
      const requestedTrailId = String.fromEnvironment('AUDIT_TRAIL_ID');
      final selectedTrails = requestedTrailId.trim().isEmpty
          ? trails
          : trails
                .where((trail) => trail.trailId == requestedTrailId.trim())
                .toList(growable: false);
      expect(
        selectedTrails,
        isNotEmpty,
        reason: 'AUDIT_TRAIL_ID must match an exported Firebase trail.',
      );
      final env = File('${root.path}/.env').readAsStringSync();
      final token = RegExp(
        r'^MAPBOX_ACCESS_TOKEN\s*=\s*([^\r\n]+)',
        multiLine: true,
      ).firstMatch(env)?.group(1)?.trim();
      expect(token, isNotNull);

      final databaseFile = File('${root.path}/tmp/trail_hazard_audit.db');
      if (databaseFile.existsSync()) databaseFile.deleteSync();
      final database = LocalSessionDatabase(databasePath: databaseFile.path);
      final service = StaticHazardDatasetService(
        database: database,
        accessToken: token,
      );
      await service.downloadForTrails(
        selectedTrails,
        onProgress: (completed, total) {
          if (completed == total || completed % 25 == 0) {
            // ignore: avoid_print
            print('Hazard audit map scan: $completed/$total');
          }
        },
      );

      final report = <Map<String, dynamic>>[];
      for (final trail in selectedTrails) {
        final matches = await database.loadStaticHazardsForTrail(trail.trailId);
        final counts = <String, int>{};
        for (final match in matches) {
          counts.update(
            match.hazard.hazardType,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
        report.add({
          'trailId': trail.trailId,
          'name': trail.name,
          'state': trail.state,
          'total': matches.length,
          'counts': counts,
          'hazards': [
            for (final match in matches)
              {
                'type': match.hazard.hazardType,
                'title': match.hazard.title,
                'latitude': match.hazard.latitude,
                'longitude': match.hazard.longitude,
                'routeProgress': match.routeProgress,
                'distanceMeters': match.distanceMeters,
                'source': match.hazard.sourceName,
              },
          ],
        });
      }
      report.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
      final reportName = requestedTrailId.trim().isEmpty
          ? 'trail_hazard_audit.json'
          : 'trail_hazard_audit_single.json';
      File('${root.path}/tmp/$reportName').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'trails': report,
        }),
      );

      final iconDirectory = Directory('${root.path}/tmp/pdfs/hazard-icons')
        ..createSync(recursive: true);
      const types = [
        'river',
        'bridge_crossing',
        'cliff',
        'ford_crossing',
        'stepping_stones',
        'steep_ascent',
        'steep_descent',
        'rope_assisted_section',
        'ladder_section',
        'scrambling_section',
        'loose_rock',
        'muddy_surface',
        'rough_surface',
      ];
      for (final type in types) {
        final now = DateTime.now().toUtc();
        final hazard = LocalStaticHazard(
          hazardId: 'preview:$type',
          hazardType: type,
          title: type,
          description: type,
          latitude: 4,
          longitude: 102,
          severity: 'warning',
          confidence: 'preview',
          sourceName: 'preview',
          sourceUrl: '',
          sourceFeatureId: type,
          safetyGuidance: '',
          downloadedAt: now,
        );
        final match = LocalTrailHazardMatch(
          trailId: 'preview',
          hazard: hazard,
          relationship: 'on_route',
          distanceMeters: 0,
          routeProgress: 0,
          computedAt: now,
        );
        File(
          '${iconDirectory.path}/$type.png',
        ).writeAsBytesSync(await staticHazardMarkerImageFor(match));
      }
      await database.close();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
