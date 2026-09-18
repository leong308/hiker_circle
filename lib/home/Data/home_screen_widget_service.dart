import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  Future<void> clear() async {
    _enabled = false;
    _revision++;
    _forecasts.clear();
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
    final ids = selected.map((h) => h.id).toSet();
    _forecasts.removeWhere((id, _) => !ids.contains(id));
    Map<String, dynamic> item(UpcomingHike hike) {
      final preparation = plan?.upcomingHikeId == hike.id ? plan : null;
      final key = _forecastKey(hike);
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
        if (_forecasts[hike.id]?['key'] == key) 'weather': _forecasts[hike.id],
      };
    }

    await _publish(selected.map(item).toList());
    if (revision != _revision || selected.isEmpty) return;
    final next = selected.first;
    if (next.departureTime.toUtc().difference(now) >= const Duration(days: 7)) {
      return;
    }
    try {
      final forecast = await _weather.fetch(next.latitude, next.longitude);
      if (revision != _revision) return;
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
      await _publish(selected.map(item).toList());
    } catch (error) {
      // Retain the last dated forecast; native views mark old data as outdated.
      debugPrint('Home widget forecast unavailable: $error');
    }
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
