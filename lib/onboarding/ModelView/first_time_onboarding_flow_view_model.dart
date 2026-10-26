part of '../first_time_onboarding_flow_feature.dart';

/// Owns the state and non-visual actions of FirstTimeOnboardingFlow.
class _FirstTimeOnboardingFlowStateViewModel extends ChangeNotifier {
  /// Creates first time onboarding flow state view model.
  _FirstTimeOnboardingFlowStateViewModel({
    required this.readOnCompleted,
    required this.readSession,
  });
  final Future<void> Function() Function() readOnCompleted;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final OnboardingRepository stateOnboardingRepository;

  late final EmergencyContactsRepository stateContactsRepository;

  OnboardingProfile stateProfile = const OnboardingProfile();

  List<EmergencyContact> stateContacts = const [];

  late bool stateProfileComplete;

  bool stateSafetyQuestionsComplete = false;

  bool stateIsLoading = true;

  String? stateLoadError;

  /// Restore saved profile and emergency contacts so an interrupted onboarding flow can resume.
  Future<void> commandLoadSavedProgress() async {
    _publish(() {
      stateIsLoading = true;
      stateLoadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        stateOnboardingRepository.loadProfile(readSession()),
        stateContactsRepository.loadEmergencyContacts(session: readSession()),
      ]);
      if (!mounted) {
        return;
      }
      final profile = results[0] as OnboardingProfile;
      _publish(() {
        stateProfile = profile;
        stateProfileComplete = stateProfileComplete && profile.isComplete;
        stateContacts = results[1] as List<EmergencyContact>;
        stateIsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _publish(() {
        stateIsLoading = false;
        stateLoadError = error.toString();
      });
    }
  }

  /// Saves profile.
  Future<void> commandSaveProfile(OnboardingProfile profile) async {
    await stateOnboardingRepository.saveProfile(
      session: readSession(),
      profile: profile,
    );
    if (!mounted) {
      return;
    }
    _publish(() {
      stateProfile = profile;
      stateProfileComplete = true;
    });
  }

  /// Computes on safety questions done.
  Future<void> commandOnSafetyQuestionsDone() async {
    _publish(() {
      stateSafetyQuestionsComplete = true;
    });
  }

  /// Save emergency contacts before marking onboarding complete and notifying the app shell.
  Future<void> commandComplete(List<EmergencyContact> contacts) async {
    await stateContactsRepository.saveEmergencyContacts(
      session: readSession(),
      contacts: contacts,
    );
    await stateOnboardingRepository.completeOnboarding(readSession());
    stateContacts = contacts;
    await readOnCompleted()();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
