part of '../profile_details_page_feature.dart';

/// Displays the profile details page.
class ProfileDetailsPage extends StatefulWidget {
  /// Creates profile details page.
  const ProfileDetailsPage({
    super.key,
    required this.session,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.repository,
  });

  final AppSession session;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final OnboardingRepository? repository;

  /// Creates the presentation state for this widget.
  @override
  State<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

/// Manages the profile details page presentation and lifecycle.
class _ProfileDetailsPageState extends State<ProfileDetailsPage> {
  late final _ProfileDetailsPageStateViewModel _screenModel;

  /// Returns repository.
  OnboardingRepository get _repository => _screenModel.stateRepository;

  /// Updates repository.
  set _repository(OnboardingRepository value) =>
      _screenModel.stateRepository = value;

  /// Returns profile future.
  Future<OnboardingProfile> get _profileFuture =>
      _screenModel.stateProfileFuture;

  /// Updates profile future.
  set _profileFuture(Future<OnboardingProfile> value) =>
      _screenModel.stateProfileFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final HikerCircleFirebaseRepository _firebaseRepository;
  final LocalSessionDatabase _localSessionDatabase = LocalSessionDatabase();

  bool _isSaving = false;
  Uint8List? _profilePhotoBytes;
  String _profilePhotoURL = '';
  final ImagePicker _imagePicker = ImagePicker();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ProfileDetailsPageStateViewModel(
      readSession: () => widget.session,
      effectSaveProfile: _saveProfile,
      effectShowChoiceEditor: _showChoiceEditor,
      readIsSaving: () => _isSaving,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentEditResidentialCityEffect1 =
        _presentEditResidentialCityEffect1;

    _repository =
        widget.repository ??
        OnboardingRepository(
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        );
    _firebaseRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _profilePhotoBytes = widget.session.photoBytes;
    _profilePhotoURL = widget.session.photoURL ?? '';
    _profileFuture = _ProfileDetailsPageDataActions.loadProfile(_repository)(
      widget.session,
    );
    _screenModel.commandWatchCachedProfile();
  }

  /// Delegates retry to the ViewModel.
  void _retry() => _screenModel.commandRetry();

  /// Preview and crop the selected image before persisting it as the account profile photo.
  Future<void> _changePhoto(OnboardingProfile profile) => _screenModel
      .commandWithProfileEditor(() => _changePhotoFromDevice(profile));

  Future<void> _changePhotoFromDevice(OnboardingProfile profile) async {
    if (!_screenModel.canEditProfile) return;
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null || !mounted || !_screenModel.canEditProfile) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const HikerCircleFirebaseRepositoryException(
          'Profile photos must be 10 MB or smaller.',
        );
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final croppedBytes = await _presentChangePhotoEffect1(bytes);
      if (croppedBytes == null || !mounted || !_screenModel.canEditProfile) {
        return;
      }
      setState(() => _isSaving = true);
      final url =
          await _ProfileDetailsPageDataActions.uploadProfilePhoto(
            _firebaseRepository,
          )(
            phoneNumber: widget.session.phoneNumber,
            bytes: croppedBytes,
            fileName: 'profile_photo.png',
            contentType: 'image/png',
          );
      if (!mounted || !_screenModel.canEditProfile) return;
      final updated = profile.copyWith(photoURL: url);
      await _ProfileDetailsPageDataActions.saveProfile(_repository)(
        session: widget.session,
        profile: updated,
      );
      await _ProfileDetailsPageDataActions.saveSession(_localSessionDatabase)(
        widget.session.copyWith(photoURL: url, photoBytes: croppedBytes),
      );
      if (mounted) {
        setState(() {
          _profilePhotoBytes = croppedBytes;
          _profilePhotoURL = url;
          _profileFuture = Future.value(updated);
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Delegates edit experience to the ViewModel.
  Future<void> _editExperience(OnboardingProfile profile) =>
      _screenModel.commandWithProfileEditor(
        () => _screenModel.commandEditExperience(profile),
      );

  /// Delegates edit frequency to the ViewModel.
  Future<void> _editFrequency(OnboardingProfile profile) =>
      _screenModel.commandWithProfileEditor(
        () => _screenModel.commandEditFrequency(profile),
      );

  /// Delegates edit residential city to the ViewModel.
  Future<void> _editResidentialCity(OnboardingProfile profile) =>
      _screenModel.commandWithProfileEditor(
        () => _screenModel.commandEditResidentialCity(profile),
      );

  /// Shows choice editor.
  Future<String?> _showChoiceEditor({
    required String title,
    required String currentValue,
    required List<(String, String)> choices,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final choice in choices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      choice.$1 == currentValue
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _ProfileColors.green,
                    ),
                    title: Text(choice.$2),
                    onTap: () => Navigator.of(context).pop(choice.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Saves profile.
  Future<OnboardingProfile?> _saveProfile(OnboardingProfile profile) async {
    if (_isSaving || !_screenModel.canEditProfile) {
      return null;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _ProfileDetailsPageDataActions.saveProfile(_repository)(
        session: widget.session,
        profile: profile,
      );
      if (!mounted || !_screenModel.canEditProfile) {
        return null;
      }
      setState(() {
        _profileFuture = Future.value(profile);
      });
      return profile;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ProfileColors.backgroundFor(context),
      body: SafeArea(
        child: FutureBuilder<OnboardingProfile>(
          future: _profileFuture,
          builder: (context, snapshot) {
            final profile = snapshot.data ?? const OnboardingProfile();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(onBack: _close)),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: HikerCircleLoadingView(
                      message: 'Loading your profile…',
                      detail: 'Getting your hiking and safety information.',
                    ),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _LoadError(
                      message: snapshot.error.toString(),
                      onRetry: _retry,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                    sliver: SliverList.list(
                      children: [
                        _IdentityCard(
                          profile: profile,
                          photoBytes: profile.photoURL == _profilePhotoURL
                              ? _profilePhotoBytes
                              : null,
                          onChangePhoto: _isSaving
                              ? null
                              : () => _changePhoto(profile),
                        ),
                        const SizedBox(height: 18),
                        const SectionLabel(label: 'ABOUT YOU'),
                        const SizedBox(height: 8),
                        _DetailsGroup(
                          rows: [
                            _ProfileDetail(
                              icon: CupertinoIcons.person_2_fill,
                              label: 'Gender',
                              value: _genderLabel(snapshot.data?.gender),
                            ),
                            _ProfileDetail(
                              icon: Icons.hiking_rounded,
                              label: 'Hiking experience',
                              value: _experienceLabel(
                                snapshot.data?.hikerExperience,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editExperience(profile),
                            ),
                            _ProfileDetail(
                              icon: CupertinoIcons.calendar,
                              label: 'Hike frequency',
                              value: _frequencyLabel(
                                snapshot.data?.hikeFrequency,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editFrequency(profile),
                            ),
                            _ProfileDetail(
                              icon: CupertinoIcons.location_solid,
                              label: 'Residential city',
                              value: _displayValue(
                                snapshot.data?.residentialLocation,
                              ),
                              onEdit: _isSaving
                                  ? null
                                  : () => _editResidentialCity(profile),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const SectionLabel(label: 'ACCOUNT'),
                        const SizedBox(height: 8),
                        _DetailsGroup(
                          rows: [
                            _ProfileDetail(
                              icon: CupertinoIcons.phone_fill,
                              label: 'Phone number',
                              value: widget.session.phoneNumber,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Closes.
  void _close() {
    Navigator.of(context).pop();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Presents the change photo effect1 UI.
  Future<Uint8List?> _presentChangePhotoEffect1(Uint8List bytes) =>
      showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProfilePhotoCropDialog(bytes: bytes),
      );

  /// Presents the edit residential city effect1 UI.
  Future<ResidentialCitySelection?> _presentEditResidentialCityEffect1(
    OnboardingProfile profile,
  ) => Navigator.of(context).push<ResidentialCitySelection>(
    MaterialPageRoute<ResidentialCitySelection>(
      builder: (context) => ResidentialCityPickerPage(
        initialLatitude: profile.residentialLatitude,
        initialLongitude: profile.residentialLongitude,
        allowCancel: true,
      ),
    ),
  );
}

/// Displays the profile photo crop dialog.
class _ProfilePhotoCropDialog extends StatefulWidget {
  /// Creates profile photo crop dialog.
  const _ProfilePhotoCropDialog({required this.bytes});

  final Uint8List bytes;

  /// Creates the presentation state for this widget.
  @override
  State<_ProfilePhotoCropDialog> createState() =>
      _ProfilePhotoCropDialogState();
}

/// Manages the profile photo crop dialog presentation and lifecycle.
class _ProfilePhotoCropDialogState extends State<_ProfilePhotoCropDialog> {
  late final _ProfilePhotoCropDialogStateViewModel _screenModel;

  /// Returns scale.
  double get _scale => _screenModel.stateScale;

  /// Updates scale.
  set _scale(double value) => _screenModel.stateScale = value;

  /// Returns offset.
  Offset get _offset => _screenModel.stateOffset;

  /// Updates offset.
  set _offset(Offset value) => _screenModel.stateOffset = value;

  /// Returns gesture start scale.
  double get _gestureStartScale => _screenModel.stateGestureStartScale;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const double _outputSize = 512;
  static const double _maxScale = 5;

  late final Future<ui.Image> _imageFuture;
  ui.Image? _image;

  double _viewportSize = 280;

  bool _isCropping = false;
  String? _cropError;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _ProfilePhotoCropDialogStateViewModel()
      ..addListener(_renderScreenModel);

    _imageFuture = _decodeImage(widget.bytes);
  }

  /// Delegates decode image to the ViewModel.
  Future<ui.Image> _decodeImage(Uint8List bytes) =>
      _screenModel.commandDecodeImage(bytes);

  /// Delegates base display size to the ViewModel.
  Size _baseDisplaySize(ui.Image image, double viewportSize) =>
      _screenModel.commandBaseDisplaySize(image, viewportSize);

  /// Delegates clamp offset to the ViewModel.
  Offset _clampOffset({
    required Offset offset,
    required double scale,
    required ui.Image image,
    required double viewportSize,
  }) => _screenModel.commandClampOffset(
    offset: offset,
    scale: scale,
    image: image,
    viewportSize: viewportSize,
  );

  /// Delegates handle scale start to the ViewModel.
  void _handleScaleStart(ScaleStartDetails details) =>
      _screenModel.commandHandleScaleStart(details);

  /// Handles scale update.
  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final image = _image;
    if (image == null) return;
    final nextScale = (_gestureStartScale * details.scale).clamp(1, _maxScale);
    final nextOffset = _offset + details.focalPointDelta;
    setState(() {
      _scale = nextScale.toDouble();
      _offset = _clampOffset(
        offset: nextOffset,
        scale: _scale,
        image: image,
        viewportSize: _viewportSize,
      );
    });
  }

  /// Computes zoom.
  void _zoom(double delta) {
    final image = _image;
    if (image == null) return;
    setState(() {
      _scale = (_scale + delta).clamp(1, _maxScale).toDouble();
      _offset = _clampOffset(
        offset: _offset,
        scale: _scale,
        image: image,
        viewportSize: _viewportSize,
      );
    });
  }

  /// Delegates reset to the ViewModel.
  void _reset() => _screenModel.commandReset();

  /// Render the chosen crop from decoded image coordinates before handing the bytes to profile persistence.
  Future<Uint8List> _cropImage() async {
    final image = _image;
    if (image == null) {
      throw StateError('Image is still loading.');
    }
    final viewportSize = _viewportSize;
    final baseSize = _baseDisplaySize(image, viewportSize);
    final drawWidth = baseSize.width * _scale;
    final drawHeight = baseSize.height * _scale;
    final left = (viewportSize - drawWidth) / 2 + _offset.dx;
    final top = (viewportSize - drawHeight) / 2 + _offset.dy;
    final sourceRect = Rect.fromLTWH(
      ((0 - left) / drawWidth) * image.width,
      ((0 - top) / drawHeight) * image.height,
      (viewportSize / drawWidth) * image.width,
      (viewportSize / drawHeight) * image.height,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outputRect = Rect.fromLTWH(0, 0, _outputSize, _outputSize);
    canvas.clipPath(Path()..addOval(outputRect));
    canvas.drawImageRect(
      image,
      sourceRect,
      outputRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final outputImage = await picture.toImage(
      _outputSize.toInt(),
      _outputSize.toInt(),
    );
    final byteData = await outputImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) {
      throw StateError('Unable to encode cropped image.');
    }
    return byteData.buffer.asUint8List();
  }

  /// Computes confirm crop.
  Future<void> _confirmCrop() async {
    if (_isCropping) {
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _isCropping = true;
      _cropError = null;
    });
    try {
      final cropped = await _cropImage();
      if (!mounted) return;
      navigator.pop(cropped);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cropError = 'Unable to crop this image. Try another photo.';
      });
    } finally {
      if (mounted) {
        setState(() => _isCropping = false);
      }
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: FutureBuilder<ui.Image>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_rounded, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Unable to load this image.',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
          final image = snapshot.data;
          if (image == null) {
            return const SizedBox(
              height: 220,
              child: HikerCircleLoadingView(
                message: 'Preparing your photo…',
                detail: '',
                compact: true,
                padding: EdgeInsets.all(10),
              ),
            );
          }
          _image = image;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Adjust profile photo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Drag and zoom the photo to fit the circle.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportSize = math.min(constraints.maxWidth, 320.0);
                    _viewportSize = viewportSize;
                    _offset = _clampOffset(
                      offset: _offset,
                      scale: _scale,
                      image: image,
                      viewportSize: viewportSize,
                    );
                    final baseSize = _baseDisplaySize(image, viewportSize);
                    return Center(
                      child: GestureDetector(
                        onScaleStart: _handleScaleStart,
                        onScaleUpdate: _handleScaleUpdate,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _ProfileColors.green,
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: SizedBox.square(
                              dimension: viewportSize,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.translate(
                                    offset: _offset,
                                    child: Transform.scale(
                                      scale: _scale,
                                      child: Image.memory(
                                        widget.bytes,
                                        width: baseSize.width,
                                        height: baseSize.height,
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.outlined(
                      tooltip: 'Zoom out',
                      onPressed: _scale <= 1 ? null : () => _zoom(-0.2),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      tooltip: 'Reset position',
                      onPressed: _reset,
                      icon: const Icon(Icons.center_focus_strong_rounded),
                    ),
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      tooltip: 'Zoom in',
                      onPressed: _scale >= _maxScale ? null : () => _zoom(0.2),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_cropError != null) ...[
                  Text(
                    _cropError!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isCropping ? null : _confirmCrop,
                        child: Text(
                          _isCropping ? 'Processing...' : 'Use Photo',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
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

/// Displays the details group.
class _DetailsGroup extends StatelessWidget {
  /// Creates details group.
  const _DetailsGroup({required this.rows});

  final List<_ProfileDetail> rows;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: _ProfileColors.surfaceFor(context),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              _DetailRow(detail: rows[index]),
              if (index != rows.length - 1)
                Divider(
                  height: 1,
                  indent: 58,
                  color: _ProfileColors.separatorFor(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Displays the load error.
class _LoadError extends StatelessWidget {
  /// Creates load error.
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Unable to load profile',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Computes display value.
String _displayValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}

/// Computes gender label.
String _genderLabel(String? value) {
  return switch (value) {
    'male' => 'Male',
    'female' => 'Female',
    'non_binary' => 'Non-binary',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => _displayValue(value),
  };
}

/// Computes experience label.
String _experienceLabel(String? value) {
  return switch (value) {
    'new' => 'New hiker',
    'experienced' => 'Experienced hiker',
    _ => _displayValue(value),
  };
}

/// Computes frequency label.
String _frequencyLabel(String? value) {
  return switch (value) {
    'rarely' => 'A few times a year',
    'monthly' => 'About once a month',
    'several_times_monthly' => 'Several times a month',
    'weekly' => 'Weekly or more',
    _ => _displayValue(value),
  };
}

/// Represents profile colors.
abstract final class _ProfileColors {
  static const green = Color(0xFF3F8F5E);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7);

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : const Color(0xFF111111);

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : const Color(0xFFE3E7E4);

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : const Color(0xFFEAF7EE);

  /// Computes hero gradient for.
  static List<Color> heroGradientFor(BuildContext context) => isDark(context)
      ? const [Color(0xFF183625), Color(0xFF24573A)]
      : const [Color(0xFF3F8F5E), Color(0xFF2F7450)];
}
