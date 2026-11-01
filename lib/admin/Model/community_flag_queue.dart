import 'community_flag.dart';

/// Limits the queue to the requested kind of public community content.
enum CommunityFlagContentFilter {
  all('All content'),
  post('Posts'),
  comment('Comments');

  /// Associates a content choice with its visible label.
  const CommunityFlagContentFilter(this.label);
  final String label;
}

/// Orders loaded flags without claiming that unloaded records were searched.
enum CommunityFlagSort {
  newest('Newest first'),
  oldest('Oldest first'),
  priority('Highest priority');

  /// Associates a sorting choice with its visible label.
  const CommunityFlagSort(this.label);
  final String label;
}

/// Holds the applied queue controls separately from the filter sheet's draft.
class CommunityFlagFilters {
  /// Defaults to all pending content, newest first.
  const CommunityFlagFilters({
    this.source = CommunityFlagSourceFilter.all,
    this.content = CommunityFlagContentFilter.all,
    this.sort = CommunityFlagSort.newest,
  });

  final CommunityFlagSourceFilter source;
  final CommunityFlagContentFilter content;
  final CommunityFlagSort sort;

  /// Shows a filter indicator only when a default control was changed.
  bool get isActive =>
      source != CommunityFlagSourceFilter.all ||
      content != CommunityFlagContentFilter.all ||
      sort != CommunityFlagSort.newest;

  /// Summarizes controls in the queue without a wall of dropdowns.
  String get description =>
      '${content.label} · ${source.label} · ${sort.label}';

  /// Filters and sorts the loaded pending records without mutating their data.
  List<CommunityFlag> apply(Iterable<CommunityFlag> flags, String query) {
    final visible = flags
        .where(
          (flag) =>
              flag.matchesSource(source) &&
              (content == CommunityFlagContentFilter.all ||
                  flag.isComment ==
                      (content == CommunityFlagContentFilter.comment)) &&
              flag.matchesQuery(query),
        )
        .toList();
    visible.sort((a, b) {
      if (sort == CommunityFlagSort.priority) {
        final priority = _priority(b).compareTo(_priority(a));
        if (priority != 0) return priority;
      }
      final left = a.flaggedAt?.millisecondsSinceEpoch ?? 0;
      final right = b.flaggedAt?.millisecondsSinceEpoch ?? 0;
      final time = sort == CommunityFlagSort.oldest
          ? left.compareTo(right)
          : right.compareTo(left);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return visible;
  }

  /// Keeps urgency sorting independent from display colours.
  static int _priority(CommunityFlag flag) => switch (flag.severity) {
    'critical' => 4,
    'high' => 3,
    'medium' => 2,
    'low' => 1,
    _ => 0,
  };
}
