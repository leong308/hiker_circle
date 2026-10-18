// ProfileDetailsPage edits public hiker details and crops the selected profile photo.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/loading_toast.dart';
import '../../onboarding/Data/onboarding_repository.dart';
import '../../onboarding/Data/google_city_geocoding_service.dart';
import '../../onboarding/Model/onboarding_profile.dart';
import '../../onboarding/View/residential_city_picker_page.dart';

class ProfileDetailsPage extends StatefulWidget {
  const ProfileDetailsPage({
    super.key,
    required this.session,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.repository,
  });

  final AppSession session;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final OnboardingRepository? repository;

  @override
  State<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends State<ProfileDetailsPage> {
  late final OnboardingRepository _repository;
  late final HikerCircleFirebaseRepository _firebaseRepository;
  final LocalSessionDatabase _localSessionDatabase = LocalSessionDatabase();
  late Future<OnboardingProfile> _profileFuture;
  bool _isSaving = false;
  Uint8List? _profilePhotoBytes;
  String _profilePhotoURL = '';
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
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
    _profileFuture = _repository.loadProfile(widget.session);
  }

  void _retry() {
    setState(() {
      _profileFuture = _repository.loadProfile(widget.session);
    });
  }

  /// Preview and crop the selected image before persisting it as the account profile photo.
  Future<void> _changePhoto(OnboardingProfile profile) async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null || !mounted) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const HikerCircleFirebaseRepositoryException(
          'Profile photos must be 10 MB or smaller.',
        );
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ProfilePhotoCropDialog(bytes: bytes),
      );
      if (croppedBytes == null || !mounted) return;
      setState(() => _isSaving = true);
      final url = await _firebaseRepository.uploadProfilePhoto(
        phoneNumber: widget.session.phoneNumber,
        bytes: croppedBytes,
        fileName: 'profile_photo.png',
        contentType: 'image/png',
      );
      if (!mounted) return;
      final updated = profile.copyWith(photoURL: url);
      await _repository.saveProfile(session: widget.session, profile: updated);
      await _localSessionDatabase.saveSession(
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

  Future<void> _editExperience(OnboardingProfile profile) async {
    final value = await _showChoiceEditor(
      title: 'Hiking experience',
      currentValue: profile.hikerExperience,
      choices: const [
        ('new', 'New hiker'),
        ('experienced', 'Experienced hiker'),
      ],
    );
    if (value != null) {
      await _saveProfile(profile.copyWith(hikerExperience: value));
    }
  }

  Future<void> _editFrequency(OnboardingProfile profile) async {
    final value = await _showChoiceEditor(
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
      await _saveProfile(profile.copyWith(hikeFrequency: value));
    }
  }

  Future<void> _editResidentialCity(OnboardingProfile profile) async {
    final selection = await Navigator.of(context)
        .push<ResidentialCitySelection>(
          MaterialPageRoute<ResidentialCitySelection>(
            builder: (context) => ResidentialCityPickerPage(
              initialLatitude: profile.residentialLatitude,
              initialLongitude: profile.residentialLongitude,
              allowCancel: true,
            ),
          ),
        );
    if (selection == null || !mounted) {
      return;
    }
    await _saveProfile(
      profile.copyWith(
        residentialLocation: selection.label,
        residentialLatitude: selection.latitude,
        residentialLongitude: selection.longitude,
      ),
    );
  }

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

  Future<OnboardingProfile?> _saveProfile(OnboardingProfile profile) async {
    if (_isSaving) {
      return null;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _repository.saveProfile(session: widget.session, profile: profile);
      if (!mounted) {
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
                        const _SectionLabel('ABOUT YOU'),
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
                        const _SectionLabel('ACCOUNT'),
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

  void _close() {
    Navigator.of(context).pop();
  }
}

class _ProfilePhotoCropDialog extends StatefulWidget {
  const _ProfilePhotoCropDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_ProfilePhotoCropDialog> createState() =>
      _ProfilePhotoCropDialogState();
}

class _ProfilePhotoCropDialogState extends State<_ProfilePhotoCropDialog> {
  static const double _outputSize = 512;
  static const double _maxScale = 5;

  late final Future<ui.Image> _imageFuture;
  ui.Image? _image;
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _viewportSize = 280;

  double _gestureStartScale = 1;
  bool _isCropping = false;
  String? _cropError;

  @override
  void initState() {
    super.initState();
    _imageFuture = _decodeImage(widget.bytes);
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Size _baseDisplaySize(ui.Image image, double viewportSize) {
    final aspect = image.width / image.height;
    if (aspect >= 1) {
      return Size(viewportSize * aspect, viewportSize);
    }
    return Size(viewportSize, viewportSize / aspect);
  }

  Offset _clampOffset({
    required Offset offset,
    required double scale,
    required ui.Image image,
    required double viewportSize,
  }) {
    final baseSize = _baseDisplaySize(image, viewportSize);
    final drawWidth = baseSize.width * scale;
    final drawHeight = baseSize.height * scale;
    final maxDx = math.max(0, (drawWidth - viewportSize) / 2);
    final maxDy = math.max(0, (drawHeight - viewportSize) / 2);
    return Offset(
      offset.dx.clamp(-maxDx, maxDx).toDouble(),
      offset.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _scale;
  }

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

  void _reset() {
    setState(() {
      _scale = 1;
      _offset = Offset.zero;
    });
  }

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
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    child: PageHeader(title: 'Personal Profile', onBack: onBack),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.profile,
    this.photoBytes,
    this.onChangePhoto,
  });

  final OnboardingProfile profile;
  final Uint8List? photoBytes;
  final VoidCallback? onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final username = profile.username.trim().isEmpty
        ? 'Trail Friend'
        : profile.username.trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _ProfileColors.heroGradientFor(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243F8F5E),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onChangePhoto,
            child: Stack(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.36),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(39),
                    child: photoBytes != null && photoBytes!.isNotEmpty
                        ? Image.memory(
                            photoBytes!,
                            width: 78,
                            height: 78,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  CupertinoIcons.person_fill,
                                  color: Colors.white,
                                  size: 40,
                                ),
                          )
                        : profile.photoURL != null
                        ? Image.network(
                            profile.photoURL!,
                            width: 78,
                            height: 78,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  CupertinoIcons.person_fill,
                                  color: Colors.white,
                                  size: 40,
                                ),
                          )
                        : const Icon(
                            CupertinoIcons.person_fill,
                            color: Colors.white,
                            size: 40,
                          ),
                  ),
                ),
                if (onChangePhoto != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF3F8F5E),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.camera_fill,
                        size: 13,
                        color: Color(0xFF3F8F5E),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _ProfileColors.secondaryTextFor(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DetailsGroup extends StatelessWidget {
  const _DetailsGroup({required this.rows});

  final List<_ProfileDetail> rows;

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

class _ProfileDetail {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onEdit;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});

  final _ProfileDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _ProfileColors.greenSoftFor(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(detail.icon, color: _ProfileColors.green, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _ProfileColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _ProfileColors.textFor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (detail.onEdit != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: detail.onEdit,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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

String _displayValue(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? 'Not provided' : trimmed;
}

String _genderLabel(String? value) {
  return switch (value) {
    'male' => 'Male',
    'female' => 'Female',
    'non_binary' => 'Non-binary',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => _displayValue(value),
  };
}

String _experienceLabel(String? value) {
  return switch (value) {
    'new' => 'New hiker',
    'experienced' => 'Experienced hiker',
    _ => _displayValue(value),
  };
}

String _frequencyLabel(String? value) {
  return switch (value) {
    'rarely' => 'A few times a year',
    'monthly' => 'About once a month',
    'several_times_monthly' => 'Several times a month',
    'weekly' => 'Weekly or more',
    _ => _displayValue(value),
  };
}

abstract final class _ProfileColors {
  static const green = Color(0xFF3F8F5E);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : const Color(0xFFF2F2F7);

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : const Color(0xFF111111);

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : const Color(0xFF6E6E73);

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : const Color(0xFFE3E7E4);

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : const Color(0xFFEAF7EE);

  static List<Color> heroGradientFor(BuildContext context) => isDark(context)
      ? const [Color(0xFF183625), Color(0xFF24573A)]
      : const [Color(0xFF3F8F5E), Color(0xFF2F7450)];
}
