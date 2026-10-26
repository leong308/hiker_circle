part of '../trail_weather_panel_feature.dart';

/// Owns the state and non-visual actions of TrailWeatherPanel.
class _TrailWeatherPanelStateViewModel extends ChangeNotifier {
  /// Creates trail weather panel state view model.
  _TrailWeatherPanelStateViewModel({
    required this.readOnDepartureChanged,
    required this.readWeather,
  });
  final ValueChanged<DateTime?>? Function() readOnDepartureChanged;
  final TrailWeather Function() readWeather;
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
  Map get commandData => readWeather().forecastData;

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
    super.dispose();
  }
}
