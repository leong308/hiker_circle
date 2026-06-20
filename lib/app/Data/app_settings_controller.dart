import 'package:flutter/material.dart';

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
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  HikerCircleThemeSetting _themeSetting = HikerCircleThemeSetting.system;
  bool _preciseLocationEnabled = true;
  bool _anonymousTrailRecommendationsEnabled = false;
  bool _hapticSafetyFeedbackEnabled = true;
  bool _lowBatterySafetyWarningEnabled = true;

  HikerCircleThemeSetting get themeSetting => _themeSetting;
  ThemeMode get themeMode => _themeSetting.themeMode;
  bool get preciseLocationEnabled => _preciseLocationEnabled;
  bool get anonymousTrailRecommendationsEnabled =>
      _anonymousTrailRecommendationsEnabled;
  bool get hapticSafetyFeedbackEnabled => _hapticSafetyFeedbackEnabled;
  bool get lowBatterySafetyWarningEnabled => _lowBatterySafetyWarningEnabled;

  Map<String, Object?> get debugSnapshot => {
    'storageType': 'In-memory app settings',
    'persistence': 'Process lifetime only',
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
    notifyListeners();
  }

  void setPreciseLocationEnabled(bool enabled) {
    if (_preciseLocationEnabled == enabled) {
      return;
    }
    _preciseLocationEnabled = enabled;
    notifyListeners();
  }

  void setAnonymousTrailRecommendationsEnabled(bool enabled) {
    if (_anonymousTrailRecommendationsEnabled == enabled) {
      return;
    }
    _anonymousTrailRecommendationsEnabled = enabled;
    notifyListeners();
  }

  void setHapticSafetyFeedbackEnabled(bool enabled) {
    if (_hapticSafetyFeedbackEnabled == enabled) {
      return;
    }
    _hapticSafetyFeedbackEnabled = enabled;
    notifyListeners();
  }

  void setLowBatterySafetyWarningEnabled(bool enabled) {
    if (_lowBatterySafetyWarningEnabled == enabled) {
      return;
    }
    _lowBatterySafetyWarningEnabled = enabled;
    notifyListeners();
  }
}
