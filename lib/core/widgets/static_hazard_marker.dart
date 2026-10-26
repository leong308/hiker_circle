// Static hazard marker widgets draw hazard-specific icons and present route-related water, bridge
// and steep-section details.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/local_session_database.dart';

/// Defines the static hazard marker kind choices.
enum StaticHazardMarkerKind {
  generic,
  water,
  bridge,
  cliff,
  ford,
  steppingStones,
  steepAscent,
  steepDescent,
  steepTerrain,
  rope,
  ladder,
  scrambling,
  looseRock,
  mud,
  roughSurface,
}

final Map<StaticHazardMarkerKind, Future<Uint8List>> _staticHazardMarkerImages =
    {};

/// Computes static hazard marker image.
Future<Uint8List> staticHazardMarkerImage() {
  return _markerImage(StaticHazardMarkerKind.generic);
}

/// Computes static hazard marker image for.
Future<Uint8List> staticHazardMarkerImageFor(LocalTrailHazardMatch match) {
  return _markerImage(staticHazardMarkerKindFor(match));
}

/// Computes marker image.
Future<Uint8List> _markerImage(StaticHazardMarkerKind kind) {
  return _staticHazardMarkerImages.putIfAbsent(
    kind,
    () => _drawStaticHazardMarker(kind),
  );
}

/// Computes static hazard marker kind for.
StaticHazardMarkerKind staticHazardMarkerKindFor(LocalTrailHazardMatch match) {
  return staticHazardMarkerKindForType(match.hazard.hazardType);
}

/// Computes static hazard marker kind for type.
StaticHazardMarkerKind staticHazardMarkerKindForType(String hazardType) {
  return switch (hazardType.trim().toLowerCase()) {
    'river' ||
    'stream' ||
    'stream_intermittent' => StaticHazardMarkerKind.water,
    'bridge_crossing' => StaticHazardMarkerKind.bridge,
    'cliff' => StaticHazardMarkerKind.cliff,
    'ford_crossing' => StaticHazardMarkerKind.ford,
    'stepping_stones' => StaticHazardMarkerKind.steppingStones,
    'steep_ascent' => StaticHazardMarkerKind.steepAscent,
    'steep_descent' => StaticHazardMarkerKind.steepDescent,
    'steep_section' => StaticHazardMarkerKind.steepTerrain,
    'rope_assisted_section' => StaticHazardMarkerKind.rope,
    'ladder_section' => StaticHazardMarkerKind.ladder,
    'scrambling_section' => StaticHazardMarkerKind.scrambling,
    'loose_rock' => StaticHazardMarkerKind.looseRock,
    'muddy_surface' => StaticHazardMarkerKind.mud,
    'rough_surface' => StaticHazardMarkerKind.roughSurface,
    _ => StaticHazardMarkerKind.generic,
  };
}

/// Computes uses bridge hazard marker.
bool usesBridgeHazardMarker(LocalTrailHazardMatch match) {
  return staticHazardMarkerKindFor(match) == StaticHazardMarkerKind.bridge;
}

/// Produces a readable set of map pins without discarding the underlying
/// caution records. Steep terrain samples are spatially grouped because
/// switchbacks and out-and-back routes can otherwise place several ascent and
/// descent pins over the same physical section.
List<LocalTrailHazardMatch> prepareStaticHazardsForMapDisplay(
  List<LocalTrailHazardMatch> hazards,
) {
  if (hazards.length < 2) return List.of(hazards);
  final fixed = <LocalTrailHazardMatch>[];
  final steep = <LocalTrailHazardMatch>[];
  for (final hazard in hazards) {
    if (_isSteepType(hazard.hazard.hazardType)) {
      steep.add(hazard);
    } else {
      fixed.add(hazard);
    }
  }
  if (steep.length < 2) {
    return [...fixed, ...steep]
      ..sort((a, b) => a.routeProgress.compareTo(b.routeProgress));
  }

  final clusterRadius = steep.length > 16
      ? 700.0
      : steep.length > 8
      ? 500.0
      : 300.0;
  final clusters = <List<LocalTrailHazardMatch>>[];
  for (final hazard in steep..sort(_compareHazardsByStrength)) {
    List<LocalTrailHazardMatch>? nearestCluster;
    var nearestDistance = double.infinity;
    for (final cluster in clusters) {
      final centerLatitude =
          cluster.map((item) => item.hazard.latitude).reduce((a, b) => a + b) /
          cluster.length;
      final centerLongitude =
          cluster.map((item) => item.hazard.longitude).reduce((a, b) => a + b) /
          cluster.length;
      final distance = _coordinateDistance(
        hazard.hazard.latitude,
        hazard.hazard.longitude,
        centerLatitude,
        centerLongitude,
      );
      if (distance <= clusterRadius && distance < nearestDistance) {
        nearestCluster = cluster;
        nearestDistance = distance;
      }
    }
    if (nearestCluster == null) {
      clusters.add([hazard]);
    } else {
      nearestCluster.add(hazard);
    }
  }

  final result = <LocalTrailHazardMatch>[
    ...fixed,
    for (final cluster in clusters) _combineSteepDisplayCluster(cluster),
  ];
  result.sort((a, b) => a.routeProgress.compareTo(b.routeProgress));
  return result;
}

/// Checks whether steep type.
bool _isSteepType(String type) {
  final normalized = type.trim().toLowerCase();
  return normalized == 'steep_ascent' ||
      normalized == 'steep_descent' ||
      normalized == 'steep_section';
}

/// Computes compare hazards by strength.
int _compareHazardsByStrength(
  LocalTrailHazardMatch first,
  LocalTrailHazardMatch second,
) {
  return _steepDetails(
    second,
  ).gradePercent.compareTo(_steepDetails(first).gradePercent);
}

/// Computes combine steep display cluster.
LocalTrailHazardMatch _combineSteepDisplayCluster(
  List<LocalTrailHazardMatch> cluster,
) {
  if (cluster.length == 1) return cluster.single;
  final representative = cluster.reduce(
    (first, second) =>
        _compareHazardsByStrength(first, second) <= 0 ? first : second,
  );
  final types = cluster.map((item) => item.hazard.hazardType).toSet();
  final bothDirections =
      types.contains('steep_ascent') && types.contains('steep_descent');
  final ascent = representative.hazard.hazardType == 'steep_ascent';
  final details = _steepDetails(representative);
  final direction = bothDirections
      ? 'in both directions'
      : ascent
      ? 'uphill'
      : 'downhill';
  final changeVerb = bothDirections
      ? 'changes elevation'
      : ascent
      ? 'rises'
      : 'drops';
  final type = bothDirections
      ? 'steep_section'
      : representative.hazard.hazardType;
  final downloadedAt = cluster
      .map((item) => item.hazard.downloadedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final hazard = LocalStaticHazard(
    hazardId:
        'display:steep:${representative.trailId}:'
        '${(representative.routeProgress * 10000).round()}:${cluster.length}',
    hazardType: type,
    title: bothDirections
        ? 'Steep terrain area'
        : ascent
        ? 'Steep uphill area'
        : 'Steep downhill area',
    description:
        '${cluster.length} nearby steep route sections are grouped here '
        '$direction. The most demanding section $changeVerb about '
        '${details.changeMeters} m over roughly ${details.spanMeters} m.',
    latitude: representative.hazard.latitude,
    longitude: representative.hazard.longitude,
    severity: cluster.any((item) => item.hazard.severity == 'warning')
        ? 'warning'
        : 'caution',
    confidence: representative.hazard.confidence,
    sourceName: representative.hazard.sourceName,
    sourceUrl: representative.hazard.sourceUrl,
    sourceFeatureId:
        'display_cluster:${cluster.length}:grade=${details.gradePercent}:'
        'change=${details.changeMeters}:span=${details.spanMeters}',
    safetyGuidance: bothDirections
        ? 'Slow down, keep the group together and use controlled steps through this entire area.'
        : representative.hazard.safetyGuidance,
    sourceUpdatedAt: representative.hazard.sourceUpdatedAt,
    downloadedAt: downloadedAt,
    expiresAt: representative.hazard.expiresAt,
  );
  return LocalTrailHazardMatch(
    trailId: representative.trailId,
    hazard: hazard,
    relationship: 'steep_area',
    distanceMeters: 0,
    routeProgress: representative.routeProgress,
    computedAt: representative.computedAt,
  );
}

/// Computes coordinate distance.
double _coordinateDistance(
  double firstLatitude,
  double firstLongitude,
  double secondLatitude,
  double secondLongitude,
) {
  const earthRadiusMeters = 6371000.0;
  final latitude1 = firstLatitude * math.pi / 180;
  final latitude2 = secondLatitude * math.pi / 180;
  final latitudeDelta = (secondLatitude - firstLatitude) * math.pi / 180;
  final longitudeDelta = (secondLongitude - firstLongitude) * math.pi / 180;
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(latitude1) *
          math.cos(latitude2) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters *
      2 *
      math.atan2(
        math.sqrt(a.clamp(0.0, 1.0)),
        math.sqrt((1 - a).clamp(0.0, 1.0)),
      );
}

/// Computes static hazard annotation.
mapbox.PointAnnotationOptions staticHazardAnnotation(
  LocalTrailHazardMatch match,
  Uint8List markerImage, {
  double scaleFactor = 1,
}) {
  return mapbox.PointAnnotationOptions(
    geometry: mapbox.Point(
      coordinates: mapbox.Position(
        match.hazard.longitude,
        match.hazard.latitude,
      ),
    ),
    image: markerImage,
    iconAnchor: mapbox.IconAnchor.CENTER,
    iconSize: (match.hazard.severity == 'warning' ? 0.72 : 0.64) * scaleFactor,
    symbolSortKey: 900,
    customData: {
      'hazard_id': match.hazard.hazardId,
      'hazard_type': match.hazard.hazardType,
    },
  );
}

/// Shows static hazard details.
Future<void> showStaticHazardDetails(
  BuildContext context,
  LocalTrailHazardMatch match,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _StaticHazardDetailsSheet(match: match),
  );
}

/// Displays the static hazard details sheet.
class _StaticHazardDetailsSheet extends StatelessWidget {
  /// Creates static hazard details sheet.
  const _StaticHazardDetailsSheet({required this.match});

  final LocalTrailHazardMatch match;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final hazard = match.hazard;
    final kind = staticHazardMarkerKindFor(match);
    final steep = _isSteepType(hazard.hazardType);
    final downloaded = MaterialLocalizations.of(
      context,
    ).formatMediumDate(hazard.downloadedAt.toLocal());
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final technical = steep ? _steepDetails(match) : null;
    final heading = technical == null
        ? hazard.title
        : technical.combinedDirections
        ? 'Steep terrain area'
        : '${technical.level} ${technical.ascent ? 'uphill' : 'downhill'}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _markerColor(kind).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: _HazardGlyph(
                    kind: kind,
                    size: 30,
                    color: _markerColor(kind),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        steep
                            ? 'Plan a slower pace through this section.'
                            : 'Review this mapped caution before continuing.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (technical != null) ...[
              _SteepSectionSummary(details: technical),
              const SizedBox(height: 14),
            ] else ...[
              Text(hazard.description, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 14),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.directions_walk_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What to do',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(hazard.safetyGuidance),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 10),
              title: Text(
                'How this caution was estimated',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                if (technical != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${technical.gradePercent}% average grade over about '
                      '${technical.spanMeters} m. Elevation change is '
                      'approximately ${technical.changeMeters} m.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${hazard.sourceName} · updated $downloaded · '
                    '${hazard.confidence.replaceAll('_', ' ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Map data is advisory. Conditions may have changed since this caution was recorded.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the steep section summary.
class _SteepSectionSummary extends StatelessWidget {
  /// Creates steep section summary.
  const _SteepSectionSummary({required this.details});

  final _SteepHazardDetails details;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final directionLabel = details.combinedDirections
        ? 'Mixed'
        : details.ascent
        ? 'Uphill'
        : 'Downhill';
    final changeLabel = details.combinedDirections
        ? '~${details.changeMeters} m change'
        : details.ascent
        ? '~${details.changeMeters} m rise'
        : '~${details.changeMeters} m drop';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          details.sectionCount > 1
              ? '${details.sectionCount} nearby steep sections are grouped in this area.'
              : '${details.level} terrain continues for roughly ${details.spanMeters} m.',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _HazardMetric(
                icon: details.ascent
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                label: 'Direction',
                value: directionLabel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HazardMetric(
                icon: Icons.height_rounded,
                label: 'Elevation',
                value: changeLabel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HazardMetric(
                icon: Icons.landscape_rounded,
                label: 'Difficulty',
                value: details.level,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: (details.gradePercent / 50).clamp(0.08, 1.0),
            backgroundColor: colors.surfaceContainerHighest,
            color: details.gradePercent >= 40
                ? colors.error
                : details.gradePercent >= 30
                ? const Color(0xFFE46C35)
                : colors.primary,
          ),
        ),
      ],
    );
  }
}

/// Displays the hazard metric.
class _HazardMetric extends StatelessWidget {
  /// Creates hazard metric.
  const _HazardMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Computes steep details.
_SteepHazardDetails _steepDetails(LocalTrailHazardMatch match) {
  final hazard = match.hazard;

  /// Reads.
  int read(String key) {
    final structured = RegExp(
      '$key=(\\d+)',
    ).firstMatch(hazard.sourceFeatureId)?.group(1);
    return int.tryParse(structured ?? '') ?? 0;
  }

  var grade = read('grade');
  var change = read('change');
  var span = read('span');
  if (grade == 0) {
    grade =
        int.tryParse(
          RegExp(r'(\d+)\s*%').firstMatch(hazard.description)?.group(1) ?? '',
        ) ??
        0;
  }
  if (change == 0) {
    change =
        int.tryParse(
          RegExp(
                r'(\d+)\s*m\s*(?:rise|drop|change)',
                caseSensitive: false,
              ).firstMatch(hazard.description)?.group(1) ??
              '',
        ) ??
        0;
  }
  span = span == 0 ? 300 : span;
  final clusterCount =
      int.tryParse(
        RegExp(
              r'display_cluster:(\d+)',
            ).firstMatch(hazard.sourceFeatureId)?.group(1) ??
            '',
      ) ??
      1;
  return _SteepHazardDetails(
    gradePercent: grade,
    changeMeters: change,
    spanMeters: span,
    sectionCount: clusterCount,
    ascent: hazard.hazardType == 'steep_ascent',
    combinedDirections: hazard.hazardType == 'steep_section',
  );
}

/// Represents steep hazard details.
class _SteepHazardDetails {
  /// Creates steep hazard details.
  const _SteepHazardDetails({
    required this.gradePercent,
    required this.changeMeters,
    required this.spanMeters,
    required this.sectionCount,
    required this.ascent,
    required this.combinedDirections,
  });

  final int gradePercent;
  final int changeMeters;
  final int spanMeters;
  final int sectionCount;
  final bool ascent;
  final bool combinedDirections;

  /// Returns level.
  String get level => gradePercent >= 40
      ? 'Extreme'
      : gradePercent >= 30
      ? 'Very steep'
      : 'Steep';
}

/// Computes marker color.
Color _markerColor(StaticHazardMarkerKind kind) {
  return switch (kind) {
    StaticHazardMarkerKind.water => const Color(0xFF2089D8),
    StaticHazardMarkerKind.bridge => const Color(0xFFF59E0B),
    StaticHazardMarkerKind.cliff => const Color(0xFFE05252),
    StaticHazardMarkerKind.ford => const Color(0xFF138A87),
    StaticHazardMarkerKind.steppingStones => const Color(0xFF397EAD),
    StaticHazardMarkerKind.steepAscent => const Color(0xFFE46C35),
    StaticHazardMarkerKind.steepDescent => const Color(0xFF8057B5),
    StaticHazardMarkerKind.steepTerrain => const Color(0xFFD15A35),
    StaticHazardMarkerKind.rope => const Color(0xFF6750A4),
    StaticHazardMarkerKind.ladder => const Color(0xFF9A6531),
    StaticHazardMarkerKind.scrambling => const Color(0xFFC66A18),
    StaticHazardMarkerKind.looseRock => const Color(0xFF667078),
    StaticHazardMarkerKind.mud => const Color(0xFF8C5B3E),
    StaticHazardMarkerKind.roughSurface => const Color(0xFF546E7A),
    StaticHazardMarkerKind.generic => const Color(0xFFF59E0B),
  };
}

/// Computes draw static hazard marker.
Future<Uint8List> _drawStaticHazardMarker(StaticHazardMarkerKind kind) async {
  const width = 80;
  const height = 72;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  _paintStaticHazardMarker(canvas, kind);

  final image = await recorder.endRecording().toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Unable to encode the static hazard marker.');
    }
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Uses the exact same artwork as the native map annotation.
class StaticHazardMarkerIcon extends StatelessWidget {
  /// Creates static hazard marker icon.
  const StaticHazardMarkerIcon({super.key, required this.kind});
  final StaticHazardMarkerKind kind;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(44, 40),
    painter: _StaticHazardIconPainter(kind),
  );
}

/// Represents static hazard icon painter.
class _StaticHazardIconPainter extends CustomPainter {
  /// Creates static hazard icon painter.
  const _StaticHazardIconPainter(this.kind);
  final StaticHazardMarkerKind kind;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 80, size.height / 72);
    _paintStaticHazardMarker(canvas, kind);
    canvas.restore();
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(_StaticHazardIconPainter oldDelegate) =>
      oldDelegate.kind != kind;
}

/// Computes paint static hazard marker.
void _paintStaticHazardMarker(ui.Canvas canvas, StaticHazardMarkerKind kind) {
  final triangle = ui.Path()
    ..moveTo(40, 5)
    ..lineTo(75, 65)
    ..quadraticBezierTo(76, 68, 71, 68)
    ..lineTo(9, 68)
    ..quadraticBezierTo(4, 68, 5, 65)
    ..close();

  canvas.save();
  canvas.translate(0, 2);
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = const ui.Color(0x44000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
  );
  canvas.restore();
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = _markerColor(kind)
      ..style = ui.PaintingStyle.fill,
  );
  canvas.drawPath(
    triangle,
    ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  _drawHazardGlyph(
    canvas,
    kind,
    const ui.Rect.fromLTWH(18, 24, 44, 33),
    const ui.Color(0xFFFFFFFF),
  );
}

/// Computes draw hazard glyph.
void _drawHazardGlyph(
  ui.Canvas canvas,
  StaticHazardMarkerKind kind,
  ui.Rect bounds,
  ui.Color color,
) {
  final stroke = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = bounds.width * 0.085
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  final fill = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.fill;

  /// Computes x.
  double x(double value) => bounds.left + bounds.width * value;

  /// Computes y.
  double y(double value) => bounds.top + bounds.height * value;

  switch (kind) {
    case StaticHazardMarkerKind.water:
      for (final level in const [0.35, 0.58, 0.81]) {
        final wave = ui.Path()
          ..moveTo(x(0.08), y(level))
          ..quadraticBezierTo(x(0.25), y(level - 0.16), x(0.42), y(level))
          ..quadraticBezierTo(x(0.59), y(level + 0.16), x(0.76), y(level))
          ..quadraticBezierTo(x(0.86), y(level - 0.09), x(0.94), y(level));
        canvas.drawPath(wave, stroke);
      }
    case StaticHazardMarkerKind.bridge:
      canvas.drawLine(
        ui.Offset(x(0.05), y(0.68)),
        ui.Offset(x(0.95), y(0.68)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.12), y(0.68)),
        ui.Offset(x(0.12), y(0.94)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.88), y(0.68)),
        ui.Offset(x(0.88), y(0.94)),
        stroke,
      );
      final arch = ui.Path()
        ..moveTo(x(0.12), y(0.68))
        ..quadraticBezierTo(x(0.31), y(0.10), x(0.50), y(0.68))
        ..quadraticBezierTo(x(0.69), y(0.10), x(0.88), y(0.68));
      canvas.drawPath(arch, stroke);
    case StaticHazardMarkerKind.cliff:
      final cliff = ui.Path()
        ..moveTo(x(0.08), y(0.22))
        ..lineTo(x(0.52), y(0.22))
        ..lineTo(x(0.52), y(0.48))
        ..lineTo(x(0.69), y(0.61))
        ..lineTo(x(0.60), y(0.94));
      canvas.drawPath(cliff, stroke);
      canvas.drawCircle(ui.Offset(x(0.80), y(0.72)), bounds.width * 0.07, fill);
    case StaticHazardMarkerKind.ford:
      final wave = ui.Path()
        ..moveTo(x(0.04), y(0.72))
        ..quadraticBezierTo(x(0.25), y(0.50), x(0.46), y(0.72))
        ..quadraticBezierTo(x(0.68), y(0.94), x(0.96), y(0.69));
      canvas.drawPath(wave, stroke);
      canvas.drawLine(
        ui.Offset(x(0.20), y(0.20)),
        ui.Offset(x(0.80), y(0.52)),
        stroke,
      );
    case StaticHazardMarkerKind.steppingStones:
      canvas.drawCircle(ui.Offset(x(0.18), y(0.72)), bounds.width * 0.09, fill);
      canvas.drawCircle(ui.Offset(x(0.48), y(0.50)), bounds.width * 0.09, fill);
      canvas.drawCircle(ui.Offset(x(0.80), y(0.28)), bounds.width * 0.09, fill);
      canvas.drawLine(
        ui.Offset(x(0.04), y(0.91)),
        ui.Offset(x(0.96), y(0.91)),
        stroke,
      );
    case StaticHazardMarkerKind.steepAscent:
      canvas.drawLine(
        ui.Offset(x(0.08), y(0.86)),
        ui.Offset(x(0.82), y(0.20)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.82), y(0.20)),
        ui.Offset(x(0.61), y(0.22)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.82), y(0.20)),
        ui.Offset(x(0.80), y(0.43)),
        stroke,
      );
    case StaticHazardMarkerKind.steepDescent:
      canvas.drawLine(
        ui.Offset(x(0.08), y(0.20)),
        ui.Offset(x(0.82), y(0.86)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.82), y(0.86)),
        ui.Offset(x(0.60), y(0.83)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.82), y(0.86)),
        ui.Offset(x(0.80), y(0.63)),
        stroke,
      );
    case StaticHazardMarkerKind.steepTerrain:
      // A solid terrain silhouette stays legible at small map-pin sizes.
      // Two clear peaks replace the overlapping slope arrows.
      final terrain = ui.Path()
        ..moveTo(x(0.06), y(0.88))
        ..lineTo(x(0.32), y(0.38))
        ..lineTo(x(0.46), y(0.61))
        ..lineTo(x(0.65), y(0.17))
        ..lineTo(x(0.96), y(0.88))
        ..close();
      canvas.drawPath(terrain, fill);
    case StaticHazardMarkerKind.rope:
      final rope = ui.Path()
        ..moveTo(x(0.18), y(0.12))
        ..cubicTo(x(0.92), y(0.16), x(0.08), y(0.65), x(0.72), y(0.86));
      canvas.drawPath(rope, stroke);
      canvas.drawCircle(
        ui.Offset(x(0.75), y(0.86)),
        bounds.width * 0.07,
        stroke,
      );
    case StaticHazardMarkerKind.ladder:
      canvas.drawLine(
        ui.Offset(x(0.28), y(0.08)),
        ui.Offset(x(0.28), y(0.94)),
        stroke,
      );
      canvas.drawLine(
        ui.Offset(x(0.72), y(0.08)),
        ui.Offset(x(0.72), y(0.94)),
        stroke,
      );
      for (final level in const [0.23, 0.48, 0.73]) {
        canvas.drawLine(
          ui.Offset(x(0.28), y(level)),
          ui.Offset(x(0.72), y(level)),
          stroke,
        );
      }
    case StaticHazardMarkerKind.scrambling:
      final mountain = ui.Path()
        ..moveTo(x(0.04), y(0.91))
        ..lineTo(x(0.34), y(0.27))
        ..lineTo(x(0.50), y(0.57))
        ..lineTo(x(0.68), y(0.12))
        ..lineTo(x(0.96), y(0.91));
      canvas.drawPath(mountain, stroke);
    case StaticHazardMarkerKind.looseRock:
      canvas.drawCircle(ui.Offset(x(0.27), y(0.29)), bounds.width * 0.10, fill);
      canvas.drawCircle(ui.Offset(x(0.55), y(0.54)), bounds.width * 0.13, fill);
      canvas.drawCircle(ui.Offset(x(0.78), y(0.82)), bounds.width * 0.08, fill);
      canvas.drawLine(
        ui.Offset(x(0.10), y(0.92)),
        ui.Offset(x(0.92), y(0.92)),
        stroke,
      );
    case StaticHazardMarkerKind.mud:
      canvas.drawOval(
        ui.Rect.fromLTRB(x(0.08), y(0.57), x(0.92), y(0.92)),
        stroke,
      );
      canvas.drawCircle(ui.Offset(x(0.35), y(0.30)), bounds.width * 0.07, fill);
      canvas.drawCircle(ui.Offset(x(0.65), y(0.42)), bounds.width * 0.06, fill);
    case StaticHazardMarkerKind.roughSurface:
      final rough = ui.Path()
        ..moveTo(x(0.03), y(0.76))
        ..lineTo(x(0.22), y(0.48))
        ..lineTo(x(0.38), y(0.73))
        ..lineTo(x(0.56), y(0.31))
        ..lineTo(x(0.73), y(0.68))
        ..lineTo(x(0.96), y(0.41));
      canvas.drawPath(rough, stroke);
    case StaticHazardMarkerKind.generic:
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(
            x(0.43),
            y(0.08),
            bounds.width * 0.14,
            bounds.height * 0.56,
          ),
          ui.Radius.circular(bounds.width * 0.07),
        ),
        fill,
      );
      canvas.drawCircle(ui.Offset(x(0.50), y(0.86)), bounds.width * 0.08, fill);
  }
}

/// Displays the hazard glyph.
class _HazardGlyph extends StatelessWidget {
  /// Creates hazard glyph.
  const _HazardGlyph({
    required this.kind,
    required this.size,
    required this.color,
  });

  final StaticHazardMarkerKind kind;
  final double size;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _HazardGlyphPainter(kind, color)),
    );
  }
}

/// Represents hazard glyph painter.
class _HazardGlyphPainter extends CustomPainter {
  /// Creates hazard glyph painter.
  const _HazardGlyphPainter(this.kind, this.color);

  final StaticHazardMarkerKind kind;
  final Color color;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    _drawHazardGlyph(canvas, kind, Offset.zero & size, color);
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(_HazardGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
