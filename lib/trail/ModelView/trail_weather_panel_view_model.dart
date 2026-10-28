part of '../trail_weather_panel_feature.dart';

/// Owns the state and non-visual actions of TrailWeatherPanel.
class _TrailWeatherPanelStateViewModel extends ChangeNotifier {
  /// Creates trail weather panel state view model.
  _TrailWeatherPanelStateViewModel({
    required this.readOnDepartureChanged,
    required this.readWeather,
    required this.readTrail,
    required this.readLocationWeather,
  });
  final ValueChanged<DateTime?>? Function() readOnDepartureChanged;
  final TrailWeather Function() readWeather;
  final Trail? Function() readTrail;
  final Stream<TrailWeather> Function(Trail, TrailWeatherLocation)? Function()
  readLocationWeather;
  StreamSubscription<TrailWeather>? _locationSubscription;
  int _locationGeneration = 0;
  String stateLocationKey = TrailWeatherLocation.trailheadKey;
  bool stateLoadingLocation = false;
  bool stateRefreshingLocation = false;
  String? stateLocationError;
  final _locationForecasts = <String, TrailWeather>{};

  /// Lists the trailhead and unique saved checkpoints for longer routes.
  List<TrailWeatherLocation> get commandLocations => readTrail() == null
      ? const []
      : TrailWeatherLocation.forTrail(readTrail()!);

  /// Keeps the default trailhead forecast independent from checkpoint selection.
  TrailWeather get commandWeather =>
      _locationForecasts[stateLocationKey] ?? readWeather();

  /// Prevents the previous location's readings from appearing under a new checkpoint.
  bool get commandHasLocationWeather =>
      stateLocationKey == TrailWeatherLocation.trailheadKey ||
      _locationForecasts.containsKey(stateLocationKey);

  /// Changes the displayed forecast, with stale-response protection for rapid selections.
  void commandSelectLocation(String key, {bool retry = false}) {
    final trail = readTrail();
    final location = commandLocations
        .where((point) => point.key == key)
        .firstOrNull;
    if (trail == null ||
        location == null ||
        (key == stateLocationKey &&
            !retry &&
            (key == TrailWeatherLocation.trailheadKey ||
                stateRefreshingLocation ||
                !commandHasLocationWeather ||
                !commandWeather.isStale))) {
      return;
    }
    final generation = ++_locationGeneration;
    unawaited(_locationSubscription?.cancel());
    _locationSubscription = null;
    stateLocationKey = key;
    stateLocationError = null;
    stateRefreshingLocation = false;
    stateLoadingLocation = !commandHasLocationWeather;
    notifyListeners();
    if (key == TrailWeatherLocation.trailheadKey) return;
    final cached = _locationForecasts[key];
    if (!retry &&
        cached != null &&
        DateTime.now().toUtc().difference(cached.cachedAt.toUtc()) <
            TrailWeather.cacheFreshness) {
      return;
    }
    final load = readLocationWeather();
    if (load == null) {
      _locationFailed(generation);
      return;
    }
    stateRefreshingLocation = true;
    _locationSubscription = load(trail, location).listen(
      (weather) {
        if (_disposed || generation != _locationGeneration) return;
        _locationForecasts[key] = weather;
        stateLoadingLocation = false;
        stateLocationError = null;
        notifyListeners();
      },
      onError: (Object error) => _locationFailed(generation),
      onDone: () {
        if (_disposed || generation != _locationGeneration) return;
        stateRefreshingLocation = false;
        notifyListeners();
        if (!_disposed &&
            generation == _locationGeneration &&
            !commandHasLocationWeather) {
          _locationFailed(generation);
        }
      },
    );
  }

  /// Retains a truthful cached forecast when a refresh is unavailable.
  void _locationFailed(int generation) {
    if (_disposed || generation != _locationGeneration) return;
    stateLoadingLocation = false;
    stateRefreshingLocation = false;
    stateLocationError = commandHasLocationWeather
        ? 'Could not refresh this checkpoint. The saved forecast is shown.'
        : 'Could not load this checkpoint forecast. Try again.';
    notifyListeners();
  }

  /// Restores the trailhead if the parent trail or its saved checkpoints change.
  void commandResetLocations() {
    _locationGeneration++;
    unawaited(_locationSubscription?.cancel());
    _locationSubscription = null;
    _locationForecasts.clear();
    stateLocationKey = TrailWeatherLocation.trailheadKey;
    stateLoadingLocation = false;
    stateRefreshingLocation = false;
    stateLocationError = null;
  }

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  int stateSelected = 0;

  TimeOfDay? stateDeparture;

  /// Notifies departure changed.
  void commandNotifyDepartureChanged() {
    final day = commandValue(commandDaily, 'time', stateSelected);
    final time = stateDeparture;
    readOnDepartureChanged()?.call(
      day == null || time == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (day * 1000).round(),
              isUtc: true,
            ).add(Duration(hours: time.hour, minutes: time.minute)),
    );
  }

  /// Returns command data.
  Map get commandData => commandWeather.forecastData;

  /// Returns command daily.
  Map get commandDaily =>
      commandData['daily'] is Map ? commandData['daily'] as Map : const {};

  /// Returns command hourly.
  Map get commandHourly =>
      commandData['hourly'] is Map ? commandData['hourly'] as Map : const {};

  /// Returns command days.
  List get commandDays =>
      commandDaily['time'] is List ? commandDaily['time'] as List : const [];

  /// Computes value.
  num? commandValue(Map source, String key, int i) {
    final values = source[key];
    if (values is! List || i >= values.length || values[i] is! num) return null;
    final n = values[i] as num;
    return n.isFinite ? n : null;
  }

  /// Computes local.
  DateTime commandLocal(num epoch) => DateTime.fromMillisecondsSinceEpoch(
    ((epoch + ((commandData['utc_offset_seconds'] as num?) ?? 0)) * 1000)
        .round(),
    isUtc: true,
  );

  /// Computes clock.
  String commandClock(num epoch) {
    final t = commandLocal(epoch);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Computes date.
  String commandDate(num epoch) {
    final t = commandLocal(epoch);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[t.weekday - 1]} ${t.day}/${t.month}';
  }

  /// Computes condition.
  String commandCondition(num? code) => code == null
      ? 'Conditions unavailable'
      : HourlyForecast(
          time: DateTime(2000),
          temperature: 0,
          precipitationProbability: 0,
          weatherCode: code.toInt(),
        ).weatherLabel;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    _locationGeneration++;
    unawaited(_locationSubscription?.cancel());
    super.dispose();
  }
}
