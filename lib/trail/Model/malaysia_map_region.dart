/// Generous camera framing presets, not administrative boundaries or trail data.
/// These values must never be used to infer a selected pin's state/country.
enum MalaysiaMapRegion {
  peninsula('Peninsular Malaysia', 98.9, 1.0, 104.8, 6.9),
  johor('Johor', 102.4, 1.15, 104.6, 3.0),
  kedah('Kedah', 99.5, 5.0, 101.25, 6.6),
  kelantan('Kelantan', 101.3, 4.5, 102.7, 6.3),
  melaka('Melaka', 101.8, 2.0, 102.65, 2.55),
  negeriSembilan('Negeri Sembilan', 101.65, 2.35, 102.75, 3.3),
  pahang('Pahang', 101.3, 2.4, 104.3, 4.9),
  penang('Penang', 100.1, 5.1, 100.6, 5.6),
  perak('Perak', 100.1, 3.6, 101.8, 6.0),
  perlis('Perlis', 100.05, 6.2, 100.65, 6.75),
  sabah('Sabah', 115.1, 3.9, 119.4, 7.5),
  sarawak('Sarawak', 109.5, 0.8, 115.8, 5.1),
  selangor('Selangor', 100.7, 2.5, 102.0, 3.9),
  terengganu('Terengganu', 102.35, 3.8, 103.7, 6.0),
  kualaLumpur('Kuala Lumpur (Federal Territory)', 101.58, 3.02, 101.79, 3.26),
  labuan('Labuan (Federal Territory)', 115.1, 5.15, 115.35, 5.4),
  putrajaya('Putrajaya (Federal Territory)', 101.64, 2.86, 101.75, 2.982445);

  /// Creates this model.
  const MalaysiaMapRegion(
    this.label,
    this.west,
    this.south,
    this.east,
    this.north,
  );
  final String label;
  final double west, south, east, north;

  /// Dataset key for drawing only; not a saved trail state.
  String? get boundaryIso => switch (this) {
    peninsula => null,
    johor => 'MY-01',
    kedah => 'MY-02',
    kelantan => 'MY-03',
    melaka => 'MY-04',
    negeriSembilan => 'MY-05',
    pahang => 'MY-06',
    penang => 'MY-07',
    perak => 'MY-08',
    perlis => 'MY-09',
    selangor => 'MY-10',
    terengganu => 'MY-11',
    sabah => 'MY-12',
    sarawak => 'MY-13',
    kualaLumpur => 'MY-14',
    labuan => 'MY-15',
    putrajaya => 'MY-16',
  };

  /// Returns longitude.
  double get longitude => (west + east) / 2;

  /// Returns latitude.
  double get latitude => (south + north) / 2;
}
