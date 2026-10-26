part of '../me_page_feature.dart';

/// Owns the state and non-visual actions of MePage.
class _MePageStateViewModel extends ChangeNotifier {
  /// Creates me page state view model.
  _MePageStateViewModel({required this.readSession});
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late final MeViewModel stateViewModel;

  late final HikerCircleFirebaseRepository stateFirebaseRepository;

  late final OnboardingRepository stateOnboardingRepository;

  late Future<List<Map<String, dynamic>>> stateAchievementsFuture;

  late final EmergencyContactsRepository stateEmergencyContactsRepository;

  List<EmergencyContact> stateEmergencyContacts = const [];

  MeProfile? stateFirestoreProfile;

  List<_ProfileHistoryItem> statePostHistoryItems = const [];

  List<_ProfileHistoryItem> stateCircleHistoryItems = const [];

  List<_ProfileHistoryItem> stateBuddyHistoryItems = const [];

  final List<_ProfileHistoryItem> stateTrailHistoryItems = const [];

  /// Returns command display profile.
  MeProfile get commandDisplayProfile =>
      stateFirestoreProfile ?? stateViewModel.profile;

  /// Loads profile achievements.
  Future<List<Map<String, dynamic>>> commandLoadProfileAchievements() async {
    final cached = await stateFirebaseRepository.loadCachedAchievementProgress(
      session: readSession(),
    );
    if (cached != null) {
      unawaited(commandRefreshProfileAchievements(cached.contentHash));
      return cached.rows;
    }
    final local = await stateFirebaseRepository.loadLocalAchievementProgress(
      session: readSession(),
    );
    unawaited(commandRefreshProfileAchievements(''));
    return local;
  }

  /// Computes reload local profile achievements.
  Future<void> commandReloadLocalProfileAchievements() async {
    final cached = await stateFirebaseRepository.loadCachedAchievementProgress(
      session: readSession(),
    );
    if (mounted && cached != null) {
      _publish(() => stateAchievementsFuture = Future.value(cached.rows));
    }
  }

  /// Fetches profile achievements.
  Future<List<Map<String, dynamic>>> commandFetchProfileAchievements() async {
    final rows = await stateFirebaseRepository.loadUserAchievementProgress(
      session: readSession(),
    );
    await stateFirebaseRepository.saveCachedAchievementProgress(
      session: readSession(),
      contentHash: achievementProgressContentHash(rows),
      rows: rows,
    );
    return rows;
  }

  /// Refreshes profile achievements.
  Future<void> commandRefreshProfileAchievements(String hash) async {
    try {
      final remote = await stateFirebaseRepository.loadAchievementProgressHash(
        session: readSession(),
      );
      if (remote.isEmpty || remote == hash) return;
      final rows = await commandFetchProfileAchievements();
      if (mounted) _publish(() => stateAchievementsFuture = Future.value(rows));
    } catch (_) {
      // Keep the saved summary available when the network is unavailable.
    }
  }

  /// Loads firestore profile.
  Future<void> commandLoadFirestoreProfile() async {
    try {
      final profile = await stateOnboardingRepository.loadProfile(
        readSession(),
      );
      if (!mounted) return;
      final username = profile.username.trim();
      _publish(() {
        stateFirestoreProfile = MeProfile(
          displayName: username.isEmpty
              ? stateViewModel.profile.displayName
              : username,
          handle: username.isEmpty
              ? stateViewModel.profile.handle
              : '@$username',
          phoneNumber: readSession().phoneNumber,
          status: stateViewModel.profile.status,
          photoURL: profile.photoURL ?? stateViewModel.profile.photoURL,
        );
      });
    } catch (_) {
      // Keep the locally cached session profile if Firestore is unavailable.
    }
  }

  /// Loads emergency contacts.
  Future<void> commandLoadEmergencyContacts() async {
    try {
      final contacts = await stateEmergencyContactsRepository
          .loadEmergencyContacts(session: readSession());
      if (!mounted) {
        return;
      }
      _publish(() {
        stateEmergencyContacts = contacts;
      });
    } catch (_) {
      return;
    }
  }

  /// Load posts, group chats and buddy profiles independently from the account's editable profile fields.
  Future<void> commandLoadProfileCollections() async {
    try {
      final results = await Future.wait<Object>([
        stateFirebaseRepository.loadCommunityPostsForUser(
          session: readSession(),
        ),
        stateFirebaseRepository.loadUserGroupChats(readSession().phoneNumber),
        stateFirebaseRepository.loadBuddyPhoneNumbers(session: readSession()),
      ]);
      final ownPhone = readSession().phoneNumber.trim();
      final posts = (results[0] as List<Map<String, dynamic>>)
          .map(
            (post) => _ProfileHistoryItem(
              title: post['trailName']?.toString().trim().isNotEmpty == true
                  ? post['trailName'].toString().trim()
                  : 'Community post',
              subtitle: post['caption']?.toString().trim() ?? '',
              meta: commandProfileHistoryDate(post['createdAtLocal']),
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
                  : 'Hike ended ${commandProfileDateLabel(chat.hikeEndedAt!)}',
              icon: Icons.groups_2_rounded,
            ),
          )
          .toList(growable: false);
      final buddyPhones = results[2] as Set<String>;
      final buddyProfiles = await Future.wait(
        buddyPhones.take(100).map((phone) async {
          try {
            return await stateFirebaseRepository.loadPublicHikerProfile(
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
              title: commandProfileDisplayName(profile),
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
      _publish(() {
        statePostHistoryItems = posts;
        stateCircleHistoryItems = chats;
        stateBuddyHistoryItems = buddies;
      });
    } catch (_) {
      // The sections stay empty while Firebase is unavailable.
    }
  }

  /// Computes profile display name.
  String commandProfileDisplayName(Map<String, dynamic> profile) {
    for (final key in const ['displayName', 'username', 'handle']) {
      final value = profile[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return 'Hiking buddy';
  }

  /// Computes profile history date.
  String commandProfileHistoryDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? 'Recent activity' : commandProfileDateLabel(parsed);
  }

  /// Computes profile date label.
  String commandProfileDateLabel(DateTime date) {
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

  /// Computes count label for action.
  String? commandCountLabelForAction(String title) => switch (title) {
    'My posts' => '${statePostHistoryItems.length}',
    'My circles' => '${stateCircleHistoryItems.length}',
    'My buddies' => '${stateBuddyHistoryItems.length}',
    'Export history' =>
      '${statePostHistoryItems.length + stateCircleHistoryItems.length + stateBuddyHistoryItems.length + stateTrailHistoryItems.length}',
    _ => null,
  };

  /// Computes own handle for phone.
  String commandOwnHandleForPhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length <= 4) {
      return 'hiker$digits';
    }
    return 'hiker${digits.substring(digits.length - 4)}';
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function() effectPresentOpenProfileDetailsEffect1;

  late final Future<List<EmergencyContact>?> Function()
  effectPresentOpenEmergencyContactsEffect1;

  late final Future<void> Function() effectPresentOpenAchievementsEffect1;

  /// Opens emergency contacts.
  Future<void> commandOpenEmergencyContacts() async {
    final contacts = await effectPresentOpenEmergencyContactsEffect1();

    if (contacts == null || !mounted) {
      return;
    }

    _publish(() {
      stateEmergencyContacts = contacts;
    });
  }

  /// Opens achievements.
  Future<void> commandOpenAchievements() async {
    await effectPresentOpenAchievementsEffect1();
    if (!mounted) {
      return;
    }
    _publish(() {
      stateAchievementsFuture = commandLoadProfileAchievements();
    });
  }

  /// Opens profile details.
  Future<void> commandOpenProfileDetails() async {
    await effectPresentOpenProfileDetailsEffect1();
    await commandLoadFirestoreProfile();
  }
}

/// Owns the state and non-visual actions of _AdvancedAppSettingsPage.
class _AdvancedAppSettingsPageStateViewModel extends ChangeNotifier {
  /// Creates advanced app settings page state view model.
  _AdvancedAppSettingsPageStateViewModel({
    required this.readFirebaseRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readFirebaseRepository;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final AppSettingsController stateSettings = AppSettingsController.instance;

  bool stateIsLoadingTimeZone = true;

  String stateTimeZoneStatus = 'Loading your saved SOS timezone…';

  /// Handles settings changed.
  void commandHandleSettingsChanged() {
    if (mounted) {
      _publish(() {});
    }
  }

  /// Loads preferred time zone.
  Future<void> commandLoadPreferredTimeZone() async {
    try {
      final saved = await readFirebaseRepository().loadPreferredTimeZone(
        session: readSession(),
      );
      if (saved != null) {
        stateSettings.setPreferredTimeZone(saved);
      } else {
        await readFirebaseRepository().savePreferredTimeZone(
          session: readSession(),
          preferredTimeZone: stateSettings.preferredTimeZone,
        );
      }
      if (!mounted) return;
      _publish(() {
        stateTimeZoneStatus = 'Synced with Firebase for outgoing SOS messages.';
      });
    } catch (_) {
      if (!mounted) return;
      _publish(() {
        stateTimeZoneStatus =
            'Could not reach Firebase. SOS messages fall back to GMT+8.';
      });
    } finally {
      if (mounted) {
        _publish(() {
          stateIsLoadingTimeZone = false;
        });
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function() effectPresentChangePasswordEffect2;

  late final void Function() effectPresentSetPrivateUnlockEffect2;

  late final Future<bool?> Function() effectPresentChangePasswordEffect1;

  late final void Function() effectPresentSetPrivateUnlockEffect1;

  /// Sets private unlock.
  Future<void> commandSetPrivateUnlock(bool enabled) async {
    try {
      if (enabled && !await PrivateScreenUnlock.available()) {
        if (mounted) {
          effectPresentSetPrivateUnlockEffect1();
        }
        return;
      }
      if (!await PrivateScreenUnlock.authenticate() || !mounted) return;
      stateSettings.setPrivateScreenUnlockEnabled(enabled);
    } catch (_) {
      if (mounted) {
        effectPresentSetPrivateUnlockEffect2();
      }
    }
  }

  /// Computes change password.
  Future<void> commandChangePassword() async {
    final verified = await effectPresentChangePasswordEffect1();
    if (verified == true && mounted) {
      await effectPresentChangePasswordEffect2();
    }
  }
}

/// Owns the state and non-visual actions of AchievementsPage.
class _AchievementsPageStateViewModel extends ChangeNotifier {
  /// Creates achievements page state view model.
  _AchievementsPageStateViewModel({
    required this.readRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  late Future<List<Map<String, dynamic>>> stateAchievementsFuture;

  /// Computes reload local achievements.
  Future<void> commandReloadLocalAchievements() async {
    final cached = await readRepository().loadCachedAchievementProgress(
      session: readSession(),
    );
    if (mounted && cached != null) {
      _publish(() => stateAchievementsFuture = Future.value(cached.rows));
    }
  }

  /// Loads achievements cache first.
  Future<List<Map<String, dynamic>>> commandLoadAchievementsCacheFirst() async {
    final cached = await readRepository().loadCachedAchievementProgress(
      session: readSession(),
    );
    if (cached != null) {
      unawaited(commandRevalidateAchievementCache(cached.contentHash));
      return cached.rows;
    }

    final rows = await readRepository().loadLocalAchievementProgress(
      session: readSession(),
    );
    unawaited(commandRevalidateAchievementCache(''));
    return rows;
  }

  /// Computes cache fresh achievement rows.
  Future<void> commandCacheFreshAchievementRows(
    List<Map<String, dynamic>> rows,
  ) async {
    await readRepository().saveCachedAchievementProgress(
      session: readSession(),
      contentHash: achievementProgressContentHash(rows),
      rows: rows,
    );
  }

  /// Computes revalidate achievement cache.
  Future<void> commandRevalidateAchievementCache(String cachedHash) async {
    final remoteHash = await readRepository().loadAchievementProgressHash(
      session: readSession(),
    );
    if (remoteHash.isEmpty || remoteHash == cachedHash) return;
    final rows = await readRepository().loadUserAchievementProgress(
      session: readSession(),
    );
    if (rows.isEmpty) return;
    await commandCacheFreshAchievementRows(rows);
    if (!mounted) return;
    _publish(() {
      stateAchievementsFuture = Future.value(rows);
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  late final Future<void> Function() effectPresentOpenRewardModerationEffect1;

  bool stateOpeningRewardModeration = false;

  /// Opens reward moderation.
  Future<void> commandOpenRewardModeration() async {
    if (!readSession().isAdmin || stateOpeningRewardModeration) return;
    stateOpeningRewardModeration = true;
    try {
      await effectPresentOpenRewardModerationEffect1();
      if (mounted) {
        _publish(() {
          stateAchievementsFuture = commandLoadAchievementsCacheFirst();
        });
      }
    } finally {
      stateOpeningRewardModeration = false;
    }
  }
}

/// Owns the state and non-visual actions of _AchievementLeaderboardPage.
class _AchievementLeaderboardPageStateViewModel extends ChangeNotifier {
  /// Creates achievement leaderboard page state view model.
  _AchievementLeaderboardPageStateViewModel({required this.readRepository});
  final HikerCircleFirebaseRepository Function() readRepository;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  String statePeriod = 'month';

  List<Map<String, dynamic>>? statePreviewEntries;

  DateTime? stateLastTitleTap;

  int stateTitleTaps = 0;

  late Future<List<Map<String, dynamic>>> stateEntriesFuture;

  /// Computes tap title.
  void commandTapTitle() {
    final now = DateTime.now();
    stateTitleTaps =
        stateLastTitleTap != null &&
            now.difference(stateLastTitleTap!).inMilliseconds < 600
        ? stateTitleTaps + 1
        : 1;
    stateLastTitleTap = now;
    if (stateTitleTaps < 3) return;
    stateTitleTaps = 0;
    _publish(() {
      statePreviewEntries = List.generate(
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

  /// Selects period.
  void commandSelectPeriod(String period) {
    if (period == statePeriod) return;
    _publish(() {
      statePeriod = period;
      if (statePreviewEntries != null) return;
      stateEntriesFuture = readRepository().loadAchievementLeaderboard(
        period: period,
      );
    });
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
