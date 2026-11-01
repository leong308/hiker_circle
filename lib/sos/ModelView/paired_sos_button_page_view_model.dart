part of '../paired_sos_button_page_feature.dart';

/// Owns the state and non-visual actions of PairedSosButtonPage.
class _PairedSosButtonPageStateViewModel extends ChangeNotifier {
  /// Creates paired sos button page state view model.
  _PairedSosButtonPageStateViewModel({required this.readAccountId});
  final String Function() readAccountId;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final HikerBleService stateBle = const HikerBleService();

  List<PairedSosButton> statePaired = const [];

  bool stateAccountReady = false;

  bool stateRegistryNeedsReset = false;

  String? stateMessage;

  SosButtonReadiness? stateReadiness;

  bool stateReadinessLoading = false;
  StreamSubscription<HikerBleEvent>? _presenceSubscription;
  bool _refreshAgain = false;

  /// Computes initialize.
  Future<void> commandInitialize() async {
    try {
      await stateBle.setActiveSosAccount(readAccountId());
      if (!mounted) return;
      stateAccountReady = true;
      _presenceSubscription ??= stateBle.events.listen((event) {
        if (event is HikerBleStatusEvent &&
            {
              'paired_button_presence_changed',
              'paired_button_notice',
              'paired_button_paired',
            }.contains(event.status)) {
          unawaited(commandRefreshReadiness());
        }
      }, onError: (Object _) {});
      await commandLoadPaired();
    } on HikerBleException catch (error) {
      if (!mounted) return;
      _publish(() => stateMessage = error.message);
    }
  }

  /// Cancels button test silently.
  Future<void> commandCancelButtonTestSilently() async {
    try {
      await stateBle.cancelPairedSosButtonTest();
    } catch (_) {
      // Native test mode is also bounded by its own 30-second expiry.
    }
  }

  /// Loads paired.
  Future<void> commandLoadPaired() async {
    try {
      final paired = await stateBle.listPairedSosButtons();
      if (mounted) {
        _publish(() {
          if (stateReadiness == null || !stateReadiness!.supported) {
            statePaired = paired;
          }
          stateRegistryNeedsReset = false;
        });
        await commandRefreshReadiness();
      }
    } on HikerBleException {
      if (mounted) _publish(() => stateRegistryNeedsReset = true);
      rethrow;
    }
  }

  /// Refreshes readiness.
  Future<void> commandRefreshReadiness() async {
    if (stateReadinessLoading) {
      _refreshAgain = true;
      return;
    }
    if (mounted) _publish(() => stateReadinessLoading = true);
    try {
      final readiness = await stateBle.getSosButtonReadiness();
      if (mounted) {
        _publish(() {
          stateReadiness = readiness;
          // Both sections must render the exact same native presence snapshot.
          if (readiness.supported) statePaired = readiness.pairedButtons;
        });
      }
    } on HikerBleException catch (error) {
      if (mounted) _publish(() => stateMessage = error.message);
    } finally {
      if (mounted) {
        _publish(() => stateReadinessLoading = false);
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(commandRefreshReadiness());
        }
      }
    }
  }

  /// Formats uptime.
  String commandFormatUptime(Duration uptime) {
    final hours = uptime.inHours;
    final minutes = uptime.inMinutes.remainder(60);
    final seconds = uptime.inSeconds.remainder(60);
    return '${hours}h ${minutes}m ${seconds}s';
  }

  /// Formats log record.
  String commandFormatLogRecord(HikerBleButtonLogRecord record) {
    final when =
        record.epochTime?.toUtc().toIso8601String() ??
        'uptime=${record.uptimeMillis}ms';
    return 'seq=${record.sequence} type=${record.typeLabel} $when '
        'event=${record.eventId} detail=${record.detail} '
        'reset=${record.resetReason}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    unawaited(_presenceSubscription?.cancel());
    super.dispose();
  }

  late final Future<bool?> Function() effectPresentDownloadLogsEffect1;

  late final Future<bool?> Function() effectPresentOpenPairingGuideEffect1;

  late final Future<void> Function(
    PairedSosButton button,
    List<HikerBleButtonLogRecord> records,
  )
  effectPresentDownloadLogsEffect2;

  late final Future<bool?> Function(PairedSosButton button)
  effectPresentUnpairEffect1;

  late final void Function(HikerBleException error)
  effectPresentDownloadLogsEffect3;

  late final Future<bool?> Function() effectPresentResetPairingDataEffect1;

  late final void Function(HikerBleException error) effectPresentUnpairEffect2;

  late final Future<void> Function(PairedSosButton button)
  effectShowLogServiceRecoveryDialog;

  bool statePairingInProgress = false;

  String? stateDownloadingLogsFor;

  /// Opens pairing guide.
  Future<void> commandOpenPairingGuide() async {
    if (!stateAccountReady ||
        stateRegistryNeedsReset ||
        statePairingInProgress) {
      return;
    }
    _publish(() {
      statePairingInProgress = true;
      stateMessage = null;
    });
    final paired = await effectPresentOpenPairingGuideEffect1();
    if (!mounted) return;
    _publish(() {
      statePairingInProgress = false;
      if (paired == true) {
        stateMessage = 'SOS button paired and ready.';
      }
    });
  }

  /// Computes unpair.
  Future<void> commandUnpair(PairedSosButton button) async {
    final confirmed = await effectPresentUnpairEffect1(button);
    if (confirmed != true) return;
    try {
      final removed = await stateBle.unpairSosButton(button.deviceId);
      if (!removed) {
        throw const HikerBleException(
          'The SOS button was not removed. Refresh and try again.',
        );
      }
      await commandLoadPaired();
    } on HikerBleException catch (error) {
      if (mounted) {
        effectPresentUnpairEffect2(error);
      }
    }
  }

  /// Resets pairing data.
  Future<void> commandResetPairingData() async {
    final confirmed = await effectPresentResetPairingDataEffect1();
    if (confirmed != true || !mounted) return;

    _publish(() => statePairingInProgress = true);
    try {
      await stateBle.resetPairedSosButtonRegistry();
      await commandLoadPaired();
      if (!mounted) return;
      _publish(() {
        stateMessage =
            'Local pairing data was reset. Put the button in setup mode and pair it again.';
      });
    } on HikerBleException catch (error) {
      if (mounted) _publish(() => stateMessage = error.message);
    } finally {
      if (mounted) _publish(() => statePairingInProgress = false);
    }
  }

  /// Downloads logs.
  Future<void> commandDownloadLogs(PairedSosButton button) async {
    final ready = await effectPresentDownloadLogsEffect1();
    if (ready != true || !mounted) return;

    await stateBle.stopPairedButtonSetupScan();
    if (!mounted) return;
    _publish(() {
      stateDownloadingLogsFor = button.deviceId;
    });
    try {
      final records = await stateBle.readPairedSosButtonLog(button.deviceId);
      if (!mounted) return;
      await effectPresentDownloadLogsEffect2(button, records);
    } on HikerBleException catch (error) {
      if (mounted) {
        if (error.code == 'paired_button_log_service_missing' ||
            error.code == 'paired_button_log_bluetooth_cache_stale') {
          await effectShowLogServiceRecoveryDialog(button);
        } else {
          effectPresentDownloadLogsEffect3(error);
        }
      }
    } finally {
      if (mounted) _publish(() => stateDownloadingLogsFor = null);
    }
  }
}
