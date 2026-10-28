/// Aggregate HikerCircle activity allowed in a host's join-request review.
class HikeJoinRequestStats {
  /// Keeps missing statistics distinct from a new hiker with no completed hikes.
  const HikeJoinRequestStats({
    this.available = false,
    this.completedHikes = 0,
    this.totalDistanceKm = 0,
    this.longestHikeKm = 0,
    this.soloHikes = 0,
    this.groupHikes = 0,
    this.hikerLevel = 1,
    this.achievementPoints = 0,
    this.unlockedAchievements = 0,
  });

  final bool available;
  final int completedHikes,
      soloHikes,
      groupHikes,
      hikerLevel,
      achievementPoints,
      unlockedAchievements;
  final double totalDistanceKm, longestHikeKm;

  /// Reads only bounded aggregate fields and ignores any private source data.
  factory HikeJoinRequestStats.fromMap(Object? value) {
    final data = value is Map ? value : const {};
    return HikeJoinRequestStats(
      available: data['available'] == true,
      completedHikes: _number(data['completedHikes']).floor(),
      totalDistanceKm: _number(data['totalDistanceKm']),
      longestHikeKm: _number(data['longestHikeKm']),
      soloHikes: _number(data['soloHikes']).floor(),
      groupHikes: _number(data['groupHikes']).floor(),
      hikerLevel: _number(data['hikerLevel']).floor().clamp(1, 1000),
      achievementPoints: _number(data['achievementPoints']).floor(),
      unlockedAchievements: _number(data['unlockedAchievements']).floor(),
    );
  }

  /// Excludes invalid or unbounded numeric values from the review.
  static double _number(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(0, 1000000000)
      : 0;
}

/// Uses a public alias without exposing phone-like names or an email address.
String safeJoinRequestAlias(Object? value) {
  final alias = value is String
      ? value
            .replaceAll(
              RegExp(
                r'[\x00-\x1f\x7f-\x9f\u2028\u2029\u202a-\u202e\u2066-\u2069]',
              ),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
      : '';
  final bounded = alias.length > 80 ? alias.substring(0, 80) : alias;
  return bounded.isEmpty ||
          RegExp(
            r'\S+@\S+|\+?\d[\d\s().-]{6,}\d|^Hiker\s+\d{4}$',
            caseSensitive: false,
          ).hasMatch(bounded)
      ? 'A hiker'
      : bounded;
}
