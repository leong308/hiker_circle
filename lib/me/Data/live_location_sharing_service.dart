import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../Model/live_location_models.dart';
import 'live_location_repository.dart';

class LiveLocationSharingService extends ChangeNotifier {
  LiveLocationSharingService._();

  static final LiveLocationSharingService instance =
      LiveLocationSharingService._();

  final SosDeviceAlertService _deviceService = const SosDeviceAlertService();

  LiveLocationRepository? _repository;
  String? _phoneNumber;
  Timer? _publishTimer;
  LiveLocationShare? _share;
  bool _isActive = false;
  bool _isBusy = false;
  bool _isSharing = false;
  bool _isPublishing = false;
  String? _errorMessage;
  int _configurationGeneration = 0;
  Future<void>? _publishFuture;

  LiveLocationShare? get share => _share;
  bool get isActive => _isActive;
  bool get isBusy => _isBusy;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;

  Map<String, Object?> get debugSnapshot => {
    'storageType': 'In-memory live-location sharing session',
    'persistence': 'Process lifetime; cloud share is stored separately',
    'repositoryConfigured': _repository != null,
    'configuredPhoneNumber': _phoneNumber,
    'publishTimerActive': _publishTimer?.isActive == true,
    'isActive': _isActive,
    'isBusy': _isBusy,
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

    if (_isActive || _isBusy) {
      return;
    }

    final repository = _repository!;
    final generation = _configurationGeneration;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
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
      if (existingShare != null) {
        _share = existingShare;
        _isActive = true;
        await LocationSnapshotService.instance.start(
          interval: LocationSnapshotService.liveSnapshotInterval,
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
      await LocationSnapshotService.instance.start(
        interval: LocationSnapshotService.liveSnapshotInterval,
      );
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

  Future<void> deactivate() async {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    if (repository == null || phoneNumber == null || _isBusy) {
      return;
    }

    final generation = _configurationGeneration;
    _isBusy = true;
    _errorMessage = null;
    _publishTimer?.cancel();
    _publishTimer = null;
    notifyListeners();

    try {
      await _publishFuture;
      await repository.deactivate(phoneNumber: phoneNumber, share: _share);
      if (!_isCurrentConfiguration(generation, repository, phoneNumber)) {
        return;
      }
      _isActive = false;
      _share = _share?.copyWith(isActive: false);
    } on LiveLocationRepositoryException catch (error) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _errorMessage = 'Unable to stop live location sharing.';
      }
    } finally {
      if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
        _isBusy = false;
        if (_isActive) {
          _startPublishTimer();
        }
        notifyListeners();
      }
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
        await repository.deactivate(phoneNumber: phoneNumber, share: share);
        if (_isCurrentConfiguration(generation, repository, phoneNumber)) {
          _isActive = false;
          _publishTimer?.cancel();
          _publishTimer = null;
          _share = share.copyWith(isActive: false);
        }
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
    if (share == null || repository == null || _phoneNumber != phoneNumber) {
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
    final publishFuture = _publishFuture;
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
    _isSharing = false;
    _isPublishing = false;
    _publishFuture = null;
    _errorMessage = null;
    notifyListeners();
    if (shouldDeactivate) {
      _deactivateBestEffort(
        repository: repository,
        phoneNumber: phoneNumber,
        share: share,
        publishFuture: publishFuture,
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
    final previousPublishFuture = _publishFuture;
    final previousWasActive = _isActive;
    _configurationGeneration += 1;
    _publishTimer?.cancel();
    _publishTimer = null;
    _share = null;
    _isActive = false;
    _isBusy = false;
    _isSharing = false;
    _isPublishing = false;
    _publishFuture = null;
    _errorMessage = null;
    if (previousWasActive &&
        previousRepository != null &&
        previousPhoneNumber != null) {
      _deactivateBestEffort(
        repository: previousRepository,
        phoneNumber: previousPhoneNumber,
        share: previousShare,
        publishFuture: previousPublishFuture,
      );
    }

    _phoneNumber = phoneNumber;
    _repository = LiveLocationRepository(
      firebaseBootstrapResult: firebaseBootstrapResult,
    );
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
    Future<void>? publishFuture,
  }) {
    unawaited(() async {
      try {
        await publishFuture;
        await repository.deactivate(phoneNumber: phoneNumber, share: share);
      } catch (_) {
        // Account/session cleanup is best effort and must not escape its zone.
      }
    }());
  }

  void _startPublishTimer() {
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(
      LocationSnapshotService.liveSnapshotInterval,
      (_) {
        unawaited(publishLatest());
      },
    );
  }
}
