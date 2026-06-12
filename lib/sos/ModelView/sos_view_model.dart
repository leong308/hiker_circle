import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../Data/emergency_contacts_repository.dart';
import '../Data/sos_alert_repository.dart';
import '../Data/sos_repository.dart';
import '../Model/sos_models.dart';

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
       manualSosDetails = repository.loadManualSosDetails(),
       sections = repository.loadSections();

  final AppSession _session;
  final EmergencyContactsRepository emergencyContactsRepository;
  final SosAlertRepository _sosAlertRepository;
  final SosDashboard dashboard;
  final List<SosMetric> _metrics;
  final List<SosActionDetail> manualSosDetails;
  final List<SosFeatureSection> sections;
  List<EmergencyContact> _emergencyContacts;
  bool _isLoadingEmergencyContacts = false;
  bool _isSendingSosAlert = false;
  String? _emergencyContactsErrorMessage;
  String? _sosAlertErrorMessage;
  SosAlertResult? _latestSosAlertResult;

  List<EmergencyContact> get emergencyContacts {
    return List.unmodifiable(_emergencyContacts);
  }

  List<SosMetric> get metrics {
    return [
      SosMetric(label: 'Contacts', value: '${_emergencyContacts.length}/5'),
      SosMetric(
        label: 'Latest',
        value: _latestSosAlertResult?.alert.status.label ?? 'Ready',
      ),
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

  Future<void> loadEmergencyContacts() async {
    if (_isLoadingEmergencyContacts) {
      return;
    }

    _isLoadingEmergencyContacts = true;
    _emergencyContactsErrorMessage = null;
    notifyListeners();

    try {
      _emergencyContacts = await emergencyContactsRepository
          .loadEmergencyContacts(session: _session);
    } on EmergencyContactsRepositoryException catch (error) {
      _emergencyContactsErrorMessage = error.message;
    } catch (_) {
      _emergencyContactsErrorMessage =
          'Unable to load emergency contacts right now.';
    } finally {
      _isLoadingEmergencyContacts = false;
      notifyListeners();
    }
  }

  void replaceEmergencyContacts(List<EmergencyContact> contacts) {
    _emergencyContacts = List.of(contacts);
    notifyListeners();
  }

  Future<SosAlertResult?> triggerAlert({
    required SosAlertMode mode,
    required DateTime triggeredAt,
    required SosTriggerLocation? triggerLocation,
    String? customMessageNote,
  }) async {
    if (_isSendingSosAlert) {
      return null;
    }

    _isSendingSosAlert = true;
    _sosAlertErrorMessage = null;
    notifyListeners();

    try {
      final result = await _sosAlertRepository.triggerAlert(
        session: _session,
        mode: mode,
        triggeredAt: triggeredAt,
        triggerLocation: triggerLocation,
        contacts: emergencyContacts,
        customMessageNote: customMessageNote,
      );
      _latestSosAlertResult = result;
      return result;
    } on SosAlertRepositoryException catch (error) {
      _sosAlertErrorMessage = error.message;
    } catch (_) {
      _sosAlertErrorMessage =
          'Unable to send SOS alert. Please check your connection and try again.';
    } finally {
      _isSendingSosAlert = false;
      notifyListeners();
    }

    return null;
  }
}
