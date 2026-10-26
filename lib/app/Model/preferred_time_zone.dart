// PreferredTimeZone validates IANA zone IDs and formats local labels, offsets and schedule times
// consistently.
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

/// Represents preferred time zone.
abstract final class PreferredTimeZone {
  static const String fallbackId = 'Asia/Kuala_Lumpur';
  static const Map<String, String> _friendlyNames = {
    'Asia/Kuala_Lumpur': 'Malaysia / Kuala Lumpur',
  };

  static bool _initialized = false;

  /// Ensures initialized.
  static void ensureInitialized() {
    if (_initialized) return;
    time_zone_data.initializeTimeZones();
    _initialized = true;
  }

  /// Checks whether valid.
  static bool isValid(String? timeZoneId) {
    ensureInitialized();
    final normalized = timeZoneId?.trim() ?? '';
    return normalized == fallbackId ||
        (normalized.isNotEmpty &&
            time_zone.timeZoneDatabase.locations.containsKey(normalized));
  }

  /// Normalizes.
  static String normalize(String? timeZoneId) {
    final normalized = timeZoneId?.trim() ?? '';
    if (normalized == 'Asia/Kuching') return fallbackId;
    return isValid(normalized) ? normalized : fallbackId;
  }

  /// Returns all ids.
  static List<String> get allIds {
    ensureInitialized();
    final ids = time_zone.timeZoneDatabase.locations.keys.toList()..sort();
    ids.remove(fallbackId);
    ids.remove('Asia/Kuching');
    return [fallbackId, ...ids];
  }

  /// Computes compact label.
  static String compactLabel(String timeZoneId, {DateTime? at}) {
    final normalized = normalize(timeZoneId);
    final name =
        _friendlyNames[normalized] ??
        normalized.split('/').last.replaceAll('_', ' ');
    return '$name (${offsetLabel(normalized, at: at)})';
  }

  /// Computes full label.
  static String fullLabel(String timeZoneId, {DateTime? at}) {
    final normalized = normalize(timeZoneId);
    final friendly = _friendlyNames[normalized];
    return '${offsetLabel(normalized, at: at)}  '
        '${friendly ?? normalized.replaceAll('_', ' ')}'
        '${friendly == null ? '' : ' · $normalized'}';
  }

  /// Computes offset label.
  static String offsetLabel(String timeZoneId, {DateTime? at}) {
    ensureInitialized();
    final location = _location(timeZoneId);
    final instant = (at ?? DateTime.now()).toUtc();
    final offset = time_zone.TZDateTime.from(instant, location).timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final totalMinutes = offset.inMinutes.abs();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0
        ? 'GMT$sign$hours'
        : 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  /// Computes location.
  static time_zone.Location _location(String? timeZoneId) {
    final id = normalize(timeZoneId);
    // Some bundled databases omit the Kuala Lumpur alias. Keep the standard
    // ID in saved preferences and labels while resolving UTC+8 internally.
    return time_zone.getLocation(
      id == fallbackId && !time_zone.timeZoneDatabase.locations.containsKey(id)
          ? 'Asia/Kuching'
          : id,
    );
  }

  /// Formats instant.
  static String formatInstant(DateTime instant, String? timeZoneId) {
    ensureInitialized();
    final normalized = normalize(timeZoneId);
    final local = time_zone.TZDateTime.from(
      instant.toUtc(),
      _location(normalized),
    );
    const months = <String>[
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
    final second = local.second.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '$hour:$minute:$second $period '
        '(${offsetLabel(normalized, at: instant)} · $normalized)';
  }
}
