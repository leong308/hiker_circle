// MeViewModel exposes profile overview data from MeRepository to the account screen.
import 'package:flutter/foundation.dart';

import '../../app/Model/app_session.dart';
import '../Data/me_repository.dart';
import '../Model/me_models.dart';

class MeViewModel extends ChangeNotifier {
  MeViewModel({
    required AppSession session,
    MeRepository repository = const MeRepository(),
  }) : profile = repository.loadProfile(session: session),
       stats = repository.loadStats(),
       sections = repository.loadSections();

  final MeProfile profile;
  final List<MeStat> stats;
  final List<MeSection> sections;
}
