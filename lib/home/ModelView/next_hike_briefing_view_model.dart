part of '../next_hike_briefing_feature.dart';

/// Owns the state and non-visual actions of NextHikeBriefing.
class _NextHikeBriefingStateViewModel extends ChangeNotifier {
  /// Creates next hike briefing state view model.
  _NextHikeBriefingStateViewModel({
    required this.readHike,
    required this.readIsVisible,
    required this.readTrail,
    required this.readWeatherService,
  });
  final UpcomingHike Function() readHike;
  final bool Function() readIsVisible;
  final Trail? Function() readTrail;
  final HikeBriefingWeatherService? Function() readWeatherService;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  TrailWeather? stateWeather;

  bool stateLoading = false;

  bool stateFailed = false;

  bool stateForeground = true;

  DateTime? stateRetryAt;

  int stateGeneration = 0;

  /// Returns command service.
  HikeBriefingWeatherService get commandService =>
      readWeatherService() ?? HikeBriefingWeatherService.shared;

  /// Returns command beyond forecast.
  bool get commandBeyondForecast =>
      HikeBriefingWeatherService.isBeyondForecast(readHike().departureTime);

  /// Computes seed.
  void commandSeed() {
    final weather = readTrail()?.weather;
    // Old summary-only caches cannot describe a future hiking window.
    if (weather != null &&
        weather.forecastData['hourly'] is Map &&
        weather.forecastData['utc_offset_seconds'] is num) {
      stateWeather = weather;
    }
  }

  /// Computes tick.
  void commandTick() {
    if (!mounted || !readIsVisible() || !stateForeground) return;
    _publish(() {});
    if (stateLoading ||
        commandBeyondForecast ||
        (stateRetryAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final weather = stateWeather;
    final covered =
        weather != null &&
        HikeWeatherBriefing.fromWeather(
          weather,
          readHike().departureTime,
          readHike().expectedReturnTime,
        ).covered;
    if (weather == null || weather.isStale || !covered) {
      unawaited(commandLoad());
    }
  }

  /// Loads.
  Future<void> commandLoad({bool force = false}) async {
    if (stateLoading) return;
    final generation = stateGeneration;
    _publish(() {
      stateLoading = true;
    });
    try {
      final weather = await commandService.fetch(
        readHike().latitude,
        readHike().longitude,
        force: force,
      );
      if (!mounted || generation != stateGeneration) return;
      _publish(() {
        stateWeather = weather;
        stateFailed = false;
        stateRetryAt = DateTime.now().add(HikeBriefingWeatherService.freshness);
      });
      unawaited(
        HomeScreenWidgetService.shared.acceptForecast(readHike(), weather),
      );
    } catch (_) {
      if (!mounted || generation != stateGeneration) return;
      _publish(() {
        stateFailed = true;
        stateRetryAt = DateTime.now().add(const Duration(minutes: 15));
      });
    } finally {
      if (mounted && generation == stateGeneration) {
        _publish(() {
          stateLoading = false;
        });
      }
    }
  }

  /// Computes clock time.
  String commandClockTime(DateTime value) {
    final date = value.toLocal();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
