import 'package:flutter/foundation.dart';
import '../Model/admin_analytics_snapshot.dart';

/// Owns dashboard selection and derived presentation, leaving views to render it.
class AdminDashboardViewModel extends ChangeNotifier {
  /// Accepts an aggregate snapshot without performing additional client database reads.
  AdminDashboardViewModel(Map<String, dynamic>? data)
    : snapshot = data == null ? null : AdminAnalyticsSnapshot(data);
  AdminAnalyticsSnapshot? snapshot;
  AdminDashboardArea area = AdminDashboardArea.overview;
  AdminDashboardPeriod period = AdminDashboardPeriod.month;
  String trendMetric = 'hikes';

  /// Shows date controls only in areas that contain period-based analysis.
  bool get supportsPeriod =>
      area != AdminDashboardArea.trails &&
      area != AdminDashboardArea.operations;

  /// Replaces a refreshed snapshot while retaining the administrator's selections.
  void updateData(Map<String, dynamic>? data) {
    snapshot = data == null ? null : AdminAnalyticsSnapshot(data);
  }

  /// Selects a dashboard area with an appropriate initial timeline metric.
  void selectArea(AdminDashboardArea value) {
    if (area == value) return;
    area = value;
    trendMetric = value == AdminDashboardArea.people
        ? 'users'
        : value == AdminDashboardArea.safety
        ? 'hazards'
        : 'hikes';
    notifyListeners();
  }

  /// Applies one comparison range consistently across period-based sections.
  void selectPeriod(AdminDashboardPeriod value) {
    if (period != value) {
      period = value;
      notifyListeners();
    }
  }

  /// Changes the activity plotted without changing the period or other metrics.
  void selectTrend(String value) {
    if (trendSources.containsKey(value) && trendMetric != value) {
      trendMetric = value;
      notifyListeners();
    }
  }

  /// Builds a safely scoped metric from snapshot-level aggregates.
  AdminDashboardMetric metric(
    String title,
    String path,
    List<String> sources,
    String detail, {
    String unit = '',
    bool exactTotal = false,
    bool requireComplete = false,
  }) {
    final data = snapshot;
    final known = exactTotal
        ? data?.number(path) != null
        : data?.hasSources(sources) == true;
    final partial =
        known && !exactTotal && data?.completeSources(sources) != true;
    final samples = path == 'hikes.distanceKm'
        ? data?.number('hikes.distanceSamples')
        : path == 'hikes.hours'
        ? data?.number('hikes.durationSamples')
        : null;
    final missingMeasurements =
        samples != null && samples < (data?.number('hikes.completed') ?? 0);
    return AdminDashboardMetric(
      title: title,
      value: known && (!(unit == '%' || requireComplete) || !partial)
          ? data?.number(path)
          : null,
      detail: detail,
      unit: unit,
      partial:
          (partial || missingMeasurements) && !(unit == '%' || requireComplete),
    );
  }

  /// Supplies current/previous period values with the same source coverage rules.
  AdminDashboardMetric periodMetric(
    String title,
    String key,
    List<String> sources, {
    String unit = '',
    bool? higherIsBetter,
  }) {
    final data = snapshot;
    final known = data?.hasSources(sources) == true,
        complete = data?.completeSources(sources) == true;
    final sampleKey = const {
      'distanceKm': 'distanceSamples',
      'hours': 'durationSamples',
      'averageDistanceKm': 'distanceSamples',
      'averageHours': 'durationSamples',
    }[key];
    final samples = sampleKey == null
        ? null
        : data?.periodNumber(period, sampleKey);
    final missingMeasurements =
        samples != null &&
        samples < (data?.periodNumber(period, 'completedHikes') ?? 0);
    final previousSamples = sampleKey == null
        ? null
        : data?.periodNumber(period, sampleKey, previous: true);
    final previousMissing =
        previousSamples != null &&
        previousSamples <
            (data?.periodNumber(period, 'completedHikes', previous: true) ?? 0);
    final needsComplete = const {
      'completionRate',
      'contactConfirmationRate',
      'averageDistanceKm',
      'averageHours',
    }.contains(key);
    return AdminDashboardMetric(
      title: title,
      value: known && (!needsComplete || complete)
          ? data?.periodNumber(period, key)
          : null,
      previous: complete && !missingMeasurements && !previousMissing
          ? data?.periodNumber(period, key, previous: true)
          : null,
      detail:
          'Selected ${period.label.toLowerCase()}${key.startsWith('average') ? ' · measured sessions' : ''}',
      unit: unit,
      compare: true,
      partial:
          known &&
          (!complete || (missingMeasurements && !key.startsWith('average'))) &&
          unit != '%',
      higherIsBetter: higherIsBetter,
      comparisonNote: missingMeasurements || previousMissing
          ? 'Comparison unavailable · missing measurements'
          : null,
    );
  }

  /// Calculates a coverage percentage only when the relevant source was fully read.
  AdminDashboardMetric ratio(
    String title,
    String numeratorPath,
    String denominatorPath,
    List<String> sources,
    String detail,
  ) {
    final data = snapshot;
    final numerator = data?.number(numeratorPath),
        denominator = data?.number(denominatorPath);
    return AdminDashboardMetric(
      title: title,
      value:
          data?.completeSources(sources) == true &&
              numerator != null &&
              denominator != null &&
              denominator > 0
          ? numerator / denominator * 100
          : null,
      detail: detail,
      unit: '%',
    );
  }

  /// Resolves a breakdown only when its source has usable data.
  List<Map<String, dynamic>> rows(String path, List<String> sources) =>
      snapshot?.hasSources(sources) == true ? snapshot!.rows(path) : const [];

  /// Explains an empty breakdown without implying a failed source contains zero records.
  String emptyLabel(List<String> sources) =>
      snapshot?.hasSources(sources) == true
      ? 'No records in this scope.'
      : 'Analysis unavailable for this source.';

  /// Marks only usable but incomplete source reads as lower-bound counts.
  bool partial(List<String> sources) =>
      snapshot?.hasSources(sources) == true &&
      snapshot?.completeSources(sources) != true;

  /// Formats the terminal cohort without assuming missing periods contain zero hikes.
  String get periodEndedLabel {
    if (snapshot?.hasSources(['hikeSessions']) != true) return '—';
    final completed = snapshot?.periodNumber(period, 'completedHikes');
    final abandoned = snapshot?.periodNumber(period, 'abandonedHikes');
    if (completed == null || abandoned == null) return '—';
    return '${partial(['hikeSessions']) ? '≥ ' : ''}${AdminDashboardMetric.formatNumber(completed + abandoned)}';
  }

  /// Separates supported active/archived rules from retired stored definitions.
  List<Map<String, dynamic>> get definitionRows => [
    for (final entry in {
      'active': 'Active',
      'inactive': 'Archived',
      'retired': 'Retired / unsupported',
    }.entries)
      if (snapshot?.hasSources(['achievements']) == true &&
          snapshot?.number('rewards.${entry.key}') != null)
        {
          'label': entry.value,
          'value': snapshot!.number('rewards.${entry.key}'),
        },
  ];

  /// Provides a limited activity series for the selected reporting window.
  List<Map<String, dynamic>> get trendRows =>
      snapshot?.hasSources([trendSources[trendMetric]!]) == true
      ? snapshot!.series(period)
      : const [];

  /// Labels the plotted series in human terms rather than backend field names.
  String get trendLabel => trendLabels[trendMetric] ?? 'Activity';

  /// Adds a concise scope description to charts and comparisons.
  String get periodHint => '${period.label} · Malaysia time · today is partial';

  /// Discloses which completed sessions supplied quantities instead of treating missing measurements as zero.
  String get measurementCoverageLabel {
    final completed = snapshot?.periodNumber(period, 'completedHikes');
    final distances = snapshot?.periodNumber(period, 'distanceSamples');
    final durations = snapshot?.periodNumber(period, 'durationSamples');
    if (completed == null ||
        distances == null ||
        durations == null ||
        snapshot?.hasSources(['hikeSessions']) != true) {
      return 'Recorded measurement coverage is unavailable.';
    }
    return 'Among analysed completions in this period: distance is available for ${AdminDashboardMetric.formatNumber(distances)} of ${AdminDashboardMetric.formatNumber(completed)} hikes; duration for ${AdminDashboardMetric.formatNumber(durations)} of ${AdminDashboardMetric.formatNumber(completed)}. Missing values are excluded from averages.';
  }

  /// Shows the provider's latest known contact outcomes for the chosen dispatch cohort.
  List<Map<String, dynamic>> get periodContacts => [
    for (final entry in {
      'contactConfirmed': 'Confirmed',
      'contactSending': 'Sending',
      'contactUnconfirmed': 'Unconfirmed',
      'contactFailed': 'Failed',
    }.entries)
      if (snapshot?.periodNumber(period, entry.key) != null)
        {
          'label': entry.value,
          'value': snapshot!.periodNumber(period, entry.key),
        },
  ];

  /// Exposes period outcomes without recalculating database totals in widgets.
  List<Map<String, dynamic>> get periodOutcomes =>
      rows('windows.${period.days}.current.outcomes', ['hikeSessions']);

  /// Keeps missing or future-dated events visible in data-quality analysis.
  List<Map<String, dynamic>> get dateIssues =>
      snapshot
          ?.map('quality.dateIssues')
          .entries
          .map((entry) {
            final data = entry.value is Map ? entry.value as Map : const {};
            return {
              'label':
                  AdminAnalyticsSnapshot.sourceNames[entry.key] ??
                  {
                    'hikeStarts': 'Hike starts',
                    'hikeEnds': 'Hike completions',
                  }[entry.key] ??
                  'Activity dates',
              'value':
                  (data['missing'] is num ? data['missing'] as num : 0) +
                  (data['future'] is num ? data['future'] as num : 0),
            };
          })
          .where((row) => (row['value'] as num) > 0)
          .toList() ??
      const [];

  /// Restricts chart selection to metrics with a known source and public label.
  static const trendSources = {
    'hikes': 'hikeSessions',
    'users': 'users',
    'distanceKm': 'hikeSessions',
    'hazards': 'hazardReports',
    'sosAlerts': 'sosAlerts',
    'awards': 'userAchievements',
    'posts': 'communityPosts',
  };
  static const trendLabels = {
    'hikes': 'Completed hikes',
    'users': 'New accounts',
    'distanceKm': 'Distance (km)',
    'hazards': 'Hazard reports',
    'sosAlerts': 'SOS alerts',
    'awards': 'Achievement awards',
    'posts': 'Community posts',
  };
}
