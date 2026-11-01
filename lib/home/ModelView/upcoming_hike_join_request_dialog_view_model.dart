part of '../upcoming_hike_join_request_dialog_feature.dart';

/// Owns the state and non-visual actions of UpcomingHikeJoinRequestDialog.
class _UpcomingHikeJoinRequestDialogStateViewModel extends ChangeNotifier {
  /// Creates upcoming hike join request dialog state view model.
  _UpcomingHikeJoinRequestDialogStateViewModel({
    required this.readReview,
    required this.resolve,
  });
  final UpcomingHikeJoinRequestReview Function() readReview;
  final Future<UpcomingHikeJoinRequestReview> Function(bool) resolve;
  bool resolving = false;
  String? error;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Serializes the host decision and retains the review after a timeout or failure.
  Future<UpcomingHikeJoinRequestReview?> commandResolve(bool accept) async {
    if (_disposed || resolving || !readReview().canResolve) return null;
    resolving = true;
    error = null;
    notifyListeners();
    try {
      return await resolve(accept).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      error =
          'The response is taking longer than expected. Reopen the request to check its status.';
    } on HikerCircleFirebaseRepositoryException catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Unable to respond right now. Please try again.';
    } finally {
      resolving = false;
      if (!_disposed) notifyListeners();
    }
    return null;
  }

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
