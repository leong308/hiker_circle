import 'package:flutter/foundation.dart';

import '../Data/home_feature_repository.dart';
import '../Model/safety_feature.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    HomeFeatureRepository featureRepository = const HomeFeatureRepository(),
  }) : safetyFeatures = featureRepository.loadSafetySetupFeatures();

  final List<SafetyFeature> safetyFeatures;
}
