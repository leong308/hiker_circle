/// The layout used for trail cards, with grid as the first-use default.
enum TrailCardView {
  list,
  grid;

  /// Restores a saved layout and falls back to grid for missing or invalid data.
  static TrailCardView fromPreference(String? value) =>
      value == list.name ? list : grid;
}
