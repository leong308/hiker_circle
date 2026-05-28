import 'package:flutter/foundation.dart';

import '../Data/me_repository.dart';
import '../Model/me_models.dart';

class MeViewModel extends ChangeNotifier {
  MeViewModel({
    required String phoneNumber,
    MeRepository repository = const MeRepository(),
  }) : profile = repository.loadProfile(phoneNumber: phoneNumber),
       stats = repository.loadStats(),
       sections = repository.loadSections();

  final MeProfile profile;
  final List<MeStat> stats;
  final List<MeSection> sections;
}
