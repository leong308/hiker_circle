part of '../hiking_forecast_sheet_feature.dart';

/// Owns the state and non-visual actions of HikingForecastSheet.
class _ForecastStateViewModel extends ChangeNotifier {
  /// Creates forecast state view model.
  _ForecastStateViewModel({required this.readHike});
  final UpcomingHike Function() readHike;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  DateTime? stateSelected;

  /// Returns command beyond forecast.
  bool get commandBeyondForecast =>
      HikeBriefingWeatherService.isBeyondForecast(readHike().departureTime);

  /// Computes clock.
  String commandClock(DateTime time, Duration offset) {
    final t = time.toUtc().add(offset);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Computes date.
  String commandDate(DateTime time, Duration offset) {
    final t = time.toUtc().add(offset);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${t.day} ${months[t.month - 1]} · ${commandClock(time, offset)}';
  }

  /// Computes session time.
  String commandSessionTime(SessionWeatherForecast forecast) {
    final offset = forecast.session.utcOffset;
    final start = forecast.departure.toUtc().add(offset);
    final end = forecast.returning.toUtc().add(offset);
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    return '${commandDate(forecast.departure, offset)} → ${sameDay ? commandClock(forecast.returning, offset) : commandDate(forecast.returning, offset)}';
  }

  /// Computes temperature range.
  String commandTemperatureRange(HikeWeatherBriefing session) {
    final low = session.minTemperature?.round(),
        high = session.maxTemperature?.round();
    if (low == null || high == null) return 'Temperature unavailable';
    return low == high ? '$low°C' : '$low–$high°C';
  }

  /// Computes value.
  String commandValue(double? value, String unit) => value == null
      ? 'Unavailable'
      : '${value.toStringAsFixed(unit == 'mm' ? 1 : 0)}$unit';

  /// Computes range.
  String commandRange(({double min, double max})? values, String unit) {
    if (values == null) return 'Unavailable';
    final decimals = unit == 'mm' ? 1 : 0;
    return '${values.min.toStringAsFixed(decimals)} – ${values.max.toStringAsFixed(decimals)}$unit';
  }

  /// Computes phase.
  String commandPhase(HikeWeatherHour hour, SessionWeatherForecast forecast) {
    final end = hour.time.add(const Duration(hours: 1));
    if (hour.time.isBefore(forecast.departure) &&
        end.isAfter(forecast.departure)) {
      return 'Departure hour';
    }
    if (hour.time.isBefore(forecast.returning) &&
        end.isAfter(forecast.returning)) {
      return 'Return hour';
    }
    if (hour.time.isBefore(forecast.departure)) return 'Before departure';
    if (hour.time.isBefore(forecast.returning)) return 'During hike';
    return 'After return';
  }

  /// Computes selected hour.
  HikeWeatherHour? commandSelectedHour(SessionWeatherForecast forecast) {
    final target = (stateSelected ?? forecast.departure).toUtc();
    final hour = forecast.buffer.hours
        .where((h) => !h.time.isAfter(target))
        .lastOrNull;
    // A smooth cursor can cross missing hours; never carry a previous reading
    // into a gap or interpolate it into an invented higher-resolution forecast.
    return hour != null &&
            target.isBefore(hour.time.add(const Duration(hours: 1)))
        ? hour
        : null;
  }

  /// Computes condition.
  String commandCondition(HikeWeatherHour hour) {
    final code = hour.value('weather_code');
    if (code == null) return 'Conditions unavailable';
    if (code >= 95) return 'Thunderstorms';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return 'Snow';
    if (code >= 51) return 'Rain or showers';
    if (code == 45 || code == 48) return 'Fog';
    return code <= 1 ? 'Clear or mainly clear' : 'Partly cloudy or overcast';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
