part of '../trail_rating_dialog_feature.dart';

/// Represents trail rating feedback.
class TrailRatingFeedback {
  /// Creates trail rating feedback.
  const TrailRatingFeedback({
    required this.rating,
    required this.difficulty,
    required this.comment,
  });

  final int rating;
  final String difficulty;
  final String comment;
}
