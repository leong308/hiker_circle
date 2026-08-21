class TrailCheckpoint {
  const TrailCheckpoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.order,
  });

  factory TrailCheckpoint.fromPersistence(Map<String, dynamic> data) {
    return TrailCheckpoint(
      name: _trailStringFrom(data['name']),
      latitude: _trailDoubleFrom(data['latitude']),
      longitude: _trailDoubleFrom(data['longitude']),
      order: _trailIntFrom(data['order']),
    );
  }

  final String name;
  final double latitude;
  final double longitude;
  final int order;

  bool get hasValidCoordinate =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'order': order,
    };
  }

  TrailCheckpoint copyWith({
    String? name,
    double? latitude,
    double? longitude,
    int? order,
  }) {
    return TrailCheckpoint(
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      order: order ?? this.order,
    );
  }
}

class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.precipitationProbability,
    required this.weatherCode,
  });

  final DateTime time;
  final double temperature;
  final int precipitationProbability;
  final int weatherCode;

  factory HourlyForecast.fromPersistence(Map<String, dynamic> data) {
    return HourlyForecast(
      time:
          _trailDateFrom(data['timeLocal']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      temperature: _trailDoubleFrom(data['temperature']),
      precipitationProbability: _trailIntFrom(data['precipitationProbability']),
      weatherCode: _trailIntFrom(data['weatherCode']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'timeLocal': time.toUtc().toIso8601String(),
      'temperature': temperature,
      'precipitationProbability': precipitationProbability,
      'weatherCode': weatherCode,
    };
  }

  String get weatherLabel => _wmoSummary(weatherCode);
}

class TrailWeather {
  const TrailWeather({
    required this.summary,
    required this.temperatureRange,
    required this.rainProbability,
    required this.cachedAt,
    this.humidity,
    this.windSpeed,
    this.uvIndex,
    this.feelsLike,
    this.hourlyForecast = const [],
  });

  final String summary;
  final String temperatureRange;
  final int rainProbability;
  final DateTime cachedAt;
  final int? humidity;
  final double? windSpeed;
  final double? uvIndex;
  final double? feelsLike;
  final List<HourlyForecast> hourlyForecast;

  factory TrailWeather.fromPersistence(Map<String, dynamic> data) {
    return TrailWeather(
      summary: _trailStringFrom(data['summary']),
      temperatureRange: _trailStringFrom(data['temperatureRange']),
      rainProbability: _trailIntFrom(data['rainProbability']),
      cachedAt:
          _trailDateFrom(data['cachedAtLocal']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      humidity: _trailNullableIntFrom(data['humidity']),
      windSpeed: _trailNullableDoubleFrom(data['windSpeed']),
      uvIndex: _trailNullableDoubleFrom(data['uvIndex']),
      feelsLike: _trailNullableDoubleFrom(data['feelsLike']),
      hourlyForecast: _trailListOfMaps(
        data['hourlyForecast'],
      ).map(HourlyForecast.fromPersistence).toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'summary': summary,
      'temperatureRange': temperatureRange,
      'rainProbability': rainProbability,
      'cachedAtLocal': cachedAt.toUtc().toIso8601String(),
      if (humidity != null) 'humidity': humidity,
      if (windSpeed != null) 'windSpeed': windSpeed,
      if (uvIndex != null) 'uvIndex': uvIndex,
      if (feelsLike != null) 'feelsLike': feelsLike,
      if (hourlyForecast.isNotEmpty)
        'hourlyForecast': hourlyForecast.map((h) => h.toFirestore()).toList(),
    };
  }

  bool get isStale {
    return DateTime.now().toUtc().difference(cachedAt.toUtc()).inHours >= 4;
  }
}

String _wmoSummary(int code) {
  const mapping = {
    0: 'Clear sky',
    1: 'Mainly clear',
    2: 'Partly cloudy',
    3: 'Cloudy',
    45: 'Foggy',
    48: 'Depositing rime fog',
    51: 'Light drizzle',
    53: 'Moderate drizzle',
    55: 'Dense drizzle',
    56: 'Light freezing drizzle',
    57: 'Dense freezing drizzle',
    61: 'Slight rain',
    63: 'Moderate rain',
    65: 'Heavy rain',
    66: 'Light freezing rain',
    67: 'Heavy freezing rain',
    71: 'Slight snow',
    73: 'Moderate snow',
    75: 'Heavy snow',
    77: 'Snow grains',
    80: 'Slight rain showers',
    81: 'Moderate rain showers',
    82: 'Violent rain showers',
    85: 'Slight snow showers',
    86: 'Heavy snow showers',
    95: 'Thunderstorm',
    96: 'Thunderstorm with slight hail',
    99: 'Thunderstorm with heavy hail',
  };
  return mapping[code] ?? 'Unknown';
}

class TrailHazard {
  const TrailHazard({
    required this.type,
    required this.description,
    required this.severity,
    required this.locationLabel,
    required this.reportedAt,
  });

  final String type;
  final String description;
  final String severity;
  final String locationLabel;
  final DateTime reportedAt;

  factory TrailHazard.fromPersistence(Map<String, dynamic> data) {
    return TrailHazard(
      type: _trailStringFrom(data['type']),
      description: _trailStringFrom(data['description']),
      severity: _trailStringFrom(data['severity']),
      locationLabel: _trailStringFrom(data['locationLabel']),
      reportedAt:
          _trailDateFrom(data['reportedAtLocal']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'description': description,
      'severity': severity,
      'locationLabel': locationLabel,
      'reportedAtLocal': reportedAt.toUtc().toIso8601String(),
    };
  }
}

class Trail {
  const Trail({
    required this.trailId,
    required this.name,
    required this.area,
    required this.state,
    this.country = '',
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.difficulty,
    required this.estimatedDurationMinutes,
    required this.elevationGainMeters,
    required this.ratingAverage,
    required this.offlineMapAvailable,
    required this.offlineMapDownloaded,
    required this.isVerifiedTrail,
    required this.routeFilePath,
    required this.coverColorValue,
    this.coverImageUrls = const <String>[],
    required this.checkpoints,
    required this.weather,
    required this.hazards,
    this.routeEncodedPolyline,
    this.routeCheckpointsHash,
  });

  factory Trail.fromPersistence(Map<String, dynamic> data) {
    final coverValue = data['coverImageUrl'] ?? data['coverImageUrls'];
    final coverImageUrls = switch (coverValue) {
      String value when value.trim().isNotEmpty => <String>[value.trim()],
      Iterable values =>
        values
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
      _ => <String>[],
    };
    final checkpoints =
        _trailListOfMaps(data['checkpoints'])
            .where(_trailCheckpointMapHasValidCoordinate)
            .map(TrailCheckpoint.fromPersistence)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return Trail(
      trailId: _trailStringFrom(data['trailId']),
      name: _trailStringFrom(data['name']),
      area: _trailStringFrom(data['area']),
      state: _trailStringFrom(data['state']),
      country: _trailStringFrom(data['country']),
      latitude: _trailDoubleFrom(data['latitude']),
      longitude: _trailDoubleFrom(data['longitude']),
      distanceKm: _trailDoubleFrom(data['distanceKm']),
      difficulty: _trailDifficultyFrom(data['difficulty']),
      estimatedDurationMinutes: _trailIntFrom(data['estimatedDurationMinutes']),
      elevationGainMeters: _trailIntFrom(data['elevationGainMeters']),
      ratingAverage: _trailDoubleFrom(data['ratingAverage']),
      offlineMapAvailable: data['offlineMapAvailable'] == true,
      offlineMapDownloaded: data['offlineMapDownloaded'] == true,
      isVerifiedTrail: data['isVerifiedTrail'] == true,
      routeFilePath: _trailStringFrom(data['routeFilePath']),
      coverColorValue: _trailIntFrom(data['coverColorValue']),
      coverImageUrls: coverImageUrls,
      checkpoints: checkpoints,
      weather: TrailWeather.fromPersistence(_trailMapFrom(data['weather'])),
      hazards: _trailListOfMaps(
        data['hazards'],
      ).map(TrailHazard.fromPersistence).toList(),
      routeEncodedPolyline: _trailNullableStringFrom(
        data['routeEncodedPolyline'],
      ),
      routeCheckpointsHash: _trailNullableStringFrom(
        data['routeCheckpointsHash'],
      ),
    );
  }

  final String trailId;
  final String name;
  final String area;
  final String state;
  final String country;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String difficulty;
  final int estimatedDurationMinutes;
  final int elevationGainMeters;
  final double ratingAverage;
  final bool offlineMapAvailable;
  final bool offlineMapDownloaded;
  final bool isVerifiedTrail;
  final String routeFilePath;
  final int coverColorValue;
  final List<String> coverImageUrls;

  String get coverImageUrl =>
      coverImageUrls.isNotEmpty ? coverImageUrls.first : '';
  final List<TrailCheckpoint> checkpoints;
  final TrailWeather weather;
  final List<TrailHazard> hazards;
  final String? routeEncodedPolyline;
  final String? routeCheckpointsHash;

  Map<String, dynamic> toFirestore() {
    return {
      'trailId': trailId,
      'name': name,
      'area': area,
      'state': state,
      if (country.trim().isNotEmpty) 'country': country.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'distanceKm': distanceKm,
      'difficulty': difficulty.toLowerCase(),
      'estimatedDurationMinutes': estimatedDurationMinutes,
      'elevationGainMeters': elevationGainMeters,
      'ratingAverage': ratingAverage,
      'offlineMapAvailable': offlineMapAvailable,
      'offlineMapDownloaded': offlineMapDownloaded,
      'isVerifiedTrail': isVerifiedTrail,
      'routeFilePath': routeFilePath,
      'coverColorValue': coverColorValue,
      'coverImageUrl': coverImageUrls,
      'checkpoints': checkpoints
          .where((checkpoint) => checkpoint.hasValidCoordinate)
          .map((checkpoint) => checkpoint.toFirestore())
          .toList(),
      'weather': weather.toFirestore(),
      'hazards': hazards.map((hazard) => hazard.toFirestore()).toList(),
      if (routeEncodedPolyline != null)
        'routeEncodedPolyline': routeEncodedPolyline,
      if (routeCheckpointsHash != null)
        'routeCheckpointsHash': routeCheckpointsHash,
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toPersistence() {
    return {...toFirestore(), 'difficulty': difficulty};
  }

  String get locationLabel => [
    area,
    state,
    country,
  ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(', ');

  String get durationLabel {
    final hours = estimatedDurationMinutes ~/ 60;
    final minutes = estimatedDurationMinutes % 60;
    if (hours == 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}m';
  }

  String get distanceLabel => '${distanceKm.toStringAsFixed(1)} km';

  Trail copyWith({
    String? trailId,
    String? name,
    String? area,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    double? distanceKm,
    String? difficulty,
    int? estimatedDurationMinutes,
    int? elevationGainMeters,
    double? ratingAverage,
    bool? offlineMapAvailable,
    bool? offlineMapDownloaded,
    bool? isVerifiedTrail,
    String? routeFilePath,
    int? coverColorValue,
    List<String>? coverImageUrls,
    List<TrailCheckpoint>? checkpoints,
    TrailWeather? weather,
    List<TrailHazard>? hazards,
    String? routeEncodedPolyline,
    String? routeCheckpointsHash,
  }) {
    return Trail(
      trailId: trailId ?? this.trailId,
      name: name ?? this.name,
      area: area ?? this.area,
      state: state ?? this.state,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceKm: distanceKm ?? this.distanceKm,
      difficulty: difficulty ?? this.difficulty,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      ratingAverage: ratingAverage ?? this.ratingAverage,
      offlineMapAvailable: offlineMapAvailable ?? this.offlineMapAvailable,
      offlineMapDownloaded: offlineMapDownloaded ?? this.offlineMapDownloaded,
      isVerifiedTrail: isVerifiedTrail ?? this.isVerifiedTrail,
      routeFilePath: routeFilePath ?? this.routeFilePath,
      coverColorValue: coverColorValue ?? this.coverColorValue,
      coverImageUrls: coverImageUrls ?? this.coverImageUrls,
      checkpoints: checkpoints ?? this.checkpoints,
      weather: weather ?? this.weather,
      hazards: hazards ?? this.hazards,
      routeEncodedPolyline: routeEncodedPolyline ?? this.routeEncodedPolyline,
      routeCheckpointsHash: routeCheckpointsHash ?? this.routeCheckpointsHash,
    );
  }
}

Map<String, dynamic> _trailMapFrom(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : const {};
}

List<Map<String, dynamic>> _trailListOfMaps(Object? value) {
  if (value is! Iterable) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _trailStringFrom(Object? value) => value is String ? value : '';

String? _trailNullableStringFrom(Object? value) {
  final result = _trailStringFrom(value).trim();
  return result.isEmpty ? null : result;
}

int _trailIntFrom(Object? value) =>
    value is num && value.isFinite ? value.toInt() : 0;

int? _trailNullableIntFrom(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

double _trailDoubleFrom(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : 0;

double? _trailNullableDoubleFrom(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

bool _trailCheckpointMapHasValidCoordinate(Map<String, dynamic> data) {
  final latitude = data['latitude'];
  final longitude = data['longitude'];
  return latitude is num &&
      longitude is num &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

String _trailDifficultyFrom(Object? value) {
  switch (_trailStringFrom(value).trim().toLowerCase()) {
    case 'easy':
      return 'Easy';
    case 'hard':
      return 'Hard';
    case 'expert':
      return 'Expert';
    case 'moderate':
    case 'medium':
    default:
      return 'Moderate';
  }
}

DateTime? _trailDateFrom(Object? value) {
  if (value is DateTime) {
    return value;
  }
  return value is String ? DateTime.tryParse(value) : null;
}
