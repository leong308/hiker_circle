import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Data/app_settings_controller.dart';
import '../../app/Model/preferred_time_zone.dart';
import '../Model/hike_reminder_timeline.dart';
import '../Model/hike_session_models.dart';

/// Keeps available choices and the timeline aligned as departure approaches.
class HikeReminderPreferencesViewModel extends ChangeNotifier {
  /// Starts a clock and follows changes to the app's selected time zone.
  HikeReminderPreferencesViewModel({
    required HikeReminderPreference preference,
    required DateTime departureTime,
    DateTime Function()? now,
    AppSettingsController? settings,
  }) : _preference = preference,
       _departureTime = departureTime,
       _now = now ?? DateTime.now,
       _settings = settings ?? AppSettingsController.instance {
    _instant = _now();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    _settings.addListener(refresh);
  }

  HikeReminderPreference _preference;
  DateTime _departureTime;
  DateTime Function() _now;
  final AppSettingsController _settings;
  late DateTime _instant;
  late final Timer _clock;

  /// Returns choices that can still be saved before this departure.
  HikeReminderPreference get preference =>
      _preference.fitToDeparture(_departureTime, _instant);

  /// Lists first reminder offsets with a one-minute saving buffer.
  List<int> get firstOptions =>
      HikeReminderPreference.availableFirstReminders(_departureTime, _instant);

  /// Offers repeats only when a second reminder fits before the start.
  List<int> get repeatOptions => HikeReminderPreference.repeatIntervalOptions
      .where((minutes) => minutes < preference.firstReminderMinutesBefore)
      .toList();

  /// Names the selected app time zone for every displayed timeline time.
  String get timeZoneLabel =>
      PreferredTimeZone.compactLabel(_settings.preferredTimeZone, at: _instant);

  /// Explains how to read the proposed schedule, including disabled states.
  String get scheduleHint {
    if (!_departureTime.isAfter(_instant)) {
      return 'This hike start time has passed.';
    }
    if (firstOptions.isEmpty) {
      return 'No reminder time remains before this hike starts.';
    }
    if (!preference.enabled) {
      return 'Departure reminders are off for this hike.';
    }
    return preference.repeatIntervalMinutes == 0
        ? 'One reminder before your hike starts.'
        : 'Reminders repeat until before your hike starts.';
  }

  /// Builds chronological anchors and every future departure reminder.
  List<HikeReminderTimelineEntry> get timeline {
    final entries = <HikeReminderTimelineEntry>[
      _entry(HikeReminderTimelineKind.now, _instant, 'Now'),
      for (final (index, time)
          in preference.scheduledTimes(_departureTime, after: _instant).indexed)
        _entry(
          HikeReminderTimelineKind.reminder,
          time,
          'Reminder ${index + 1}',
          detail:
              '${hikeReminderDurationLabel(_departureTime.difference(time).inMinutes)} before start',
        ),
      _entry(HikeReminderTimelineKind.start, _departureTime, 'Hike start'),
    ];
    entries.sort((a, b) => a.instant.compareTo(b.instant));
    return entries;
  }

  /// Applies parent changes without notifying during a widget rebuild.
  void updateInputs({
    required HikeReminderPreference preference,
    required DateTime departureTime,
    DateTime Function()? now,
  }) {
    _preference = preference;
    _departureTime = departureTime;
    _now = now ?? DateTime.now;
    _instant = _now();
  }

  /// Saves an editor selection and returns its effective choices to the parent.
  HikeReminderPreference select(HikeReminderPreference value) {
    _preference = value.fitToDeparture(_departureTime, _instant);
    notifyListeners();
    return _preference;
  }

  /// Refreshes one shared instant so dropdowns and timeline cannot disagree.
  void refresh() {
    _instant = _now();
    notifyListeners();
  }

  /// Formats one point using the same clock and app time zone as the choices.
  HikeReminderTimelineEntry _entry(
    HikeReminderTimelineKind kind,
    DateTime time,
    String title, {
    String? detail,
  }) => HikeReminderTimelineEntry(
    kind: kind,
    instant: time,
    title: title,
    detail: detail,
    timeZoneId: _settings.preferredTimeZone,
    now: _instant,
  );

  /// Releases the clock and settings subscription when the editor closes.
  @override
  void dispose() {
    _clock.cancel();
    _settings.removeListener(refresh);
    super.dispose();
  }
}
