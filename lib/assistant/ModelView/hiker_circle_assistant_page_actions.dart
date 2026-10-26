part of '../hiker_circle_assistant_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _HikerCircleAssistantPageDataActions {
  /// Binds ask to the selected data source.
  static Future<HikerCircleAssistantAnswer> Function(
    String, {
    List<Map<String, String>> history,
    Map<String, double>? location,
  })
  ask(HikerCircleAssistantRepository receiver) => receiver.ask;
}
