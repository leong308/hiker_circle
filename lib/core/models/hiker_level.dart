class HikerLevel {
  const HikerLevel({
    required this.number,
    required this.name,
    required this.minimumPoints,
    required this.nextLevelPoints,
  });

  final int number;
  final String name;
  final int minimumPoints;
  final int? nextLevelPoints;

  String get badgeLabel => 'Lv. $number $name';

  double progressFor(int points) {
    final next = nextLevelPoints;
    if (next == null) {
      return 1;
    }
    final span = next - minimumPoints;
    if (span <= 0) {
      return 1;
    }
    return ((points - minimumPoints) / span).clamp(0, 1).toDouble();
  }

  int pointsToNextLevel(int points) {
    final next = nextLevelPoints;
    if (next == null) {
      return 0;
    }
    return (next - points).clamp(0, next);
  }

  static const List<HikerLevel> tiers = [
    HikerLevel(
      number: 1,
      name: 'Trailhead',
      minimumPoints: 0,
      nextLevelPoints: 250,
    ),
    HikerLevel(
      number: 2,
      name: 'Pathfinder',
      minimumPoints: 250,
      nextLevelPoints: 600,
    ),
    HikerLevel(
      number: 3,
      name: 'Trekker',
      minimumPoints: 600,
      nextLevelPoints: 1200,
    ),
    HikerLevel(
      number: 4,
      name: 'Summit Seeker',
      minimumPoints: 1200,
      nextLevelPoints: 2200,
    ),
    HikerLevel(
      number: 5,
      name: 'Trail Expert',
      minimumPoints: 2200,
      nextLevelPoints: 3500,
    ),
    HikerLevel(
      number: 6,
      name: 'Mountain Guardian',
      minimumPoints: 3500,
      nextLevelPoints: 5500,
    ),
    HikerLevel(
      number: 7,
      name: 'HikerCircle Elite',
      minimumPoints: 5500,
      nextLevelPoints: null,
    ),
  ];

  static HikerLevel fromPoints(int points) {
    final normalized = points < 0 ? 0 : points;
    for (final tier in tiers.reversed) {
      if (normalized >= tier.minimumPoints) {
        return tier;
      }
    }
    return tiers.first;
  }
}
