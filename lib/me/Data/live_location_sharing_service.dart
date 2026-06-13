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

  LiveLocationShare? get share => _share;
  bool get isActive => _isActive;
  bool get isBusy => _isBusy;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;

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

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final existingShare = await _repository!.loadForUser(
        phoneNumber: phoneNumber,
      );
      if (existingShare != null) {
        _share = existingShare;
        _isActive = true;
        await LocationSnapshotService.instance.start(
          interval: LocationSnapshotService.liveSnapshotInterval,
        );
        _startPublishTimer();
        unawaited(publishLatest());
      }
    } catch (_) {
      _errorMessage = 'Unable to load live location sharing status.';
    } finally {
      _isBusy = false;
      notifyListeners();
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

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await LocationSnapshotService.instance.start(
        interval: LocationSnapshotService.liveSnapshotInterval,
      );
      final location = await LocationSnapshotService.instance.refresh();
      if (location == null) {
        throw const LiveLocationRepositoryException(
          'Location unavailable. Check GPS and location permission.',
        );
      }

      final share = await _repository!.activate(
        phoneNumber: phoneNumber,
        location: location,
      );
      _share = share;
      _isActive = true;
      _startPublishTimer();
    } on LiveLocationRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to activate live location sharing.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> deactivate() async {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    if (repository == null || phoneNumber == null || _isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await repository.deactivate(phoneNumber: phoneNumber, share: _share);
      _isActive = false;
      _publishTimer?.cancel();
      _publishTimer = null;
      _share = _share?.copyWith(isActive: false);
    } on LiveLocationRepositoryException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Unable to stop live location sharing.';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> publishLatest() async {
    final repository = _repository;
    final phoneNumber = _phoneNumber;
    final share = _share;
    if (!_isActive ||
        _isPublishing ||
        repository == null ||
        phoneNumber == null ||
        share == null) {
      return;
    }

    _isPublishing = true;
    try {
      final location =
          LocationSnapshotService.instance.latestLocation ??
          await LocationSnapshotService.instance.refresh();
      if (location == null) {
        return;
      }

      await repository.updateLocation(
        phoneNumber: phoneNumber,
        share: share,
        location: location,
      );
      _share = share.copyWith(latestLocation: location);
    } finally {
      _isPublishing = false;
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
    if (share == null) {
      return;
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await publishLatest();
      final text = 'HikerCircle live location\n${share.shareUrl}';
      await _deviceService.shareText(
        subject: 'HikerCircle live location',
        text: text,
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: share.shareUrl));
    } finally {
      _isSharing = false;
      notifyListeners();
    }
  }

  void reset() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _repository = null;
    _phoneNumber = null;
    _share = null;
    _isActive = false;
    _isBusy = false;
    _isSharing = false;
    _isPublishing = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _configure({
    required String phoneNumber,
    required FirebaseBootstrapResult firebaseBootstrapResult,
  }) {
    if (_phoneNumber == phoneNumber && _repository != null) {
      return;
    }

    _phoneNumber = phoneNumber;
    _repository = LiveLocationRepository(
      firebaseBootstrapResult: firebaseBootstrapResult,
    );
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
