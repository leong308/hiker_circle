import '../../app/Model/preferred_time_zone.dart';

/// Identifies each point in the departure reminder timeline.
enum HikeReminderTimelineKind { now, reminder, start }

/// Supplies one chronological point without formatting dates in the view.
class HikeReminderTimelineEntry {
  /// Creates a point with its display labels in the hiker's selected time zone.
  HikeReminderTimelineEntry({
    required this.kind,
    required this.instant,
    required this.title,
    required String timeZoneId,
    required DateTime now,
    this.detail,
  }) : timeLabel = _timeLabel(instant, now, timeZoneId);

  final HikeReminderTimelineKind kind;
  final DateTime instant;
  final String title;
  final String timeLabel;
  final String? detail;

  /// Keeps dates explicit across midnight, years and daylight-saving changes.
  static String _timeLabel(DateTime instant, DateTime now, String zone) {
    final local = PreferredTimeZone.localDateTime(instant, zone);
    final current = PreferredTimeZone.localDateTime(now, zone);
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
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final year = local.year == current.year ? '' : ' ${local.year}';
    final offset = local.timeZoneOffset == current.timeZoneOffset
        ? ''
        : ' (${PreferredTimeZone.offsetLabel(zone, at: instant)})';
    return '${local.day} ${months[local.month - 1]}$year · '
        '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}$offset';
  }
}

/// Labels reminder offsets consistently in the editor and timeline.
String hikeReminderDurationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return '$hours hour${hours == 1 ? '' : 's'}';
  }
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
