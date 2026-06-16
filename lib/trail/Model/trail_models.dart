class TrailCheckpoint {
  const TrailCheckpoint({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.order,
  });

  final String name;
  final double latitude;
  final double longitude;
  final int order;

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'order': order,
    };
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
    this.coverImageUrl = '',
    required this.checkpoints,
    required this.weather,
    required this.hazards,
  });

  final String trailId;
  final String name;
  final String area;
  final String state;
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
  final String coverImageUrl;
  final List<TrailCheckpoint> checkpoints;
  final TrailWeather weather;
  final List<TrailHazard> hazards;

  Map<String, dynamic> toFirestore() {
    return {
      'trailId': trailId,
      'name': name,
      'area': area,
      'state': state,
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
      'coverImageUrl': coverImageUrl.trim(),
      'checkpoints': checkpoints
          .map((checkpoint) => checkpoint.toFirestore())
          .toList(),
      'weather': weather.toFirestore(),
      'hazards': hazards.map((hazard) => hazard.toFirestore()).toList(),
      'updatedAtLocal': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String get locationLabel => '$area, $state';

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
    String? coverImageUrl,
    List<TrailCheckpoint>? checkpoints,
    TrailWeather? weather,
    List<TrailHazard>? hazards,
  }) {
    return Trail(
      trailId: trailId ?? this.trailId,
      name: name ?? this.name,
      area: area ?? this.area,
      state: state ?? this.state,
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
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      checkpoints: checkpoints ?? this.checkpoints,
      weather: weather ?? this.weather,
      hazards: hazards ?? this.hazards,
    );
  }
}
