// LiveLocationShare describes the current share link, coordinates, expiry and sharing state.
import '../../sos/Model/sos_models.dart';

/// Represents live location share.
class LiveLocationShare {
  /// Creates live location share.
  const LiveLocationShare({
    required this.id,
    required this.shareUrl,
    required this.isActive,
    required this.expiresAt,
    DateTime? startedAt,
    this.latestLocation,
  }) : _startedAt = startedAt;

  final String id;
  final String shareUrl;
  final bool isActive;
  final DateTime expiresAt;
  final DateTime? _startedAt;
  final SosTriggerLocation? latestLocation;

  /// Activation fixes the lifetime at 24 hours; GPS updates and retries never
  /// move its beginning. Older active links retain that same original instant.
  DateTime get startedAt =>
      _startedAt?.toUtc() ??
      expiresAt.toUtc().subtract(const Duration(hours: 24));

  /// Returns a copy with the supplied fields changed.
  LiveLocationShare copyWith({
    String? id,
    String? shareUrl,
    bool? isActive,
    DateTime? expiresAt,
    DateTime? startedAt,
    SosTriggerLocation? latestLocation,
  }) {
    return LiveLocationShare(
      id: id ?? this.id,
      shareUrl: shareUrl ?? this.shareUrl,
      isActive: isActive ?? this.isActive,
      expiresAt: expiresAt ?? this.expiresAt,
      startedAt: startedAt ?? _startedAt,
      latestLocation: latestLocation ?? this.latestLocation,
    );
  }
}
