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

  /// Uses only the public alias; no general profile-field renderer is exposed.
  String commandRequesterName() => safeJoinRequestAlias(
    readReview().profile['displayName'] ?? readReview().requesterName,
  );

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
