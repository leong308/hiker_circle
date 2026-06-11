import '../../sos/Model/sos_models.dart';

class LiveLocationShare {
  const LiveLocationShare({
    required this.id,
    required this.shareUrl,
    required this.isActive,
    this.latestLocation,
  });

  final String id;
  final String shareUrl;
  final bool isActive;
  final SosTriggerLocation? latestLocation;

  LiveLocationShare copyWith({
    String? id,
    String? shareUrl,
    bool? isActive,
    SosTriggerLocation? latestLocation,
  }) {
    return LiveLocationShare(
      id: id ?? this.id,
      shareUrl: shareUrl ?? this.shareUrl,
      isActive: isActive ?? this.isActive,
      latestLocation: latestLocation ?? this.latestLocation,
    );
  }
}
