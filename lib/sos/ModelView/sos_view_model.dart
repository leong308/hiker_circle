import 'package:flutter/foundation.dart';

import '../Data/sos_repository.dart';
import '../Model/sos_models.dart';

class SosViewModel extends ChangeNotifier {
  SosViewModel({SosRepository repository = const SosRepository()})
    : dashboard = repository.loadDashboard(),
      emergencyContacts = repository.loadEmergencyContacts(),
      metrics = repository.loadMetrics(),
      manualSosDetails = repository.loadManualSosDetails(),
      sections = repository.loadSections();

  final SosDashboard dashboard;
  final List<EmergencyContact> emergencyContacts;
  final List<SosMetric> metrics;
  final List<SosActionDetail> manualSosDetails;
  final List<SosFeatureSection> sections;
}
