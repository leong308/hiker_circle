part of '../first_time_onboarding_flow_feature.dart';

/// Displays the first time onboarding flow.
class FirstTimeOnboardingFlow extends StatefulWidget {
  /// Creates first time onboarding flow.
  const FirstTimeOnboardingFlow({
    super.key,
    required this.session,
    required this.onCompleted,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final Future<void> Function() onCompleted;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  /// Creates the presentation state for this widget.
  @override
  State<FirstTimeOnboardingFlow> createState() =>
      _FirstTimeOnboardingFlowState();
}

/// Manages the first time onboarding flow presentation and lifecycle.
class _FirstTimeOnboardingFlowState extends State<FirstTimeOnboardingFlow> {
  late final _FirstTimeOnboardingFlowStateViewModel _screenModel;

  /// Updates onboarding repository.
  set _onboardingRepository(OnboardingRepository value) =>
      _screenModel.stateOnboardingRepository = value;

  /// Returns contacts repository.
  EmergencyContactsRepository get _contactsRepository =>
      _screenModel.stateContactsRepository;

  /// Updates contacts repository.
  set _contactsRepository(EmergencyContactsRepository value) =>
      _screenModel.stateContactsRepository = value;

  /// Returns profile.
  OnboardingProfile get _profile => _screenModel.stateProfile;

  /// Returns contacts.
  List<EmergencyContact> get _contacts => _screenModel.stateContacts;

  /// Returns profile complete.
  bool get _profileComplete => _screenModel.stateProfileComplete;

  /// Updates profile complete.
  set _profileComplete(bool value) => _screenModel.stateProfileComplete = value;

  /// Returns safety questions complete.
  bool get _safetyQuestionsComplete =>
      _screenModel.stateSafetyQuestionsComplete;

  /// Returns is loading.
  bool get _isLoading => _screenModel.stateIsLoading;

  /// Returns load error.
  String? get _loadError => _screenModel.stateLoadError;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _FirstTimeOnboardingFlowStateViewModel(
      readOnCompleted: () => widget.onCompleted,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);

    _profileComplete = widget.session.isOnboardingProfileComplete;
    _onboardingRepository = OnboardingRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _contactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    unawaited(_loadSavedProgress());
  }

  /// Restore saved profile and emergency contacts so an interrupted onboarding flow can resume.
  Future<void> _loadSavedProgress() => _screenModel.commandLoadSavedProgress();

  /// Delegates save profile to the ViewModel.
  Future<void> _saveProfile(OnboardingProfile profile) =>
      _screenModel.commandSaveProfile(profile);

  /// Delegates on safety questions done to the ViewModel.
  Future<void> _onSafetyQuestionsDone() =>
      _screenModel.commandOnSafetyQuestionsDone();

  /// Save emergency contacts before marking onboarding complete and notifying the app shell.
  Future<void> _complete(List<EmergencyContact> contacts) =>
      _screenModel.commandComplete(contacts);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: SafeArea(
          child: HikerCircleLoadingView(
            message: 'Loading your profile…',
            detail: 'Preparing your hiking and safety preferences.',
          ),
        ),
      );
    }
    if (_loadError != null) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48),
                    const SizedBox(height: 14),
                    const Text(
                      'Unable to load account setup',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _loadSavedProgress,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_profileComplete) {
      return OnboardingProfilePage(
        initialProfile: _profile,
        onSubmit: _saveProfile,
      );
    }
    if (!_safetyQuestionsComplete) {
      return SafetyQuestionsSetupPage(onSubmitted: _onSafetyQuestionsDone);
    }
    return EmergencyContactsPage(
      session: widget.session,
      initialContacts: _contacts,
      repository: _contactsRepository,
      onboardingRequired: true,
      onOnboardingCompleted: _complete,
    );
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }
}
