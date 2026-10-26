part of '../upcoming_hike_join_request_dialog_feature.dart';

/// Owns the state and non-visual actions of UpcomingHikeJoinRequestDialog.
class _UpcomingHikeJoinRequestDialogStateViewModel extends ChangeNotifier {
  /// Creates upcoming hike join request dialog state view model.
  _UpcomingHikeJoinRequestDialogStateViewModel({required this.readReview});
  final UpcomingHikeJoinRequestReview Function() readReview;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes departure label.
  String commandDepartureLabel() {
    final departure = readReview().departureTime?.toLocal();
    if (departure == null) return 'Scheduled upcoming hike';
    final minute = departure.minute.toString().padLeft(2, '0');
    return '${departure.day}/${departure.month}/${departure.year} · '
        '${departure.hour}:$minute';
  }

  /// Computes profile text.
  String commandProfileText(String key, [String fallback = 'Not provided']) {
    final value = readReview().profile[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  /// Computes history subtitle.
  String commandHistorySubtitle(Map<String, dynamic> hike) {
    final distance = (hike['recordedDistanceKm'] as num?)?.toDouble() ?? 0;
    final seconds = (hike['durationSeconds'] as num?)?.toInt() ?? 0;
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final kind = hike['hikeType'] == 'team' ? 'Group hike' : 'Solo hike';
    return '$kind · ${distance.toStringAsFixed(1)} km · '
        '${hours > 0 ? '${hours}h ' : ''}${minutes}m';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
