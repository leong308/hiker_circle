import '../Model/safety_feature.dart';

class HomeFeatureRepository {
  const HomeFeatureRepository();

  List<SafetyFeature> loadSafetySetupFeatures() {
    return const [
      SafetyFeature.planHike(),
      SafetyFeature.emergencyContacts(),
      SafetyFeature.sosMode(),
      SafetyFeature.teamSession(),
    ];
  }
}
