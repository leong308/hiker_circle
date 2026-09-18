class RouteGearAssessment {
  const RouteGearAssessment({
    required this.routeKey,
    required this.checkedAt,
    required this.status,
    this.featureCount = 0,
    this.waterNearby = false,
    this.possibleCrossing = false,
    this.rough = false,
    this.muddy = false,
    this.technical = false,
    this.surfaceMapped = false,
  });
  final String routeKey, status;
  final DateTime checkedAt;
  final int featureCount;
  final bool waterNearby,
      possibleCrossing,
      rough,
      muddy,
      technical,
      surfaceMapped;
  bool get isFresh =>
      DateTime.now().difference(checkedAt) < const Duration(days: 7);
  bool get usable => status == 'complete' || status == 'partial';
  Map<String, dynamic> toJson() => {
    'routeKey': routeKey,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'status': status,
    'featureCount': featureCount,
    'waterNearby': waterNearby,
    'possibleCrossing': possibleCrossing,
    'rough': rough,
    'muddy': muddy,
    'technical': technical,
    'surfaceMapped': surfaceMapped,
  };
  factory RouteGearAssessment.fromJson(Map data) => RouteGearAssessment(
    routeKey: data['routeKey'] as String,
    checkedAt: DateTime.parse(data['checkedAt'] as String),
    status: data['status'] as String,
    featureCount: (data['featureCount'] as num?)?.toInt() ?? 0,
    waterNearby: data['waterNearby'] == true,
    possibleCrossing: data['possibleCrossing'] == true,
    rough: data['rough'] == true,
    muddy: data['muddy'] == true,
    technical: data['technical'] == true,
    surfaceMapped: data['surfaceMapped'] == true,
  );
}
