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
  StreamSubscription<CacheResourceUpdate>? _cachedReadSubscription;
  final Set<String> _revokedReadTypes = {};
  int _profileReadRevision = 0;
  int _collectionReadRevision = 0;

  void commandWatchCachedReads() {
    _cachedReadSubscription = stateFirebaseRepository.cachedReadUpdates.listen((
      change,
    ) async {
      if (!mounted || change.owner != readSession().phoneNumber) {
        return;
      }
      if (change.revoked) {
        _revokedReadTypes.add(change.type);
        if (change.type == 'profile') _profileReadRevision++;
        if (change.type == 'mobile_chat_list' ||
            change.type == 'mobile_social') {
          _collectionReadRevision++;
        }
        _publish(() {
          if (change.type == 'profile') stateFirestoreProfile = null;
          if (change.type == 'mobile_achievement_progress') {
            stateAchievementsFuture = Future.value(const []);
          }
          if (change.type == 'mobile_chat_list') {
            stateCircleHistoryItems = const [];
          }
          if (change.type == 'mobile_social') stateBuddyHistoryItems = const [];
        });
        return;
      }
      if (change.invalidated) return;
      _revokedReadTypes.remove(change.type);
      try {
        if (change.type == 'profile') {
          await commandLoadFirestoreProfile();
        } else if (change.type == 'mobile_achievement_progress') {
          await commandFetchProfileAchievements();
          await commandReloadLocalProfileAchievements();
        } else if (change.type == 'mobile_chat_list' ||
            change.type == 'mobile_social') {
          await commandLoadProfileCollections();
        }
      } catch (_) {
        // Keep the visible local view if its refreshed projection cannot load.
      }
    });
  }

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
    if (_revokedReadTypes.contains('mobile_achievement_progress')) return;
    final cached = await stateFirebaseRepository.loadCachedAchievementProgress(
      session: readSession(),
    );
    if (mounted &&
        cached != null &&
        !_revokedReadTypes.contains('mobile_achievement_progress')) {
      _publish(() => stateAchievementsFuture = Future.value(cached.rows));
    }
  }

  /// Fetches profile achievements.
  Future<List<Map<String, dynamic>>> commandFetchProfileAchievements() async {
    if (_revokedReadTypes.contains('mobile_achievement_progress')) {
      return const [];
    }
    final rows = await stateFirebaseRepository.loadUserAchievementProgress(
      session: readSession(),
    );
    if (_revokedReadTypes.contains('mobile_achievement_progress')) {
      return const [];
    }
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
      final rows = await commandFetchProfileAchievements();
      if (mounted &&
          !_revokedReadTypes.contains('mobile_achievement_progress')) {
        _publish(() => stateAchievementsFuture = Future.value(rows));
      }
    } catch (_) {
      // Keep the saved summary available when the network is unavailable.
    }
  }

  /// Loads firestore profile.
  Future<void> commandLoadFirestoreProfile() async {
    final session = readSession();
    final revision = ++_profileReadRevision;
    try {
      final profile = await stateOnboardingRepository.loadProfile(session);
      if (!mounted ||
          revision != _profileReadRevision ||
          session.phoneNumber != readSession().phoneNumber ||
          _revokedReadTypes.contains('profile')) {
        return;
      }
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
    final session = readSession();
    final revision = ++_collectionReadRevision;
    try {
      final results = await Future.wait<Object>([
        stateFirebaseRepository.loadCommunityPostsForUser(session: session),
        stateFirebaseRepository.loadUserGroupChats(session.phoneNumber),
        stateFirebaseRepository.loadBuddyPhoneNumbers(session: session),
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
      if (!mounted ||
          revision != _collectionReadRevision ||
          session.phoneNumber != readSession().phoneNumber) {
        return;
      }
      _publish(() {
        statePostHistoryItems = posts;
        stateCircleHistoryItems = _revokedReadTypes.contains('mobile_chat_list')
            ? const []
            : chats;
        stateBuddyHistoryItems = _revokedReadTypes.contains('mobile_social')
            ? const []
            : buddies;
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
    _cachedReadSubscription?.cancel();
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
  StreamSubscription<CacheResourceUpdate>? _cachedPreferences;
  int _timeZoneReadRevision = 0;
  bool stateIsSavingTimeZone = false;

  void commandSetTimeZoneSaving(bool saving) {
    stateIsSavingTimeZone = saving;
    _timeZoneReadRevision++;
  }

  void commandWatchCachedPreferences() {
    _cachedPreferences = readFirebaseRepository().cachedReadUpdates.listen((
      change,
    ) async {
      if (!mounted ||
          stateIsSavingTimeZone ||
          change.invalidated ||
          change.owner != readSession().phoneNumber ||
          change.type != 'mobile_preferences') {
        return;
      }
      final revision = ++_timeZoneReadRevision;
      final owner = readSession().phoneNumber;
      try {
        final data = await readFirebaseRepository().readMobileSnapshot(
          owner: owner,
          resourceType: 'preferences',
          cacheOnly: true,
        );
        final preferences = data['preferences'];
        final saved = preferences is Map
            ? preferences['preferredTimeZone']
            : null;
        if (!mounted ||
            owner != readSession().phoneNumber ||
            revision != _timeZoneReadRevision ||
            stateIsSavingTimeZone ||
            saved is! String ||
            !PreferredTimeZone.isValid(saved)) {
          return;
        }
        stateSettings.setPreferredTimeZone(saved);
        _publish(() {
          stateTimeZoneStatus = 'Using your saved timezone for SOS messages.';
        });
      } catch (_) {
        // Keep the phone's last setting if its downloaded view is unavailable.
      }
    });
  }

  /// Handles settings changed.
  void commandHandleSettingsChanged() {
    if (mounted) {
      _publish(() {});
    }
  }

  /// Loads preferred time zone.
  Future<void> commandLoadPreferredTimeZone() async {
    final revision = ++_timeZoneReadRevision;
    final session = readSession();
    try {
      final saved = await readFirebaseRepository().loadPreferredTimeZone(
        session: session,
      );
      if (!mounted ||
          session.phoneNumber != readSession().phoneNumber ||
          revision != _timeZoneReadRevision ||
          stateIsSavingTimeZone) {
        return;
      }
      if (saved != null) {
        stateSettings.setPreferredTimeZone(saved);
      }
      if (!mounted) return;
      _publish(() {
        stateTimeZoneStatus = saved != null
            ? 'Using your saved timezone for SOS messages.'
            : 'Using this phone\'s timezone setting. Choose a timezone to update it.';
      });
    } catch (_) {
      if (!mounted) return;
      _publish(() {
        stateTimeZoneStatus =
            'Could not refresh your timezone. Using this phone\'s saved setting.';
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
    unawaited(_cachedPreferences?.cancel());
    super.dispose();
  }

  late final Future<void> Function() effectPresentChangePasswordEffect2;

  late final Future<bool?> Function() effectPresentChangePasswordEffect1;

  late final void Function(String) effectShowBiometricUnlockIssue;
  bool _updatingBiometricUnlock = false;
  late final Future<bool?> Function() effectConfirmDisableHapticFeedback;
  bool _updatingHapticFeedback = false;

  /// Requires an explicit confirmation before disabling haptic safety feedback.
  Future<void> commandSetHapticSafetyFeedback(bool enabled) async {
    if (!mounted || _updatingHapticFeedback) return;
    _updatingHapticFeedback = true;
    try {
      if (!enabled && await effectConfirmDisableHapticFeedback() != true) {
        return;
      }
      if (mounted) stateSettings.setHapticSafetyFeedbackEnabled(enabled);
    } finally {
      _updatingHapticFeedback = false;
    }
  }

  /// Changes the saved preference only after a successful biometric challenge.
  Future<void> commandSetPrivateUnlock(bool enabled) async {
    if (!mounted || _updatingBiometricUnlock) return;
    _updatingBiometricUnlock = true;
    try {
      final result = await PrivateScreenUnlock.requestAuthentication();
      if (!mounted) return;
      if (result == BiometricUnlockResult.authenticated) {
        stateSettings.setPrivateScreenUnlockEnabled(enabled);
      } else {
        final message = switch (result) {
          BiometricUnlockResult.notEnrolled =>
            'Set up Face ID or fingerprints in your phone settings before enabling App biometric unlock.',
          BiometricUnlockResult.unavailable =>
            'Biometric access is unavailable. Check your phone settings and allow HikerCircle to use Face ID or fingerprints.',
          BiometricUnlockResult.lockedOut =>
            'Biometrics are locked. Unlock your phone with its passcode, then try again.',
          BiometricUnlockResult.failed =>
            'Biometric verification was not completed. Please try again.',
          _ => null,
        };
        if (message != null) effectShowBiometricUnlockIssue(message);
      }
    } catch (_) {
      if (mounted) {
        effectShowBiometricUnlockIssue(
          'Biometric verification was not completed. Please try again.',
        );
      }
    } finally {
      _updatingBiometricUnlock = false;
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

/// Owns cached progress, admin mutations and stale-load protection for the achievements page.
class _AchievementsPageStateViewModel extends ChangeNotifier {
  /// Reads the current account at each operation instead of trusting a stale form.
  _AchievementsPageStateViewModel({
    required this.readRepository,
    required this.readSession,
  });
  final HikerCircleFirebaseRepository Function() readRepository;
  final AppSession Function() readSession;
  bool _disposed = false;
  int _revision = 0;
  List<Map<String, dynamic>> _rows = [];
  bool stateSavingAchievement = false;
  String? stateAchievementError;
  late Future<List<Map<String, dynamic>>> stateAchievementsFuture;
  late final Future<void> Function() effectPresentOpenRewardModerationEffect1;
  bool stateOpeningRewardModeration = false;

  /// Whether async results can still update this page.
  bool get mounted => !_disposed;

  /// Publishes presentation changes only while this account page is mounted.
  void _publish(VoidCallback update) {
    update();
    if (mounted) notifyListeners();
  }

  /// Applies current rule visibility and progress from the shared repository listener.
  void commandApplyLiveRows(List<Map<String, dynamic>> rows) {
    if (!mounted) return;
    _revision++;
    _rows = rows;
    _publish(() => stateAchievementsFuture = Future.value(rows));
  }

  /// Reopens the locally committed snapshot after a notification or catalog update.
  Future<void> commandReloadLocalAchievements() async {
    final generation = ++_revision;
    final cached = await readRepository().loadCachedAchievementProgress(
      session: readSession(),
    );
    if (mounted && generation == _revision && cached != null) {
      _rows = cached.rows;
      _publish(() => stateAchievementsFuture = Future.value(cached.rows));
    }
  }

  /// Shows cached content immediately, then checks the live catalog for admin-only inactive rules too.
  Future<List<Map<String, dynamic>>> commandLoadAchievementsCacheFirst() async {
    final cached = await readRepository().loadCachedAchievementProgress(
      session: readSession(),
    );
    if (cached != null) {
      _rows = cached.rows;
      unawaited(commandRevalidateAchievementCache(cached.contentHash));
      return cached.rows;
    }
    final rows = await readRepository().loadLocalAchievementProgress(
      session: readSession(),
    );
    _rows = rows;
    unawaited(commandRevalidateAchievementCache(''));
    return rows;
  }

  /// Persists row metadata alongside progress so archived flags survive app restart.
  Future<void> commandCacheFreshAchievementRows(
    List<Map<String, dynamic>> rows,
  ) => readRepository().saveCachedAchievementProgress(
    session: readSession(),
    contentHash: achievementProgressContentHash(rows),
    rows: rows,
  );

  /// Refreshes the user's progress without allowing an earlier request to restore an archived card.
  Future<void> commandRevalidateAchievementCache(String cachedHash) async {
    final generation = ++_revision;
    final rows = await readRepository().loadUserAchievementProgress(
      session: readSession(),
    );
    if (!mounted || generation != _revision) return;
    await commandCacheFreshAchievementRows(rows);
    if (mounted && generation == _revision) {
      _rows = rows;
      _publish(() => stateAchievementsFuture = Future.value(rows));
    }
  }

  /// Saves a supported rule and commits its known server result locally before further refreshes.
  Future<bool> commandSaveAchievement(
    Map<String, dynamic> values, {
    String achievementId = '',
  }) => _mutate(() async {
    final id = await readRepository().saveAchievementByAdmin(
      session: readSession(),
      achievement: values,
      achievementId: achievementId,
    );
    final rows = await _mutationRows();
    final index = rows.indexWhere((row) => row['achievementId'] == id);
    final row = {
      if (index >= 0) ...rows[index],
      ...values,
      'achievementId': id,
    };
    if (index < 0) {
      rows.add(row);
    } else {
      rows[index] = row;
    }
    await _commitMutationRows(rows);
  });

  /// Archives or unarchives just this definition; prior awards and points remain untouched.
  Future<bool> commandSetAchievementActive(String id, bool isActive) =>
      _mutate(() async {
        await readRepository().setAchievementActiveByAdmin(
          session: readSession(),
          achievementId: id,
          isActive: isActive,
        );
        final before = await _mutationRows();
        final rows = [
          for (final row in before)
            row['achievementId'] == id ? {...row, 'isActive': isActive} : row,
        ];
        await _commitMutationRows(rows);
      });

  /// Uses in-memory rows if a successful server update cannot read the local cache.
  Future<List<Map<String, dynamic>>> _mutationRows() async {
    try {
      final cached = await readRepository().loadCachedAchievementProgress(
        session: readSession(),
      );
      return [...(cached?.rows ?? _rows)];
    } catch (_) {
      return [..._rows];
    }
  }

  /// A cache failure must not misreport an already-saved rule and invite duplicate creation.
  Future<void> _commitMutationRows(List<Map<String, dynamic>> rows) async {
    try {
      await commandCacheFreshAchievementRows(rows);
    } catch (_) {
      // The rule listener will retry the authoritative snapshot after local storage recovers.
    }
    if (mounted) commandApplyLiveRows(rows);
  }

  /// Serializes moderation requests and reports failures without changing the visible archive state.
  Future<bool> _mutate(Future<void> Function() action) async {
    if (!mounted || !readSession().isAdmin || stateSavingAchievement) {
      return false;
    }
    _revision++;
    _publish(() {
      stateSavingAchievement = true;
      stateAchievementError = null;
    });
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        _publish(
          () => stateAchievementError =
              error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'This achievement could not be updated. Please retry.',
        );
      }
      return false;
    } finally {
      if (mounted) _publish(() => stateSavingAchievement = false);
    }
  }

  /// Retains the existing dashboard shortcut and reloads its changes on return.
  Future<void> commandOpenRewardModeration() async {
    if (!readSession().isAdmin || stateOpeningRewardModeration) return;
    stateOpeningRewardModeration = true;
    try {
      await effectPresentOpenRewardModerationEffect1();
      if (mounted) await commandRevalidateAchievementCache('');
    } finally {
      stateOpeningRewardModeration = false;
    }
  }

  /// Stops late requests from updating a disposed account page.
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
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
