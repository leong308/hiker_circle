part of '../hiker_circle_assistant_page_feature.dart';

/// Represents assistant message.
class _AssistantMessage {
  /// Creates assistant message.
  const _AssistantMessage({
    required this.text,
    required this.isUser,
    this.id = '',
    this.createdAtMicros = 0,
    this.sources = const [],
    this.isEmergency = false,
    this.isError = false,
    this.notice,
    this.trails = const [],
    this.action,
  });

  /// Creates assistant message using new entry.
  factory _AssistantMessage.newEntry({
    required String text,
    required bool isUser,
    List<HikerCircleAssistantSource> sources = const [],
    bool isEmergency = false,
    bool isError = false,
    String? notice,
    List<HikerCircleAssistantTrail> trails = const [],
    HikerCircleAssistantAction? action,
  }) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return _AssistantMessage(
      id: '$now-${math.Random().nextInt(1 << 32)}',
      createdAtMicros: now,
      text: text,
      isUser: isUser,
      sources: sources,
      isEmergency: isEmergency,
      isError: isError,
      notice: notice,
      trails: trails,
      action: action,
    );
  }

  final String text;
  final bool isUser;
  final String id;
  final int createdAtMicros;
  final List<HikerCircleAssistantSource> sources;
  final bool isEmergency;
  final bool isError;
  final String? notice;
  final List<HikerCircleAssistantTrail> trails;
  final HikerCircleAssistantAction? action;

  /// Serializes this value as a map.
  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAtMicros': createdAtMicros,
    'text': text,
    'isUser': isUser,
    'isEmergency': isEmergency,
    'isError': isError,
    if (notice != null) 'notice': notice,
    'sources': sources
        .map((source) => {'id': source.id, 'title': source.title})
        .toList(),
    'trails': trails
        .map(
          (trail) => {
            'id': trail.id,
            'name': trail.name,
            'area': trail.area,
            'state': trail.state,
            'difficulty': trail.difficulty,
            'distanceKm': trail.distanceKm,
            'estimatedDurationMinutes': trail.estimatedDurationMinutes,
            if (trail.coverImageUrl.isNotEmpty)
              'coverImageUrl': trail.coverImageUrl,
            if (trail.distanceFromUserKm != null)
              'distanceFromUserKm': trail.distanceFromUserKm,
          },
        )
        .toList(),
    if (action != null)
      'action': {
        'destinationId': action!.destinationId,
        'label': action!.label,
      },
  };

  /// Creates assistant message from stored map data.
  factory _AssistantMessage.fromMap(Map<String, dynamic> data) {
    final sourceValues = data['sources'];
    final trailValues = data['trails'];
    final actionValue = data['action'];
    return _AssistantMessage(
      id: data['id']?.toString() ?? '',
      createdAtMicros: (data['createdAtMicros'] as num?)?.toInt() ?? 0,
      text: data['text']?.toString() ?? '',
      isUser: data['isUser'] == true,
      isEmergency: data['isEmergency'] == true,
      isError: data['isError'] == true,
      notice: data['notice']?.toString(),
      sources: sourceValues is List
          ? sourceValues
                .whereType<Map>()
                .map(
                  (value) => HikerCircleAssistantSource.fromMap(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : const [],
      trails: trailValues is List
          ? trailValues
                .whereType<Map>()
                .map(
                  (value) => HikerCircleAssistantTrail.fromMap(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList()
          : const [],
      action:
          actionValue is Map && actionValue['destinationId'] != 'offline_maps'
          ? HikerCircleAssistantAction(
              destinationId: actionValue['destinationId']?.toString() ?? '',
              label: actionValue['label']?.toString() ?? '',
            )
          : null,
    );
  }
}
