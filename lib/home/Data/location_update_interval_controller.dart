import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../Model/location_update_interval.dart';

typedef LoadLocationInterval = Future<Object?> Function(String owner);
typedef SaveLocationInterval = Future<void> Function(String owner, int seconds);

/// Keeps one per-user cadence, with the active hike draft as its current owner.
/// The preference contains no coordinates and uses the encrypted session store.
class LocationUpdateIntervalController extends ChangeNotifier {
  /// Creates location update interval controller.
  LocationUpdateIntervalController({
    required LoadLocationInterval load,
    required SaveLocationInterval save,
  }) : _load = load,
       _save = save;

  static const preferenceKey = 'locationUpdateIntervalSeconds';
  static final _database = LocalSessionDatabase();
  static final instance = LocationUpdateIntervalController(
    load: (owner) => _database.loadLocalPreference(
      ownerPhoneNumber: owner,
      key: preferenceKey,
    ),
    save: (owner, seconds) => _database.saveLocalPreference(
      ownerPhoneNumber: owner,
      key: preferenceKey,
      value: seconds,
    ),
  );

  final LoadLocationInterval _load;
  final SaveLocationInterval _save;
  String? _owner;
  int _generation = 0;
  int _revision = 0;
  int _preferenceRevision = 0;
  Duration _interval = LocationUpdateInterval.defaultValue;
  Duration _preferredInterval = LocationUpdateInterval.defaultValue;
  bool _hasActiveHike = false;
  Future<void>? _loading;
  Future<void> _saveChain = Future<void>.value();

  /// Returns interval.
  Duration get interval => _interval;

  /// Returns preferred interval.
  Duration get preferredInterval => _preferredInterval;

  /// Returns has active hike.
  bool get hasActiveHike => _hasActiveHike;

  /// Loads for user.
  Future<void> loadForUser(String phoneNumber) {
    final owner = phoneNumber.trim();
    if (_owner == owner) return _loading ?? Future<void>.value();
    final keepActiveHike = _owner == null && _hasActiveHike;
    _owner = owner;
    final generation = ++_generation;
    _revision += 1;
    final preferenceRevision = ++_preferenceRevision;
    if (!keepActiveHike) {
      _interval = LocationUpdateInterval.defaultValue;
      _preferredInterval = LocationUpdateInterval.defaultValue;
      _hasActiveHike = false;
    }
    // Publish the owner change immediately so old-account settings cannot leak.
    notifyListeners();
    late final Future<void> loading;
    loading = (() async {
      // Establish _loading before a custom loader can complete or throw.
      await Future<void>.value();
      try {
        final saved = await _load(owner);
        if (generation != _generation ||
            preferenceRevision != _preferenceRevision) {
          return;
        }
        _preferredInterval = saved is int
            ? LocationUpdateInterval.normalize(Duration(seconds: saved))
            : LocationUpdateInterval.defaultValue;
        if (!_hasActiveHike) _interval = _preferredInterval;
        notifyListeners();
      } catch (_) {
        // A route can still be recorded if device settings cannot be restored.
      } finally {
        if (identical(_loading, loading)) _loading = null;
      }
    })();
    _loading = loading;
    return loading;
  }

  /// Persists.
  Future<void> _persist(String owner, Duration interval) {
    final write = _saveChain.then((_) => _save(owner, interval.inSeconds));
    // A failed write must not block future preference changes.
    _saveChain = write.catchError((_) {});
    return write;
  }

  /// A restored or newly started hike supplies the exact shared cadence.
  void bindActiveHike(Duration? value) {
    final active = value != null;
    final interval = value == null
        ? _preferredInterval
        : LocationUpdateInterval.normalize(value);
    if (active == _hasActiveHike && interval == _interval) return;
    _revision += 1;
    _hasActiveHike = active;
    _interval = interval;
    notifyListeners();
  }

  /// Sets interval.
  Future<bool> setInterval(Duration value) async {
    if (!LocationUpdateInterval.options.contains(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported update interval');
    }
    final owner = _owner;
    if (owner == null) return false;
    final generation = _generation;
    await (_loading ?? Future<void>.value());
    if (_generation != generation) return false;
    if (_interval == value && _preferredInterval == value) return true;
    final revision = ++_revision;
    final preferenceRevision = ++_preferenceRevision;
    await _persist(owner, value);
    if (_generation != generation ||
        _preferenceRevision != preferenceRevision) {
      return false;
    }
    _preferredInterval = value;
    if (_revision == revision) _interval = value;
    notifyListeners();
    return true;
  }

  /// Resets.
  void reset() {
    _preferenceRevision += 1;
    _generation += 1;
    _revision += 1;
    _owner = null;
    _loading = null;
    _interval = LocationUpdateInterval.defaultValue;
    _preferredInterval = LocationUpdateInterval.defaultValue;
    _hasActiveHike = false;
    notifyListeners();
  }
}
