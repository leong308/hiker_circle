/// The area and normalized region resolved from a trail's starting coordinate.
class TrailStartLocation {
  /// Keeps both trail authoring flows on the same location result.
  const TrailStartLocation({
    required this.area,
    required this.state,
    required this.country,
  });

  final String area, state, country;
}
