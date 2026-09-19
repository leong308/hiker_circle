import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_session_models.dart';
import '../Model/hike_weather_briefing.dart';
import 'hike_briefing_weather_service.dart';

/// Publishes a small, account-scoped snapshot to the native launcher widgets.
/// Widgets never receive authentication tokens or emergency contact details.
class HomeScreenWidgetService {
  HomeScreenWidgetService({
    MethodChannel? channel,
    HikeBriefingWeatherService? weather,
  }) : _channel = channel ?? const MethodChannel('hiker_circle/home_widgets'),
       _weather = weather ?? HikeBriefingWeatherService.shared;
  static final shared = HomeScreenWidgetService();
  final MethodChannel _channel;
  final HikeBriefingWeatherService _weather;
  int _revision = 0;
  bool _enabled = true;

  void activate() {
    _enabled = true;
  }

  String? _lastPayload;
  final _forecasts = <String, Map<String, dynamic>>{};
  List<UpcomingHike> _hikes = const [];
  PlannedHike? _plan;
  final _failures = <String>{};

  Future<void> clear() async {
    _enabled = false;
    _revision++;
    _forecasts.clear();
    _hikes = const [];
    _plan = null;
    _failures.clear();
    _lastPayload = null;
    await _publish(const []);
  }

  Future<void> update({
    required List<UpcomingHike> hikes,
    PlannedHike? plan,
  }) async {
    if (kIsWeb || !_enabled) return;
    final revision = ++_revision;
    final now = DateTime.now().toUtc();
    final eligible = hikes.where((h) => h.isUpcomingAt(now)).toList()
      ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
    final selected = eligible.take(8).toList();
    _hikes = selected;
    _plan = plan;
    final ids = selected.map((h) => h.id).toSet();
    _forecasts.removeWhere((id, _) => !ids.contains(id));
    final keys = selected.map(_forecastKey).toSet();
    _failures.removeWhere((key) => !keys.contains(key));

    await _publish(_items());
    if (revision != _revision || selected.isEmpty) return;
    final next = selected.first;
    if (HikeBriefingWeatherService.isBeyondForecast(
      next.departureTime,
      now: now,
    )) {
      return;
    }
    try {
      final forecast = await _weather.fetch(next.latitude, next.longitude);
      if (revision != _revision) return;
      _storeForecast(next, forecast);
      await _publish(_items());
    } catch (error) {
      if (revision != _revision) return;
      // Retain the last dated forecast; native views mark old data as outdated.
      _failures.add(_forecastKey(next));
      await _publish(_items());
      debugPrint('Home widget forecast unavailable: $error');
    }
  }

  /// A successful in-app refresh also repairs the currently published widget.
  /// Ignore callbacks for removed schedules, changed dates and signed-out users.
  Future<void> acceptForecast(UpcomingHike hike, TrailWeather forecast) async {
    if (!_enabled ||
        kIsWeb ||
        !_hikes.any(
          (current) =>
              current.id == hike.id &&
              _forecastKey(current) == _forecastKey(hike),
        )) {
      return;
    }
    // Browsing a later carousel card must not cancel the nearest hike's
    // in-flight widget forecast. Only a replacement for that hike supersedes it.
    if (_hikes.first.id == hike.id) _revision++;
    _storeForecast(hike, forecast);
    await _publish(_items());
  }

  List<Map<String, dynamic>> _items() => _hikes.map((hike) {
    final preparation = _plan?.upcomingHikeId == hike.id ? _plan : null;
    final key = _forecastKey(hike);
    final forecast = _forecasts[hike.id]?['key'] == key
        ? _forecasts[hike.id]
        : null;
    return {
      'id': hike.id,
      'name': hike.trailName,
      'startPoint': hike.startPointName,
      'distanceKm': hike.distanceKm,
      'difficulty': hike.difficulty,
      'departure': hike.departureTime.millisecondsSinceEpoch ~/ 1000,
      'returning': hike.expectedReturnTime.millisecondsSinceEpoch ~/ 1000,
      'expires': hike.visibleUntil.millisecondsSinceEpoch ~/ 1000,
      if (preparation != null) ...{
        'gearDone': preparation.checklistCompleted,
        'gearTotal': preparation.checklistTotal,
        'contactsReady': preparation.emergencyContactsSelected,
        'sharingReady': preparation.liveLocationConfigured,
        if (preparation.hasKnownBatteryLevel)
          'battery': preparation.phoneBatteryLevel,
      },
      'weatherStatus': forecast?['covered'] == true
          ? 'ready'
          : HikeBriefingWeatherService.isBeyondForecast(hike.departureTime)
          ? 'beyondRange'
          : _failures.contains(key)
          ? 'unavailable'
          : forecast != null
          ? 'incomplete'
          : 'pending',
      if (forecast != null) 'weather': forecast,
    };
  }).toList();

  void _storeForecast(UpcomingHike next, TrailWeather forecast) {
    _failures.remove(_forecastKey(next));
    final briefing = HikeWeatherBriefing.fromWeather(
      forecast,
      next.departureTime,
      next.expectedReturnTime,
    );
    _forecasts[next.id] = {
      'key': _forecastKey(next),
      'updated': forecast.cachedAt.millisecondsSinceEpoch ~/ 1000,
      'covered': briefing.covered,
      if (briefing.minTemperature != null) 'minTemp': briefing.minTemperature,
      if (briefing.maxTemperature != null) 'maxTemp': briefing.maxTemperature,
      if (briefing.peakRainChance != null) 'rain': briefing.peakRainChance,
      'daylight': briefing.startsBeforeSunrise
          ? 'Starts before sunrise'
          : briefing.endsAfterSunset
          ? 'Return after sunset'
          : 'Check daylight in app',
    };
  }

  String _forecastKey(UpcomingHike h) =>
      '${h.latitude},${h.longitude},${h.departureTime.toUtc()},${h.expectedReturnTime.toUtc()}';

  Future<void> _publish(List<Map<String, dynamic>> hikes) async {
    final payload = jsonEncode({'version': 1, 'hikes': hikes});
    if (payload == _lastPayload || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('update', payload);
      _lastPayload = payload;
    } on MissingPluginException {
      // Desktop/web tests and old native installations have no widget bridge.
    } on PlatformException catch (error) {
      debugPrint('Home widget sync failed: ${error.code}');
    }
  }
}
