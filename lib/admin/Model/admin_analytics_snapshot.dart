/// Dashboard sections keep operational detail accessible without one long page.
enum AdminDashboardArea {
  overview('Overview'),
  hiking('Hiking'),
  safety('Safety'),
  trails('Trails'),
  people('People & rewards'),
  operations('Operations');

  /// Supplies the navigation label independently of its visual treatment.
  const AdminDashboardArea(this.label);
  final String label;
}

/// Calendar windows match the backend's Malaysia-local comparison periods.
enum AdminDashboardPeriod {
  week(7, '7 days'),
  month(30, '30 days'),
  quarter(90, '90 days'),
  year(365, '1 year');

  /// Binds a readable range to the server's window key.
  const AdminDashboardPeriod(this.days, this.label);
  final int days;
  final String label;
}

/// Safe access to an aggregate snapshot; missing data stays distinct from zero.
class AdminAnalyticsSnapshot {
  /// Keeps the server response read-only for presentation and comparison.
  AdminAnalyticsSnapshot(Map<String, dynamic> data)
    : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;

  /// Reads a nested field without depending on Firestore or backend classes.
  Object? at(String path) {
    Object? value = data;
    for (final key in path.split('.')) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value;
  }

  /// Returns finite numbers only; absent figures must render as unavailable.
  num? number(String path) {
    final value = at(path);
    return value is num && value.isFinite ? value : null;
  }

  /// Decodes chart and coverage records without trusting arbitrary shapes.
  List<Map<String, dynamic>> rows(String path) {
    final value = at(path);
    return value is List
        ? value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  /// Uses an empty map only for structural access, never as a numeric default.
  Map<String, dynamic> map(String path) {
    final value = at(path);
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  /// Requires analysed records or a complete empty collection before showing data.
  bool hasSources(List<String> sources) => sources.every(
    (source) =>
        at('coverage.$source.complete') == true ||
        (number('coverage.$source.analysed') ?? 0) > 0,
  );

  /// Rates need full source coverage rather than a partial numerator or denominator.
  bool completeSources(List<String> sources) =>
      sources.every((source) => at('coverage.$source.complete') == true);

  /// Supplies readable source coverage instead of exposing database identifiers.
  List<Map<String, dynamic>> get coverage => map('coverage').entries
      .map(
        (entry) => {
          'source': entry.key,
          'label': sourceNames[entry.key] ?? 'Additional source',
          ...entry.value is Map
              ? Map<String, dynamic>.from(entry.value as Map)
              : <String, dynamic>{},
        },
      )
      .toList();

  /// Counts every incomplete source, including sources whose read failed entirely.
  int get incompleteCount =>
      coverage.where((row) => row['complete'] != true).length;

  /// Counts fully analysed sources for the dashboard's coverage summary.
  int get completeSourceCount => coverage.length - incompleteCount;

  /// Adds date exclusions without manufacturing event times for older records.
  int get dateIssueCount =>
      map('quality.dateIssues').values.fold(0, (sum, item) {
        if (item is! Map) return sum;
        return sum +
            ((item['missing'] is num ? item['missing'] as num : 0) +
                    (item['future'] is num ? item['future'] as num : 0))
                .toInt();
      });

  /// Identifies an older snapshot without pretending new metrics are zero.
  bool get hasExpandedAnalysis => (number('schemaVersion') ?? 0) >= 3;

  /// Formats a snapshot time with its explicit reporting time zone.
  String get updatedLabel {
    final millis = number('generatedAtMillis');
    if (millis == null) return 'Update time unavailable';
    final date = DateTime.fromMillisecondsSinceEpoch(
      millis.toInt(),
      isUtc: true,
    ).add(const Duration(hours: 8));
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} MYT';
  }

  /// Returns a current or previous server-computed period metric.
  num? periodNumber(
    AdminDashboardPeriod period,
    String key, {
    bool previous = false,
  }) => number(
    'windows.${period.days}.${previous ? 'previous' : 'current'}.$key',
  );

  /// Filters valid daily buckets to the chosen calendar window, grouping a year by month.
  List<Map<String, dynamic>> series(AdminDashboardPeriod period) {
    final endMillis = number('generatedAtMillis');
    if (endMillis == null) return const [];
    final end = DateTime.fromMillisecondsSinceEpoch(
      endMillis.toInt(),
      isUtc: true,
    ).add(const Duration(hours: 8));
    final start = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).subtract(Duration(days: period.days - 1));
    final selected = rows('daily').where((row) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${row['date']}')) {
        return false;
      }
      // A calendar bucket is a date, not an instant in the device's time zone.
      final date = DateTime.tryParse('${row['date']}T00:00:00Z');
      return date != null &&
          date.toIso8601String().substring(0, 10) == row['date'] &&
          !date.isBefore(start) &&
          !date.isAfter(DateTime.utc(end.year, end.month, end.day));
    }).toList()..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    if (period != AdminDashboardPeriod.year) return selected;
    final months = <String, Map<String, dynamic>>{};
    for (final row in selected) {
      final key = '${row['date']}'.substring(0, 7);
      final bucket = months.putIfAbsent(key, () => {'date': key});
      for (final entry in row.entries) {
        if (entry.value is num && (entry.value as num).isFinite) {
          bucket[entry.key] =
              (bucket[entry.key] as num? ?? 0) + (entry.value as num);
        }
      }
    }
    return months.values.toList();
  }

  /// Business labels keep data coverage useful to an administrator.
  static const sourceNames = {
    'users': 'Accounts',
    'trails': 'Trail catalogue',
    'trailRequests': 'Trail submissions',
    'hikeSessions': 'Hiker sessions',
    'upcomingHikes': 'Scheduled plans',
    'teamHikeSessions': 'Team sessions',
    'upcomingHikeJoinRequests': 'Join requests',
    'hazardReports': 'Hazard reports',
    'sosAlerts': 'SOS alerts',
    'sosWhatsAppDispatches': 'SOS contact dispatches',
    'fcmOutbox': 'Push notification jobs',
    'trailWeatherCache': 'Shared forecasts',
    'checkpointWeather': 'Checkpoint forecasts',
    'live_location_shares': 'Live location shares',
    'appFeedback': 'Hiker feedback',
    'communityPosts': 'Community posts',
    'communityModerationReviews': 'Content reviews',
    'achievements': 'Achievement definitions',
    'userAchievements': 'Achievement awards',
  };
}

/// A metric carries its scope, availability and comparison along with its value.
class AdminDashboardMetric {
  /// Keeps formatting and trend semantics out of the card widget.
  const AdminDashboardMetric({
    required this.title,
    required this.value,
    required this.detail,
    this.unit = '',
    this.partial = false,
    this.previous,
    this.compare = false,
    this.higherIsBetter,
    this.comparisonNote,
  });
  final String title, detail, unit;
  final num? value, previous;
  final bool partial, compare;
  final bool? higherIsBetter;
  final String? comparisonNote;

  /// Formats counts and quantities while visibly marking incomplete counts.
  String get formatted => value == null
      ? '—'
      : '${partial ? '≥ ' : ''}${formatNumber(value!, decimals: unit.isNotEmpty || value != value!.round())}${unit == '%'
            ? '%'
            : unit.isEmpty
            ? ''
            : ' $unit'}';

  /// Compares rates in percentage points and quantities as percentage change.
  num? get change => value == null || previous == null
      ? null
      : unit == '%'
      ? value! - previous!
      : previous == 0
      ? value == 0
            ? 0
            : null
      : (value! - previous!) / previous! * 100;

  /// Avoids infinite growth claims when the comparison period had no activity.
  String? get comparisonLabel {
    if (!compare || value == null) return null;
    if (comparisonNote != null) return comparisonNote;
    if (partial) return 'Comparison unavailable · partial data';
    if (previous == null) return 'Previous period unavailable';
    if (previous == 0 && value! > 0 && unit != '%') {
      return 'New activity this period';
    }
    final delta = change!;
    if (delta.abs() < .05) return 'No change vs previous period';
    return '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}${unit == '%' ? ' pp' : '%'} vs previous period';
  }

  /// Uses a neutral trend for activity where more does not imply better safety.
  int get trendMeaning =>
      higherIsBetter == null || change == null || change == 0
      ? 0
      : (change! > 0) == higherIsBetter
      ? 1
      : -1;

  /// Selects the noun spoken for a chart count, retaining its qualifiers.
  static String countUnit(num count, String pluralUnit) {
    if (count != 1) return pluralUnit;
    const singularNouns = {
      'accounts': 'account',
      'awards': 'award',
      'contacts': 'contact',
      'definitions': 'definition',
      'entries': 'entry',
      'events': 'event',
      'forecasts': 'forecast',
      'jobs': 'job',
      'plans': 'plan',
      'reports': 'report',
      'requests': 'request',
      'sessions': 'session',
      'teams': 'team',
      'trails': 'trail',
    };
    final start = pluralUnit.lastIndexOf(' ') + 1;
    final noun = pluralUnit.substring(start);
    return pluralUnit.substring(0, start) + (singularNouns[noun] ?? noun);
  }

  /// Keeps full count formatting readable on dashboards without scientific notation.
  static String formatNumber(num value, {bool decimals = false}) {
    final raw = decimals && value != value.round()
        ? value.toStringAsFixed(1)
        : value.round().toString();
    final parts = raw.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return parts.length == 1 ? whole : '$whole.${parts.last}';
  }
}
