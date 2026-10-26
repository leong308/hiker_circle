part of '../admin_page_feature.dart';

/// Represents firestore collection.
class _FirestoreCollection {
  /// Creates firestore collection.
  const _FirestoreCollection({
    required this.name,
    required this.documents,
    this.error,
  });

  final String name;
  final List<Map<String, dynamic>> documents;
  final String? error;
}
