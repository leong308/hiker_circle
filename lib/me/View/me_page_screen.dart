part of '../me_page_feature.dart';

/// Displays the me page.
class MePage extends StatefulWidget {
  /// Creates me page.
  const MePage({
    super.key,
    required this.session,
    required this.phoneNumber,
    required this.onSignOut,
    this.onRescheduleExpiredHike,
    this.onOpenNotificationLink,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final String phoneNumber;
  final Future<void> Function(String link)? onOpenNotificationLink;
  final VoidCallback onSignOut;
  final Future<void> Function(UpcomingHike)? onRescheduleExpiredHike;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  /// Creates the presentation state for this widget.
  @override
  State<MePage> createState() => _MePageState();
}

/// Manages the me page presentation and lifecycle.
class _MePageState extends State<MePage> {
  late final _MePageStateViewModel _screenModel;

  /// Returns view model.
  MeViewModel get viewModel => _screenModel.stateViewModel;

  /// Updates view model.
  set viewModel(MeViewModel value) => _screenModel.stateViewModel = value;

  /// Returns firebase repository.
  HikerCircleFirebaseRepository get firebaseRepository =>
      _screenModel.stateFirebaseRepository;

  /// Updates firebase repository.
  set firebaseRepository(HikerCircleFirebaseRepository value) =>
      _screenModel.stateFirebaseRepository = value;

  /// Returns onboarding repository.
  OnboardingRepository get onboardingRepository =>
      _screenModel.stateOnboardingRepository;

  /// Updates onboarding repository.
  set onboardingRepository(OnboardingRepository value) =>
      _screenModel.stateOnboardingRepository = value;

  /// Returns achievements future.
  Future<List<Map<String, dynamic>>> get achievementsFuture =>
      _screenModel.stateAchievementsFuture;

  /// Updates achievements future.
  set achievementsFuture(Future<List<Map<String, dynamic>>> value) =>
      _screenModel.stateAchievementsFuture = value;

  /// Returns emergency contacts repository.
  EmergencyContactsRepository get emergencyContactsRepository =>
      _screenModel.stateEmergencyContactsRepository;

  /// Updates emergency contacts repository.
  set emergencyContactsRepository(EmergencyContactsRepository value) =>
      _screenModel.stateEmergencyContactsRepository = value;

  /// Returns emergency contacts.
  List<EmergencyContact> get emergencyContacts =>
      _screenModel.stateEmergencyContacts;

  /// Updates emergency contacts.
  set emergencyContacts(List<EmergencyContact> value) =>
      _screenModel.stateEmergencyContacts = value;

  /// Returns firestore profile.
  MeProfile? get firestoreProfile => _screenModel.stateFirestoreProfile;

  /// Updates firestore profile.
  set firestoreProfile(MeProfile? value) =>
      _screenModel.stateFirestoreProfile = value;

  /// Returns post history items.
  List<_ProfileHistoryItem> get _postHistoryItems =>
      _screenModel.statePostHistoryItems;

  /// Returns circle history items.
  List<_ProfileHistoryItem> get _circleHistoryItems =>
      _screenModel.stateCircleHistoryItems;

  /// Returns buddy history items.
  List<_ProfileHistoryItem> get _buddyHistoryItems =>
      _screenModel.stateBuddyHistoryItems;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  StreamSubscription<String>? _achievementChanges;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _MePageStateViewModel(readSession: () => widget.session)
      ..addListener(_renderScreenModel);
    _screenModel.effectPresentOpenProfileDetailsEffect1 =
        _presentOpenProfileDetailsEffect1;
    _screenModel.effectPresentOpenEmergencyContactsEffect1 =
        _presentOpenEmergencyContactsEffect1;
    _screenModel.effectPresentOpenAchievementsEffect1 =
        _presentOpenAchievementsEffect1;

    viewModel = MeViewModel(session: widget.session);
    firebaseRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    onboardingRepository = OnboardingRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    _screenModel.commandWatchCachedReads();
    achievementsFuture = _loadProfileAchievements();
    _achievementChanges = AchievementNotificationEvents.changes.listen((owner) {
      if (owner == widget.session.phoneNumber) {
        unawaited(_reloadLocalProfileAchievements());
      }
    });
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    unawaited(_loadEmergencyContacts());
    unawaited(_loadFirestoreProfile());
    unawaited(_loadProfileCollections());
  }

  /// Returns display profile.
  MeProfile get _displayProfile => _screenModel.commandDisplayProfile;

  /// Delegates load profile achievements to the ViewModel.
  Future<List<Map<String, dynamic>>> _loadProfileAchievements() =>
      _screenModel.commandLoadProfileAchievements();

  /// Delegates reload local profile achievements to the ViewModel.
  Future<void> _reloadLocalProfileAchievements() =>
      _screenModel.commandReloadLocalProfileAchievements();

  /// Delegates load firestore profile to the ViewModel.
  Future<void> _loadFirestoreProfile() =>
      _screenModel.commandLoadFirestoreProfile();

  /// Delegates load emergency contacts to the ViewModel.
  Future<void> _loadEmergencyContacts() =>
      _screenModel.commandLoadEmergencyContacts();

  /// Load posts, group chats and buddy profiles independently from the account's editable profile fields.
  Future<void> _loadProfileCollections() =>
      _screenModel.commandLoadProfileCollections();

  /// Delegates count label for action to the ViewModel.
  String? _countLabelForAction(String title) =>
      _screenModel.commandCountLabelForAction(title);

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _achievementChanges?.cancel();
    viewModel.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _MeColors.backgroundFor(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    profile: _displayProfile,
                    onShowQr: _openQrCode,
                    onOpenScanner: _openQrScanner,
                    onOpenSettings: _openAdvancedSettings,
                  ),
                  const SizedBox(height: 16),
                  _ProfileCell(
                    profile: _displayProfile,
                    photoBytes:
                        _displayProfile.photoURL == widget.session.photoURL
                        ? widget.session.photoBytes
                        : null,
                    onTap: _openProfileDetails,
                  ),
                  const SizedBox(height: 14),
                  _AchievementsSummaryCard(
                    achievementsFuture: achievementsFuture,
                    onTap: _openAchievements,
                  ),
                  const SizedBox(height: 22),
                  for (final section in viewModel.sections) ...[
                    _SettingsSection(
                      section: section,
                      onItemTap: _openActionItem,
                      countForTitle: _countLabelForAction,
                    ),
                    const SizedBox(height: 18),
                  ],
                  _SignOutCell(onSignOut: widget.onSignOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens action item.
  void _openActionItem(MeActionItem item) {
    switch (item.title) {
      case 'Send feedback':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FeedbackPage(isAdmin: widget.session.isAdmin),
          ),
        );
      case 'Hike history':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => HikeHistoryPage(
              repository: firebaseRepository,
              session: widget.session,
              onRescheduleExpiredHike: widget.onRescheduleExpiredHike,
            ),
          ),
        );
      case 'My posts':
        _openHistoryPage(
          title: 'My Posts',
          subtitle: 'Trail updates from your hiking history',
          icon: Icons.forum_rounded,
          items: _postHistoryItems,
        );
      case 'My circles':
        _openHistoryPage(
          title: 'My Circles',
          subtitle: 'Each circle represents a hiking team',
          icon: Icons.groups_2_rounded,
          items: _circleHistoryItems,
        );
      case 'My buddies':
        _openHistoryPage(
          title: 'My Buddies',
          subtitle: 'People from past hikes and QR adds',
          icon: Icons.person_add_alt_1_rounded,
          items: _buddyHistoryItems,
        );
      case 'Emergency contacts':
        _openEmergencyContacts();
      case 'Location sharing':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LocationSharingPage(
              phoneNumber: widget.phoneNumber,
              firebaseBootstrapResult: widget.firebaseBootstrapResult,
            ),
          ),
        );
      case 'Notifications':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => DeviceNotificationsPage(
              phoneNumber: widget.session.phoneNumber,
              onOpenDeepLink: widget.onOpenNotificationLink,
            ),
          ),
        );
      case 'Privacy Policy':
        unawaited(_openPrivacyPolicy());
      case 'Disclaimer':
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const DisclaimerPage()));
      case 'Help center':
        _openHelpCenter();
      case 'Account preferences':
        _openSettingsDetail(
          title: 'Account Preferences',
          subtitle: 'Profile and sign-in controls',
          icon: Icons.account_circle_rounded,
          rows: [
            (
              'Display name',
              widget.session.username.trim().isEmpty
                  ? widget.phoneNumber
                  : widget.session.username.trim(),
            ),
            ('Phone sign-in', 'Verified'),
            ('Profile QR', 'Enabled'),
            ('Account recovery', 'Phone number'),
          ],
        );
    }
  }

  /// Open the shared privacy-policy destination and surface a launch failure in the account UI.
  Future<void> _openPrivacyPolicy() async {
    final launched = await launchPrivacyPolicy();
    if (!mounted || launched) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open the Privacy Policy. Check your connection and try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Delegates open emergency contacts to the ViewModel.
  Future<void> _openEmergencyContacts() =>
      _screenModel.commandOpenEmergencyContacts();

  /// Delegates open achievements to the ViewModel.
  Future<void> _openAchievements() => _screenModel.commandOpenAchievements();

  /// Opens history page.
  void _openHistoryPage({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_ProfileHistoryItem> items,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileHistoryPage(
          title: title,
          subtitle: subtitle,
          icon: icon,
          items: items,
        ),
      ),
    );
  }

  /// Opens settings detail.
  void _openSettingsDetail({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<(String, String)> rows,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileSettingsDetailPage(
          title: title,
          subtitle: subtitle,
          icon: icon,
          rows: rows,
        ),
      ),
    );
  }

  /// Opens help center.
  void _openHelpCenter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HelpCenterPage(
          isAdmin: widget.session.isAdmin,
          isSuperAdmin: widget.session.isSuperAdmin,
          ownerPhoneNumber: widget.session.phoneNumber,
        ),
      ),
    );
  }

  /// Opens advanced settings.
  void _openAdvancedSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AdvancedAppSettingsPage(
          session: widget.session,
          firebaseRepository: firebaseRepository,
        ),
      ),
    );
  }

  /// Opens qr code.
  void _openQrCode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileQrPage(profile: _displayProfile),
      ),
    );
  }

  /// Delegates open profile details to the ViewModel.
  Future<void> _openProfileDetails() =>
      _screenModel.commandOpenProfileDetails();

  /// Opens qr scanner.
  void _openQrScanner() {
    final ownHandle = _ownHandleForPhone(widget.phoneNumber);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => QrScannerPage(
          session: widget.session,
          repository: firebaseRepository,
          ownPhoneNumber: widget.phoneNumber,
          ownHandle: ownHandle,
        ),
      ),
    );
  }

  /// Delegates own handle for phone to the ViewModel.
  String _ownHandleForPhone(String phoneNumber) =>
      _screenModel.commandOwnHandleForPhone(phoneNumber);

  /// Presents the open emergency contacts effect1 UI.
  Future<List<EmergencyContact>?> _presentOpenEmergencyContactsEffect1() =>
      Navigator.of(context).push<List<EmergencyContact>>(
        MaterialPageRoute<List<EmergencyContact>>(
          builder: (context) => EmergencyContactsPage(
            session: widget.session,
            initialContacts: emergencyContacts,
            repository: emergencyContactsRepository,
          ),
        ),
      );

  /// Presents the open achievements effect1 UI.
  Future<void> _presentOpenAchievementsEffect1() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => AchievementsPage(
        session: widget.session,
        repository: firebaseRepository,
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      ),
    ),
  );

  /// Presents the open profile details effect1 UI.
  Future<void> _presentOpenProfileDetailsEffect1() =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ProfileDetailsPage(
            session: widget.session,
            firebaseBootstrapResult: widget.firebaseBootstrapResult,
          ),
        ),
      );
}

/// Displays the header action.
class _HeaderAction extends StatelessWidget {
  /// Creates header action.
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    color: _MeColors.green,
    surface: _MeColors.surfaceFor(context),
  );
}

/// Displays the profile cell.
class _ProfileCell extends StatelessWidget {
  /// Creates profile cell.
  const _ProfileCell({
    required this.profile,
    required this.onTap,
    this.photoBytes,
  });

  final MeProfile profile;
  final VoidCallback onTap;
  final Uint8List? photoBytes;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _MeColors.greenSoftFor(context),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(29),
                  child: photoBytes != null && photoBytes!.isNotEmpty
                      ? Image.memory(
                          photoBytes!,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                CupertinoIcons.person_fill,
                                color: _MeColors.green,
                                size: 31,
                              ),
                        )
                      : profile.photoURL != null
                      ? Image.network(
                          profile.photoURL!,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                CupertinoIcons.person_fill,
                                color: _MeColors.green,
                                size: 31,
                              ),
                        )
                      : const Icon(
                          CupertinoIcons.person_fill,
                          color: _MeColors.green,
                          size: 31,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _MeColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _MeColors.chevronFor(context),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the profile qr page.
class _ProfileQrPage extends StatelessWidget {
  /// Creates profile qr page.
  const _ProfileQrPage({required this.profile});

  final MeProfile profile;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final link = _profileLink(profile);
    final qr = _QrMatrix.encode(link);

    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Profile QR',
                    subtitle: 'Share your HikerCircle profile',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _MeColors.separatorFor(context),
                              ),
                            ),
                            child: CustomPaint(
                              painter: _QrPainter(matrix: qr.modules),
                              child: const SizedBox.square(dimension: 236),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            profile.displayName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _MeColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            link,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _MeColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _shareProfileLink(context, link),
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: const Text('Share Link'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _copyProfileLink(context, link),
                                  icon: const Icon(Icons.copy_rounded),
                                  label: const Text('Copy'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _InsetGroup(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Glyph(icon: Icons.link_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Scanning this QR opens HikerCircle through a deeplink. If another hiker scans it, the app shows an add-buddy prompt; your own QR is ignored.',
                            ),
                          ),
                        ],
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
  }

  /// Computes copy profile link.
  void _copyProfileLink(BuildContext context, String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Profile link copied for sharing.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Computes share profile link.
  Future<void> _shareProfileLink(BuildContext context, String link) async {
    try {
      await const MethodChannel('hiker_circle/sos_device_alerts').invokeMethod(
        'shareText',
        {'subject': 'Add me on HikerCircle', 'text': link},
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _copyProfileLink(context, link);
    }
  }
}

/// Represents qr painter.
class _QrPainter extends CustomPainter {
  /// Creates qr painter.
  const _QrPainter({required this.matrix});

  final List<List<bool>> matrix;

  /// Computes paint.
  @override
  void paint(Canvas canvas, Size size) {
    final modules = matrix.length;
    final quietZone = 4;
    final cell = size.shortestSide / (modules + quietZone * 2);
    final offset = Offset(
      (size.width - cell * (modules + quietZone * 2)) / 2,
      (size.height - cell * (modules + quietZone * 2)) / 2,
    );
    final paint = Paint()..color = _MeColors.text;

    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (!matrix[y][x]) {
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              offset.dx + (x + quietZone) * cell,
              offset.dy + (y + quietZone) * cell,
              cell,
              cell,
            ),
            Radius.circular(cell * 0.12),
          ),
          paint,
        );
      }
    }
  }

  /// Computes should repaint.
  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.matrix != matrix;
  }
}

/// Computes profile link.
String _profileLink(MeProfile profile) {
  var handle = profile.handle.replaceFirst('@', '').trim();
  if (handle.isEmpty) {
    handle = 'hiker';
  }
  var normalizedPhone = profile.phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  if (normalizedPhone.length > 18) {
    normalizedPhone = normalizedPhone.substring(0, 18);
  }
  final phone = Uri.encodeComponent(normalizedPhone);

  /// Builds link.
  String buildLink() =>
      'hikercircle://buddy/add?h=${Uri.encodeComponent(handle)}&p=$phone';

  // The bundled encoder is QR version 4-L (73 byte payload). The phone number
  // is the stable buddy identifier, so trim only the display handle for legacy
  // profiles whose usernames predate the current length limit.
  while (utf8.encode(buildLink()).length > 73 && handle.runes.length > 1) {
    final runes = handle.runes.toList()..removeLast();
    handle = String.fromCharCodes(runes);
  }
  return buildLink();
}

/// Computes achievement icon for.
IconData _achievementIconFor(String iconName) {
  return switch (iconName) {
    'verified_user' => Icons.verified_user_rounded,
    'map' => Icons.map_rounded,
    'health_and_safety' => Icons.health_and_safety_rounded,
    'task_alt' => Icons.task_alt_rounded,
    'volunteer_activism' => Icons.volunteer_activism_rounded,
    'groups' => Icons.groups_2_rounded,
    'hiking' => Icons.hiking_rounded,
    'terrain' => Icons.terrain_rounded,
    'military_tech' => Icons.military_tech_rounded,
    'route' => Icons.route_rounded,
    'timer' => Icons.timer_rounded,
    'explore' => Icons.explore_rounded,
    'travel_explore' => Icons.travel_explore_rounded,
    'public' => Icons.public_rounded,
    'forum' => Icons.forum_rounded,
    'warning' => Icons.warning_amber_rounded,
    _ => Icons.emoji_events_rounded,
  };
}

/// Displays the profile history page.
class _ProfileHistoryPage extends StatelessWidget {
  /// Creates profile history page.
  const _ProfileHistoryPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_ProfileHistoryItem> items;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: title,
                    subtitle: subtitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _Glyph(icon: icon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${items.length} history item${items.length == 1 ? '' : 's'} from profile activity.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: _MeColors.textFor(context),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No profile activity is available here yet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _MeColors.secondaryTextFor(context),
                                letterSpacing: 0,
                              ),
                        ),
                      ),
                    )
                  else
                    for (final item in items) ...[
                      _ProfileHistoryCard(item: item),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the profile settings detail page.
class _ProfileSettingsDetailPage extends StatelessWidget {
  /// Creates profile settings detail page.
  const _ProfileSettingsDetailPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<(String, String)> rows;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: title,
                    subtitle: subtitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Glyph(icon: icon),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Configured for HikerCircle profile behavior.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: _MeColors.textFor(context),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (var index = 0; index < rows.length; index++) ...[
                            _InfoLine(
                              label: rows[index].$1,
                              value: rows[index].$2,
                            ),
                            if (index != rows.length - 1)
                              const _HorizontalSeparator(),
                          ],
                        ],
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
  }
}

/// Displays the advanced app settings page.
class _AdvancedAppSettingsPage extends StatefulWidget {
  /// Creates advanced app settings page.
  const _AdvancedAppSettingsPage({
    required this.session,
    required this.firebaseRepository,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository firebaseRepository;

  /// Creates the presentation state for this widget.
  @override
  State<_AdvancedAppSettingsPage> createState() =>
      _AdvancedAppSettingsPageState();
}

/// Manages the advanced app settings page presentation and lifecycle.
class _AdvancedAppSettingsPageState extends State<_AdvancedAppSettingsPage> {
  late final _AdvancedAppSettingsPageStateViewModel _screenModel;

  /// Returns settings.
  AppSettingsController get _settings => _screenModel.stateSettings;

  /// Returns is loading time zone.
  bool get _isLoadingTimeZone => _screenModel.stateIsLoadingTimeZone;

  /// Returns time zone status.
  String get _timeZoneStatus => _screenModel.stateTimeZoneStatus;

  /// Updates time zone status.
  set _timeZoneStatus(String value) => _screenModel.stateTimeZoneStatus = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();

  bool get _isSavingTimeZone => _screenModel.stateIsSavingTimeZone;
  set _isSavingTimeZone(bool value) =>
      _screenModel.commandSetTimeZoneSaving(value);

  /// Delegates set private unlock to the ViewModel.
  Future<void> _setPrivateUnlock(bool enabled) =>
      _screenModel.commandSetPrivateUnlock(enabled);

  /// Delegates change password to the ViewModel.
  Future<void> _changePassword() => _screenModel.commandChangePassword();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _AdvancedAppSettingsPageStateViewModel(
      readFirebaseRepository: () => widget.firebaseRepository,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);
    _screenModel.effectPresentChangePasswordEffect2 =
        _presentChangePasswordEffect2;
    _screenModel.effectPresentChangePasswordEffect1 =
        _presentChangePasswordEffect1;
    _screenModel.effectShowBiometricUnlockIssue = _showBiometricUnlockIssue;
    _screenModel.effectConfirmDisableHapticFeedback =
        _confirmDisableHapticFeedback;

    _settings.addListener(_handleSettingsChanged);
    _screenModel.commandWatchCachedPreferences();
    unawaited(
      LocationUpdateIntervalController.instance.loadForUser(
        widget.session.phoneNumber,
      ),
    );
    unawaited(_loadPreferredTimeZone());
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates handle settings changed to the ViewModel.
  void _handleSettingsChanged() => _screenModel.commandHandleSettingsChanged();

  /// Delegates load preferred time zone to the ViewModel.
  Future<void> _loadPreferredTimeZone() =>
      _screenModel.commandLoadPreferredTimeZone();

  /// Computes choose preferred time zone.
  Future<void> _choosePreferredTimeZone() async {
    if (_isLoadingTimeZone || _isSavingTimeZone) return;
    final selected = await _presentChoosePreferredTimeZoneEffect1();
    if (selected == null ||
        selected == _settings.preferredTimeZone ||
        !mounted) {
      return;
    }

    final previous = _settings.preferredTimeZone;
    _settings.setPreferredTimeZone(selected);
    setState(() {
      _isSavingTimeZone = true;
      _timeZoneStatus = 'Saving to Firebase…';
    });
    try {
      await _MePageDataActions.savePreferredTimeZone(widget.firebaseRepository)(
        session: widget.session,
        preferredTimeZone: selected,
      );
      if (!mounted) return;
      setState(() {
        _timeZoneStatus = 'Synced with Firebase for outgoing SOS messages.';
      });
    } catch (error) {
      _settings.setPreferredTimeZone(previous);
      if (!mounted) return;
      setState(() {
        _timeZoneStatus =
            'Not saved. SOS messages continue using the previous timezone.';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error is HikerCircleFirebaseRepositoryException
                  ? error.message
                  : 'Unable to save the SOS timezone right now.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingTimeZone = false;
        });
      }
    }
  }

  /// Sets precise location.
  Future<void> _setPreciseLocation(bool enabled) async {
    if (!enabled) {
      final confirmed = await _presentSetPreciseLocationEffect1();
      if (confirmed != true) {
        return;
      }
    }

    try {
      await _deviceAlertService.setPreciseLocationEnabled(enabled);
      _settings.setPreciseLocationEnabled(enabled);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to update location accuracy right now.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Presents the shared settings layout with the existing guarded preference actions.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _MeColors.backgroundFor(context),
    body: SafeArea(
      child: AppSettingsContent(
        settings: _settings,
        onBack: () => Navigator.of(context).pop(),
        onLoginSecurity: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SecurityMethodsPage()),
        ),
        onChangePassword: () => unawaited(_changePassword()),
        onPrivateUnlock: (value) => unawaited(_setPrivateUnlock(value)),
        onPreciseLocation: (value) => unawaited(_setPreciseLocation(value)),
        onHapticFeedback: (value) =>
            unawaited(_screenModel.commandSetHapticSafetyFeedback(value)),
        onTimeZone: () => unawaited(_choosePreferredTimeZone()),
        timeZoneLabel: PreferredTimeZone.compactLabel(
          _settings.preferredTimeZone,
        ),
        timeZoneBusy: _isLoadingTimeZone || _isSavingTimeZone,
        timeZoneError:
            _timeZoneStatus.startsWith('Could') ||
                _timeZoneStatus.startsWith('Not saved')
            ? _timeZoneStatus
            : null,
      ),
    ),
  );

  /// Presents the specific setup or access problem reported by device verification.
  void _showBiometricUnlockIssue(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Presents the change password effect1 UI.
  Future<bool?> _presentChangePasswordEffect1() =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RecentSecurityVerificationPage(
            phoneNumber: widget.session.phoneNumber,
            sendCodeOnOpen: false,
          ),
        ),
      );

  /// Presents the change password effect2 UI.
  Future<void> _presentChangePasswordEffect2() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const ChangePasswordPage()));

  /// Presents the choose preferred time zone effect1 UI.
  Future<String?> _presentChoosePreferredTimeZoneEffect1() =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: _MeColors.surfaceFor(context),
        builder: (context) =>
            _TimeZonePickerSheet(selectedTimeZone: _settings.preferredTimeZone),
      );

  /// Matches the location-accuracy warning before turning off haptic feedback.
  Future<bool?> _confirmDisableHapticFeedback() => showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('Turn off haptic safety feedback?'),
      content: const Text(
        'Vibration helps you notice safety alerts and SOS countdowns when you are not looking at the screen. Keeping it enabled is recommended.',
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep On'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn Off'),
        ),
      ],
    ),
  );

  /// Presents the set precise location effect1 UI.
  Future<bool?>
  _presentSetPreciseLocationEffect1() => showCupertinoDialog<bool>(
    context: context,
    builder: (context) {
      return CupertinoAlertDialog(
        title: const Text('Reduce Location Accuracy?'),
        content: const Text(
          'Turning off precise location can improve battery life, but hike tracking, pins, and SOS map links may be less accurate.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Precise'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Turn Off'),
          ),
        ],
      );
    },
  );
}

/// Defines the achievement status tab choices.
enum _AchievementStatusTab { all, earned, locked }

/// Displays the achievements page.
class AchievementsPage extends StatefulWidget {
  /// Creates achievements page.
  const AchievementsPage({
    super.key,
    required this.session,
    required this.repository,
    required this.firebaseBootstrapResult,
    this.initiallyShowEarned = false,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final bool initiallyShowEarned;

  /// Creates the presentation state for this widget.
  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

/// Manages the achievements page presentation and lifecycle.
class _AchievementsPageState extends State<AchievementsPage> {
  late final _AchievementsPageStateViewModel _screenModel;

  /// Returns achievements future.
  Future<List<Map<String, dynamic>>> get _achievementsFuture =>
      _screenModel.stateAchievementsFuture;

  /// Updates achievements future.
  set _achievementsFuture(Future<List<Map<String, dynamic>>> value) =>
      _screenModel.stateAchievementsFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late _AchievementStatusTab _achievementTab;
  StreamSubscription<String>? _achievementChanges;
  StreamSubscription<List<Map<String, dynamic>>>? _catalogChanges;
  bool _managementDialogOpen = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _AchievementsPageStateViewModel(
      readRepository: () => widget.repository,
      readSession: () => widget.session,
    )..addListener(_renderScreenModel);

    _achievementTab = widget.session.isAdmin
        ? _AchievementStatusTab.all
        : widget.initiallyShowEarned
        ? _AchievementStatusTab.earned
        : _AchievementStatusTab.locked;
    _achievementsFuture = _loadAchievementsCacheFirst();
    _catalogChanges = widget.repository
        .watchUserAchievementProgress(session: widget.session)
        .listen(
          _screenModel.commandApplyLiveRows,
          onError: (Object _, StackTrace __) {
            // Cached visibility remains available while Firestore reconnects.
          },
        );
    _achievementChanges = AchievementNotificationEvents.changes.listen((owner) {
      if (owner == widget.session.phoneNumber) {
        unawaited(_reloadLocalAchievements());
      }
    });
  }

  /// Rebinds role and owner-specific content if the account changes while the page is mounted.
  @override
  void didUpdateWidget(covariant AchievementsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.phoneNumber != widget.session.phoneNumber ||
        oldWidget.session.isAdmin != widget.session.isAdmin) {
      _catalogChanges?.cancel();
      _achievementTab = widget.session.isAdmin
          ? _AchievementStatusTab.all
          : widget.initiallyShowEarned
          ? _AchievementStatusTab.earned
          : _AchievementStatusTab.locked;
      _achievementsFuture = _loadAchievementsCacheFirst();
      _catalogChanges = widget.repository
          .watchUserAchievementProgress(session: widget.session)
          .listen(
            _screenModel.commandApplyLiveRows,
            onError: (Object _, StackTrace __) {},
          );
    }
  }

  /// Delegates reload local achievements to the ViewModel.
  Future<void> _reloadLocalAchievements() =>
      _screenModel.commandReloadLocalAchievements();

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _achievementChanges?.cancel();
    _catalogChanges?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Delegates load achievements cache first to the ViewModel.
  Future<List<Map<String, dynamic>>> _loadAchievementsCacheFirst() =>
      _screenModel.commandLoadAchievementsCacheFirst();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _AchievementAmbientBackdrop()),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _achievementsFuture,
              builder: (context, snapshot) {
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData;
                final achievements = _achievementItemsFromRows(
                  snapshot.data ?? const [],
                  includeInactive: widget.session.isAdmin,
                );
                final earned = achievements
                    .where((item) => item.isUnlocked)
                    .toList();
                final locked = achievements
                    .where((item) => !item.isUnlocked)
                    .toList();
                final visibleAchievements =
                    _achievementTab == _AchievementStatusTab.all
                    ? achievements
                    : _achievementTab == _AchievementStatusTab.earned
                    ? earned
                    : locked;

                return ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AchievementPageHeader(
                              onBack: () => Navigator.of(context).pop(),
                              onLeaderboard: _openLeaderboard,
                            ),
                            const SizedBox(height: 16),
                            if (!widget
                                .firebaseBootstrapResult
                                .isAvailable) ...[
                              _AchievementNoticeCard(
                                icon: Icons.cloud_off_rounded,
                                title: 'Cloud achievements unavailable',
                                message:
                                    'Showing the local badge catalog until Firebase reconnects.',
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (isLoading)
                              const _AchievementLoadingCard()
                            else ...[
                              _AchievementProgressPanel(
                                items: achievements,
                                retainedPoints: _retainedAchievementPoints(
                                  snapshot.data ?? const [],
                                  includeInactive: widget.session.isAdmin,
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (widget.session.isAdmin) ...[
                                Row(
                                  children: [
                                    const Expanded(
                                      child: SectionLabel(
                                        label: 'Achievement rules',
                                      ),
                                    ),
                                    FilledButton.icon(
                                      key: const Key(
                                        'achievement-add-rule-button',
                                      ),
                                      onPressed:
                                          _screenModel.stateSavingAchievement
                                          ? null
                                          : () => unawaited(_editAchievement()),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Add rule'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Swipe right to edit · left to archive or unarchive',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                              ],
                              _AchievementStatusTabs(
                                selected: _achievementTab,
                                allCount: widget.session.isAdmin
                                    ? achievements.length
                                    : null,
                                earnedCount: earned.length,
                                lockedCount: locked.length,
                                onSelected: (value) {
                                  setState(() => _achievementTab = value);
                                },
                              ),
                              const SizedBox(height: 12),
                              if (visibleAchievements.isEmpty)
                                _AchievementNoticeCard(
                                  icon:
                                      _achievementTab ==
                                          _AchievementStatusTab.earned
                                      ? Icons.emoji_events_outlined
                                      : Icons.lock_open_rounded,
                                  title: achievements.isEmpty
                                      ? (widget.session.isAdmin
                                            ? 'No achievement rules yet'
                                            : 'No active achievements')
                                      : _achievementTab ==
                                            _AchievementStatusTab.earned
                                      ? 'No badges unlocked yet'
                                      : 'Every badge is unlocked',
                                  message: achievements.isEmpty
                                      ? (widget.session.isAdmin
                                            ? 'Add a rule to create an achievement.'
                                            : 'New achievements will appear here when available.')
                                      : _achievementTab ==
                                            _AchievementStatusTab.earned
                                      ? 'Open Locked to choose your next hiking goal.'
                                      : 'Keep hiking to build your rank and help the community.',
                                )
                              else
                                _AchievementCollectionGrid(
                                  items: visibleAchievements,
                                  onTap: _showAchievementDetail,
                                  onEdit: widget.session.isAdmin
                                      ? (item) => _editAchievement(item)
                                      : null,
                                  onToggleActive: widget.session.isAdmin
                                      ? _toggleAchievementActive
                                      : null,
                                  actionsEnabled:
                                      !_screenModel.stateSavingAchievement,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Presents the shared editor; saving and role validation remain in the ViewModel/backend.
  Future<void> _editAchievement([_AchievementProfileItem? item]) async {
    if (!widget.session.isAdmin ||
        _managementDialogOpen ||
        _screenModel.stateSavingAchievement) {
      return;
    }
    _managementDialogOpen = true;
    Map<String, dynamic>? values;
    try {
      values = await showAchievementEditorSheet(context, initial: item?.source);
    } finally {
      _managementDialogOpen = false;
    }
    if (!mounted || values == null) return;
    final success = await _screenModel.commandSaveAchievement(
      values,
      achievementId: item?.achievementId ?? '',
    );
    if (!mounted) return;
    HikerCircleToast.show(
      context,
      success
          ? (item == null ? 'Achievement added.' : 'Achievement updated.')
          : _screenModel.stateAchievementError ??
                'The achievement could not be saved.',
      tone: success ? HikerCircleToastTone.success : HikerCircleToastTone.error,
    );
  }

  /// Confirms the reversible visibility change without deleting any hiker's award history.
  Future<void> _toggleAchievementActive(_AchievementProfileItem item) async {
    if (!widget.session.isAdmin ||
        _managementDialogOpen ||
        _screenModel.stateSavingAchievement) {
      return;
    }
    _managementDialogOpen = true;
    final label = item.isActive ? 'Archive' : 'Unarchive';
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            item.isActive ? Icons.archive_rounded : Icons.unarchive_rounded,
          ),
          title: Text('$label achievement?'),
          content: Text(
            item.isActive
                ? 'This achievement will be hidden from hikers. Previously awarded points are kept.'
                : 'This achievement will be visible to hikers again. Eligible progress will be checked.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(label),
            ),
          ],
        ),
      );
    } finally {
      _managementDialogOpen = false;
    }
    if (!mounted || confirmed != true) return;
    final success = await _screenModel.commandSetAchievementActive(
      item.achievementId,
      !item.isActive,
    );
    if (!mounted) return;
    HikerCircleToast.show(
      context,
      success
          ? 'Achievement ${item.isActive ? 'archived' : 'unarchived'}.'
          : _screenModel.stateAchievementError ??
                'The achievement could not be updated.',
      tone: success ? HikerCircleToastTone.success : HikerCircleToastTone.error,
    );
  }

  /// Opens leaderboard.
  void _openLeaderboard() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) =>
            _AchievementLeaderboardPage(repository: widget.repository),
      ),
    );
  }

  /// Shows achievement detail.
  void _showAchievementDetail(_AchievementProfileItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AchievementDetailSheet(item: item),
    );
  }
}

/// Displays the achievement page header.
class _AchievementPageHeader extends StatelessWidget {
  /// Creates achievement page header.
  const _AchievementPageHeader({
    required this.onBack,
    required this.onLeaderboard,
  });

  final VoidCallback onBack;
  final VoidCallback onLeaderboard;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        'Achievements',
        style: PageHeaderStyle.title(context, _MeColors.textFor(context)),
      );
      final subtitle = Text(
        'Collect milestones from every adventure',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PageHeaderStyle.subtitle(
          context,
          _MeColors.secondaryTextFor(context),
        ),
      );
      final back = _AchievementHeaderButton(
        tooltip: 'Back',
        icon: CupertinoIcons.chevron_back,
        onPressed: onBack,
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AchievementHeaderButton(
            key: const Key('achievement-leaderboard-button'),
            tooltip: 'Open leaderboard',
            icon: CupertinoIcons.chart_bar_alt_fill,
            onPressed: onLeaderboard,
          ),
        ],
      );
      if (constraints.maxWidth < 330 ||
          MediaQuery.textScalerOf(context).scale(26) > 32) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [back, const Spacer(), actions]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: title,
            ),
            subtitle,
          ],
        );
      }
      return Row(
        children: [
          back,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, subtitle],
            ),
          ),
          const SizedBox(width: 10),
          actions,
        ],
      );
    },
  );
}

/// Displays the achievement leaderboard page.
class _AchievementLeaderboardPage extends StatefulWidget {
  /// Creates achievement leaderboard page.
  const _AchievementLeaderboardPage({required this.repository});

  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<_AchievementLeaderboardPage> createState() =>
      _AchievementLeaderboardPageState();
}

/// Manages the achievement leaderboard page presentation and lifecycle.
class _AchievementLeaderboardPageState
    extends State<_AchievementLeaderboardPage> {
  late final _AchievementLeaderboardPageStateViewModel _screenModel;

  /// Returns period.
  String get _period => _screenModel.statePeriod;

  /// Returns preview entries.
  List<Map<String, dynamic>>? get _previewEntries =>
      _screenModel.statePreviewEntries;

  /// Updates preview entries.
  set _previewEntries(List<Map<String, dynamic>>? value) =>
      _screenModel.statePreviewEntries = value;

  /// Returns entries future.
  Future<List<Map<String, dynamic>>> get _entriesFuture =>
      _screenModel.stateEntriesFuture;

  /// Updates entries future.
  set _entriesFuture(Future<List<Map<String, dynamic>>> value) =>
      _screenModel.stateEntriesFuture = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  /// Delegates tap title to the ViewModel.
  void _tapTitle() => _screenModel.commandTapTitle();

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _AchievementLeaderboardPageStateViewModel(
      readRepository: () => widget.repository,
    )..addListener(_renderScreenModel);

    _entriesFuture = _MePageDataActions.loadAchievementLeaderboard(
      widget.repository,
    )();
  }

  /// Delegates select period to the ViewModel.
  void _selectPeriod(String period) => _screenModel.commandSelectPeriod(period);

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _AchievementAmbientBackdrop()),
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailHeader(
                          title: 'Leaderboard',
                          subtitle: 'Hikers earning the most trail points',
                          onBack: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 18),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _entriesFuture,
                          builder: (context, snapshot) {
                            return _AchievementLeaderboardCard(
                              period: _period,
                              entries:
                                  _previewEntries ?? snapshot.data ?? const [],
                              onTitleTap: _tapTitle,
                              isPreview: _previewEntries != null,
                              onExitPreview: () => setState(() {
                                _previewEntries = null;
                                _entriesFuture =
                                    _MePageDataActions.loadAchievementLeaderboard(
                                      widget.repository,
                                    )(period: _period);
                              }),
                              isLoading:
                                  _previewEntries == null &&
                                  snapshot.connectionState ==
                                      ConnectionState.waiting,
                              onPeriodChanged: _selectPeriod,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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

/// Displays the achievement status tabs.
class _AchievementStatusTabs extends StatelessWidget {
  /// Creates achievement status tabs.
  const _AchievementStatusTabs({
    required this.selected,
    this.allCount,
    required this.earnedCount,
    required this.lockedCount,
    required this.onSelected,
  });

  final _AchievementStatusTab selected;
  final int? allCount;
  final int earnedCount;
  final int lockedCount;
  final ValueChanged<_AchievementStatusTab> onSelected;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _AchievementGlassSurface(
      key: const Key('achievement-status-tabs'),
      radius: 24,
      blur: true,
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLtr = Directionality.of(context) == TextDirection.ltr;
          final choices = [
            if (allCount != null) _AchievementStatusTab.all,
            _AchievementStatusTab.earned,
            _AchievementStatusTab.locked,
          ];
          final index = choices.indexOf(selected).clamp(0, choices.length - 1);
          final alignment = -1.0 + 2.0 * index / (choices.length - 1);

          /// Selects from drag.
          void selectFromDrag(DragUpdateDetails details) {
            final fraction = details.localPosition.dx / constraints.maxWidth;
            final next =
                choices[((isLtr ? fraction : 1 - fraction) * choices.length)
                    .floor()
                    .clamp(0, choices.length - 1)];
            if (next != selected) onSelected(next);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: selectFromDrag,
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(isLtr ? alignment : -alignment, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / choices.length,
                    child: Container(
                      key: const Key('achievement-tab-thumb'),
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF58C97C), Color(0xFF22924B)],
                        ),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: Colors.white30),
                        boxShadow: [
                          BoxShadow(
                            color: _MeColors.green.withValues(alpha: 0.3),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (allCount != null)
                      Expanded(
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size.fromHeight(48),
                          onPressed: () =>
                              onSelected(_AchievementStatusTab.all),
                          child: _AchievementTabLabel(
                            key: const Key('achievement-tab-all'),
                            icon: CupertinoIcons.square_grid_2x2,
                            label: 'All  $allCount',
                            selected: selected == _AchievementStatusTab.all,
                          ),
                        ),
                      ),
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.fromHeight(48),
                        onPressed: () =>
                            onSelected(_AchievementStatusTab.earned),
                        child: _AchievementTabLabel(
                          key: const Key('achievement-tab-earned'),
                          icon: CupertinoIcons.rosette,
                          label: 'Earned  $earnedCount',
                          selected: selected == _AchievementStatusTab.earned,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.fromHeight(48),
                        onPressed: () =>
                            onSelected(_AchievementStatusTab.locked),
                        child: _AchievementTabLabel(
                          key: const Key('achievement-tab-locked'),
                          icon: CupertinoIcons.lock,
                          label: 'Locked  $lockedCount',
                          selected: selected == _AchievementStatusTab.locked,
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

/// Displays the achievement podium.
class _AchievementPodium extends StatelessWidget {
  /// Creates achievement podium.
  const _AchievementPodium({required this.entries});
  final List<Map<String, dynamic>> entries;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final index in [1, 0, 2])
          if (index < entries.length)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Icon(
                      index == 0
                          ? CupertinoIcons.rosette
                          : CupertinoIcons.person_crop_circle_fill,
                      size: index == 0 ? 44 : 34,
                      color: [
                        const Color(0xFFD6A72C),
                        const Color(0xFF96A6B5),
                        const Color(0xFFBD8053),
                      ][index],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${entries[index]['displayName']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${entries[index]['points']} pts',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: index == 0
                          ? 110
                          : index == 1
                          ? 80
                          : 60,
                      width: double.infinity,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _MeColors.green.withValues(
                              alpha: index == 0 ? 0.7 : 0.35,
                            ),
                            _MeColors.green.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// Displays the achievement hero orb.
class _AchievementHeroOrb extends StatelessWidget {
  /// Creates achievement hero orb.
  const _AchievementHeroOrb({required this.size, this.color});

  final double size;
  final Color? color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final glow = color ?? Colors.white.withValues(alpha: 0.13);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [glow, glow.withValues(alpha: 0)]),
      ),
    );
  }
}

/// Displays the achievement level medallion.
class _AchievementLevelMedallion extends StatelessWidget {
  /// Creates achievement level medallion.
  const _AchievementLevelMedallion({required this.level, required this.onTap});

  final int level;
  final VoidCallback onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Level $level badge. View all hiker levels',
      child: CupertinoButton(
        key: const Key('achievement-level-medallion'),
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(86),
        onPressed: onTap,
        child: Container(
          width: 86,
          height: 86,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [Color(0xFFFFD166), Colors.white, Color(0xFFFFD166)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD166).withValues(alpha: 0.3),
                blurRadius: 24,
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF173F2C), Color(0xFF071C11)],
              ),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.landscape_rounded,
                  color: Color(0xFFFFD166),
                  size: 30,
                ),
                Text(
                  'LV $level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows hiker level roadmap.
void _showHikerLevelRoadmap(BuildContext context, int points) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _HikerLevelRoadmapSheet(points: points),
  );
}

/// Displays the hiker level roadmap sheet.
class _HikerLevelRoadmapSheet extends StatefulWidget {
  /// Creates hiker level roadmap sheet.
  const _HikerLevelRoadmapSheet({required this.points});
  final int points;

  /// Creates the presentation state for this widget.
  @override
  State<_HikerLevelRoadmapSheet> createState() =>
      _HikerLevelRoadmapSheetState();
}

/// Manages the hiker level roadmap sheet presentation and lifecycle.
class _HikerLevelRoadmapSheetState extends State<_HikerLevelRoadmapSheet> {
  late int _selected = HikerLevel.fromPoints(widget.points).number;
  late final PageController _levelController = PageController(
    initialPage: _selected - 1,
    viewportFraction: 0.9,
  );

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _levelController.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final current = HikerLevel.fromPoints(widget.points);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _MeColors.surfaceFor(context),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _MeColors.separatorFor(context),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hiker levels',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _MeColors.textFor(context),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        semanticLabel: 'Close hiker levels',
                        color: _MeColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _MeColors.green.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR HIKER RANK',
                              style: TextStyle(
                                color: _MeColors.secondaryTextFor(context),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.landscape_rounded,
                                  size: 40,
                                  color: _MeColors.green,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    current.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  'LV ${current.number}',
                                  style: const TextStyle(
                                    color: _MeColors.green,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${_formatRankPoints(widget.points)} achievement points',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: current.progressFor(widget.points),
                                minHeight: 6,
                                color: _MeColors.green,
                                backgroundColor: _MeColors.green.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              current.nextLevelPoints == null
                                  ? 'Highest rank reached. Every adventure still counts.'
                                  : '${_formatRankPoints(current.pointsToNextLevel(widget.points))} points to ${HikerLevel.tiers[current.number].name}',
                              style: TextStyle(
                                color: _MeColors.secondaryTextFor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Explore your next milestone',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Swipe to explore levels and their requirements.',
                        style: TextStyle(
                          color: _MeColors.secondaryTextFor(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 320,
                        child: PageView.builder(
                          key: const Key('hiker-level-carousel'),
                          controller: _levelController,
                          itemCount: HikerLevel.tiers.length,
                          onPageChanged: (index) =>
                              setState(() => _selected = index + 1),
                          itemBuilder: (context, index) {
                            final level = HikerLevel.tiers[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: Opacity(
                                opacity: level.number <= current.number
                                    ? 1
                                    : 0.5,
                                child: _HikerLevelRoadmapRow(
                                  level: level,
                                  currentLevel: current,
                                  points: widget.points,
                                  selected: true,
                                  onTap: () => _levelController.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Text(
                        'Level $_selected of ${HikerLevel.tiers.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _MeColors.secondaryTextFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats rank points.
String _formatRankPoints(int points) {
  final normalized = points < 0 ? 0 : points;
  if (normalized < 1000) return '$normalized';
  final thousands = normalized ~/ 1000;
  final remainder = (normalized % 1000).toString().padLeft(3, '0');
  return '$thousands,$remainder';
}

/// Displays the achievement collection grid.
class _AchievementCollectionGrid extends StatelessWidget {
  /// Creates achievement collection grid.
  const _AchievementCollectionGrid({
    required this.items,
    required this.onTap,
    this.onEdit,
    this.onToggleActive,
    this.actionsEnabled = true,
  });

  final List<_AchievementProfileItem> items;
  final ValueChanged<_AchievementProfileItem> onTap;
  final Future<void> Function(_AchievementProfileItem)? onEdit, onToggleActive;
  final bool actionsEnabled;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 540 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            mainAxisExtent:
                (onEdit == null ? 236 : 260) +
                (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0, 24) *
                    3,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final card = _AchievementBadgeCard(
              item: item,
              onTap: () => onTap(item),
            );
            if (onEdit == null || onToggleActive == null) return card;
            return AchievementRuleSwipeCard(
              key: ValueKey('achievement-admin-${item.achievementId}'),
              achievementId: item.achievementId,
              isActive: item.isActive,
              enabled: actionsEnabled,
              onEdit: () => onEdit!(item),
              onToggleActive: () => onToggleActive!(item),
              child: card,
            );
          },
        );
      },
    );
  }
}

/// Displays the achievement tag.
class _AchievementTag extends StatelessWidget {
  /// Creates achievement tag.
  const _AchievementTag({
    required this.label,
    this.accent,
    this.compact = false,
  });

  final String label;
  final Color? accent;
  final bool compact;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: (accent ?? _MeColors.green).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (accent ?? _MeColors.green).withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent ?? _MeColors.secondaryTextFor(context),
          fontSize: compact ? 9 : null,
          fontWeight: FontWeight.w800,
          letterSpacing: compact ? 0.7 : 0,
        ),
      ),
    );
  }
}

/// Displays the achievement detail sheet.
class _AchievementDetailSheet extends StatelessWidget {
  /// Creates achievement detail sheet.
  const _AchievementDetailSheet({required this.item});

  final _AchievementProfileItem item;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final guidance = _AchievementGuidance.forItem(item);
    final displayPoints = item.isUnlocked
        ? item.pointsAwarded
        : item.rewardPoints;
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.84,
        minChildSize: 0.56,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: _MeColors.surfaceFor(context),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _MeColors.separatorFor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: _AchievementBadge(
                              icon: _achievementIconFor(item.iconName),
                              color: item.accentColor,
                              unlocked: item.isUnlocked,
                              size: 94,
                              showShadow: false,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            item.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: _MeColors.textFor(context),
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Center(
                            child: _AchievementTag(
                              label: !item.isActive
                                  ? 'INACTIVE · ${item.category.toUpperCase()}'
                                  : item.isUnlocked
                                  ? 'EARNED · $displayPoints POINTS'
                                  : '${item.category.toUpperCase()} · $displayPoints POINTS',
                              accent: item.accentColor,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (item.isCumulative)
                            _AchievementDetailProgress(item: item),
                          if (item.isCumulative) const SizedBox(height: 12),
                          _AchievementDetailSection(
                            icon: CupertinoIcons.heart_fill,
                            title: 'Why this achievement exists',
                            body: guidance.whyItMatters,
                            accent: item.accentColor,
                          ),
                          const SizedBox(height: 10),
                          _AchievementDetailSection(
                            icon: CupertinoIcons.scope,
                            title: 'Your goal',
                            body: item.condition,
                            accent: item.accentColor,
                            footer: item.isUnlocked
                                ? 'Goal completed${item.awardedAt == null ? '' : ' on ${_formatAchievementDate(item.awardedAt!)}'}.'
                                : guidance.goalProgress(item),
                          ),
                          const SizedBox(height: 10),
                          _AchievementDetailSection(
                            icon: CupertinoIcons.checkmark_alt_circle_fill,
                            title: 'What counts',
                            body: guidance.whatCounts,
                            accent: item.accentColor,
                          ),
                          const SizedBox(height: 10),
                          _AchievementDetailSection(
                            icon: CupertinoIcons.sparkles,
                            title: 'Reward and recognition',
                            body:
                                '${item.rewardRecognition}\n\n$displayPoints points · awarded once · contributes to your Trail Journey level.',
                            accent: item.accentColor,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size.fromHeight(48),
                      color: _MeColors.green,
                      borderRadius: BorderRadius.circular(17),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Displays the achievement detail progress.
class _AchievementDetailProgress extends StatelessWidget {
  /// Creates achievement detail progress.
  const _AchievementDetailProgress({required this.item});

  final _AchievementProfileItem item;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final remaining = (item.targetCount - item.progressCount).clamp(
      0,
      item.targetCount,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            item.accentColor.withValues(alpha: 0.17),
            item.accentColor.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: item.accentColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                item.isUnlocked ? 'Completed' : 'Current progress',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              Text(
                '${AchievementCatalog.quantity(item.metricKey, item.progressCount, unit: false)} / ${AchievementCatalog.quantity(item.metricKey, item.targetCount)}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: item.accentColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 9,
              backgroundColor: item.accentColor.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(item.accentColor),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.isUnlocked
                  ? 'This milestone is complete.'
                  : '${AchievementCatalog.quantity(item.metricKey, remaining)} remaining before this badge unlocks.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _MeColors.secondaryTextFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the achievement ambient backdrop.
class _AchievementAmbientBackdrop extends StatelessWidget {
  /// Creates achievement ambient backdrop.
  const _AchievementAmbientBackdrop();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = _MeColors.isDark(context);
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -110,
            top: -85,
            child: _AchievementAura(
              size: 300,
              color: const Color(
                0xFF34A853,
              ).withValues(alpha: isDark ? 0.14 : 0.11),
            ),
          ),
          Positioned(
            left: -130,
            top: 380,
            child: _AchievementAura(
              size: 280,
              color: const Color(
                0xFF57C7B6,
              ).withValues(alpha: isDark ? 0.08 : 0.09),
            ),
          ),
          Positioned(
            right: -90,
            bottom: 40,
            child: _AchievementAura(
              size: 230,
              color: const Color(
                0xFFFFD166,
              ).withValues(alpha: isDark ? 0.045 : 0.07),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the achievement aura.
class _AchievementAura extends StatelessWidget {
  /// Creates achievement aura.
  const _AchievementAura({required this.size, required this.color});

  final double size;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 1],
        ),
      ),
    );
  }
}

/// Displays the achievement glass surface.
class _AchievementGlassSurface extends StatelessWidget {
  /// Creates achievement glass surface.
  const _AchievementGlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = false,
    this.accent,
    this.gradient,
    this.borderColor,
    this.shadowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final Color? accent;
  final Gradient? gradient;
  final Color? borderColor;
  final Color? shadowColor;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final isDark = _MeColors.isDark(context);
    final surface = _MeColors.surfaceFor(context);
    final border =
        borderColor ??
        (accent?.withValues(alpha: isDark ? 0.22 : 0.16) ??
            Colors.white.withValues(alpha: isDark ? 0.1 : 0.76));
    final decoration = BoxDecoration(
      color: gradient == null
          ? surface.withValues(alpha: isDark ? 0.76 : 0.72)
          : null,
      gradient:
          gradient ??
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: isDark ? 0.08 : 0.7),
              surface.withValues(alpha: isDark ? 0.62 : 0.54),
            ],
          ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color:
              shadowColor ??
              Colors.black.withValues(alpha: isDark ? 0.2 : 0.075),
          blurRadius: blur ? 25 : 15,
          offset: Offset(0, blur ? 12 : 7),
        ),
        if (accent != null)
          BoxShadow(
            color: accent!.withValues(alpha: isDark ? 0.08 : 0.055),
            blurRadius: 18,
            spreadRadius: -3,
          ),
      ],
    );
    final content = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 17, sigmaY: 17),
              child: content,
            )
          : content,
    );
  }
}

/// Displays the achievement section glyph.
class _AchievementSectionGlyph extends StatelessWidget {
  /// Creates achievement section glyph.
  const _AchievementSectionGlyph({required this.icon});

  final IconData icon;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF58C97C), Color(0xFF22924B)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white30),
        boxShadow: [
          BoxShadow(
            color: _MeColors.green.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

/// Displays the time zone picker sheet.
class _TimeZonePickerSheet extends StatefulWidget {
  /// Creates time zone picker sheet.
  const _TimeZonePickerSheet({required this.selectedTimeZone});

  final String selectedTimeZone;

  /// Creates the presentation state for this widget.
  @override
  State<_TimeZonePickerSheet> createState() => _TimeZonePickerSheetState();
}

/// Manages the time zone picker sheet presentation and lifecycle.
class _TimeZonePickerSheetState extends State<_TimeZonePickerSheet> {
  String _query = '';

  /// Returns filtered time zones.
  List<String> get _filteredTimeZones {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return PreferredTimeZone.allIds;
    return PreferredTimeZone.allIds
        .where((timeZoneId) {
          return timeZoneId.toLowerCase().contains(query) ||
              PreferredTimeZone.fullLabel(
                timeZoneId,
              ).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final timeZones = _filteredTimeZones;
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOS message timezone',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _MeColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Alert times use this timezone even when the phone is elsewhere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _MeColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search city or timezone',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: _MeColors.backgroundFor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: timeZones.isEmpty
                  ? Center(
                      child: Text(
                        'No matching timezone',
                        style: TextStyle(
                          color: _MeColors.secondaryTextFor(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: timeZones.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: _MeColors.separatorFor(context),
                      ),
                      itemBuilder: (context, index) {
                        final timeZoneId = timeZones[index];
                        final isSelected =
                            timeZoneId == widget.selectedTimeZone;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          title: Text(
                            PreferredTimeZone.fullLabel(timeZoneId),
                            style: TextStyle(
                              color: _MeColors.textFor(context),
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(timeZoneId),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: _MeColors.green,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(timeZoneId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the settings cell.
class _SettingsCell extends StatelessWidget {
  /// Creates settings cell.
  const _SettingsCell({
    required this.item,
    required this.onTap,
    this.countLabel,
  });

  final MeActionItem item;
  final VoidCallback onTap;
  final String? countLabel;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final displayedCount = countLabel;
    return _TapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            _Glyph(icon: item.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (displayedCount != null) ...[
              _MiniPill(label: displayedCount),
              const SizedBox(width: 8),
            ],
            Icon(
              CupertinoIcons.chevron_forward,
              color: _MeColors.chevronFor(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the sign out cell.
class _SignOutCell extends StatelessWidget {
  /// Creates sign out cell.
  const _SignOutCell({required this.onSignOut});

  final VoidCallback onSignOut;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onSignOut,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              'Sign Out',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _MeColors.destructiveFor(context),
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays the info line.
class _InfoLine extends StatelessWidget {
  /// Creates info line.
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _MeColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _MeColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon});

  final IconData icon;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _MeColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

/// Displays the tap surface.
class _TapSurface extends StatelessWidget {
  /// Creates tap surface.
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap ?? () {}, child: child),
    );
  }
}

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _MeColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _MeColors.separatorFor(context),
    );
  }
}

/// Represents me colors.
abstract final class _MeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes chevron for.
  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  /// Computes destructive for.
  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}

/// Provides UI styling for _AchievementProfileItem.
extension _AchievementProfileItemPresentation on _AchievementProfileItem {
  /// Returns accent color.
  Color get accentColor {
    if (accentColorValue == 0) {
      return _MeColors.green;
    }
    return Color(accentColorValue);
  }
}
