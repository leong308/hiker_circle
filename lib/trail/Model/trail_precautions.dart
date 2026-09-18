import 'trail_models.dart';

class TrailPrecaution {
  const TrailPrecaution(this.id, this.priority, this.title, this.message);
  final String id;
  final int priority;
  final String title;
  final String message;
}

/// Pure rules; missing values never become zero or a safety clearance.
List<TrailPrecaution> trailPrecautions({
  required TrailWeather weather,
  required int day,
  required DateTime now,
  int elevationGain = 0,
  int durationMinutes = 0,
  int? departureMinute,
  DateTime? assessmentStart,
  DateTime? assessmentEnd,
}) {
  final result = <TrailPrecaution>[];
  void add(String id, int priority, String title, String message) =>
      result.add(TrailPrecaution(id, priority, title, message));
  final data = weather.forecastData;
  final daily = data['daily'] is Map ? data['daily'] as Map : const {};
  final hourly = data['hourly'] is Map ? data['hourly'] as Map : const {};
  num? read(Map map, String key, int index) {
    final list = map[key];
    if (list is! List || index < 0 || index >= list.length) return null;
    final v = list[index];
    return v is num && v.isFinite ? v : null;
  }

  final midnight = read(daily, 'time', day);
  final start = midnight == null
      ? null
      : midnight + (departureMinute ?? 0) * 60;
  final finish = start == null
      ? null
      : departureMinute == null
      ? start + 86400
      : start + (durationMinutes + 60) * 60;
  final assessmentFrom = assessmentStart != null
      ? assessmentStart.toUtc().millisecondsSinceEpoch / 1000
      : start;
  final assessmentTo = assessmentEnd != null
      ? assessmentEnd.toUtc().millisecondsSinceEpoch / 1000
      : finish;
  final times = hourly['time'] is List ? hourly['time'] as List : const [];
  final rows = <int>[];
  for (var i = 0; i < times.length; i++) {
    final time = read(hourly, 'time', i);
    if (time != null &&
        assessmentFrom != null &&
        assessmentTo != null &&
        time + 3600 > assessmentFrom &&
        time < assessmentTo) {
      rows.add(i);
    }
  }
  num? peak(String key) {
    final values = rows.map((i) => read(hourly, key, i)).whereType<num>();
    return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  }

  bool any(bool Function(int) predicate) => rows.any(predicate);
  String metric(String key, String unit) => peak(key) == null
      ? 'unavailable'
      : '${peak(key)!.toStringAsFixed(0)}$unit';
  final stale = now.toUtc().difference(weather.cachedAt.toUtc()).inHours >= 4;
  final requiredKeys = [
    'temperature_2m',
    'relative_humidity_2m',
    'apparent_temperature',
    'precipitation',
    'precipitation_probability',
    'weather_code',
    'wind_speed_10m',
    'wind_gusts_10m',
    'visibility',
    'uv_index',
  ];
  final incomplete =
      rows.isEmpty ||
      (assessmentFrom != null &&
          rows.isNotEmpty &&
          (read(hourly, 'time', rows.first) ?? double.infinity) >
              assessmentFrom) ||
      rows
          .skip(1)
          .any(
            (i) =>
                read(hourly, 'time', i - 1) == null ||
                read(hourly, 'time', i)! - read(hourly, 'time', i - 1)! != 3600,
          ) ||
      requiredKeys.any(
        (key) => rows.any((i) => read(hourly, key, i) == null),
      ) ||
      (assessmentTo != null &&
          (times.isEmpty ||
              (read(hourly, 'time', times.length - 1) ?? 0) + 3600 <
                  assessmentTo));
  if (stale || incomplete) {
    add(
      'data',
      3,
      'Conditions could not be fully assessed',
      '${stale ? 'Forecast is over four hours old. ' : ''}${incomplete ? 'Some forecast hours or measurements are unavailable. ' : ''}Refresh weather and check official warnings before departure.',
    );
  }
  final thunder = any(
    (i) => [95, 96, 99].contains(read(hourly, 'weather_code', i)),
  );
  final heavy = any(
    (i) =>
        (read(hourly, 'precipitation', i) ?? -1) >= 10 ||
        [65, 67, 82].contains(read(hourly, 'weather_code', i)),
  );
  final rain = (peak('precipitation_probability') ?? -1) > 50;
  if (thunder) {
    add(
      'storm',
      3,
      'Thunderstorms forecast — consider postponing',
      'Avoid exposed ridges, summits and water. Seek a substantial building or enclosed vehicle, not an isolated tree.',
    );
  }
  if (heavy) {
    add(
      'rain',
      3,
      'Heavy rain may affect trail access',
      'Peak forecast rainfall: ${metric('precipitation', ' mm/h')}. Consider postponing; avoid streams, gullies and unstable slopes. Check closures.',
    );
  } else if (rain) {
    add(
      'rain',
      1,
      'Wet trail expected',
      'Peak rain chance: ${metric('precipitation_probability', '%')}. Expect slippery roots and rocks; protect essential gear. Rain chance is not rainfall intensity.',
    );
  }
  final humidHeat = any(
    (i) =>
        (read(hourly, 'temperature_2m', i) ?? -100) >= 30 &&
        (read(hourly, 'relative_humidity_2m', i) ?? -1) >= 80,
  );
  final hot = any(
    (i) =>
        (read(hourly, 'temperature_2m', i) ?? -100) >= 32 ||
        (read(hourly, 'apparent_temperature', i) ?? -100) >= 35,
  );
  if (hot || humidHeat) {
    add(
      'heat',
      2,
      humidHeat ? 'Heat and humidity increase strain' : 'Heat stress risk',
      'Peak temperature: ${metric('temperature_2m', '°C')}; feels like: ${metric('apparent_temperature', '°C')}.${elevationGain >= 500 ? ' The $elevationGain m ascent adds exertion.' : ''} Slow down, rest in shade and carry drinking water. Stop if dizzy or unusually fatigued.',
    );
  }
  if (any(
    (i) =>
        read(hourly, 'temperature_2m', i) != null &&
        read(hourly, 'temperature_2m', i)! <= 15 &&
        ((read(hourly, 'precipitation', i) ?? -1) > 0 ||
            (read(hourly, 'wind_speed_10m', i) ?? -1) >= 20),
  )) {
    add(
      'cold',
      2,
      'Risk of getting cold when wet',
      'Pack a waterproof outer layer and dry clothing. Avoid prolonged exposed stops.',
    );
  }
  if ((peak('wind_speed_10m') ?? -1) >= 25 ||
      (peak('wind_gusts_10m') ?? -1) >= 40) {
    add(
      'wind',
      (peak('wind_gusts_10m') ?? -1) >= 60 ? 3 : 2,
      'Strong winds expected',
      'Peak wind: ${metric('wind_speed_10m', ' km/h')}; gusts: ${metric('wind_gusts_10m', ' km/h')}. Avoid exposed sections and damaged trees; gusts may affect balance.',
    );
  }
  if (elevationGain >= 500 && !hot && !humidHeat) {
    add(
      'ascent',
      elevationGain >= 1000 ? 2 : 1,
      'Demanding ascent',
      'This route climbs $elevationGain m. Pace yourself, allow extra breaks and save energy for the descent.',
    );
  }
  if ((peak('uv_index') ?? -1) >= 3) {
    add(
      'uv',
      (peak('uv_index') ?? -1) >= 8 ? 2 : 1,
      'Sun protection needed',
      'Peak UV: ${metric('uv_index', '')}. Use sun protection and shade; minimise prolonged exposure.',
    );
  }
  if (any(
    (i) =>
        [45, 48].contains(read(hourly, 'weather_code', i)) ||
        (read(hourly, 'visibility', i) != null &&
            read(hourly, 'visibility', i)! < 1000),
  )) {
    add(
      'visibility',
      2,
      'Navigation may be difficult',
      'Fog or poor visibility may obscure markers and edges. Download the route and keep your group together.',
    );
  }
  String clock(num epoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      ((epoch + ((data['utc_offset_seconds'] as num?) ?? 0)) * 1000).round(),
      isUtc: true,
    );
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  if (departureMinute != null && start != null && durationMinutes > 0) {
    final sunset = read(daily, 'sunset', day);
    final sunrise = read(daily, 'sunrise', day);
    final end = start + durationMinutes * 60;
    if (sunset == null || sunrise == null) {
      add(
        'daylight-data',
        2,
        'Daylight timing unavailable',
        'Sunrise or sunset data is missing. Check daylight before departure.',
      );
    } else if (start < sunrise || end >= sunset) {
      add(
        'dark',
        3,
        start < sunrise
            ? (end >= sunset
                  ? 'Hike overlaps darkness'
                  : 'Departure is before sunrise')
            : start >= sunset
            ? 'Departure is after sunset'
            : end == sunset
            ? 'Estimated finish is at sunset'
            : 'Hike extends past sunset',
        '${start < sunrise ? 'Departure: ${clock(start)}; sunrise: ${clock(sunrise)}. ' : ''}'
            '${end >= sunset ? 'Estimated finish: ${clock(end)}; sunset: ${clock(sunset)}. ' : 'Estimated finish: ${clock(end)}. '}'
            'Carry a headlamp and spare power.${end > sunset ? ' Consider an earlier departure or a shorter route to finish before sunset.' : ''}',
      );
    } else if (end >= sunset - 3600) {
      add(
        'sunset',
        2,
        'Limited daylight buffer',
        'Estimated finish: ${clock(end)}; sunset: ${clock(sunset)}. Allow for delays and carry a headlamp with spare power.',
      );
    }
  }
  if (durationMinutes >= 240) {
    add(
      'duration',
      1,
      'Plan for a longer hike',
      'Estimated hiking time: ${(durationMinutes / 60).toStringAsFixed(1)} hours, before delays. Carry food, water and backup power; share your return time.',
    );
  }
  result.sort((a, b) {
    final priority = b.priority.compareTo(a.priority);
    return priority == 0 ? a.id.compareTo(b.id) : priority;
  });
  return result;
}
