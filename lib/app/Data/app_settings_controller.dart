import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../Model/preferred_time_zone.dart';

enum HikerCircleThemeSetting {
  system('System', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  const HikerCircleThemeSetting(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  static HikerCircleThemeSetting fromLabel(String label) {
    return HikerCircleThemeSetting.values.firstWhere(
      (setting) => setting.label == label,
      orElse: () => HikerCircleThemeSetting.system,
    );
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._() {
    _initialization = _loadFromDisk();
  }

  static final AppSettingsController instance = AppSettingsController._();

  HikerCircleThemeSetting _themeSetting = HikerCircleThemeSetting.system;
  String _language = 'English';
  String _preferredTimeZone = PreferredTimeZone.fallbackId;
  bool _preciseLocationEnabled = true;
  bool _anonymousTrailRecommendationsEnabled = false;
  bool _hapticSafetyFeedbackEnabled = true;
  bool _lowBatterySafetyWarningEnabled = true;

  late final Future<void> _initialization;
  Future<void> _writeChain = Future<void>.value();
  bool _isLoading = true;
  bool _changedWhileLoading = false;

  HikerCircleThemeSetting get themeSetting => _themeSetting;
  ThemeMode get themeMode => _themeSetting.themeMode;
  String get language => _language;
  String get preferredTimeZone => _preferredTimeZone;
  bool get preciseLocationEnabled => _preciseLocationEnabled;
  bool get anonymousTrailRecommendationsEnabled =>
      _anonymousTrailRecommendationsEnabled;
  bool get hapticSafetyFeedbackEnabled => _hapticSafetyFeedbackEnabled;
  bool get lowBatterySafetyWarningEnabled => _lowBatterySafetyWarningEnabled;

  Map<String, Object?> get debugSnapshot => {
    'storageType': 'App-scoped JSON settings',
    'persistence': 'Persistent on this device',
    'language': _language,
    'preferredTimeZone': _preferredTimeZone,
    'themeSetting': _themeSetting.label,
    'themeMode': _themeSetting.themeMode.name,
    'preciseLocationEnabled': _preciseLocationEnabled,
    'anonymousTrailRecommendationsEnabled':
        _anonymousTrailRecommendationsEnabled,
    'hapticSafetyFeedbackEnabled': _hapticSafetyFeedbackEnabled,
    'lowBatterySafetyWarningEnabled': _lowBatterySafetyWarningEnabled,
    'hasListeners': hasListeners,
  };

  void setThemeSetting(HikerCircleThemeSetting setting) {
    if (_themeSetting == setting) {
      return;
    }
    _themeSetting = setting;
    _settingsChanged();
  }

  void setLanguage(String language) {
    const supported = {'English'};
    final normalized = supported.contains(language) ? language : 'English';
    if (_language == normalized) {
      return;
    }
    _language = normalized;
    _settingsChanged();
  }

  void setPreferredTimeZone(String timeZoneId) {
    final normalized = PreferredTimeZone.normalize(timeZoneId);
    if (_preferredTimeZone == normalized) {
      return;
    }
    _preferredTimeZone = normalized;
    _settingsChanged();
  }

  void setPreciseLocationEnabled(bool enabled) {
    if (_preciseLocationEnabled == enabled) {
      return;
    }
    _preciseLocationEnabled = enabled;
    _settingsChanged();
  }

  void setAnonymousTrailRecommendationsEnabled(bool enabled) {
    if (_anonymousTrailRecommendationsEnabled == enabled) {
      return;
    }
    _anonymousTrailRecommendationsEnabled = enabled;
    _settingsChanged();
  }

  void setHapticSafetyFeedbackEnabled(bool enabled) {
    if (_hapticSafetyFeedbackEnabled == enabled) {
      return;
    }
    _hapticSafetyFeedbackEnabled = enabled;
    _settingsChanged();
  }

  void setLowBatterySafetyWarningEnabled(bool enabled) {
    if (_lowBatterySafetyWarningEnabled == enabled) {
      return;
    }
    _lowBatterySafetyWarningEnabled = enabled;
    _settingsChanged();
  }

  void _settingsChanged() {
    if (_isLoading) {
      _changedWhileLoading = true;
    }
    notifyListeners();
    unawaited(_queuePersist());
  }

  Future<String> _settingsPath() async {
    final separator = Platform.pathSeparator;
    final directory = await getDatabasesPath();
    return '$directory${directory.endsWith(separator) ? '' : separator}'
        'hiker_circle_app_settings.json';
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = File(await _settingsPath());
      if (!await file.exists()) {
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || _changedWhileLoading) {
        return;
      }
      final values = Map<String, dynamic>.from(decoded);
      _themeSetting = HikerCircleThemeSetting.fromLabel(
        values['themeSetting'] is String
            ? values['themeSetting'] as String
            : HikerCircleThemeSetting.system.label,
      );
      _language = 'English';
      _preferredTimeZone = PreferredTimeZone.normalize(
        values['preferredTimeZone'] is String
            ? values['preferredTimeZone'] as String
            : null,
      );
      _preciseLocationEnabled = values['preciseLocationEnabled'] is bool
          ? values['preciseLocationEnabled'] as bool
          : true;
      _anonymousTrailRecommendationsEnabled =
          values['anonymousTrailRecommendationsEnabled'] is bool
          ? values['anonymousTrailRecommendationsEnabled'] as bool
          : false;
      _hapticSafetyFeedbackEnabled =
          values['hapticSafetyFeedbackEnabled'] is bool
          ? values['hapticSafetyFeedbackEnabled'] as bool
          : true;
      _lowBatterySafetyWarningEnabled =
          values['lowBatterySafetyWarningEnabled'] is bool
          ? values['lowBatterySafetyWarningEnabled'] as bool
          : true;
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to load app settings: $error');
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _queuePersist() {
    _writeChain = _writeChain.then((_) async {
      try {
        await _initialization;
        final target = File(await _settingsPath());
        final data = jsonEncode({
          'themeSetting': _themeSetting.label,
          'language': _language,
          'preferredTimeZone': _preferredTimeZone,
          'preciseLocationEnabled': _preciseLocationEnabled,
          'anonymousTrailRecommendationsEnabled':
              _anonymousTrailRecommendationsEnabled,
          'hapticSafetyFeedbackEnabled': _hapticSafetyFeedbackEnabled,
          'lowBatterySafetyWarningEnabled': _lowBatterySafetyWarningEnabled,
        });
        await target.parent.create(recursive: true);
        await target.writeAsString(data, flush: true);
      } catch (error) {
        debugPrint('Unable to save app settings: $error');
      }
    });
    return _writeChain;
  }
}
