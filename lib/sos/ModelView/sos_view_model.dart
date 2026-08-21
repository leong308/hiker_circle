import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_repository.dart';
import '../Model/sos_models.dart';
import 'emergency_contacts_view_model.dart';

class SosViewModel extends ChangeNotifier {
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
       sections = repository.loadSections();

  final AppSession _session;
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

  List<EmergencyContact> get emergencyContacts {
    return List.unmodifiable(_emergencyContacts);
  }

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

  bool get isLoadingEmergencyContacts => _isLoadingEmergencyContacts;
  bool get isSendingSosAlert => _isSendingSosAlert;
  String? get emergencyContactsErrorMessage => _emergencyContactsErrorMessage;
  String? get sosAlertErrorMessage => _sosAlertErrorMessage;
  SosAlertResult? get latestSosAlertResult => _latestSosAlertResult;
  SosAlertResult? get latestSosAcknowledgement => _latestSosAcknowledgement;
  List<SosAlert> get cloudAlertLogs => List.unmodifiable(_cloudAlertLogs);
  int get queuedAlertCount => _queuedAlertCount;
  bool get isFlushingQueuedAlerts => _isFlushingQueuedAlerts;
  Map<SosAlertMode, String> get customWhatsAppNotes {
    return Map.unmodifiable(_customWhatsAppNotes);
  }

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

  void replaceEmergencyContacts(List<EmergencyContact> contacts) {
    if (_isDisposed) {
      return;
    }
    _emergencyContacts = List.of(contacts);
    _notifyListenersIfActive();
  }

  Future<void> loadCustomWhatsAppNotes() async {
    if (_isDisposed) {
      return;
    }
    try {
      final notes = await _sosAlertRepository.loadCustomWhatsAppNotes(
        session: _session,
      );
      if (_isDisposed) {
        return;
      }
      _customWhatsAppNotes = notes;
      _notifyListenersIfActive();
    } catch (_) {
      // Custom notes are optional; the composer default remains available.
    }
  }

  Future<void> saveCustomWhatsAppNote({
    required SosAlertMode mode,
    required String note,
  }) async {
    if (_isDisposed) {
      return;
    }
    _customWhatsAppNotes = {..._customWhatsAppNotes, mode: note};
    _notifyListenersIfActive();
    await _sosAlertRepository.saveCustomWhatsAppNote(
      session: _session,
      mode: mode,
      note: note,
    );
  }

  Future<void> loadCloudAlertLogs() async {
    if (_isDisposed) {
      return;
    }
    final logs = await _sosAlertRepository.loadAlertLogs(session: _session);
    if (_isDisposed) {
      return;
    }
    _cloudAlertLogs = logs;
    _notifyListenersIfActive();
  }

  Future<void> loadQueuedAlertCount() async {
    if (_isDisposed) {
      return;
    }
    try {
      final count = await _sosAlertRepository.countQueuedAlerts(
        session: _session,
      );
      if (_isDisposed) return;
      _queuedAlertCount = count;
      _notifyListenersIfActive();
    } catch (_) {
      // A damaged or temporarily unavailable local queue must not surface as
      // an uncaught startup error on the SOS screen.
    }
  }

  Future<List<SosQueuedDispatch>> loadQueuedDispatches() {
    return _sosAlertRepository.loadQueuedDispatches(session: _session);
  }

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
      if (_isDisposed) {
        return submission.submittedResult;
      }
      _applyAlertResult(submission.submittedResult);
      _isSendingSosAlert = false;
      _notifyListenersIfActive();
      unawaited(
        _observeAcknowledgement(
          submission.acknowledgement,
          submission.submittedResult.alert.id,
        ),
      );
      return submission.submittedResult;
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

  Future<List<SosContactDispatch>> sendWhatsAppTestMessage() async {
    return _sosAlertRepository.sendWhatsAppTestMessage(
      session: _session,
      contacts: emergencyContacts,
    );
  }

  void _notifyListenersIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
