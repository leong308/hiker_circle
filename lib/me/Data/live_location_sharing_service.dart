// LiveLocationSharingService coordinates sharing preferences, fresh fixes, publishing and explicit stops.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart'
    show LiveLocationContactNotificationResult;
import '../../home/Data/location_update_interval_controller.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../Model/live_location_models.dart';
import '../Model/live_location_message.dart';
import 'live_location_repository.dart';

class LiveLocationSharingService extends ChangeNotifier {
  LiveLocationSharingService({
    LiveLocationRepository Function(FirebaseBootstrapResult)? repositoryFactory,
    LocationUpdateIntervalController? intervalController,
  }) : _repositoryFactory =
           repositoryFactory ??
           ((bootstrap) =>
               LiveLocationRepository(firebaseBootstrapResult: bootstrap)),
       _intervalController =
           intervalController ?? LocationUpdateIntervalController.instance {
    _intervalController.addListener(_updateIntervalChanged);
    _publishInterval = _intervalController.interval;
  }

  final LocationUpdateIntervalController _intervalController;

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
  int _manualStartRevision = 0;
  SosTriggerLocation? _latestHikeLocation;
  int _configurationGeneration = 0;
  Future<void>? _loadFuture;
  Future<void>? _publishFuture;
  Future<void>? _contactNotificationFuture;
  String? _notificationEligibleShareId;
  bool _isNotifyingContacts = false;
  LiveLocationContactNotificationResult? _contactNotificationResult;
  String? _contactNotificationError;

  LiveLocationShare? get share => _share;
  bool get isActive => _isActive;
  bool get isBusy => _isBusy || _isPreferenceBusy;
  bool get isPreferenceBusy => _isPreferenceBusy;
  bool get isSharing => _isSharing;
  bool get autoShareOnHikeStart => _autoShareOnHikeStart;
  String? get errorMessage => _errorMessage;
  Duration get updateInterval => _intervalController.interval;
  bool get hasActiveHike => _intervalController.hasActiveHike;
  SosTriggerLocation? get latestHikeLocation => _latestHikeLocation;
  int get manualStartRevision => _manualStartRevision;
  bool get isNotifyingContacts => _isNotifyingContacts;
  LiveLocationContactNotificationResult? get contactNotificationResult =>
      _contactNotificationResult;
  String? get contactNotificationError => _contactNotificationError;
  bool get canRetryContactNotifications =>
      _isActive &&
      !hasActiveHike &&
      !_isNotifyingContacts &&
      _share?.id == _notificationEligibleShareId &&
      (_contactNotificationError != null ||
          _contactNotificationResult?.shouldRetry == true);

  String? get contactNotificationStatus {
    if (_isNotifyingContacts) {
      return 'Sending live location to your saved SOS contacts…';
    }
    if (_contactNotificationError != null) return _contactNotificationError;
    final result = _contactNotificationResult;
    if (result == null) return null;
    if (result.contactCount == 0) {
      return 'No saved SOS contacts to notify. Your live location is active.';
    }
    if (result.sentCount == result.contactCount) {
      return 'Live location sent to all ${result.contactCount} saved SOS contacts.';
    }
    final details = <String>[
      '${result.sentCount} of ${result.contactCount} SOS contacts sent',
      if (result.failedCount > 0) '${result.failedCount} failed',
      if (result.uncertainCount > 0)
        '${result.uncertainCount} awaiting delivery confirmation',
      if (result.inProgressCount > 0) '${result.inProgressCount} still sending',
    ];
    return '${details.join('; ')}. Your live location remains active.';
  }

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
    'hasActiveHike': hasActiveHike,
    'snapshotIntervalSeconds': _snapshotInterval.inSeconds,
    'isActive': _isActive,
    'manualStopRevision': _manualStopRevision,
    'manualStartRevision': _manualStartRevision,
    'isBusy': _isBusy,
    'isPreferenceBusy': _isPreferenceBusy,
    'autoShareOnHikeStart': _autoShareOnHikeStart,
    'isSharing': _isSharing,
    'isPublishing': _isPublishing,
    'isNotifyingContacts': _isNotifyingContacts,
    'contactNotificationStatus': contactNotificationStatus,
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
      await _loadUpdateInterval(phoneNumber);
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
        if (!hasActiveHike) {
          await LocationSnapshotService.instance.start(
            interval: _snapshotInterval,
          );
        }
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
    bool manual = true,
  }) async {
    _configure(
      phoneNumber: phoneNumber,
      firebaseBootstrapResult: firebaseBootstrapResult,
    );

    if (_isBusy || _isActive) {
      return;
    }

    final repository = _repository!;
    final generation = _configurationGeneration;
    _isBusy = true;
    _errorMessage = null;
    var notifyContactsAfterActivation = false;
    notifyListeners();

    try {
      await _loadUpdateInterval(phoneNumber);
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      final snapshots = LocationSnapshotService.instance;
      if (!hasActiveHike) {
        await snapshots.start(interval: _snapshotInterval);
      }
      final location = snapshots.latestLocation ?? await snapshots.refresh();
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
      if (manual) _manualStartRevision += 1;
      _startPublishTimer();
      if (manual && !hasActiveHike) {
        _notificationEligibleShareId = share.id;
        notifyContactsAfterActivation = true;
      }
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
    if (notifyContactsAfterActivation &&
        _isCurrentConfiguration(generation, repository, phoneNumber)) {
      unawaited(retryStandaloneContactNotifications());
    }
  }

  /// Explicit retries reuse the existing share and the backend recipient deduplication.
  /// Restoration, GPS publication and interval changes never call this method.
  Future<void> retryStandaloneContactNotifications() {
    final pending = _contactNotificationFuture;
    if (pending != null) return pending;
    if (_isNotifyingContacts) return Future<void>.value();
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    final share = _share;
    if (!_isActive ||
        hasActiveHike ||
        repository == null ||
        phoneNumber == null ||
        share == null ||
        share.id != _notificationEligibleShareId) {
      return Future<void>.value();
    }
    if (_contactNotificationResult != null &&
        !_contactNotificationResult!.shouldRetry &&
        _contactNotificationError == null) {
      return Future<void>.value();
    }
    final generation = _configurationGeneration;
    _isNotifyingContacts = true;
    _contactNotificationError = null;
    notifyListeners();
    late final Future<void> operation;
    operation =
        _notifyStandaloneContacts(
          repository,
          phoneNumber,
          share.id,
          generation,
        ).whenComplete(() {
          if (identical(_contactNotificationFuture, operation)) {
            _contactNotificationFuture = null;
          }
        });
    _contactNotificationFuture = operation;
    return operation;
  }

  Future<void> _notifyStandaloneContacts(
    LiveLocationRepository repository,
    String phoneNumber,
    String shareId,
    int generation,
  ) async {
    bool isCurrent() =>
        _isCurrentConfiguration(generation, repository, phoneNumber) &&
        _isActive &&
        !hasActiveHike &&
        _share?.id == shareId &&
        _notificationEligibleShareId == shareId;
    try {
      final result = await repository.notifyStandaloneContacts(
        shareId: shareId,
      );
      if (isCurrent()) _contactNotificationResult = result;
    } catch (_) {
      if (isCurrent()) {
        _contactNotificationError =
            'Live location is active, but SOS contact notification could not be confirmed. Retry when connected.';
      }
    } finally {
      if (isCurrent()) {
        _isNotifyingContacts = false;
        notifyListeners();
      }
    }
  }

  void _clearContactNotifications() {
    _contactNotificationFuture = null;
    _notificationEligibleShareId = null;
    _isNotifyingContacts = false;
    _contactNotificationResult = null;
    _contactNotificationError = null;
  }

  /// Stop local publication immediately and preserve manual-stop intent while backend cleanup retries.
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
    _clearContactNotifications();
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
    // Footprint uploads already update the public share from the same sample.
    // This must precede any GPS, database or network work while hiking.
    if (hasActiveHike) return Future<void>.value();
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

  /// Discard work from an old account/configuration and publish only an acceptable current location fix.
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
      if (hasActiveHike ||
          !_isCurrentConfiguration(generation, repository, phoneNumber)) {
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
      final text = composeStandaloneLiveLocationMessage(
        ownerPhone: phoneNumber,
        share: share,
        timeZoneId: AppSettingsController.instance.preferredTimeZone,
      );
      await _deviceService.shareText(
        subject: 'HikerCircle Live Location',
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
    _latestHikeLocation = null;
    _clearContactNotifications();
    _intervalController.reset();
    _publishInterval = _intervalController.interval;
    _snapshotInterval = _publishInterval;
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
    _latestHikeLocation = null;
    _clearContactNotifications();
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
    unawaited(_loadUpdateInterval(phoneNumber));
  }

  /// Guard late asynchronous results against account switches and reconfiguration.
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

  Future<void> _loadUpdateInterval(String phoneNumber) =>
      _intervalController.loadForUser(phoneNumber);

  Future<bool> setUpdateInterval(Duration interval) async {
    final phoneNumber = _phoneNumber;
    final repository = _repository;
    if (phoneNumber == null || repository == null || _isPreferenceBusy) {
      return false;
    }
    final generation = _configurationGeneration;
    _isPreferenceBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _loadUpdateInterval(phoneNumber);
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return false;
      }
      return await _intervalController.setInterval(interval);
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage =
            'Unable to save the location update interval. Try again.';
      }
      return false;
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isPreferenceBusy = false;
        notifyListeners();
      }
    }
  }

  /// The active hike owns the same value used by the standalone sharing page.
  void setPublishInterval(Duration? interval) {
    _intervalController.bindActiveHike(interval);
  }

  /// Observe an already accepted footprint for this screen; perform no fetch,
  /// upload or GPS acquisition. The footprint batch separately feeds the viewer.
  void recordHikeLocation(SosTriggerLocation location) {
    final capturedAt = location.capturedAt;
    if (!hasActiveHike ||
        capturedAt == null ||
        !location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        location.longitude < -180 ||
        location.longitude > 180) {
      return;
    }
    final now = DateTime.now().toUtc();
    if (capturedAt.isAfter(now.add(const Duration(minutes: 2))) ||
        now.difference(capturedAt) >
            LocationSnapshotService.maximumEmergencySnapshotAge) {
      return;
    }
    final previousAt = _latestHikeLocation?.capturedAt;
    if (previousAt != null && !capturedAt.isAfter(previousAt)) return;
    _latestHikeLocation = location;
    notifyListeners();
  }

  void _updateIntervalChanged() {
    if (hasActiveHike) _clearContactNotifications();
    if (!hasActiveHike) _latestHikeLocation = null;
    _publishInterval = _intervalController.interval;
    _snapshotInterval = hasActiveHike
        ? const Duration(seconds: 5)
        : _publishInterval;
    _publishTimer?.cancel();
    _publishTimer = null;
    if (_isActive && !hasActiveHike) {
      unawaited(
        LocationSnapshotService.instance
            .start(interval: _snapshotInterval)
            .catchError((_) {}),
      );
      _startPublishTimer();
    }
    notifyListeners();
  }

  void _startPublishTimer() {
    _publishTimer?.cancel();
    _publishTimer = null;
    if (hasActiveHike) return;
    _publishTimer = Timer.periodic(_publishInterval, (_) {
      unawaited(publishLatest());
    });
  }

  @override
  void dispose() {
    _configurationGeneration += 1;
    _clearContactNotifications();
    _publishTimer?.cancel();
    _intervalController.removeListener(_updateIntervalChanged);
    super.dispose();
  }
}
