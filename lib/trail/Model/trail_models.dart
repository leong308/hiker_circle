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

class TrailWeather {
  const TrailWeather({
    required this.summary,
    required this.temperatureRange,
    required this.rainProbability,
    required this.cachedAt,
  });

  final String summary;
  final String temperatureRange;
  final int rainProbability;
  final DateTime cachedAt;

  Map<String, dynamic> toFirestore() {
    return {
      'summary': summary,
      'temperatureRange': temperatureRange,
      'rainProbability': rainProbability,
      'cachedAtLocal': cachedAt.toUtc().toIso8601String(),
    };
  }
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
}
