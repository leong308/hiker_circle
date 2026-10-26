part of '../find_hike_page_feature.dart';

/// Owns the state and non-visual actions of FindHikePage.
class _FindHikePageStateViewModel extends ChangeNotifier {
  /// Creates find hike page state view model.
  _FindHikePageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  List<UpcomingHike> stateHikes = const [];

  double? stateUserLat;

  double? stateUserLng;

  /// Refreshes location and resort.
  Future<void> commandRefreshLocationAndResort() async {
    try {
      final location = await LocationSnapshotService.instance.refresh();
      if (!mounted || location == null) return;
      final sorted = List<UpcomingHike>.of(stateHikes)
        ..sort(
          (a, b) => a
              .distanceFrom(location.latitude, location.longitude)
              .compareTo(b.distanceFrom(location.latitude, location.longitude)),
        );
      _publish(() {
        stateUserLat = location.latitude;
        stateUserLng = location.longitude;
        stateHikes = sorted;
      });
    } catch (_) {
      // Location only affects distance ordering. Discovery remains available.
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of UpcomingHikeCard.
class _UpcomingHikeCardStateViewModel extends ChangeNotifier {
  /// Creates upcoming hike card state view model.
  _UpcomingHikeCardStateViewModel({
    required this.readHike,
    required this.readSession,
    required this.effectShowError,
  });
  final UpcomingHike Function() readHike;
  final AppSession Function() readSession;
  final void Function(String message) effectShowError;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  bool stateJoinedLocally = false;

  /// Computes urgency phase.
  int commandUrgencyPhase(DateTime now) {
    final untilDeparture = readHike().departureTime.difference(now);
    if (untilDeparture > const Duration(minutes: 15)) return 0;
    if (!untilDeparture.isNegative) return 1;
    if (untilDeparture > const Duration(minutes: -15)) return 2;
    return 3;
  }

  /// Returns command is participating.
  bool get commandIsParticipating {
    final phone = readSession().phoneNumber;
    return stateJoinedLocally ||
        phone == readHike().creatorPhone ||
        readHike().participantPhones.contains(phone);
  }

  /// Opens directions.
  Future<void> commandOpenDirections() async {
    final lat = readHike().latitude;
    final lng = readHike().longitude;
    final googleUrl =
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final wazeUrl = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
    try {
      final googleUri = Uri.parse(googleUrl);
      final wazeUri = Uri.parse(wazeUrl);
      var launched = false;
      if (await canLaunchUrl(googleUri)) {
        launched = await launchUrl(
          googleUri,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched && await canLaunchUrl(wazeUri)) {
        launched = await launchUrl(
          wazeUri,
          mode: LaunchMode.externalApplication,
        );
      }
      if (!launched) {
        effectShowError('No maps application is available.');
      }
    } catch (_) {
      effectShowError('Unable to open directions.');
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
