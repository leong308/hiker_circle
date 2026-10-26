part of '../profile_details_page_feature.dart';

/// Owns the state and non-visual actions of ProfileDetailsPage.
class _ProfileDetailsPageStateViewModel extends ChangeNotifier {
  /// Creates profile details page state view model.
  _ProfileDetailsPageStateViewModel({
    required this.readSession,
    required this.effectSaveProfile,
    required this.effectShowChoiceEditor,
  });
  final AppSession Function() readSession;
  final Future<OnboardingProfile?> Function(OnboardingProfile profile)
  effectSaveProfile;
  final Future<String?> Function({
    required String title,
    required String currentValue,
    required List<(String, String)> choices,
  })
  effectShowChoiceEditor;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final OnboardingRepository stateRepository;

  late Future<OnboardingProfile> stateProfileFuture;

  /// Retries.
  void commandRetry() {
    _publish(() {
      stateProfileFuture = stateRepository.loadProfile(readSession());
    });
  }

  /// Computes edit experience.
  Future<void> commandEditExperience(OnboardingProfile profile) async {
    final value = await effectShowChoiceEditor(
      title: 'Hiking experience',
      currentValue: profile.hikerExperience,
      choices: const [
        ('new', 'New hiker'),
        ('experienced', 'Experienced hiker'),
      ],
    );
    if (value != null) {
      await effectSaveProfile(profile.copyWith(hikerExperience: value));
    }
  }

  /// Computes edit frequency.
  Future<void> commandEditFrequency(OnboardingProfile profile) async {
    final value = await effectShowChoiceEditor(
      title: 'Hike frequency',
      currentValue: profile.hikeFrequency,
      choices: const [
        ('rarely', 'A few times a year'),
        ('monthly', 'About once a month'),
        ('several_times_monthly', 'Several times a month'),
        ('weekly', 'Weekly or more'),
      ],
    );
    if (value != null) {
      await effectSaveProfile(profile.copyWith(hikeFrequency: value));
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<ResidentialCitySelection?> Function(
    OnboardingProfile profile,
  )
  effectPresentEditResidentialCityEffect1;

  /// Computes edit residential city.
  Future<void> commandEditResidentialCity(OnboardingProfile profile) async {
    final selection = await effectPresentEditResidentialCityEffect1(profile);
    if (selection == null || !mounted) {
      return;
    }
    await effectSaveProfile(
      profile.copyWith(
        residentialLocation: selection.label,
        residentialLatitude: selection.latitude,
        residentialLongitude: selection.longitude,
      ),
    );
  }
}

/// Owns the state and non-visual actions of _ProfilePhotoCropDialog.
class _ProfilePhotoCropDialogStateViewModel extends ChangeNotifier {
  /// Creates profile photo crop dialog state view model.
  _ProfilePhotoCropDialogStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  double stateScale = 1;

  Offset stateOffset = Offset.zero;

  double stateGestureStartScale = 1;

  /// Computes decode image.
  Future<ui.Image> commandDecodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Computes base display size.
  Size commandBaseDisplaySize(ui.Image image, double viewportSize) {
    final aspect = image.width / image.height;
    if (aspect >= 1) {
      return Size(viewportSize * aspect, viewportSize);
    }
    return Size(viewportSize, viewportSize / aspect);
  }

  /// Computes clamp offset.
  Offset commandClampOffset({
    required Offset offset,
    required double scale,
    required ui.Image image,
    required double viewportSize,
  }) {
    final baseSize = commandBaseDisplaySize(image, viewportSize);
    final drawWidth = baseSize.width * scale;
    final drawHeight = baseSize.height * scale;
    final maxDx = math.max(0, (drawWidth - viewportSize) / 2);
    final maxDy = math.max(0, (drawHeight - viewportSize) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  /// Handles scale start.
  void commandHandleScaleStart(ScaleStartDetails details) {
    stateGestureStartScale = stateScale;
  }

  /// Resets.
  void commandReset() {
    _publish(() {
      stateScale = 1;
      stateOffset = Offset.zero;
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
