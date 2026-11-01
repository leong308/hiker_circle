// SosViewModel coordinates SOS dashboard state, alert triggering, acknowledgement and retry feedback.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_repository.dart';
import '../Model/sos_models.dart';
import 'emergency_contacts_view_model.dart';

/// Coordinates sos view model state and actions.
class SosViewModel extends ChangeNotifier {
  /// Creates sos view model.
  SosViewModel({
    required AppSession session,
    SosRepository repository = const SosRepository(),
    this.emergencyContactsRepository = const EmergencyContactsRepository(),
    SosAlertRepository? sosAlertRepository,
  }) : _session = session,
       _sosAlertRepository = sosAlertRepository ?? SosAlertRepository(),
       dashboard = repository.loadDashboard(),
       _emergencyContacts = repository.loadEmergencyContacts(),
       _metrics = repository.loadMetrics(),
       sections = repository.loadSections() {
    _contactsSubscription = EmergencyContactsRepository.changes.listen((
      change,
    ) {
      if (!_isDisposed && change.phoneNumber == _session.phoneNumber) {
        replaceEmergencyContacts(change.contacts);
      }
    });
    _queueSubscription = SosAlertRepository.queueChanges.listen((change) {
      if (_isDisposed || change.phoneNumber != _session.phoneNumber) return;
      final alert = change.alert;
      if (alert != null) {
        _cloudLogsRevision++;
        _cloudAlertLogs = [
          alert,
          ..._cloudAlertLogs.where((item) => item.id != alert.id),
        ]..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
        if (_latestSosAlertResult?.alert.id == alert.id) {
          _latestSosAlertResult = SosAlertResult(
            alert: alert,
            queuedForRetry: change.queuedForRetry,
            queuedAlertCount: _queuedAlertCount,
          );
        }
        _notifyListenersIfActive();
      }
      unawaited(loadQueuedAlertCount());
    });
    _noteSubscription = SosAlertRepository.customNoteChanges.listen((change) {
      if (_isDisposed ||
          change.phoneNumber != _session.phoneNumber ||
          !change.isCurrent) {
        return;
      }
      _customNoteReadRevisions[change.mode] =
          (_customNoteReadRevisions[change.mode] ?? 0) + 1;
      if (_customWhatsAppNotes[change.mode] == change.note) return;
      _customWhatsAppNotes = {
        ..._customWhatsAppNotes,
        change.mode: change.note,
      };
      _notifyListenersIfActive();
    });
  }

  final AppSession _session;
  StreamSubscription<EmergencyContactsChange>? _contactsSubscription;
  StreamSubscription<SosQueueChange>? _queueSubscription;
  StreamSubscription<SosCustomNoteChange>? _noteSubscription;
  final Map<SosAlertMode, int> _customNoteReadRevisions = {};
  int _queueCountRevision = 0;
  int _cloudLogsRevision = 0;
  final EmergencyContactsRepository emergencyContactsRepository;
  final SosAlertRepository _sosAlertRepository;
  final SosDashboard dashboard;
  final List<SosMetric> _metrics;
  final List<SosFeatureSection> sections;
  List<EmergencyContact> _emergencyContacts;
  bool _isLoadingEmergencyContacts = false;
  bool _isSendingSosAlert = false;
  String? _emergencyContactsErrorMessage;
  String? _sosAlertErrorMessage;
  SosAlertResult? _latestSosAlertResult;
  SosAlertResult? _latestSosAcknowledgement;
  Map<SosAlertMode, String> _customWhatsAppNotes = const {};
  List<SosAlert> _cloudAlertLogs = const [];
  int _queuedAlertCount = 0;
  bool _isFlushingQueuedAlerts = false;
  bool _isDisposed = false;

  /// Returns emergency contacts.
  List<EmergencyContact> get emergencyContacts {
    return List.unmodifiable(_emergencyContacts);
  }

  /// Returns metrics.
  List<SosMetric> get metrics {
    return [
      SosMetric(
        label: 'Contacts',
        value:
            '${_emergencyContacts.length}/${EmergencyContactsViewModel.maxContacts}',
      ),
      SosMetric(label: 'Queued', value: _queuedAlertCount.toString()),
      ..._metrics.where(
        (metric) => metric.label != 'Contacts' && metric.label != 'Queued',
      ),
    ];
  }

  /// Returns is loading emergency contacts.
  bool get isLoadingEmergencyContacts => _isLoadingEmergencyContacts;

  /// Returns is sending sos alert.
  bool get isSendingSosAlert => _isSendingSosAlert;

  /// Returns emergency contacts error message.
  String? get emergencyContactsErrorMessage => _emergencyContactsErrorMessage;

  /// Returns sos alert error message.
  String? get sosAlertErrorMessage => _sosAlertErrorMessage;

  /// Returns latest sos alert result.
  SosAlertResult? get latestSosAlertResult => _latestSosAlertResult;

  /// Returns latest sos acknowledgement.
  SosAlertResult? get latestSosAcknowledgement => _latestSosAcknowledgement;

  /// Returns cloud alert logs.
  List<SosAlert> get cloudAlertLogs => List.unmodifiable(_cloudAlertLogs);

  /// Returns queued alert count.
  int get queuedAlertCount => _queuedAlertCount;

  /// Returns is flushing queued alerts.
  bool get isFlushingQueuedAlerts => _isFlushingQueuedAlerts;

  /// Returns custom whats app notes.
  Map<SosAlertMode, String> get customWhatsAppNotes {
    return Map.unmodifiable(_customWhatsAppNotes);
  }

  /// Loads emergency contacts.
  Future<void> loadEmergencyContacts() async {
    if (_isDisposed || _isLoadingEmergencyContacts) {
      return;
    }

    _isLoadingEmergencyContacts = true;
    _emergencyContactsErrorMessage = null;
    _notifyListenersIfActive();

    try {
      final contacts = await emergencyContactsRepository.loadEmergencyContacts(
        session: _session,
      );
      if (_isDisposed) {
        return;
      }
      _emergencyContacts = contacts;
    } on EmergencyContactsRepositoryException catch (error) {
      if (_isDisposed) {
        return;
      }
      _emergencyContactsErrorMessage = error.message;
    } catch (_) {
      if (_isDisposed) {
        return;
      }
      _emergencyContactsErrorMessage =
          'Unable to load emergency contacts right now.';
    } finally {
      if (!_isDisposed) {
        _isLoadingEmergencyContacts = false;
        _notifyListenersIfActive();
      }
    }
  }

  /// Computes replace emergency contacts.
  void replaceEmergencyContacts(List<EmergencyContact> contacts) {
    if (_isDisposed) {
      return;
    }
    _emergencyContacts = List.of(contacts);
    _notifyListenersIfActive();
  }

  /// Loads custom whats app notes.
  Future<void> loadCustomWhatsAppNotes() async {
    if (_isDisposed) {
      return;
    }
    final revisions = Map<SosAlertMode, int>.from(_customNoteReadRevisions);
    try {
      final notes = await _sosAlertRepository.loadCustomWhatsAppNotes(
        session: _session,
      );
      if (_isDisposed) {
        return;
      }
      _customWhatsAppNotes = {
        ..._customWhatsAppNotes,
        for (final entry in notes.entries)
          if ((revisions[entry.key] ?? 0) ==
              (_customNoteReadRevisions[entry.key] ?? 0))
            entry.key: entry.value,
      };
      _notifyListenersIfActive();
    } catch (_) {
      // Custom notes are optional; the composer default remains available.
    }
  }

  /// Saves custom whats app note.
  Future<void> saveCustomWhatsAppNote({
    required SosAlertMode mode,
    required String note,
  }) async {
    if (_isDisposed) {
      return;
    }
    _customNoteReadRevisions[mode] = (_customNoteReadRevisions[mode] ?? 0) + 1;
    _customWhatsAppNotes = {..._customWhatsAppNotes, mode: note};
    _notifyListenersIfActive();
    await _sosAlertRepository.saveCustomWhatsAppNote(
      session: _session,
      mode: mode,
      note: note,
    );
  }

  /// Loads cloud alert logs.
  Future<void> loadCloudAlertLogs() async {
    if (_isDisposed) {
      return;
    }
    final revision = _cloudLogsRevision;
    final logs = await _sosAlertRepository.loadAlertLogs(session: _session);
    if (_isDisposed) {
      return;
    }
    _cloudAlertLogs =
        revision == _cloudLogsRevision
              ? [...logs]
              : [
                  ..._cloudAlertLogs,
                  ...logs.where(
                    (item) => !_cloudAlertLogs.any(
                      (current) => current.id == item.id,
                    ),
                  ),
                ]
          ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    _notifyListenersIfActive();
  }

  /// Loads queued alert count.
  Future<void> loadQueuedAlertCount() async {
    if (_isDisposed) {
      return;
    }
    final revision = ++_queueCountRevision;
    try {
      final count = await _sosAlertRepository.countQueuedAlerts(
        session: _session,
      );
      if (_isDisposed || revision != _queueCountRevision) return;
      _queuedAlertCount = count;
      _notifyListenersIfActive();
    } catch (_) {
      // A damaged or temporarily unavailable local queue must not surface as
      // an uncaught startup error on the SOS screen.
    }
  }

  /// Loads queued dispatches.
  Future<List<SosQueuedDispatch>> loadQueuedDispatches() {
    return _sosAlertRepository.loadQueuedDispatches(session: _session);
  }

  /// Flushes queued alerts.
  Future<SosQueueFlushResult?> flushQueuedAlerts() async {
    if (_isDisposed || _isFlushingQueuedAlerts) {
      return null;
    }

    _isFlushingQueuedAlerts = true;
    _notifyListenersIfActive();
    try {
      final result = await _sosAlertRepository.flushQueuedAlerts(
        session: _session,
        contacts: emergencyContacts,
      );
      if (_isDisposed) {
        return result;
      }
      _queuedAlertCount = result.remaining;
      if (result.didFlushAny) {
        await loadCloudAlertLogs();
      }
      return result;
    } catch (_) {
      if (!_isDisposed) {
        await loadQueuedAlertCount();
      }
      return null;
    } finally {
      if (!_isDisposed) {
        _isFlushingQueuedAlerts = false;
        _notifyListenersIfActive();
      }
    }
  }

  /// Expose the local queued submission first, then observe the authoritative delivery acknowledgement.
  Future<SosAlertResult?> triggerAlert({
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    String? customMessageNote,
    SosAlertTriggerSource? triggerSource,
  }) async {
    if (_isDisposed || _isSendingSosAlert) {
      return null;
    }

    _isSendingSosAlert = true;
    _latestSosAcknowledgement = null;
    _sosAlertErrorMessage = null;
    _notifyListenersIfActive();

    try {
      if (_emergencyContacts.isEmpty) {
        final contacts = await emergencyContactsRepository
            .loadCachedEmergencyContacts(session: _session);
        if (_isDisposed) {
          return null;
        }
        _emergencyContacts = contacts;
      }
      final submission = await _sosAlertRepository.submitAlert(
        session: _session,
        mode: mode,
        triggeredAt: triggeredAt,
        triggerLocation: triggerLocation,
        contacts: emergencyContacts,
        customMessageNote: customMessageNote,
        triggerSource: triggerSource,
      );
      if (!_isDisposed) _applyAlertResult(submission.submittedResult);
      await _observeAcknowledgement(
        submission.acknowledgement,
        submission.submittedResult.alert.id,
      );
      return _isDisposed ? null : _latestSosAcknowledgement;
    } on SosAlertRepositoryException catch (error) {
      if (!_isDisposed) {
        _sosAlertErrorMessage = error.message;
      }
    } catch (_) {
      if (!_isDisposed) {
        _sosAlertErrorMessage =
            'Unable to send SOS alert. Please check your connection and try again.';
      }
    } finally {
      if (!_isDisposed && _isSendingSosAlert) {
        _isSendingSosAlert = false;
        _notifyListenersIfActive();
      }
    }

    return null;
  }

  /// Replace pending UI state with the matching alert's final or retryable result.
  Future<void> _observeAcknowledgement(
    Future<SosAlertResult> acknowledgement,
    String submittedAlertId,
  ) async {
    try {
      final result = await acknowledgement;
      if (_isDisposed || result.alert.id != submittedAlertId) return;
      _latestSosAcknowledgement = result;
      _applyAlertResult(result);
    } on SosAlertRepositoryException catch (error) {
      if (_isDisposed) return;
      _sosAlertErrorMessage = error.message;
      await _recordAcknowledgementFailure(submittedAlertId);
    } catch (_) {
      if (_isDisposed) return;
      _sosAlertErrorMessage =
          'Firebase did not acknowledge the SOS dispatch. It remains in the pending retry queue.';
      await _recordAcknowledgementFailure(submittedAlertId);
    } finally {
      _notifyListenersIfActive();
    }
  }

  /// Records acknowledgement failure.
  Future<void> _recordAcknowledgementFailure(String alertId) async {
    await loadQueuedAlertCount();
    if (_isDisposed) return;
    final submitted = _cloudAlertLogs
        .where((alert) => alert.id == alertId)
        .firstOrNull;
    if (submitted == null) return;
    final failed = SosAlert(
      id: submitted.id,
      mode: submitted.mode,
      status: SosAlertStatus.queued,
      triggeredAt: submitted.triggeredAt,
      triggeredByPhoneNumber: submitted.triggeredByPhoneNumber,
      contactCount: submitted.contactCount,
      sentCount: 0,
      failedCount: submitted.contactCount,
      dispatches: const [],
      message: submitted.message,
      triggerLocation: submitted.triggerLocation,
      triggerSource: submitted.triggerSource,
    );
    final result = SosAlertResult(
      alert: failed,
      queuedForRetry: true,
      queuedAlertCount: _queuedAlertCount,
    );
    _latestSosAcknowledgement = result;
    _applyAlertResult(result);
  }

  /// Applies alert result.
  void _applyAlertResult(SosAlertResult result) {
    final current = _latestSosAlertResult;
    if (current == null ||
        result.alert.triggeredAt.isAfter(current.alert.triggeredAt) ||
        result.alert.id == current.alert.id) {
      _latestSosAlertResult = result;
    }
    _queuedAlertCount = result.queuedAlertCount;
    _cloudAlertLogs = [
      result.alert,
      ..._cloudAlertLogs.where((alert) => alert.id != result.alert.id),
    ]..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
  }

  /// Sends whats app test message.
  Future<List<SosContactDispatch>> sendWhatsAppTestMessage() async {
    return _sosAlertRepository.sendWhatsAppTestMessage(
      session: _session,
      contacts: emergencyContacts,
    );
  }

  /// Notifies listeners if active.
  void _notifyListenersIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _queueSubscription?.cancel();
    unawaited(_noteSubscription?.cancel());
    _isDisposed = true;
    unawaited(_contactsSubscription?.cancel());
    super.dispose();
  }
}
