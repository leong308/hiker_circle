import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../Model/live_location_models.dart';
import 'live_location_repository.dart';

class LiveLocationSharingService extends ChangeNotifier {
  LiveLocationSharingService({
    LiveLocationRepository Function(FirebaseBootstrapResult)? repositoryFactory,
  }) : _repositoryFactory =
           repositoryFactory ??
           ((bootstrap) =>
               LiveLocationRepository(firebaseBootstrapResult: bootstrap));

  final LiveLocationRepository Function(FirebaseBootstrapResult)
  _repositoryFactory;

  static final LiveLocationSharingService instance =
      LiveLocationSharingService();

  final SosDeviceAlertService _deviceService = const SosDeviceAlertService();

  LiveLocationRepository? _repository;
  String? _phoneNumber;
  Timer? _publishTimer;
  Duration _publishInterval = LocationSnapshotService.liveSnapshotInterval;
  Duration _snapshotInterval = LocationSnapshotService.liveSnapshotInterval;
  LiveLocationShare? _share;
  bool _isActive = false;
  bool _isBusy = false;
  bool _isPreferenceBusy = false;
  bool _isSharing = false;
  bool _isPublishing = false;
  String? _errorMessage;
  bool _autoShareOnHikeStart = false;
  int _manualStopRevision = 0;
  int _configurationGeneration = 0;
  Future<void>? _loadFuture;
  Future<void>? _publishFuture;

  LiveLocationShare? get share => _share;
  bool get isActive => _isActive;
  bool get isBusy => _isBusy || _isPreferenceBusy;
  bool get isPreferenceBusy => _isPreferenceBusy;
  bool get isSharing => _isSharing;
  bool get autoShareOnHikeStart => _autoShareOnHikeStart;
  String? get errorMessage => _errorMessage;

  /// Changes synchronously when the user requests a stop. This stays monotonic
  /// across account/configuration resets so listeners can persist hike opt-outs.
  int get manualStopRevision => _manualStopRevision;

  Map<String, Object?> get debugSnapshot => {
    'storageType': 'In-memory live-location sharing session',
    'persistence': 'Process lifetime; cloud share is stored separately',
    'repositoryConfigured': _repository != null,
    'configuredPhoneNumber': _phoneNumber,
    'publishTimerActive': _publishTimer?.isActive == true,
    'publishIntervalSeconds': _publishInterval.inSeconds,
    'snapshotIntervalSeconds': _snapshotInterval.inSeconds,
    'isActive': _isActive,
    'manualStopRevision': _manualStopRevision,
    'isBusy': _isBusy,
    'isPreferenceBusy': _isPreferenceBusy,
    'autoShareOnHikeStart': _autoShareOnHikeStart,
    'isSharing': _isSharing,
    'isPublishing': _isPublishing,
    'errorMessage': _errorMessage,
    'share': _share == null
        ? null
        : {
            'id': _share!.id,
            'shareUrl': _share!.shareUrl,
            'isActive': _share!.isActive,
            'expiresAt': _share!.expiresAt.toIso8601String(),
            'latestLocation': _share!.latestLocation?.toFirestore(),
          },
  };

  Future<void> loadExisting({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) async {
    _configure(
      phoneNumber: phoneNumber,
      firebaseBootstrapResult: firebaseBootstrapResult,
    );

    final pendingLoad = _loadFuture;
    if (pendingLoad != null) {
      await pendingLoad;
      return;
    }
    if (_isActive || _isBusy) return;

    late final Future<void> operation;
    operation = _loadExistingForCurrentConfiguration(phoneNumber: phoneNumber)
        .whenComplete(() {
          if (identical(_loadFuture, operation)) {
            _loadFuture = null;
          }
        });
    _loadFuture = operation;
    await operation;
  }

  Future<void> _loadExistingForCurrentConfiguration({
    required String phoneNumber,
  }) async {
    final repository = _repository!;
    final generation = _configurationGeneration;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final autoShareOnHikeStart = await repository.loadAutoShareOnHikeStart(
        phoneNumber: phoneNumber,
      );
      final existingShare = await repository.loadForUser(
        phoneNumber: phoneNumber,
      );
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        if (existingShare != null) {
          _deactivateBestEffort(
            repository: repository,
            phoneNumber: phoneNumber,
            share: existingShare,
          );
        }
        return;
      }
      _autoShareOnHikeStart = autoShareOnHikeStart;
      if (existingShare != null) {
        _share = existingShare;
        _isActive = true;
        await LocationSnapshotService.instance.start(
          interval: _snapshotInterval,
        );
        if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
          _deactivateBestEffort(
            repository: repository,
            phoneNumber: phoneNumber,
            share: existingShare,
          );
          return;
        }
        _startPublishTimer();
        unawaited(publishLatest());
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = 'Unable to load live location sharing status.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> setAutoShareOnHikeStart({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
    required bool enabled,
  }) async {
    _configure(
      phoneNumber: phoneNumber,
      firebaseBootstrapResult: firebaseBootstrapResult,
    );
    if (_isPreferenceBusy) return;

    final repository = _repository!;
    final generation = _configurationGeneration;
    _isPreferenceBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await repository.setAutoShareOnHikeStart(
        phoneNumber: phoneNumber,
        enabled: enabled,
      );
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _autoShareOnHikeStart = enabled;
      }
    } on LiveLocationRepositoryException catch (error) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = 'Unable to save the automatic sharing preference.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isPreferenceBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> activate({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) async {
    _configure(
      phoneNumber: phoneNumber,
      firebaseBootstrapResult: firebaseBootstrapResult,
    );

    if (_isBusy) {
      return;
    }

    final repository = _repository!;
    final generation = _configurationGeneration;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await LocationSnapshotService.instance.start(interval: _snapshotInterval);
      final location = await LocationSnapshotService.instance.refresh();
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      if (location == null) {
        throw const LiveLocationRepositoryException(
          'Location unavailable. Check GPS and location permission.',
        );
      }

      final share = await repository.activate(
        phoneNumber: phoneNumber,
        location: location,
      );
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _deactivateBestEffort(
          repository: repository,
          phoneNumber: phoneNumber,
          share: share,
        );
        return;
      }
      _share = share;
      _isActive = true;
      _startPublishTimer();
    } on LiveLocationRepositoryException catch (error) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = 'Unable to activate live location sharing.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> deactivate({bool manual = true}) async {
    if (manual) _manualStopRevision += 1;
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    if (repository == null || phoneNumber == null) {
      if (manual) notifyListeners();
      return;
    }
    final previousShare = _share;
    final generation = ++_configurationGeneration;
    _publishTimer?.cancel();
    _publishTimer = null;
    _loadFuture = null;
    _publishFuture = null;
    _isPublishing = false;
    _isActive = false;
    _share = previousShare?.copyWith(isActive: false);
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Repository persists the stop before contacting the cloud. In-flight
      // location refreshes have already been invalidated by the generation.
      await repository.deactivate(
        phoneNumber: phoneNumber,
        share: previousShare,
      );
    } on LiveLocationStopPersistenceException {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage =
            'Sharing paused on this phone, but the stop could not be saved. Try stopping again before closing the app.';
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage =
            'Sharing stopped on this phone. Cloud deactivation is pending and will retry when connected.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> retryPendingStop() async {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    if (repository == null || phoneNumber == null) return;
    try {
      await repository.retryPendingStop(phoneNumber);
    } catch (_) {
      // The durable stop remains pending; local publication stays disabled.
    }
  }

  Future<void> publishLatest() {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    final share = _share;
    if (!_isActive ||
        _isBusy ||
        _isPublishing ||
        repository == null ||
        phoneNumber == null ||
        share == null) {
      return Future<void>.value();
    }

    final generation = _configurationGeneration;
    _isPublishing = true;
    late final Future<void> operation;
    operation =
        _publishLatest(
          repository: repository,
          phoneNumber: phoneNumber,
          share: share,
          generation: generation,
        ).whenComplete(() {
          if (identical(_publishFuture, operation)) {
            _publishFuture = null;
          }
        });
    _publishFuture = operation;
    return operation;
  }

  Future<void> _publishLatest({
    required LiveLocationRepository repository,
    required String phoneNumber,
    required LiveLocationShare share,
    required int generation,
  }) async {
    try {
      final snapshotService = LocationSnapshotService.instance;
      final location =
          await snapshotService.refresh() ?? snapshotService.latestLocation;
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      if (location == null) {
        return;
      }
      if (!share.expiresAt.isAfter(DateTime.now().toUtc())) {
        await deactivate(manual: false);
        return;
      }

      await repository.updateLocation(
        phoneNumber: phoneNumber,
        share: share,
        location: location,
      );
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      _share = share.copyWith(latestLocation: location);
      _errorMessage = null;
    } on LiveLocationRepositoryException catch (error) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = 'Unable to update live location right now.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isPublishing = false;
        notifyListeners();
      }
    }
  }

  Future<void> shareLiveLocation({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) async {
    if (!_isActive || _share == null) {
      await activate(
        phoneNumber: phoneNumber,
        firebaseBootstrapResult: firebaseBootstrapResult,
      );
    }

    final share = _share;
    final repository = _repository;
    if (!_isActive ||
        share == null ||
        repository == null ||
        _phoneNumber != phoneNumber) {
      return;
    }

    final generation = _configurationGeneration;
    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await publishLatest();
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      final text = 'HikerCircle live location\n${share.shareUrl}';
      await _deviceService.shareText(
        subject: 'HikerCircle live location',
        text: text,
      );
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        await Clipboard.setData(ClipboardData(text: share.shareUrl));
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isSharing = false;
        notifyListeners();
      }
    }
  }

  void reset() {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    final share = _share;
    final shouldDeactivate =
        _isActive && repository != null && phoneNumber != null;
    _configurationGeneration += 1;
    _publishTimer?.cancel();
    _publishTimer = null;
    _repository = null;
    _phoneNumber = null;
    _share = null;
    _isActive = false;
    _isBusy = false;
    _isPreferenceBusy = false;
    _isSharing = false;
    _isPublishing = false;
    _publishFuture = null;
    _loadFuture = null;
    _errorMessage = null;
    _autoShareOnHikeStart = false;
    _publishInterval = LocationSnapshotService.liveSnapshotInterval;
    _snapshotInterval = LocationSnapshotService.liveSnapshotInterval;
    notifyListeners();
    if (shouldDeactivate) {
      _deactivateBestEffort(
        repository: repository,
        phoneNumber: phoneNumber,
        share: share,
      );
    }
  }

  void _configure({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) {
    if (_phoneNumber == phoneNumber && _repository != null) {
      return;
    }

    final previousRepository = _repository;
    final previousPhoneNumber = _phoneNumber;
    final previousShare = _share;
    final previousWasActive = _isActive;
    _configurationGeneration += 1;
    _publishTimer?.cancel();
    _publishTimer = null;
    _share = null;
    _isActive = false;
    _isBusy = false;
    _isPreferenceBusy = false;
    _isSharing = false;
    _isPublishing = false;
    _publishFuture = null;
    _loadFuture = null;
    _errorMessage = null;
    _autoShareOnHikeStart = false;
    if (previousWasActive &&
        previousRepository != null &&
        previousPhoneNumber != null) {
      _deactivateBestEffort(
        repository: previousRepository,
        phoneNumber: previousPhoneNumber,
        share: previousShare,
      );
    }

    _phoneNumber = phoneNumber;
    _repository = _repositoryFactory(firebaseBootstrapResult);
  }

  bool _isCurrentConfiguration(
    int generation,
    LiveLocationRepository repository,
    String phoneNumber,
  ) {
    return generation == _configurationGeneration &&
        identical(repository, _repository) &&
        phoneNumber == _phoneNumber;
  }

  void _deactivateBestEffort({
    required LiveLocationRepository repository,
    required String phoneNumber,
    required LiveLocationShare? share,
  }) {
    unawaited(() async {
      try {
        await repository.deactivate(phoneNumber: phoneNumber, share: share);
      } catch (_) {
        // Account/session cleanup is best effort and must not escape its zone.
      }
    }());
  }

  void setPublishInterval(Duration? interval) {
    final snapshotInterval = interval == null
        ? LocationSnapshotService.liveSnapshotInterval
        : const Duration(seconds: 5);
    if (_snapshotInterval != snapshotInterval) {
      _snapshotInterval = snapshotInterval;
      if (_isActive) {
        unawaited(
          LocationSnapshotService.instance
              .start(interval: _snapshotInterval)
              .catchError((_) {}),
        );
      }
    }
    final requested = interval ?? LocationSnapshotService.liveSnapshotInterval;
    final normalized = requested < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : requested;
    if (_publishInterval == normalized) return;
    _publishInterval = normalized;
    if (_isActive) _startPublishTimer();
  }

  void _startPublishTimer() {
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(_publishInterval, (_) {
      unawaited(publishLatest());
    });
  }
}
