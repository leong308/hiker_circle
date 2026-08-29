import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

abstract final class PreferredTimeZone {
  // The bundled timezone database does not expose the legacy
  // Asia/Kuala_Lumpur link on every platform. Asia/Kuching is Malaysia's
  // canonical UTC+8 zone and has the same civil time nationwide.
  static const String fallbackId = 'Asia/Kuching';
  static const Map<String, String> _friendlyNames = {
    'Asia/Kuala_Lumpur': 'Malaysia · Kuala Lumpur',
    'Asia/Kuching': 'Malaysia · Kuala Lumpur / Kuching',
  };

  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    time_zone_data.initializeTimeZones();
    _initialized = true;
  }

  static bool isValid(String? timeZoneId) {
    ensureInitialized();
    final normalized = timeZoneId?.trim() ?? '';
    return normalized.isNotEmpty &&
        time_zone.timeZoneDatabase.locations.containsKey(normalized);
  }

  static String normalize(String? timeZoneId) {
    final normalized = timeZoneId?.trim() ?? '';
    return isValid(normalized) ? normalized : fallbackId;
  }

  static List<String> get allIds {
    ensureInitialized();
    final ids = time_zone.timeZoneDatabase.locations.keys.toList()..sort();
    ids.remove(fallbackId);
    return [fallbackId, ...ids];
  }

  static String compactLabel(String timeZoneId, {DateTime? at}) {
    final normalized = normalize(timeZoneId);
    final name =
        _friendlyNames[normalized] ??
        normalized.split('/').last.replaceAll('_', ' ');
    return '$name (${offsetLabel(normalized, at: at)})';
  }

  static String fullLabel(String timeZoneId, {DateTime? at}) {
    final normalized = normalize(timeZoneId);
    final friendly = _friendlyNames[normalized];
    return '${offsetLabel(normalized, at: at)}  '
        '${friendly ?? normalized.replaceAll('_', ' ')}'
        '${friendly == null ? '' : ' · $normalized'}';
  }

  static String offsetLabel(String timeZoneId, {DateTime? at}) {
    ensureInitialized();
    final location = time_zone.getLocation(normalize(timeZoneId));
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

  static String formatInstant(DateTime instant, String? timeZoneId) {
    ensureInitialized();
    final normalized = normalize(timeZoneId);
    final local = time_zone.TZDateTime.from(
      instant.toUtc(),
      time_zone.getLocation(normalized),
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
