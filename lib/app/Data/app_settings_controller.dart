// AppSettingsController persists appearance and reminder choices, including the device-theme default
// when no theme preference is saved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../Model/preferred_time_zone.dart';
import '../../home/Model/path_deviation_policy.dart';

/// Defines the hiker circle theme setting choices.
enum HikerCircleThemeSetting {
  system('System', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  /// Creates this model.
  const HikerCircleThemeSetting(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  /// Creates from label.
  static HikerCircleThemeSetting fromLabel(String label) {
    return HikerCircleThemeSetting.values.firstWhere(
      (setting) => setting.label == label,
      orElse: () => HikerCircleThemeSetting.system,
    );
  }
}

/// Represents app settings controller.
class AppSettingsController extends ChangeNotifier {
  /// Creates app settings controller using .
  AppSettingsController._({String? settingsPath})
    : _settingsPathOverride = settingsPath {
    _initialization = _loadFromDisk();
  }

  /// Creates app settings controller using for testing.
  @visibleForTesting
  AppSettingsController.forTesting({required String settingsPath})
    : this._(settingsPath: settingsPath);

  static final AppSettingsController instance = AppSettingsController._();

  final String? _settingsPathOverride;

  HikerCircleThemeSetting _themeSetting = HikerCircleThemeSetting.system;
  String _preferredTimeZone = PreferredTimeZone.fallbackId;
  bool _preciseLocationEnabled = true;
  bool _privateScreenUnlockEnabled = false;
  bool _hapticSafetyFeedbackEnabled = true;
  bool _lowBatterySafetyWarningEnabled = true;
  double _fallSensorSensitivity = 5;
  int _pathDeviationDistanceMeters = PathDeviationPolicy.defaultDistanceMeters;

  late final Future<void> _initialization;
  Future<void> _writeChain = Future<void>.value();
  bool _isLoading = true;
  bool _changedWhileLoading = false;

  /// Returns theme setting.
  HikerCircleThemeSetting get themeSetting => _themeSetting;

  /// Returns theme mode.
  ThemeMode get themeMode => _themeSetting.themeMode;

  /// Completes once persisted device preferences have been restored.
  Future<void> get ready => _initialization;

  /// Returns preferred time zone.
  String get preferredTimeZone => _preferredTimeZone;

  /// Returns precise location enabled.
  bool get preciseLocationEnabled => _preciseLocationEnabled;

  /// Returns private screen unlock enabled.
  bool get privateScreenUnlockEnabled => _privateScreenUnlockEnabled;

  /// Sets private screen unlock enabled.
  void setPrivateScreenUnlockEnabled(bool value) {
    if (_privateScreenUnlockEnabled == value) return;
    _privateScreenUnlockEnabled = value;
    _settingsChanged();
  }

  /// Returns haptic safety feedback enabled.
  bool get hapticSafetyFeedbackEnabled => _hapticSafetyFeedbackEnabled;

  /// Returns low battery safety warning enabled.
  bool get lowBatterySafetyWarningEnabled => _lowBatterySafetyWarningEnabled;

  /// Returns fall sensor sensitivity.
  double get fallSensorSensitivity => _fallSensorSensitivity;

  /// Returns path deviation distance meters.
  int get pathDeviationDistanceMeters => _pathDeviationDistanceMeters;

  /// Sets fall sensor sensitivity.
  void setFallSensorSensitivity(double value) {
    if (!value.isFinite) return;
    final normalized = value.round().clamp(1, 10).toDouble();
    if (_fallSensorSensitivity == normalized) return;
    _fallSensorSensitivity = normalized;
    _settingsChanged();
  }

  /// Sets path deviation distance meters.
  void setPathDeviationDistanceMeters(int value) {
    final normalized = PathDeviationPolicy.normalizeDistance(value);
    if (_pathDeviationDistanceMeters == normalized) return;
    _pathDeviationDistanceMeters = normalized;
    _settingsChanged();
  }

  /// Returns saved.
  Future<void> get saved => _writeChain;

  /// Returns debug snapshot.
  Map<String, Object?> get debugSnapshot => {
    'storageType': 'App-scoped JSON settings',
    'persistence': 'Persistent on this device',
    'preferredTimeZone': _preferredTimeZone,
    'themeSetting': _themeSetting.label,
    'themeMode': _themeSetting.themeMode.name,
    'preciseLocationEnabled': _preciseLocationEnabled,
    'hapticSafetyFeedbackEnabled': _hapticSafetyFeedbackEnabled,
    'lowBatterySafetyWarningEnabled': _lowBatterySafetyWarningEnabled,
    'fallSensorSensitivity': _fallSensorSensitivity,
    'pathDeviationDistanceMeters': _pathDeviationDistanceMeters,
    'hasListeners': hasListeners,
  };

  /// Sets theme setting.
  void setThemeSetting(HikerCircleThemeSetting setting) {
    if (_themeSetting == setting) {
      return;
    }
    _themeSetting = setting;
    _settingsChanged();
  }

  /// Sets preferred time zone.
  void setPreferredTimeZone(String timeZoneId) {
    final normalized = PreferredTimeZone.normalize(timeZoneId);
    if (_preferredTimeZone == normalized) {
      return;
    }
    _preferredTimeZone = normalized;
    _settingsChanged();
  }

  /// Sets precise location enabled.
  void setPreciseLocationEnabled(bool enabled) {
    if (_preciseLocationEnabled == enabled) {
      return;
    }
    _preciseLocationEnabled = enabled;
    _settingsChanged();
  }

  /// Sets haptic safety feedback enabled.
  void setHapticSafetyFeedbackEnabled(bool enabled) {
    if (_hapticSafetyFeedbackEnabled == enabled) {
      return;
    }
    _hapticSafetyFeedbackEnabled = enabled;
    _settingsChanged();
  }

  /// Sets low battery safety warning enabled.
  void setLowBatterySafetyWarningEnabled(bool enabled) {
    if (_lowBatterySafetyWarningEnabled == enabled) {
      return;
    }
    _lowBatterySafetyWarningEnabled = enabled;
    _settingsChanged();
  }

  /// Computes settings changed.
  void _settingsChanged() {
    if (_isLoading) {
      _changedWhileLoading = true;
    }
    notifyListeners();
    unawaited(_queuePersist());
  }

  /// Computes settings path.
  Future<String> _settingsPath() async {
    final override = _settingsPathOverride;
    if (override != null) return override;
    final separator = Platform.pathSeparator;
    final directory = await getDatabasesPath();
    return '$directory${directory.endsWith(separator) ? '' : separator}'
        'hiker_circle_app_settings.json';
  }

  /// Loads from disk.
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
      _privateScreenUnlockEnabled =
          values['privateScreenUnlockEnabled'] == true;
      _preferredTimeZone = PreferredTimeZone.normalize(
        values['preferredTimeZone'] is String
            ? values['preferredTimeZone'] as String
            : null,
      );
      _preciseLocationEnabled = values['preciseLocationEnabled'] is bool
          ? values['preciseLocationEnabled'] as bool
          : true;
      _hapticSafetyFeedbackEnabled =
          values['hapticSafetyFeedbackEnabled'] is bool
          ? values['hapticSafetyFeedbackEnabled'] as bool
          : true;
      _lowBatterySafetyWarningEnabled =
          values['lowBatterySafetyWarningEnabled'] is bool
          ? values['lowBatterySafetyWarningEnabled'] as bool
          : true;
      final sensitivity = values['fallSensorSensitivity'];
      if (sensitivity is num && sensitivity.isFinite) {
        _fallSensorSensitivity = sensitivity.round().clamp(1, 10).toDouble();
      }
      final deviation = values['pathDeviationDistanceMeters'];
      if (deviation is num && deviation.isFinite) {
        _pathDeviationDistanceMeters = PathDeviationPolicy.normalizeDistance(
          deviation.round(),
        );
      }
      // Drop retired keys after loading, preserving every retained preference.
      if (values.containsKey('language') ||
          values.containsKey('anonymousTrailRecommendationsEnabled')) {
        unawaited(_queuePersist());
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to load app settings: $error');
    } finally {
      _isLoading = false;
    }
  }

  /// Computes queue persist.
  Future<void> _queuePersist() {
    _writeChain = _writeChain.then((_) async {
      try {
        await _initialization;
        final target = File(await _settingsPath());
        final data = jsonEncode({
          'fallSensorSensitivity': _fallSensorSensitivity,
          'pathDeviationDistanceMeters': _pathDeviationDistanceMeters,
          'themeSetting': _themeSetting.label,
          'privateScreenUnlockEnabled': _privateScreenUnlockEnabled,
          'preferredTimeZone': _preferredTimeZone,
          'preciseLocationEnabled': _preciseLocationEnabled,
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
