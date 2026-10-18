// MePage coordinates profile, account settings, privacy, achievements and security actions.
import '../../core/services/private_screen_unlock.dart';
import '../../authentication/View/recent_security_verification_page.dart';
import '../../authentication/View/change_password_page.dart';
import '../../core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../app/Model/preferred_time_zone.dart';
import '../../authentication/View/security_methods_page.dart';
import '../../assistant/View/hiker_circle_assistant_page.dart';
import '../../core/models/hiker_level.dart';
import '../../core/services/privacy_policy_launcher.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/app_toast.dart';
import '../../feedback/feedback_page.dart';
import '../../home/View/find_hike_page.dart';
import '../../home/View/first_aid_guide_page.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import '../../home/Model/hike_session_models.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../../onboarding/Data/onboarding_repository.dart';
import '../Model/me_models.dart';
import '../ModelView/me_view_model.dart';
import 'hike_history_page.dart';
import 'help_center_page.dart';
import 'location_sharing_page.dart';
import 'profile_details_page.dart';
import 'qr_scanner_page.dart';

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.session,
    required this.phoneNumber,
    required this.onSignOut,
    this.onStartHike,
    this.onOpenSos,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final String phoneNumber;
  final VoidCallback onSignOut;
  final Future<void> Function(Trail trail)? onStartHike;
  final VoidCallback? onOpenSos;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final MeViewModel viewModel;
  late final HikerCircleFirebaseRepository firebaseRepository;
  late final OnboardingRepository onboardingRepository;
  late Future<List<Map<String, dynamic>>> achievementsFuture;
  late final EmergencyContactsRepository emergencyContactsRepository;
  List<EmergencyContact> emergencyContacts = const [];
  MeProfile? firestoreProfile;
  List<_ProfileHistoryItem> _postHistoryItems = const [];
  List<_ProfileHistoryItem> _circleHistoryItems = const [];
  List<_ProfileHistoryItem> _buddyHistoryItems = const [];
  final List<_ProfileHistoryItem> _trailHistoryItems = const [];

  @override
  void initState() {
    super.initState();
    viewModel = MeViewModel(session: widget.session);
    firebaseRepository = HikerCircleFirebaseRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    onboardingRepository = OnboardingRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    achievementsFuture = _loadProfileAchievements();
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    unawaited(_loadEmergencyContacts());
    unawaited(_loadFirestoreProfile());
    unawaited(_loadProfileCollections());
  }

  MeProfile get _displayProfile => firestoreProfile ?? viewModel.profile;

  Future<List<Map<String, dynamic>>> _loadProfileAchievements() async {
    final cached = await firebaseRepository.loadCachedAchievementProgress(
      session: widget.session,
    );
    if (cached != null) {
      unawaited(_refreshProfileAchievements(cached.contentHash));
      return cached.rows;
    }
    return _fetchProfileAchievements();
  }

  Future<List<Map<String, dynamic>>> _fetchProfileAchievements() async {
    final rows = await firebaseRepository.loadUserAchievementProgress(
      session: widget.session,
    );
    await firebaseRepository.saveCachedAchievementProgress(
      session: widget.session,
      contentHash: achievementProgressContentHash(rows),
      rows: rows,
    );
    return rows;
  }

  Future<void> _refreshProfileAchievements(String hash) async {
    try {
      final remote = await firebaseRepository.loadAchievementProgressHash(
        session: widget.session,
      );
      if (remote.isEmpty || remote == hash) return;
      final rows = await _fetchProfileAchievements();
      if (mounted) setState(() => achievementsFuture = Future.value(rows));
    } catch (_) {
      // Keep the saved summary available when the network is unavailable.
    }
  }

  Future<void> _loadFirestoreProfile() async {
    try {
      final profile = await onboardingRepository.loadProfile(widget.session);
      if (!mounted) return;
      final username = profile.username.trim();
      setState(() {
        firestoreProfile = MeProfile(
          displayName: username.isEmpty
              ? viewModel.profile.displayName
              : username,
          handle: username.isEmpty ? viewModel.profile.handle : '@$username',
          phoneNumber: widget.session.phoneNumber,
          status: viewModel.profile.status,
          photoURL: profile.photoURL ?? viewModel.profile.photoURL,
        );
      });
    } catch (_) {
      // Keep the locally cached session profile if Firestore is unavailable.
    }
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      final contacts = await emergencyContactsRepository.loadEmergencyContacts(
        session: widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        emergencyContacts = contacts;
      });
    } catch (_) {
      return;
    }
  }

  /// Load posts, group chats and buddy profiles independently from the account's editable profile fields.
  Future<void> _loadProfileCollections() async {
    try {
      final results = await Future.wait<Object>([
        firebaseRepository.loadCommunityPostsForUser(session: widget.session),
        firebaseRepository.loadUserGroupChats(widget.session.phoneNumber),
        firebaseRepository.loadBuddyPhoneNumbers(session: widget.session),
      ]);
      final ownPhone = widget.session.phoneNumber.trim();
      final posts = (results[0] as List<Map<String, dynamic>>)
          .map(
            (post) => _ProfileHistoryItem(
              title: post['trailName']?.toString().trim().isNotEmpty == true
                  ? post['trailName'].toString().trim()
                  : 'Community post',
              subtitle: post['caption']?.toString().trim() ?? '',
              meta: _profileHistoryDate(post['createdAtLocal']),
              icon: Icons.forum_rounded,
            ),
          )
          .toList(growable: false);
      final chats = (results[1] as List<GroupChat>)
          .where((chat) => !chat.isDirect)
          .map(
            (chat) => _ProfileHistoryItem(
              title: chat.displayNameFor(ownPhone),
              subtitle:
                  '${chat.participantPhones.length} hikers · ${chat.trailName}',
              meta: chat.hikeEndedAt == null
                  ? 'Active circle'
                  : 'Hike ended ${_profileDateLabel(chat.hikeEndedAt!)}',
              icon: Icons.groups_2_rounded,
            ),
          )
          .toList(growable: false);
      final buddyPhones = results[2] as Set<String>;
      final buddyProfiles = await Future.wait(
        buddyPhones.take(100).map((phone) async {
          try {
            return await firebaseRepository.loadPublicHikerProfile(
              phoneNumber: phone,
            );
          } catch (_) {
            return <String, dynamic>{'phoneNumber': phone};
          }
        }),
      );
      final buddies = buddyProfiles
          .map(
            (profile) => _ProfileHistoryItem(
              title: _profileDisplayName(profile),
              subtitle: [
                profile['levelName']?.toString().trim() ?? '',
                profile['hikerExperience']?.toString().trim() ?? '',
              ].where((value) => value.isNotEmpty).join(' · '),
              meta: '${profile['achievementPoints'] ?? 0} achievement points',
              icon: Icons.person_rounded,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _postHistoryItems = posts;
        _circleHistoryItems = chats;
        _buddyHistoryItems = buddies;
      });
    } catch (_) {
      // The sections stay empty while Firebase is unavailable.
    }
  }

  String _profileDisplayName(Map<String, dynamic> profile) {
    for (final key in const ['displayName', 'username', 'handle']) {
      final value = profile[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return 'Hiking buddy';
  }

  String _profileHistoryDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? 'Recent activity' : _profileDateLabel(parsed);
  }

  String _profileDateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  List<MeStat> get _linkedProfileStats => [
    MeStat(label: 'Circles', value: '${_circleHistoryItems.length}'),
    MeStat(label: 'Buddies', value: '${_buddyHistoryItems.length}'),
    MeStat(label: 'Trails', value: '${_trailHistoryItems.length}'),
  ];

  String? _countLabelForAction(String title) => switch (title) {
    'My posts' => '${_postHistoryItems.length}',
    'My circles' => '${_circleHistoryItems.length}',
    'My buddies' => '${_buddyHistoryItems.length}',
    'Export history' =>
      '${_postHistoryItems.length + _circleHistoryItems.length + _buddyHistoryItems.length + _trailHistoryItems.length}',
    _ => null,
  };

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

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
                  _StatsGroup(
                    stats: _linkedProfileStats,
                    onTap: _openStatDetail,
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
            builder: (context) => _DeviceNotificationsPage(
              phoneNumber: widget.session.phoneNumber,
            ),
          ),
        );
      case 'Privacy Policy':
        unawaited(_openPrivacyPolicy());
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

  Future<void> _openEmergencyContacts() async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) => EmergencyContactsPage(
          session: widget.session,
          initialContacts: emergencyContacts,
          repository: emergencyContactsRepository,
        ),
      ),
    );

    if (contacts == null || !mounted) {
      return;
    }

    setState(() {
      emergencyContacts = contacts;
    });
  }

  Future<void> _openAssistantTrail(String trailId) async {
    final trails = await firebaseRepository.loadTrails();
    if (!mounted) return;
    for (final trail in trails) {
      if (trail.trailId == trailId) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrailDetailPage(
              session: widget.session,
              hikerCircleRepository: firebaseRepository,
              trail: trail,
              onStartHike: widget.onStartHike ?? (_) async {},
            ),
          ),
        );
        return;
      }
    }
    HikerCircleToast.show(context, 'This trail is no longer available.');
  }

  /// Map supported assistant destination identifiers to existing account and app screens.
  void _navigateFromAssistant(String destinationId) {
    switch (destinationId) {
      case 'trails':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrailPage(
              session: widget.session,
              hikerCircleRepository: firebaseRepository,
              onStartHike: widget.onStartHike ?? (_) async {},
            ),
          ),
        );
      case 'find_hike':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FindHikePage(
              session: widget.session,
              repository: firebaseRepository,
            ),
          ),
        );
      case 'emergency_contacts':
        unawaited(_openEmergencyContacts());
      case 'sos':
        Navigator.of(context).pop();
        Navigator.of(context).pop();
        widget.onOpenSos?.call();
      case 'first_aid':
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FirstAidGuidePage()),
        );
      case 'security':
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SecurityMethodsPage()),
        );
      case 'hike_history':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HikeHistoryPage(
              repository: firebaseRepository,
              session: widget.session,
            ),
          ),
        );
      case 'achievements':
        unawaited(_openAchievements());
      case 'feedback':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FeedbackPage(isAdmin: widget.session.isAdmin),
          ),
        );
    }
  }

  void _openStatDetail(MeStat stat) {
    switch (stat.label) {
      case 'Circles':
        _openHistoryPage(
          title: 'My Circles',
          subtitle: 'Teams you created, joined, or completed',
          icon: Icons.groups_2_rounded,
          items: _circleHistoryItems,
        );
      case 'Buddies':
        _openHistoryPage(
          title: 'My Buddies',
          subtitle: 'Friends from hikes, community, and QR scans',
          icon: Icons.person_add_alt_1_rounded,
          items: _buddyHistoryItems,
        );
      case 'Trails':
        _openHistoryPage(
          title: 'Trail History',
          subtitle: 'Saved and completed routes',
          icon: Icons.map_rounded,
          items: _trailHistoryItems,
        );
    }
  }

  Future<void> _openAchievements() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AchievementsPage(
          session: widget.session,
          repository: firebaseRepository,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      achievementsFuture = _loadProfileAchievements();
    });
  }

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

  void _openHelpCenter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HelpCenterPage(isAdmin: widget.session.isAdmin),
      ),
    );
  }

  void _openAdvancedSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _AdvancedAppSettingsPage(
          session: widget.session,
          firebaseRepository: firebaseRepository,
          onOpenTrail: _openAssistantTrail,
          onNavigate: _navigateFromAssistant,
        ),
      ),
    );
  }

  void _openQrCode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileQrPage(profile: _displayProfile),
      ),
    );
  }

  Future<void> _openProfileDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileDetailsPage(
          session: widget.session,
          firebaseBootstrapResult: widget.firebaseBootstrapResult,
        ),
      ),
    );
    await _loadFirestoreProfile();
  }

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

  String _ownHandleForPhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length <= 4) {
      return 'hiker$digits';
    }
    return 'hiker${digits.substring(digits.length - 4)}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.onShowQr,
    required this.onOpenScanner,
    required this.onOpenSettings,
  });

  final MeProfile profile;
  final VoidCallback onShowQr;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: PageHeaderStyle.title(
                    context,
                    _MeColors.textFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Welcome back, ${profile.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PageHeaderStyle.subtitle(
                    context,
                    _MeColors.secondaryTextFor(context),
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'QR code',
            icon: Icons.qr_code_rounded,
            onPressed: onShowQr,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Scan QR',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: onOpenScanner,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Settings',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    color: _MeColors.green,
    surface: _MeColors.surfaceFor(context),
  );
}

class _ProfileCell extends StatelessWidget {
  const _ProfileCell({
    required this.profile,
    required this.onTap,
    this.photoBytes,
  });

  final MeProfile profile;
  final VoidCallback onTap;
  final Uint8List? photoBytes;

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

class _ProfileQrPage extends StatelessWidget {
  const _ProfileQrPage({required this.profile});

  final MeProfile profile;

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

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) =>
      PageHeader(title: title, subtitle: subtitle, onBack: onBack);
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.matrix});

  final List<List<bool>> matrix;

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

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.matrix != matrix;
  }
}

class _QrMatrix {
  _QrMatrix._(this.modules);

  static const int _version = 4;
  static const int _size = 17 + _version * 4;
  static const int _dataCodewords = 80;
  static const int _ecCodewords = 20;
  static const int _formatBitsLowMaskZero = 0x77C4;

  final List<List<bool>> modules;

  static _QrMatrix encode(String text) {
    final data = _buildDataCodewords(text);
    final errorCorrection = _computeRemainder(
      data,
      _computeDivisor(_ecCodewords),
    );
    final codewords = [...data, ...errorCorrection];
    final qr = _MutableQr();
    qr.drawFunctionPatterns();
    qr.drawCodewords(codewords);
    qr.applyMask();
    qr.drawFormatBits(_formatBitsLowMaskZero);
    return _QrMatrix._(qr.modules);
  }

  static List<int> _buildDataCodewords(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > 73) {
      throw ArgumentError('Profile link is too long for the local QR encoder.');
    }

    final bits = <bool>[];
    _appendBits(bits, 0x4, 4);
    _appendBits(bits, bytes.length, 8);
    for (final byte in bytes) {
      _appendBits(bits, byte, 8);
    }

    final capacityBits = _dataCodewords * 8;
    final terminator = (capacityBits - bits.length).clamp(0, 4);
    _appendBits(bits, 0, terminator);
    while (bits.length % 8 != 0) {
      bits.add(false);
    }

    final result = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var value = 0;
      for (var j = 0; j < 8; j++) {
        value = (value << 1) | (bits[i + j] ? 1 : 0);
      }
      result.add(value);
    }

    var pad = 0xEC;
    while (result.length < _dataCodewords) {
      result.add(pad);
      pad ^= 0xEC ^ 0x11;
    }
    return result;
  }

  static void _appendBits(List<bool> bits, int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add(((value >> i) & 1) != 0);
    }
  }

  static List<int> _computeDivisor(int degree) {
    final result = List<int>.filled(degree, 0);
    result[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = _multiply(result[j], root);
        if (j + 1 < result.length) {
          result[j] ^= result[j + 1];
        }
      }
      root = _multiply(root, 0x02);
    }
    return result;
  }

  static List<int> _computeRemainder(List<int> data, List<int> divisor) {
    final result = List<int>.filled(divisor.length, 0, growable: true);
    for (final byte in data) {
      final factor = byte ^ result.removeAt(0);
      result.add(0);
      for (var i = 0; i < result.length; i++) {
        result[i] ^= _multiply(divisor[i], factor);
      }
    }
    return result;
  }

  static int _multiply(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      if (((y >> i) & 1) != 0) {
        z ^= x;
      }
    }
    return z & 0xFF;
  }
}

class _MutableQr {
  final List<List<bool>> modules = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );
  final List<List<bool>> _isFunction = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );

  void drawFunctionPatterns() {
    _drawFinder(3, 3);
    _drawFinder(_QrMatrix._size - 4, 3);
    _drawFinder(3, _QrMatrix._size - 4);

    for (var i = 0; i < _QrMatrix._size; i++) {
      if (!_isFunction[6][i]) {
        _setFunction(i, 6, i.isEven);
      }
      if (!_isFunction[i][6]) {
        _setFunction(6, i, i.isEven);
      }
    }

    _drawAlignment(26, 26);
    _setFunction(8, 4 * _QrMatrix._version + 9, true);
    drawFormatBits(0);
  }

  void _drawFinder(int centerX, int centerY) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final x = centerX + dx;
        final y = centerY + dy;
        if (x < 0 || x >= _QrMatrix._size || y < 0 || y >= _QrMatrix._size) {
          continue;
        }
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(x, y, distance != 2 && distance != 4);
      }
    }
  }

  void _drawAlignment(int centerX, int centerY) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(centerX + dx, centerY + dy, distance != 1);
      }
    }
  }

  void drawFormatBits(int bits) {
    for (var i = 0; i <= 5; i++) {
      _setFunction(8, i, _bit(bits, i));
    }
    _setFunction(8, 7, _bit(bits, 6));
    _setFunction(8, 8, _bit(bits, 7));
    _setFunction(7, 8, _bit(bits, 8));
    for (var i = 9; i < 15; i++) {
      _setFunction(14 - i, 8, _bit(bits, i));
    }
    for (var i = 0; i < 8; i++) {
      _setFunction(_QrMatrix._size - 1 - i, 8, _bit(bits, i));
    }
    for (var i = 8; i < 15; i++) {
      _setFunction(8, _QrMatrix._size - 15 + i, _bit(bits, i));
    }
  }

  void drawCodewords(List<int> codewords) {
    final bits = <bool>[];
    for (final codeword in codewords) {
      for (var i = 7; i >= 0; i--) {
        bits.add(((codeword >> i) & 1) != 0);
      }
    }

    var bitIndex = 0;
    var upward = true;
    for (var right = _QrMatrix._size - 1; right >= 1; right -= 2) {
      if (right == 6) {
        right = 5;
      }
      for (var vert = 0; vert < _QrMatrix._size; vert++) {
        final y = upward ? _QrMatrix._size - 1 - vert : vert;
        for (var dx = 0; dx < 2; dx++) {
          final x = right - dx;
          if (_isFunction[y][x]) {
            continue;
          }
          modules[y][x] = bitIndex < bits.length && bits[bitIndex];
          bitIndex++;
        }
      }
      upward = !upward;
    }
  }

  void applyMask() {
    for (var y = 0; y < _QrMatrix._size; y++) {
      for (var x = 0; x < _QrMatrix._size; x++) {
        if (!_isFunction[y][x] && (x + y).isEven) {
          modules[y][x] = !modules[y][x];
        }
      }
    }
  }

  void _setFunction(int x, int y, bool isDark) {
    modules[y][x] = isDark;
    _isFunction[y][x] = true;
  }

  static bool _bit(int value, int index) {
    return ((value >> index) & 1) != 0;
  }
}

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

class _AchievementProfileItem {
  const _AchievementProfileItem({
    required this.achievementId,
    required this.title,
    required this.condition,
    required this.category,
    required this.iconName,
    required this.rewardPoints,
    required this.pointsAwarded,
    required this.rewardType,
    required this.metricKey,
    required this.progressCount,
    required this.targetCount,
    required this.sortOrder,
    required this.accentColorValue,
    required this.isUnlocked,
    required this.awardedAt,
  });

  final String achievementId;
  final String title;
  final String condition;
  final String category;
  final String iconName;
  final int rewardPoints;
  final int pointsAwarded;
  final String rewardType;
  final String metricKey;
  final int progressCount;
  final int targetCount;
  final int sortOrder;
  final int accentColorValue;
  final bool isUnlocked;
  final DateTime? awardedAt;

  bool get isCumulative => rewardType == 'cumulative';

  double get progress => targetCount <= 0
      ? 0
      : (progressCount / targetCount).clamp(0, 1).toDouble();

  Color get accentColor {
    if (accentColorValue == 0) {
      return _MeColors.green;
    }
    return Color(accentColorValue);
  }

  factory _AchievementProfileItem.fromRow(Map<String, dynamic> row) {
    final title = _mapString(row['title']);
    final condition = _mapString(row['condition']);
    final category = _mapString(row['category']);
    final iconName = _mapString(row['iconName']);

    return _AchievementProfileItem(
      achievementId: _mapString(row['achievementId']),
      title: title.isEmpty ? 'Achievement' : title,
      condition: condition.isEmpty ? 'Complete a safety milestone' : condition,
      category: category.isEmpty ? 'Safety' : category,
      iconName: iconName.isEmpty ? 'emoji_events' : iconName,
      rewardPoints: _mapInt(row['rewardPoints']),
      pointsAwarded: _mapInt(row['pointsAwarded']),
      rewardType: _mapString(row['rewardType']) == 'cumulative'
          ? 'cumulative'
          : 'one_time',
      metricKey: _mapString(row['metricKey']),
      progressCount: _mapInt(row['progressCount']),
      targetCount: _mapInt(row['targetCount']).clamp(1, 1000000000),
      sortOrder: _mapInt(row['sortOrder']),
      accentColorValue: _mapInt(row['accentColorValue']),
      isUnlocked: row['isUnlocked'] == true,
      awardedAt: DateTime.tryParse(_mapString(row['awardedAtLocal'])),
    );
  }
}

List<_AchievementProfileItem> _achievementItemsFromRows(
  List<Map<String, dynamic>> rows,
) {
  return rows.map(_AchievementProfileItem.fromRow).toList()
    ..sort((left, right) {
      final orderComparison = left.sortOrder.compareTo(right.sortOrder);
      if (orderComparison != 0) {
        return orderComparison;
      }
      return left.title.compareTo(right.title);
    });
}

String _mapString(Object? value) {
  return value is String ? value : '';
}

int _mapInt(Object? value) {
  return value is num && value.isFinite ? value.toInt() : 0;
}

String _formatAchievementDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

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
    'explore' => Icons.explore_rounded,
    'travel_explore' => Icons.travel_explore_rounded,
    'public' => Icons.public_rounded,
    'forum' => Icons.forum_rounded,
    'warning' => Icons.warning_amber_rounded,
    _ => Icons.emoji_events_rounded,
  };
}

class _ProfileHistoryItem {
  const _ProfileHistoryItem({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
}

class _ProfileHistoryPage extends StatelessWidget {
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

class _ProfileHistoryCard extends StatelessWidget {
  const _ProfileHistoryCard({required this.item});

  final _ProfileHistoryItem item;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: item.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MiniPill(label: item.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSettingsDetailPage extends StatelessWidget {
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

class _DeviceNotificationsPage extends StatefulWidget {
  const _DeviceNotificationsPage({required this.phoneNumber});

  final String phoneNumber;

  @override
  State<_DeviceNotificationsPage> createState() =>
      _DeviceNotificationsPageState();
}

class _DeviceNotificationsPageState extends State<_DeviceNotificationsPage> {
  final LocalSessionDatabase _database = LocalSessionDatabase();
  late Future<List<DeviceNotificationRecord>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _loadNotifications();
  }

  Future<List<DeviceNotificationRecord>> _loadNotifications() {
    return _database.loadDeviceNotifications(
      ownerPhoneNumber: widget.phoneNumber,
      limit: 500,
    );
  }

  Future<void> _refresh() async {
    final nextFuture = _loadNotifications();
    setState(() {
      _notificationsFuture = nextFuture;
    });
    await nextFuture;
  }

  Future<void> _clearNotifications() async {
    await _database.clearDeviceNotifications(
      ownerPhoneNumber: widget.phoneNumber,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Device notifications cleared.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    await _refresh();
  }

  Future<void> _markAllOpened() async {
    await _database.markAllDeviceNotificationsOpened(
      ownerPhoneNumber: widget.phoneNumber,
    );
    if (mounted) await _refresh();
  }

  Future<void> _toggleStar(DeviceNotificationRecord notification) async {
    await _database.setDeviceNotificationStarred(
      ownerPhoneNumber: widget.phoneNumber,
      id: notification.id,
      isStarred: !notification.isStarred,
    );
    if (mounted) await _refresh();
  }

  Future<void> _deleteNotification(
    DeviceNotificationRecord notification,
  ) async {
    await _database.deleteDeviceNotification(
      ownerPhoneNumber: widget.phoneNumber,
      id: notification.id,
    );
    if (mounted) await _refresh();
  }

  Future<void> _markOpened(DeviceNotificationRecord notification) async {
    if (notification.isOpened) {
      return;
    }
    await _database.markDeviceNotificationOpened(
      ownerPhoneNumber: widget.phoneNumber,
      id: notification.id,
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: _MeColors.green,
          child: FutureBuilder<List<DeviceNotificationRecord>>(
            future: _notificationsFuture,
            builder: (context, snapshot) {
              final notifications =
                  snapshot.data ?? const <DeviceNotificationRecord>[];
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailHeader(
                          title: 'Notifications',
                          subtitle: 'FCMs received on this phone',
                          onBack: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 16),
                        if (isLoading)
                          const HikerCircleLoadingView(
                            message: 'Loading notifications…',
                            detail:
                                'Collecting notifications saved on this device.',
                            padding: EdgeInsets.only(top: 28, bottom: 12),
                          )
                        else if (notifications.isEmpty)
                          _NotificationEmptyState(onRefresh: _refresh)
                        else ...[
                          _NotificationSummaryCard(
                            count: notifications.length,
                            unreadCount: notifications
                                .where((item) => !item.isOpened)
                                .length,
                            onMarkAllRead: _markAllOpened,
                            onClear: _clearNotifications,
                          ),
                          const SizedBox(height: 12),
                          for (
                            var index = 0;
                            index < notifications.length;
                            index++
                          ) ...[
                            _DeviceNotificationTile(
                              notification: notifications[index],
                              onTap: _markOpened,
                              onStar: _toggleStar,
                              onDelete: _deleteNotification,
                            ),
                            if (index != notifications.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationSummaryCard extends StatelessWidget {
  const _NotificationSummaryCard({
    required this.count,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onClear,
  });

  final int count;
  final int unreadCount;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: CupertinoIcons.bell_fill),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count notifications saved on this device',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  Text(
                    '$unreadCount unread · newest 500 kept locally',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (unreadCount > 0)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                onPressed: () => unawaited(onMarkAllRead()),
                child: Text(
                  'Read all',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _MeColors.green,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              onPressed: () => unawaited(onClear()),
              child: Text(
                'Clear',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _MeColors.destructiveFor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _MeColors.greenSoftFor(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.bell,
                color: _MeColors.green,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No notifications on this device yet.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _MeColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Safety, circle, chat, and hike reminders appear here after this phone receives them.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _MeColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              minimumSize: Size.zero,
              onPressed: () => unawaited(onRefresh()),
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceNotificationTile extends StatelessWidget {
  const _DeviceNotificationTile({
    required this.notification,
    required this.onTap,
    required this.onStar,
    required this.onDelete,
  });

  final DeviceNotificationRecord notification;
  final Future<void> Function(DeviceNotificationRecord notification) onTap;
  final Future<void> Function(DeviceNotificationRecord notification) onStar;
  final Future<void> Function(DeviceNotificationRecord notification) onDelete;

  @override
  Widget build(BuildContext context) {
    final title = notification.title.trim().isEmpty
        ? 'HikerCircle update'
        : notification.title.trim();
    final body = notification.body.trim().isEmpty
        ? 'Tap to view details.'
        : notification.body.trim();
    final type = notification.type.trim();
    final hasDeepLink = notification.deepLink.trim().isNotEmpty;
    return _TapSurface(
      onTap: () => unawaited(onTap(notification)),
      child: _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIcon(type: type, isOpened: notification.isOpened),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: notification.isOpened
                            ? _MeColors.secondaryTextFor(context)
                            : _MeColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniPill(label: _notificationTypeLabel(type)),
                        _MiniPill(
                          label: _notificationTimeLabel(
                            notification.receivedAt,
                          ),
                        ),
                        if (hasDeepLink) const _MiniPill(label: 'Opens in app'),
                        if (notification.isOpened)
                          const _MiniPill(label: 'Opened'),
                        if (notification.isStarred)
                          const _MiniPill(label: 'Starred'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  IconButton(
                    tooltip: notification.isStarred ? 'Unstar' : 'Keep',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(onStar(notification)),
                    icon: Icon(
                      notification.isStarred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: notification.isStarred
                          ? const Color(0xFFF5A623)
                          : _MeColors.secondaryTextFor(context),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(onDelete(notification)),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: _MeColors.destructiveFor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type, required this.isOpened});

  final String type;
  final bool isOpened;

  @override
  Widget build(BuildContext context) {
    final color = isOpened
        ? _MeColors.secondaryTextFor(context)
        : _notificationAccentColor(type);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _MeColors.isDark(context) ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_notificationIcon(type), color: color, size: 20),
    );
  }
}

IconData _notificationIcon(String type) {
  final normalizedType = type.toLowerCase();
  if (normalizedType.contains('chat')) {
    return CupertinoIcons.chat_bubble_2_fill;
  }
  if (normalizedType.contains('team') || normalizedType.contains('hike')) {
    return Icons.hiking_rounded;
  }
  if (normalizedType.contains('friend') ||
      normalizedType.contains('buddy') ||
      normalizedType.contains('circle')) {
    return Icons.group_rounded;
  }
  if (normalizedType.contains('sos') ||
      normalizedType.contains('alert') ||
      normalizedType.contains('safety')) {
    return Icons.health_and_safety_rounded;
  }
  if (normalizedType.contains('upcoming') ||
      normalizedType.contains('reminder')) {
    return CupertinoIcons.clock_fill;
  }
  return CupertinoIcons.bell_fill;
}

Color _notificationAccentColor(String type) {
  final normalizedType = type.toLowerCase();
  if (normalizedType.contains('sos') ||
      normalizedType.contains('alert') ||
      normalizedType.contains('safety')) {
    return const Color(0xFFE44848);
  }
  if (normalizedType.contains('chat')) {
    return const Color(0xFF3478F6);
  }
  if (normalizedType.contains('friend') ||
      normalizedType.contains('buddy') ||
      normalizedType.contains('circle')) {
    return const Color(0xFF7A5AF8);
  }
  return _MeColors.green;
}

String _notificationTypeLabel(String type) {
  final normalizedType = type.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (normalizedType.isEmpty) {
    return 'Notification';
  }
  return normalizedType
      .split(' ')
      .where((word) => word.trim().isNotEmpty)
      .map((word) {
        final trimmed = word.trim();
        return trimmed.length == 1
            ? trimmed.toUpperCase()
            : '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
      })
      .join(' ');
}

String _notificationTimeLabel(DateTime receivedAt) {
  final localTime = receivedAt.toLocal();
  final difference = DateTime.now().difference(localTime);
  if (difference.inMinutes < 1) {
    return 'Just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }
  final hour = localTime.hour % 12 == 0 ? 12 : localTime.hour % 12;
  final minute = localTime.minute.toString().padLeft(2, '0');
  final period = localTime.hour >= 12 ? 'PM' : 'AM';
  return '${localTime.day}/${localTime.month} $hour:$minute$period';
}

class _AdvancedAppSettingsPage extends StatefulWidget {
  const _AdvancedAppSettingsPage({
    required this.session,
    required this.firebaseRepository,
    required this.onOpenTrail,
    required this.onNavigate,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository firebaseRepository;
  final Future<void> Function(String trailId) onOpenTrail;
  final void Function(String destinationId) onNavigate;

  @override
  State<_AdvancedAppSettingsPage> createState() =>
      _AdvancedAppSettingsPageState();
}

class _AdvancedAppSettingsPageState extends State<_AdvancedAppSettingsPage> {
  final AppSettingsController _settings = AppSettingsController.instance;
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  bool _isLoadingTimeZone = true;
  bool _isSavingTimeZone = false;
  String _timeZoneStatus = 'Loading your saved SOS timezone…';
  Future<void> _setPrivateUnlock(bool enabled) async {
    try {
      if (enabled && !await PrivateScreenUnlock.available()) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enroll biometrics in your phone settings before enabling private-screen unlock.',
              ),
            ),
          );
        return;
      }
      if (!await PrivateScreenUnlock.authenticate() || !mounted) return;
      _settings.setPrivateScreenUnlockEnabled(enabled);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometric verification is unavailable on this device.',
            ),
          ),
        );
    }
  }

  Future<void> _changePassword() async {
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecentSecurityVerificationPage(
          phoneNumber: widget.session.phoneNumber,
        ),
      ),
    );
    if (verified == true && mounted)
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
      );
  }

  @override
  void initState() {
    super.initState();
    _settings.addListener(_handleSettingsChanged);
    unawaited(_loadPreferredTimeZone());
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPreferredTimeZone() async {
    try {
      final saved = await widget.firebaseRepository.loadPreferredTimeZone(
        session: widget.session,
      );
      if (saved != null) {
        _settings.setPreferredTimeZone(saved);
      } else {
        await widget.firebaseRepository.savePreferredTimeZone(
          session: widget.session,
          preferredTimeZone: _settings.preferredTimeZone,
        );
      }
      if (!mounted) return;
      setState(() {
        _timeZoneStatus = 'Synced with Firebase for outgoing SOS messages.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _timeZoneStatus =
            'Could not reach Firebase. SOS messages fall back to GMT+8.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTimeZone = false;
        });
      }
    }
  }

  Future<void> _choosePreferredTimeZone() async {
    if (_isLoadingTimeZone || _isSavingTimeZone) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: _MeColors.surfaceFor(context),
      builder: (context) =>
          _TimeZonePickerSheet(selectedTimeZone: _settings.preferredTimeZone),
    );
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
      await widget.firebaseRepository.savePreferredTimeZone(
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

  Future<void> _setPreciseLocation(bool enabled) async {
    if (!enabled) {
      final confirmed = await showCupertinoDialog<bool>(
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
                    title: 'App Settings',
                    subtitle: 'Advanced preferences and device controls',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: 'HikerCircle Assistant'),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    color: _MeColors.surfaceFor(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: _MeColors.separatorFor(context)),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _MeColors.greenSoftFor(context),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: _MeColors.green,
                        ),
                      ),
                      title: const Text('Ask HikerCircle'),
                      subtitle: const Text(
                        'Quick answers from reviewed app guides',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => HikerCircleAssistantPage(
                            ownerPhoneNumber: widget.session.phoneNumber,
                            onOpenTrail: widget.onOpenTrail,
                            onNavigate: widget.onNavigate,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Account Security'),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    color: _MeColors.surfaceFor(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: _MeColors.separatorFor(context)),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.security_rounded,
                        color: _MeColors.green,
                      ),
                      title: const Text('Login security'),
                      subtitle: const Text('Manage Authenticator and passkeys'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => const SecurityMethodsPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile.adaptive(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Private-screen unlock'),
                    subtitle: const Text(
                      'Require biometrics when opening the app after it was closed. Skipped during an active hike.',
                    ),
                    value: _settings.privateScreenUnlockEnabled,
                    onChanged: _setPrivateUnlock,
                  ),
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password'),
                    subtitle: const Text(
                      'Verify your identity before changing your password',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePassword,
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Language'),
                  const SizedBox(height: 8),
                  _ChoiceSettingCard(
                    icon: Icons.language_rounded,
                    title: 'App language',
                    value: _settings.language,
                    options: const ['English'],
                    onSelected: _settings.setLanguage,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Additional languages will appear after their translations are available.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Safety & Region'),
                  const SizedBox(height: 8),
                  _TimeZoneSettingCard(
                    value: PreferredTimeZone.compactLabel(
                      _settings.preferredTimeZone,
                    ),
                    timeZoneId: _settings.preferredTimeZone,
                    status: _timeZoneStatus,
                    isBusy: _isLoadingTimeZone || _isSavingTimeZone,
                    onTap: () => unawaited(_choosePreferredTimeZone()),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Appearance & Theme'),
                  const SizedBox(height: 8),
                  _ChoiceSettingCard(
                    icon: Icons.palette_rounded,
                    title: 'Theme mode',
                    value: _settings.themeSetting.label,
                    options: HikerCircleThemeSetting.values
                        .map((setting) => setting.label)
                        .toList(),
                    onSelected: (value) => _settings.setThemeSetting(
                      HikerCircleThemeSetting.fromLabel(value),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Permissions'),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.location_on_rounded,
                    title: 'Precise location for hikes and SOS',
                    subtitle:
                        'Used for route tracking and emergency map links.',
                    value: _settings.preciseLocationEnabled,
                    onChanged: (value) => unawaited(_setPreciseLocation(value)),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Trail Recommendations'),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.insights_rounded,
                    title:
                        'Allow HikerCircle to collect and use my trail data as anonymous',
                    subtitle:
                        'Allows HikerCircle to use your trail pathway anonymously as recommendations for other hikers and reduce map-based outliers.',
                    value: _settings.anonymousTrailRecommendationsEnabled,
                    onChanged:
                        _settings.setAnonymousTrailRecommendationsEnabled,
                  ),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.vibration_rounded,
                    title: 'Haptic safety feedback',
                    subtitle:
                        'Use short vibrations for check-ins, pins, and SOS countdown actions.',
                    value: _settings.hapticSafetyFeedbackEnabled,
                    onChanged: _settings.setHapticSafetyFeedbackEnabled,
                  ),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.battery_alert_rounded,
                    title: 'Low battery safety warnings',
                    subtitle:
                        'Warn before a hike when battery may be too low for safe tracking.',
                    value: _settings.lowBatterySafetyWarningEnabled,
                    onChanged: _settings.setLowBatterySafetyWarningEnabled,
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

class _StatsGroup extends StatelessWidget {
  const _StatsGroup({required this.stats, required this.onTap});

  final List<MeStat> stats;
  final ValueChanged<MeStat> onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < stats.length; index++) ...[
              Expanded(
                child: _StatCell(
                  stat: stats[index],
                  onTap: () => onTap(stats[index]),
                ),
              ),
              if (index != stats.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _AchievementsSummaryCard extends StatelessWidget {
  const _AchievementsSummaryCard({
    required this.achievementsFuture,
    required this.onTap,
  });

  final Future<List<Map<String, dynamic>>> achievementsFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: achievementsFuture,
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final items = _achievementItemsFromRows(snapshot.data ?? const []);
        final unlocked = items.where((item) => item.isUnlocked).length;
        final total = items.isEmpty ? 0 : items.length;
        final progress = total == 0 ? 0.0 : unlocked / total;
        final points = items
            .where((item) => item.isUnlocked)
            .fold<int>(0, (total, item) => total + item.pointsAwarded);
        final level = HikerLevel.fromPoints(points);
        final locked = items.where((item) => !item.isUnlocked).toList();
        final subtitle = isLoading
            ? 'Your hiking milestones'
            : locked.isEmpty && total > 0
            ? 'All current badges unlocked'
            : locked.isEmpty
            ? 'Track your hike milestones'
            : 'Next: ${locked.first.title}';

        return _InsetGroup(
          child: _TapSurface(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: FittedBox(
                      child: _AchievementLevelMedallion(
                        level: level.number,
                        onTap: () => _showHikerLevelRoadmap(context, points),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Achievements',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: _MeColors.textFor(context),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          total == 0
                              ? subtitle
                              : '$unlocked of $total unlocked - $subtitle',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _MeColors.secondaryTextFor(context),
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: _MeColors.greenSoftFor(context),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _MeColors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    color: _MeColors.chevronFor(context),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _AchievementStatusTab { earned, locked }

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({
    super.key,
    required this.session,
    required this.repository,
    required this.firebaseBootstrapResult,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  late Future<List<Map<String, dynamic>>> _achievementsFuture;
  _AchievementStatusTab _achievementTab = _AchievementStatusTab.locked;

  @override
  void initState() {
    super.initState();
    _achievementsFuture = _loadAchievementsCacheFirst();
  }

  Future<List<Map<String, dynamic>>> _loadAchievementsCacheFirst() async {
    final cached = await widget.repository.loadCachedAchievementProgress(
      session: widget.session,
    );
    if (cached != null) {
      unawaited(_revalidateAchievementCache(cached.contentHash));
      return cached.rows;
    }

    final rows = await widget.repository.loadUserAchievementProgress(
      session: widget.session,
    );
    if (rows.isNotEmpty) unawaited(_cacheFreshAchievementRows(rows));
    return rows;
  }

  Future<void> _cacheFreshAchievementRows(
    List<Map<String, dynamic>> rows,
  ) async {
    await widget.repository.saveCachedAchievementProgress(
      session: widget.session,
      contentHash: achievementProgressContentHash(rows),
      rows: rows,
    );
  }

  Future<void> _revalidateAchievementCache(String cachedHash) async {
    final remoteHash = await widget.repository.loadAchievementProgressHash(
      session: widget.session,
    );
    if (remoteHash.isEmpty || remoteHash == cachedHash) return;
    final rows = await widget.repository.loadUserAchievementProgress(
      session: widget.session,
    );
    if (rows.isEmpty) return;
    await _cacheFreshAchievementRows(rows);
    if (!mounted) return;
    setState(() {
      _achievementsFuture = Future.value(rows);
    });
  }

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
                );
                final earned = achievements
                    .where((item) => item.isUnlocked)
                    .toList();
                final locked = achievements
                    .where((item) => !item.isUnlocked)
                    .toList();
                final visibleAchievements =
                    _achievementTab == _AchievementStatusTab.earned
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
                              _AchievementProgressPanel(items: achievements),
                              const SizedBox(height: 18),
                              _AchievementStatusTabs(
                                selected: _achievementTab,
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
                                  title:
                                      _achievementTab ==
                                          _AchievementStatusTab.earned
                                      ? 'No badges unlocked yet'
                                      : 'Every badge is unlocked',
                                  message:
                                      _achievementTab ==
                                          _AchievementStatusTab.earned
                                      ? 'Open Locked to choose your next hiking goal.'
                                      : 'Keep hiking to build your rank and help the community.',
                                )
                              else
                                _AchievementCollectionGrid(
                                  items: visibleAchievements,
                                  onTap: _showAchievementDetail,
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

  void _openLeaderboard() {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) =>
            _AchievementLeaderboardPage(repository: widget.repository),
      ),
    );
  }

  void _showAchievementDetail(_AchievementProfileItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AchievementDetailSheet(item: item),
    );
  }
}

class _AchievementPageHeader extends StatelessWidget {
  const _AchievementPageHeader({
    required this.onBack,
    required this.onLeaderboard,
  });

  final VoidCallback onBack;
  final VoidCallback onLeaderboard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AchievementHeaderButton(
          tooltip: 'Back',
          icon: CupertinoIcons.chevron_back,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Achievements',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PageHeaderStyle.title(
                  context,
                  _MeColors.textFor(context),
                ),
              ),
              Text(
                'Collect milestones from every adventure',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PageHeaderStyle.subtitle(
                  context,
                  _MeColors.secondaryTextFor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _AchievementHeaderButton(
          key: const Key('achievement-leaderboard-button'),
          tooltip: 'Open leaderboard',
          icon: CupertinoIcons.chart_bar_alt_fill,
          onPressed: onLeaderboard,
        ),
      ],
    );
  }
}

class _AchievementHeaderButton extends StatelessWidget {
  const _AchievementHeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PageHeaderAction(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    color: _MeColors.green,
    surface: _MeColors.surfaceFor(context),
  );
}

class _AchievementLeaderboardPage extends StatefulWidget {
  const _AchievementLeaderboardPage({required this.repository});

  final HikerCircleFirebaseRepository repository;

  @override
  State<_AchievementLeaderboardPage> createState() =>
      _AchievementLeaderboardPageState();
}

class _AchievementLeaderboardPageState
    extends State<_AchievementLeaderboardPage> {
  String _period = 'month';
  List<Map<String, dynamic>>? _previewEntries;
  DateTime? _lastTitleTap;
  int _titleTaps = 0;
  late Future<List<Map<String, dynamic>>> _entriesFuture;

  void _tapTitle() {
    final now = DateTime.now();
    _titleTaps =
        _lastTitleTap != null &&
            now.difference(_lastTitleTap!).inMilliseconds < 600
        ? _titleTaps + 1
        : 1;
    _lastTitleTap = now;
    if (_titleTaps < 3) return;
    _titleTaps = 0;
    setState(() {
      _previewEntries = List.generate(
        50,
        (index) => <String, dynamic>{
          'rank': index + 1,
          'displayName': index == 36
              ? 'You'
              : '${['Aiman', 'Mei', 'Arun', 'Sofia', 'Daniel', 'Nur', 'Kai', 'Priya', 'Amir', 'Lina'][index % 10]} ${index ~/ 10 + 1}',
          'points': (50 - index) * 85 + 20,
          'isCurrentUser': index == 36,
        },
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.repository.loadAchievementLeaderboard();
  }

  void _selectPeriod(String period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      if (_previewEntries != null) return;
      _entriesFuture = widget.repository.loadAchievementLeaderboard(
        period: period,
      );
    });
  }

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
                                _entriesFuture = widget.repository
                                    .loadAchievementLeaderboard(
                                      period: _period,
                                    );
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
}

class _AchievementStatusTabs extends StatelessWidget {
  const _AchievementStatusTabs({
    required this.selected,
    required this.earnedCount,
    required this.lockedCount,
    required this.onSelected,
  });

  final _AchievementStatusTab selected;
  final int earnedCount;
  final int lockedCount;
  final ValueChanged<_AchievementStatusTab> onSelected;

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
          final earnedIsLeading = isLtr;
          final selectedIsLeading = selected == _AchievementStatusTab.earned
              ? earnedIsLeading
              : !earnedIsLeading;

          void selectFromDrag(DragUpdateDetails details) {
            final isLeadingHalf = isLtr
                ? details.localPosition.dx < constraints.maxWidth / 2
                : details.localPosition.dx >= constraints.maxWidth / 2;
            final next = isLeadingHalf
                ? _AchievementStatusTab.earned
                : _AchievementStatusTab.locked;
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
                  alignment: selectedIsLeading
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
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

class _AchievementTabLabel extends StatelessWidget {
  const _AchievementTabLabel({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? Colors.white
                  : _MeColors.secondaryTextFor(context),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementPeriodButton extends StatelessWidget {
  const _AchievementPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _MeColors.green.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _MeColors.green.withValues(alpha: 0.38)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected
                  ? (_MeColors.isDark(context)
                        ? const Color(0xFF8CE7A8)
                        : const Color(0xFF16743A))
                  : _MeColors.secondaryTextFor(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementLeaderboardCard extends StatelessWidget {
  const _AchievementLeaderboardCard({
    required this.period,
    required this.entries,
    required this.isLoading,
    required this.onPeriodChanged,
    required this.onTitleTap,
    required this.onExitPreview,
    required this.isPreview,
  });

  final String period;
  final List<Map<String, dynamic>> entries;
  final bool isLoading;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onTitleTap;
  final VoidCallback onExitPreview;
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    return _AchievementGlassSurface(
      blur: true,
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _AchievementSectionGlyph(icon: Icons.leaderboard_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onTitleTap,
                      child: Text(
                        'Hiker leaderboard',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _MeColors.textFor(context),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    Text(
                      'Points earned during the selected period',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isPreview)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Preview · 50 sample hikers'),
              subtitle: const Text('Temporary data for this visit only'),
              trailing: TextButton(
                onPressed: onExitPreview,
                child: const Text('Exit'),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _MeColors.backgroundFor(context).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                _AchievementPeriodButton(
                  label: 'This month',
                  selected: period == 'month',
                  onTap: () => onPeriodChanged('month'),
                ),
                _AchievementPeriodButton(
                  label: 'This year',
                  selected: period == 'year',
                  onTap: () => onPeriodChanged('year'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(child: HikerCircleMinorLoadingIndicator(size: 72))
          else if (entries.isEmpty)
            Text(
              'No achievement points have been earned in this period yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _MeColors.secondaryTextFor(context)),
            )
          else ...[
            _AchievementPodium(entries: entries.take(3).toList()),
            const SizedBox(height: 20),
            Text('Top 10', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final entry in entries.take(10)) ...[
              _AchievementLeaderboardRow(
                rank: entry['rank'],
                displayName: entry['displayName']?.toString() ?? 'Hiker',
                points: entry['points'],
                isCurrentUser: entry['isCurrentUser'] == true,
                margin: const EdgeInsets.only(bottom: 7),
              ),
            ],
            for (final entry in entries.where(
              (entry) =>
                  entry['isCurrentUser'] == true &&
                  (int.tryParse('${entry['rank']}') ?? 0) > 10,
            )) ...[
              const Divider(height: 28),
              Text(
                'Your ranking',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _AchievementLeaderboardRow(
                rank: entry['rank'],
                displayName: entry['displayName']?.toString() ?? 'You',
                points: entry['points'],
                isCurrentUser: true,
                margin: EdgeInsets.zero,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AchievementPodium extends StatelessWidget {
  const _AchievementPodium({required this.entries});
  final List<Map<String, dynamic>> entries;

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

class _AchievementLeaderboardRow extends StatelessWidget {
  const _AchievementLeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.points,
    required this.isCurrentUser,
    required this.margin,
  });

  final Object? rank;
  final String displayName;
  final Object? points;
  final bool isCurrentUser;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final rankNumber = int.tryParse('$rank');
    final medalColor = switch (rankNumber) {
      1 => const Color(0xFFFFC857),
      2 => const Color(0xFFB9C2CE),
      3 => const Color(0xFFC98955),
      _ => _MeColors.secondaryTextFor(context),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _MeColors.green.withValues(alpha: 0.14)
            : Colors.white.withValues(
                alpha: _MeColors.isDark(context) ? 0.035 : 0.48,
              ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isCurrentUser
              ? _MeColors.green.withValues(alpha: 0.32)
              : Colors.white.withValues(
                  alpha: _MeColors.isDark(context) ? 0.07 : 0.7,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: medalColor.withValues(alpha: 0.16),
            ),
            child: Text(
              '${rankNumber ?? '-'}',
              style: TextStyle(
                color: medalColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _MeColors.textFor(context),
                fontWeight: isCurrentUser ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const _AchievementTag(label: 'You', compact: true),
            const SizedBox(width: 8),
          ],
          Text(
            '${points ?? 0} pts',
            style: const TextStyle(
              color: _MeColors.green,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementProgressPanel extends StatelessWidget {
  const _AchievementProgressPanel({required this.items});

  final List<_AchievementProfileItem> items;

  @override
  Widget build(BuildContext context) {
    final earned = items.where((item) => item.isUnlocked).toList();
    final locked = items.length - earned.length;
    final points = earned.fold<int>(
      0,
      (total, item) => total + item.pointsAwarded,
    );
    final level = HikerLevel.fromPoints(points);
    final nextLevelName = level.nextLevelPoints == null
        ? 'Peak rank reached'
        : HikerLevel.tiers[level.number].name;
    final remaining = level.pointsToNextLevel(points);
    return _AchievementGlassSurface(
      blur: true,
      radius: 30,
      padding: EdgeInsets.zero,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xEE0B3323), Color(0xE61A6A40), Color(0xDC37A95C)],
        stops: [0, 0.55, 1],
      ),
      borderColor: Colors.white24,
      shadowColor: const Color(0xFF249A51).withValues(alpha: 0.3),
      child: Stack(
        children: [
          const Positioned(
            right: -35,
            top: -45,
            child: _AchievementHeroOrb(size: 170),
          ),
          Positioned(
            left: -50,
            bottom: -80,
            child: _AchievementHeroOrb(
              size: 190,
              color: const Color(0xFFFFD166).withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'YOUR TRAIL JOURNEY',
                  style: TextStyle(
                    color: Color(0xFFC8F3D6),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.9,
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    _AchievementLevelMedallion(
                      level: level.number,
                      onTap: () => _showHikerLevelRoadmap(context, points),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            level.nextLevelPoints == null
                                ? 'You have reached the highest trail rank'
                                : '$remaining points until $nextLevelName',
                            style: const TextStyle(
                              color: Color(0xFFD9F4E2),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Row(
                            children: [
                              Text(
                                'Tap badge to view all levels',
                                style: TextStyle(
                                  color: Color(0xFFB8EDC9),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(
                                CupertinoIcons.chevron_forward,
                                color: Color(0xFFB8EDC9),
                                size: 10,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      level.nextLevelPoints == null
                          ? 'Peak achieved'
                          : 'Progress to $nextLevelName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      level.nextLevelPoints == null
                          ? '$points pts'
                          : '$points / ${level.nextLevelPoints}',
                      style: const TextStyle(
                        color: Color(0xFFFFE297),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06170E).withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: level.progressFor(points),
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFD166),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Earned',
                        value: '${earned.length}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.lock_outline_rounded,
                        label: 'Locked',
                        value: '$locked',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AchievementMetric(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Points',
                        value: '$points',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementHeroOrb extends StatelessWidget {
  const _AchievementHeroOrb({required this.size, this.color});

  final double size;
  final Color? color;

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

class _AchievementLevelMedallion extends StatelessWidget {
  const _AchievementLevelMedallion({required this.level, required this.onTap});

  final int level;
  final VoidCallback onTap;

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

void _showHikerLevelRoadmap(BuildContext context, int points) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _HikerLevelRoadmapSheet(points: points),
  );
}

class _HikerLevelRoadmapSheet extends StatefulWidget {
  const _HikerLevelRoadmapSheet({required this.points});
  final int points;

  @override
  State<_HikerLevelRoadmapSheet> createState() =>
      _HikerLevelRoadmapSheetState();
}

class _HikerLevelRoadmapSheetState extends State<_HikerLevelRoadmapSheet> {
  late int _selected = HikerLevel.fromPoints(widget.points).number;
  late final PageController _levelController = PageController(
    initialPage: _selected - 1,
    viewportFraction: 0.9,
  );

  @override
  void dispose() {
    _levelController.dispose();
    super.dispose();
  }

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

class _HikerLevelRoadmapRow extends StatelessWidget {
  const _HikerLevelRoadmapRow({
    required this.level,
    required this.currentLevel,
    required this.points,
    required this.selected,
    required this.onTap,
  });
  final HikerLevel level;
  final HikerLevel currentLevel;
  final int points;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = [
    CupertinoIcons.leaf_arrow_circlepath,
    CupertinoIcons.compass,
    Icons.hiking_rounded,
    Icons.landscape_rounded,
    CupertinoIcons.map,
    CupertinoIcons.shield,
    CupertinoIcons.rosette,
  ];
  static const _descriptions = [
    'Every journey starts here. Discover the badges you can earn on your first hikes.',
    'Build your hiking rhythm and turn your early adventures into lasting progress.',
    'Keep exploring trails and completing achievement goals as your experience grows.',
    'Celebrate the milestones collected along your journey toward new summits.',
    'Bring together the points earned through exploration, consistency, and community.',
    'Acknowledge a sustained commitment to hiking and the milestones along the way.',
    'The highest hiker rank celebrates your accumulated achievement points.',
  ];

  @override
  Widget build(BuildContext context) {
    final reached = points >= level.minimumPoints;
    final isCurrent = level.number == currentLevel.number;
    final range = level.nextLevelPoints == null
        ? '${_formatRankPoints(level.minimumPoints)}+ points'
        : '${_formatRankPoints(level.minimumPoints)}–${_formatRankPoints(level.nextLevelPoints! - 1)} points';
    final foreground = _MeColors.textFor(context);
    final secondary = _MeColors.secondaryTextFor(context);
    return AnimatedContainer(
      key: ValueKey('hiker-level-card-${level.number}'),
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? _MeColors.green.withValues(alpha: 0.07)
            : _MeColors.backgroundFor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? _MeColors.green.withValues(alpha: 0.5)
              : _MeColors.separatorFor(context),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                key: ValueKey('trail-level-${level.number}'),
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _MeColors.green.withValues(
                            alpha: reached ? 0.14 : 0.06,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          _icons[level.number - 1],
                          color: reached ? _MeColors.green : secondary,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level ${level.number} · ${level.name}',
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              range,
                              style: TextStyle(color: secondary, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isCurrent
                                  ? 'Current level'
                                  : reached
                                  ? 'Completed'
                                  : 'Locked',
                              style: TextStyle(
                                color: reached ? _MeColors.green : secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        reached
                            ? Icons.check_circle_outline_rounded
                            : Icons.lock_outline_rounded,
                        size: 15,
                        color: secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(
                            color: _MeColors.separatorFor(context),
                            height: 16,
                          ),
                          Text(
                            _descriptions[level.number - 1],
                            style: TextStyle(color: secondary, height: 1.5),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Unlocks at ${_formatRankPoints(level.minimumPoints)} points',
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            reached
                                ? 'You have reached this milestone.'
                                : '${_formatRankPoints(level.minimumPoints - points)} more points to unlock',
                            style: TextStyle(color: secondary),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: level.minimumPoints == 0
                                  ? 1
                                  : (points / level.minimumPoints).clamp(
                                      0.0,
                                      1.0,
                                    ),
                              minHeight: 5,
                              color: _MeColors.green,
                              backgroundColor: _MeColors.green.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Earn points by completing the goals listed on achievement badges.',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRankPoints(int points) {
  final normalized = points < 0 ? 0 : points;
  if (normalized < 1000) return '$normalized';
  final thousands = normalized ~/ 1000;
  final remainder = (normalized % 1000).toString().padLeft(3, '0');
  return '$thousands,$remainder';
}

class _AchievementMetric extends StatelessWidget {
  const _AchievementMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFB8EDC9), size: 17),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFFC8F3D6),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCollectionGrid extends StatelessWidget {
  const _AchievementCollectionGrid({required this.items, required this.onTap});

  final List<_AchievementProfileItem> items;
  final ValueChanged<_AchievementProfileItem> onTap;

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
            mainAxisExtent: 236,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _AchievementBadgeCard(item: item, onTap: () => onTap(item));
          },
        );
      },
    );
  }
}

class _AchievementBadgeCard extends StatelessWidget {
  const _AchievementBadgeCard({required this.item, required this.onTap});

  final _AchievementProfileItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = item.accentColor;
    final displayAccent = item.isUnlocked
        ? accent
        : Color.lerp(accent, _MeColors.secondaryTextFor(context), 0.48)!;
    final remaining = (item.targetCount - item.progressCount).clamp(
      0,
      item.targetCount,
    );

    return _AchievementGlassSurface(
      radius: 25,
      padding: EdgeInsets.zero,
      accent: displayAccent,
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _AchievementTag(
                        label: item.category.toUpperCase(),
                        accent: displayAccent,
                        compact: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    item.isUnlocked
                        ? CupertinoIcons.checkmark_seal_fill
                        : CupertinoIcons.lock_fill,
                    color: displayAccent,
                    size: 17,
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: _AchievementBadge(
                  icon: _achievementIconFor(item.iconName),
                  color: displayAccent,
                  unlocked: item.isUnlocked,
                  size: 76,
                ),
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  height: 1.13,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 9),
              if (item.isCumulative && !item.isUnlocked) ...[
                Container(
                  height: 7,
                  padding: const EdgeInsets.all(1.2),
                  decoration: BoxDecoration(
                    color: displayAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(displayAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$remaining left',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      '${item.progressCount}/${item.targetCount}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: displayAccent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  item.isUnlocked
                      ? (item.awardedAt == null
                            ? 'Earned · ${item.pointsAwarded} pts'
                            : '${_formatAchievementDate(item.awardedAt!)} · ${item.pointsAwarded} pts')
                      : 'One hike · ${item.rewardPoints} pts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: displayAccent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementTag extends StatelessWidget {
  const _AchievementTag({
    required this.label,
    this.accent,
    this.compact = false,
  });

  final String label;
  final Color? accent;
  final bool compact;

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

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.icon,
    required this.color,
    required this.unlocked,
    this.size = 62,
    this.showShadow = true,
  });

  final IconData icon;
  final Color color;
  final bool unlocked;
  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: unlocked ? 0.95 : 0.5),
            color.withValues(alpha: 0.15),
          ],
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: unlocked ? 0.28 : 0.1),
                  blurRadius: 17,
                  offset: const Offset(0, 7),
                ),
              ]
            : const [],
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _MeColors.surfaceFor(context).withValues(alpha: 0.88),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: color, size: size * 0.43),
            if (!unlocked)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _MeColors.surfaceFor(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                  ),
                  child: Icon(Icons.lock_rounded, color: color, size: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AchievementDetailSheet extends StatelessWidget {
  const _AchievementDetailSheet({required this.item});

  final _AchievementProfileItem item;

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
                              label: item.isUnlocked
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
                                'Earn $displayPoints trail-rank points when this badge unlocks. Each achievement awards its points once and contributes to your Trail Journey level.',
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

class _AchievementDetailProgress extends StatelessWidget {
  const _AchievementDetailProgress({required this.item});

  final _AchievementProfileItem item;

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
          Row(
            children: [
              Text(
                item.isUnlocked ? 'Completed' : 'Current progress',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _MeColors.textFor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Text(
                '${item.progressCount} / ${item.targetCount}',
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
                  : '$remaining remaining before this badge unlocks.',
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

class _AchievementDetailSection extends StatelessWidget {
  const _AchievementDetailSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded:
          title == 'Your goal' || title == 'Why this achievement exists',
      maintainState: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      shape: Border(bottom: BorderSide(color: _MeColors.separatorFor(context))),
      collapsedShape: Border(
        bottom: BorderSide(color: _MeColors.separatorFor(context)),
      ),
      leading: Icon(icon, color: accent, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            body,
            style: TextStyle(
              color: _MeColors.secondaryTextFor(context),
              height: 1.5,
            ),
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              footer!,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

class _AchievementGuidance {
  const _AchievementGuidance({
    required this.whyItMatters,
    required this.whatCounts,
  });

  final String whyItMatters;
  final String whatCounts;

  String goalProgress(_AchievementProfileItem item) {
    if (!item.isCumulative) {
      return 'Complete this action once to unlock the badge.';
    }
    final remaining = (item.targetCount - item.progressCount).clamp(
      0,
      item.targetCount,
    );
    return '$remaining of ${item.targetCount} qualifying activities remain.';
  }

  factory _AchievementGuidance.forItem(_AchievementProfileItem item) {
    final category = item.category.toLowerCase();
    final whyItMatters = switch (category) {
      'hike milestone' =>
        'Regular time on trail builds experience, confidence, and better judgement. This badge recognises the consistency behind becoming a capable hiker.',
      'trail exploration' =>
        'Trying different trails develops navigation skills and exposes you to new terrain instead of repeating only familiar routes.',
      'malaysia exploration' =>
        'Malaysia’s states offer distinct landscapes, climates, and trail communities. This achievement encourages responsible exploration across the country.',
      'safety habit' =>
        'Reliable check-ins keep your trusted contacts informed and make it easier to notice quickly when a hike is not going to plan.',
      'account security' =>
        'Strong account protection helps keep your identity, hike history, emergency contacts, and live-location permissions under your control.',
      'community safety' =>
        'Confirmed hazard reports give other hikers timely information that can help them prepare, reroute, or avoid preventable danger.',
      'community' =>
        'Useful trail stories and verified observations help other hikers plan with more confidence and strengthen the hiking community.',
      'team hike' =>
        'Safe group hiking depends on staying together, communicating clearly, and completing the route without a separation emergency.',
      'preparation' =>
        'Good preparation reduces avoidable risk before departure and makes safety tools more dependable when mobile coverage is weak.',
      _ =>
        'This achievement highlights a meaningful habit that supports safer, more confident, and more rewarding hiking.',
    };

    final whatCounts = switch (item.metricKey) {
      'hike_completed' =>
        'Start a hike in HikerCircle and complete it normally. Cancelled or unfinished sessions do not increase this achievement.',
      'distinct_trail_completed' =>
        'Each completed trail counts once. Repeating the same trail can still build other milestones, but it does not add another unique trail here.',
      'malaysia_state_hiked' =>
        'Complete a recorded trail in a new Malaysian state. Multiple trails in the same state count as one state for this badge.',
      'check_in_completed' =>
        'Respond successfully to scheduled safety check-ins during an active hike. Missed or expired check-ins are not counted.',
      'security_factor_type_bound' =>
        'Bind the required different security methods to your account. Only active, successfully configured methods count.',
      'hazard_report_approved' =>
        'Submit an accurate trail hazard report and wait for it to be confirmed by other hikers or moderation.',
      'community_post_created' =>
        'Publish a public trail post through HikerCircle. Drafts and private content are not included.',
      'team_hike_completed' =>
        'Complete a HikerCircle team hike without triggering a separation emergency. Every qualifying team session adds one.',
      'offline_map_verified_at_hike_start' =>
        'Download the trail’s offline map before starting and keep it available when the hike session begins.',
      'full_checklist_verified_at_departure' =>
        'Mark every required gear item complete before starting the hike session.',
      _ => item.condition,
    };

    return _AchievementGuidance(
      whyItMatters: whyItMatters,
      whatCounts: whatCounts,
    );
  }
}

class _AchievementNoticeCard extends StatelessWidget {
  const _AchievementNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _AchievementGlassSurface(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AchievementSectionGlyph(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _MeColors.textFor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _MeColors.secondaryTextFor(context),
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

class _AchievementLoadingCard extends StatelessWidget {
  const _AchievementLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _AchievementGlassSurface(
      radius: 22,
      padding: EdgeInsets.zero,
      child: HikerCircleLoadingView(
        message: 'Loading achievements…',
        detail: 'Checking your progress, levels and unlocked badges.',
        padding: EdgeInsets.all(18),
      ),
    );
  }
}

class _AchievementAmbientBackdrop extends StatelessWidget {
  const _AchievementAmbientBackdrop();

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

class _AchievementAura extends StatelessWidget {
  const _AchievementAura({required this.size, required this.color});

  final double size;
  final Color color;

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

class _AchievementGlassSurface extends StatelessWidget {
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

class _AchievementSectionGlyph extends StatelessWidget {
  const _AchievementSectionGlyph({required this.icon});

  final IconData icon;

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

class _ChoiceSettingCard extends StatelessWidget {
  const _ChoiceSettingCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Glyph(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _MiniPill(label: value),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option),
                    selected: value == option,
                    onSelected: (_) => onSelected(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeZoneSettingCard extends StatelessWidget {
  const _TimeZoneSettingCard({
    required this.value,
    required this.timeZoneId,
    required this.status,
    required this.isBusy,
    required this.onTap,
  });

  final String value;
  final String timeZoneId;
  final String status;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isBusy ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph(icon: Icons.schedule_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOS message timezone',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _MeColors.textFor(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _MeColors.green,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        timeZoneId,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _MeColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isBusy)
                  const SizedBox.square(
                    dimension: 20,
                    child: HikerCircleMinorLoadingIndicator(strokeWidth: 2.2),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _MeColors.chevronFor(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeZonePickerSheet extends StatefulWidget {
  const _TimeZonePickerSheet({required this.selectedTimeZone});

  final String selectedTimeZone;

  @override
  State<_TimeZonePickerSheet> createState() => _TimeZonePickerSheetState();
}

class _TimeZonePickerSheetState extends State<_TimeZonePickerSheet> {
  String _query = '';

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

class _SwitchSettingCard extends StatelessWidget {
  const _SwitchSettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _AnimatedBooleanToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _AnimatedBooleanToggle extends StatelessWidget {
  const _AnimatedBooleanToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedToggleSwitch<bool>.size(
      current: value,
      values: const [false, true],
      height: 38,
      spacing: 2,
      indicatorSize: const Size.square(32),
      borderWidth: 2,
      style: ToggleStyle(
        backgroundColor: _MeColors.greenSoftFor(context),
        borderColor: _MeColors.separatorFor(context),
        borderRadius: BorderRadius.circular(999),
        indicatorBorderRadius: BorderRadius.circular(999),
      ),
      styleBuilder: (enabled) => ToggleStyle(
        indicatorColor: enabled
            ? _MeColors.green
            : _MeColors.destructiveFor(context),
      ),
      iconBuilder: (enabled) => Icon(
        enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled ? _MeColors.green : _MeColors.destructiveFor(context),
        size: 17,
      ),
      foregroundIndicatorIconBuilder: (context, global) {
        final enabled = global.current;
        return Icon(
          enabled ? Icons.check_rounded : Icons.close_rounded,
          color: _MeColors.surfaceFor(context),
          size: 18,
        );
      },
      iconOpacity: 0.72,
      selectedIconOpacity: 0,
      selectedIconScale: 1,
      animationDuration: const Duration(milliseconds: 260),
      animationCurve: Curves.easeOutCubic,
      onChanged: onChanged,
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat, required this.onTap});

  final MeStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _MeColors.textFor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _MeColors.secondaryTextFor(context),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.section,
    required this.onItemTap,
    required this.countForTitle,
  });

  final MeSection section;
  final ValueChanged<MeActionItem> onItemTap;
  final String? Function(String title) countForTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 7),
          child: Text(
            section.title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _MeColors.secondaryTextFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < section.items.length; index++) ...[
                _SettingsCell(
                  item: section.items[index],
                  onTap: () => onItemTap(section.items[index]),
                  countLabel: countForTitle(section.items[index].title),
                ),
                if (index != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCell extends StatelessWidget {
  const _SettingsCell({
    required this.item,
    required this.onTap,
    this.countLabel,
  });

  final MeActionItem item;
  final VoidCallback onTap;
  final String? countLabel;

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

class _SignOutCell extends StatelessWidget {
  const _SignOutCell({required this.onSignOut});

  final VoidCallback onSignOut;

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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _MeColors.secondaryTextFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

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

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _MeColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _MeColors.green,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

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

class _TapSurface extends StatelessWidget {
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap ?? () {}, child: child),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

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

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _MeColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _MeColors.separatorFor(context),
      ),
    );
  }
}

abstract final class _MeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
