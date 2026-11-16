// Temporary capture routes: current production widgets with fictional local
// content only. Import this map from website_capture_main.dart for a new build.
// No Firebase initialization, account authentication, real message or upload.
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'admin/Model/admin_analytics_snapshot.dart';
import 'admin/Model/button_debug_entry.dart';
import 'admin/Data/button_debug_controller.dart';
import 'admin/View/admin_analytics_dashboard.dart';
import 'admin/View/button_debugging_page.dart';
import 'app/Data/conditional_cloud_cache.dart';
import 'app/Data/firebase_bootstrap.dart';
import 'app/Data/hiker_circle_firebase_repository.dart';
import 'app/Data/local_session_database.dart';
import 'app/Model/app_session.dart';
import 'authentication/Data/multi_factor_auth_service.dart';
import 'authentication/Data/privacy_consent_repository.dart';
import 'authentication/Model/mfa_models.dart';
import 'authentication/Model/privacy_consent_receipt.dart';
import 'authentication/ModelView/auth_view_model.dart';
import 'authentication/View/forgot_password_page.dart';
import 'authentication/View/phone_sign_in_page.dart';
import 'authentication/View/security_methods_page.dart';
import 'circle/View/circle_page.dart';
import 'circle/View/group_chat_detail_page.dart';
import 'core/widgets/page_header_style.dart';
import 'core/services/hiker_ble_service.dart';
import 'core/services/network_reachability_service.dart';
import 'feedback/Model/feedback_report.dart';
import 'feedback/feedback_page.dart';
import 'feedback/feedback_repository.dart';
import 'home/Model/hike_session_models.dart';
import 'me/View/profile_details_page.dart';
import 'me/View/device_notifications_page.dart';
import 'navigation/View/hiker_bottom_nav_bar.dart';
import 'onboarding/Data/onboarding_repository.dart';
import 'onboarding/Model/onboarding_profile.dart';
import 'onboarding/View/onboarding_profile_page.dart';
import 'sos/Data/emergency_contacts_repository.dart';
import 'sos/Model/sos_models.dart';
import 'sos/Model/nearby_sos_event.dart';
import 'sos/Data/sos_alert_repository.dart';
import 'sos/View/emergency_contacts_page.dart';
import 'sos/View/nearby_sos_map_page.dart';
import 'sos/View/sos_page.dart';
import 'sos/View/sos_button_pairing_sheet.dart';
import 'sos/View/widgets/paired_sos_button_card.dart';
import 'showcase_safety_main.dart' as safety;

const _offline = FirebaseBootstrapResult.unavailable(
  'Local website media demo',
);
const _phone = '+10000000000';
const _profile = OnboardingProfile(
  username: 'Alex Demo',
  gender: 'prefer_not_to_say',
  hikerExperience: 'experienced',
  hikeFrequency: 'weekly',
  residentialLocation: 'Kuala Lumpur · demo',
  residentialLatitude: 3.1390,
  residentialLongitude: 101.6869,
);
const _contacts = [
  EmergencyContact(
    name: 'Jamie Demo',
    phoneNumber: '+10000000001',
    relationship: 'Friend',
  ),
  EmergencyContact(
    name: 'Sam Demo',
    phoneNumber: '+10000000002',
    relationship: 'Family',
  ),
  EmergencyContact(
    name: 'Taylor Demo',
    phoneNumber: '+10000000003',
    relationship: 'Friend',
  ),
];

/// Every route is an isolated local demo; label its captured media accordingly.
Map<String, WidgetBuilder> websiteCaptureExtraPages() {
  final session = AppSession(
    phoneNumber: _phone,
    signedInAt: DateTime(2026, 11, 16),
    username: 'Alex Demo',
  );
  final social = _LocalSocialRepository();
  final feedback = _LocalFeedbackRepository();
  return {
    'login': (_) => const _AuthCapture(),
    'forgot-password': (_) => const _AuthCapture(reset: true),
    'onboarding': (_) => OnboardingProfilePage(
      initialProfile: _profile,
      initialPasswordConfigured: true,
      onSubmit: (_) async => _deny(),
    ),
    'profile': (_) => ProfileDetailsPage(
      session: session,
      firebaseBootstrapResult: _offline,
      repository: _LocalProfileRepository(),
    ),
    'security': (_) => SecurityMethodsPage(service: _LocalMfaService()),
    'emergency-contacts': (_) => EmergencyContactsPage(
      session: session,
      initialContacts: _contacts,
      repository: const _LocalContactsRepository(),
    ),
    'community': (_) => _CircleCapture(session: session, repository: social),
    'buddy-requests': (_) =>
        _CircleCapture(session: session, repository: social, requests: true),
    'community-story': (_) =>
        _CircleCapture(session: session, repository: social, story: true),
    'chat': (_) => GroupChatDetailPage(
      chat: social.chat,
      session: session,
      repository: social,
    ),
    'feedback': (_) => FeedbackPage(repository: feedback),
    'feedback-compose': (_) => FeedbackComposePage(
      repository: feedback,
      initialText:
          'A local demonstration draft: a clearer reminder before departure would help me prepare.',
    ),
    'feedback-inbox': (_) => FeedbackInboxPage(repository: feedback),
    'admin-feedback': (_) =>
        FeedbackInboxPage(admin: true, repository: feedback),
    'admin-overview': (_) => const _AdminCapture(),
    'notifications': (_) => DeviceNotificationsPage(
      phoneNumber: _phone,
      database: _LocalCaptureDatabase(),
      onOpenDeepLink: (_) async {},
    ),
    // No exact event location: the production radius branch uses this supplied
    // detector location and does not call the device GPS snapshot singleton.
    'nearby-sos': (_) => NearbySosMapPage(
      event: NearbySosEvent(
        ownerPhoneNumber: _phone,
        eventKey: 'website-demo-nearby',
        deviceId: 'website-demo-button',
        receivedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        updatedAt: DateTime.now(),
        rssi: -68,
        detectorLocation: const SosTriggerLocation(
          latitude: 5.4141,
          longitude: 100.3288,
        ),
      ),
      initialPhoneLocation: const SosTriggerLocation(
        latitude: 5.4141,
        longitude: 100.3288,
      ),
    ),
    'button-debug': (_) => ButtonDebuggingPage(
      session: session.copyWith(isAdmin: true),
      controller: _LocalButtonDebugController(),
    ),
    'button-debug-sim': (_) => ButtonDebuggingPage(
      session: session.copyWith(isAdmin: true),
      controller: _LocalButtonDebugController(signalReceived: true),
    ),
    'button-pairing-sim': (_) => const _SimulatedButtonHost(openPairing: true),
    'button-paired-sim': (_) => const _SimulatedButtonHost(initialPaired: true),
    // Like the original sos demo route, deny showcase GPS permission before
    // capture. The host has a non-injectable GPS reader; its list/notes are local.
    'sos-history': (_) => Scaffold(
      extendBody: true,
      bottomNavigationBar: HikerBottomNavBar(
        currentIndex: 1,
        onDestinationSelected: (_) {},
      ),
      body: SosPage(
        session: session,
        firebaseBootstrapResult: _offline,
        networkStatusOverride: const NetworkReachabilitySnapshot(
          state: NetworkReachabilityState.offline,
        ),
        sosAlertRepository: _LocalHistoryAlerts(),
        emergencyContactsRepository: const _LocalContactsRepository(),
        nearbySosEventRepository: safety.DemoNearby(),
      ),
    ),
  };
}

Never _deny() => throw StateError(
  'This action is disabled in the local website demonstration.',
);

class _NoCaptureFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => _deny();
}

class _AuthCapture extends StatefulWidget {
  const _AuthCapture({this.reset = false});
  final bool reset;
  @override
  State<_AuthCapture> createState() => _AuthCaptureState();
}

class _AuthCaptureState extends State<_AuthCapture> {
  late final _model = AuthViewModel(
    firebaseFunctions: _NoCaptureFunctions(),
    multiFactorAuthService: _LocalMfaService(),
  );
  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.reset
      ? ForgotPasswordPage(viewModel: _model)
      : PhoneSignInPage(
          viewModel: _model,
          privacyConsentRepository: _LocalConsent(),
          onSignedIn: (_) async => _deny(),
        );
}

class _LocalConsent extends PrivacyConsentRepository {
  @override
  Future<PrivacyConsentReceipt?> load(String owner) async => null;
  @override
  Future<void> accept(String owner, {required String languageCode}) async {}
  @override
  Future<void> flush(String owner) async {}
}

class _LocalProfileRepository extends OnboardingRepository {
  _LocalProfileRepository() : super(firebaseBootstrapResult: _offline);
  @override
  Stream<CacheResourceUpdate> get cachedReadUpdates => const Stream.empty();
  @override
  Future<OnboardingProfile> loadProfile(
    AppSession session, {
    bool force = false,
    bool cacheOnly = false,
  }) async => _profile;
  @override
  Future<void> saveProfile({
    required AppSession session,
    required OnboardingProfile profile,
  }) async => _deny();
}

class _LocalMfaService extends MultiFactorAuthService {
  @override
  Future<MfaStatus> loadStatus() async => const MfaStatus(
    required: true,
    factorCount: 2,
    methods: ['totp', 'passkey'],
    canRemove: false,
    factors: [
      MfaFactor(
        id: 'local-demo-totp',
        type: 'totp',
        label: 'Authenticator app · demo',
      ),
      MfaFactor(
        id: 'local-demo-passkey',
        type: 'passkey',
        label: 'Android passkey · demo',
      ),
    ],
  );
  @override
  Future<String> authenticatedPhoneNumber() async => _deny();
  @override
  Future<TotpEnrollment> beginTotpEnrollment({String? mfaToken}) async =>
      _deny();
  @override
  Future<AppSession?> enrollPasskey({String? mfaToken, String? label}) async =>
      _deny();
  @override
  Future<void> removeFactor(String factorId) async => _deny();
}

class _LocalContactsRepository extends EmergencyContactsRepository {
  const _LocalContactsRepository() : super(firebaseBootstrapResult: _offline);
  @override
  Future<List<EmergencyContact>> loadCachedEmergencyContacts({
    required AppSession session,
  }) async => _contacts;
  @override
  Future<List<EmergencyContact>> loadEmergencyContacts({
    required AppSession session,
  }) async => _contacts;
  @override
  Future<void> saveEmergencyContacts({
    required AppSession session,
    required List<EmergencyContact> contacts,
  }) async => _deny();
}

class _CircleCapture extends StatelessWidget {
  const _CircleCapture({
    required this.session,
    required this.repository,
    this.requests = false,
    this.story = false,
  });
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final bool requests, story;
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    bottomNavigationBar: HikerBottomNavBar(
      currentIndex: 2,
      onDestinationSelected: (_) {},
    ),
    body: CirclePage(
      session: session,
      hikerCircleRepository: repository,
      firebaseBootstrapResult: _offline,
      buddyRequestsOpenId: requests ? 1 : 0,
      initialPostId: story ? 'website-demo-story' : null,
    ),
  );
}

class _LocalSocialRepository extends HikerCircleFirebaseRepository {
  _LocalSocialRepository() : super(firebaseBootstrapResult: _offline);
  final now = DateTime.now();
  late final chat = GroupChat(
    id: 'website-demo-chat',
    hikeSessionId: '',
    trailName: 'Weekend Ridge Walk · Demo',
    participantPhones: const [_phone, '+10000000001', '+10000000002'],
    creatorPhone: _phone,
    createdAt: now.subtract(const Duration(days: 1)),
    participantNames: const {
      _phone: 'Alex Demo',
      '+10000000001': 'Jamie Demo',
      '+10000000002': 'Sam Demo',
    },
    lastMessage: 'See you at the trailhead at 7:30.',
    lastMessageAt: now.subtract(const Duration(minutes: 5)),
    customName: 'Weekend Ridge Walk · Demo',
  );
  late final messages = [
    ChatMessage(
      id: 'demo-1',
      chatId: chat.id,
      senderPhone: '+10000000001',
      senderName: 'Jamie Demo',
      text:
          'Shall we meet at the trailhead at 7:30? The morning forecast looks clearer.',
      sentAt: now.subtract(const Duration(minutes: 18)),
      seenBy: const [_phone],
    ),
    ChatMessage(
      id: 'demo-2',
      chatId: chat.id,
      senderPhone: _phone,
      senderName: 'Alex Demo',
      text:
          'Sounds good. I have packed water, a headlamp and the first-aid kit.',
      sentAt: now.subtract(const Duration(minutes: 16)),
      seenBy: const [_phone, '+10000000001'],
    ),
    ChatMessage(
      id: 'demo-3',
      chatId: chat.id,
      senderPhone: '+10000000002',
      senderName: 'Sam Demo',
      text:
          'I will check the trail cautions again before leaving. See you there!',
      sentAt: now.subtract(const Duration(minutes: 12)),
      seenBy: const [_phone],
    ),
    ChatMessage(
      id: 'demo-4',
      chatId: chat.id,
      senderPhone: _phone,
      senderName: 'Alex Demo',
      text: 'Great. Let us review our preparation together before we start.',
      sentAt: now.subtract(const Duration(minutes: 8)),
      seenBy: const [_phone, '+10000000001'],
    ),
    ChatMessage(
      id: 'demo-5',
      chatId: chat.id,
      senderPhone: '+10000000001',
      senderName: 'Jamie Demo',
      text: 'See you at the trailhead at 7:30.',
      sentAt: now.subtract(const Duration(minutes: 5)),
      seenBy: const [_phone],
    ),
  ];
  late final people = [
    _person(
      'jamie',
      '+10000000001',
      'Jamie Demo',
      'Experienced',
      'Weekly',
      'Kuala Lumpur',
      4,
      'Ridgewalker',
    ),
    _person(
      'sam',
      '+10000000002',
      'Sam Demo',
      'New hiker',
      'Several times a month',
      'Selangor',
      2,
      'Explorer',
    ),
    _person(
      'taylor',
      '+10000000003',
      'Taylor Demo',
      'Experienced',
      'Weekly',
      'Penang',
      5,
      'Trail Guide',
    ),
  ];
  Map<String, dynamic> _person(
    String id,
    String phone,
    String name,
    String experience,
    String frequency,
    String city,
    int level,
    String levelName,
  ) => {
    'userId': 'website-demo-$id',
    'phoneNumber': phone,
    'displayName': name,
    'handle': '@${id}_demo',
    'hikerExperience': experience,
    'hikeFrequency': frequency,
    'residentialLocation': city,
    'level': level,
    'levelName': levelName,
    'photoURL': '',
  };
  late final posts = <Map<String, dynamic>>[
    {
      'postId': 'website-demo-story',
      'authorId': 'website-demo-jamie',
      'authorPhoneNumber': '+10000000001',
      'authorName': 'Jamie Demo',
      'authorHandle': '@jamie_demo',
      'authorLevelBadge': 'Lv. 4 Ridgewalker',
      'authorLevel': 4,
      'trailName': 'Weekend Ridge Walk · Demo',
      'caption':
          'A quiet morning above the trees. We checked the weather, packed together and stayed with our group. What is on your next hike checklist?',
      'createdAtLocal': now
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'likeCount': 12,
      'commentCount': 2,
      'imageUrls': <String>[],
      'isLiked': false,
      'isOwnPost': false,
    },
    {
      'postId': 'website-demo-tip',
      'authorId': 'website-demo-sam',
      'authorPhoneNumber': '+10000000002',
      'authorName': 'Sam Demo',
      'authorHandle': '@sam_demo',
      'authorLevelBadge': 'Lv. 2 Explorer',
      'authorLevel': 2,
      'trailName': 'Community',
      'caption':
          'First team hike complete! A small group and a clear plan made the day feel much easier. Remember to bring enough water and tell someone your return time.',
      'createdAtLocal': now
          .subtract(const Duration(hours: 5))
          .toIso8601String(),
      'likeCount': 8,
      'commentCount': 1,
      'imageUrls': <String>[],
      'isLiked': false,
      'isOwnPost': false,
    },
  ];
  late final requests = <Map<String, dynamic>>[
    {
      ...people.last,
      'createdAtLocal': now
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> loadCommunityProfiles({
    required AppSession session,
    bool force = false,
  }) async => people;
  @override
  Future<Map<String, dynamic>?> loadCommunityProfile({
    String userId = '',
    String phoneNumber = '',
  }) async =>
      people
          .where(
            (p) => p['phoneNumber'] == phoneNumber || p['userId'] == userId,
          )
          .firstOrNull ??
      people.first;
  @override
  Future<Map<String, dynamic>> loadPublicHikerProfile({
    String userId = '',
    String phoneNumber = '',
  }) async => {
    'profile': await loadCommunityProfile(
      userId: userId,
      phoneNumber: phoneNumber,
    ),
    'stats': {'completedHikes': 12, 'totalDistanceKm': 68.4},
    'achievements': <Map<String, dynamic>>[],
    'posts': posts,
  };
  @override
  Future<List<Map<String, dynamic>>> loadCommunityPosts({
    AppSession? session,
    int limit = 20,
    String? afterPostId,
    bool force = false,
  }) async => afterPostId == null ? posts : [];
  @override
  Future<Map<String, dynamic>?> loadCommunityPost({
    required AppSession session,
    required String postId,
  }) async => posts.first;
  @override
  Future<List<Map<String, dynamic>>> loadCommunityComments({
    required String postId,
    int limit = 30,
    String? afterCommentId,
    bool force = false,
  }) async => [
    {
      'commentId': 'demo-comment',
      'authorPhoneNumber': '+10000000002',
      'authorName': 'Sam Demo',
      'text': 'A lovely morning for a shared adventure.',
      'createdAtLocal': now
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
    },
  ];
  @override
  Future<List<Map<String, dynamic>>> loadBuddyRequests({
    required AppSession session,
  }) async => requests;
  @override
  Stream<BuddyRelationships> watchBuddyRelationships({
    required AppSession session,
  }) => Stream.value(
    BuddyRelationships(
      buddyPhoneNumbers: const {'+10000000001'},
      outgoingRequestPhones: const {},
      incomingRequests: requests,
    ),
  );
  @override
  Future<Set<String>> loadBuddyPhoneNumbers({
    required AppSession session,
  }) async => {'+10000000001'};
  @override
  Future<Set<String>> loadOutgoingBuddyRequestPhoneNumbers({
    required AppSession session,
  }) async => {};
  @override
  Stream<List<GroupChat>> userGroupChatsStream(String phoneNumber) =>
      Stream.value([chat]);
  @override
  Future<List<GroupChat>> loadUserGroupChats(String phoneNumber) async => [
    chat,
  ];
  @override
  Future<GroupChat?> loadGroupChatById(String chatId) async => chat;
  @override
  Future<Map<String, DateTime>> loadAllLocalLastReadAt({
    required String ownerPhoneNumber,
  }) async => {};
  @override
  Future<DateTime?> loadLocalLastReadAt(
    String chatId, {
    required String ownerPhoneNumber,
  }) async => now.subtract(const Duration(days: 1));
  @override
  Future<Set<String>> loadPinnedChats({required AppSession session}) async =>
      {};
  @override
  Future<bool> loadGroupChatNotificationsEnabled({
    required AppSession session,
  }) async => true;
  @override
  Future<DateTime?> loadGroupChatMutedUntil({
    required AppSession session,
    required String chatId,
  }) async => null;
  @override
  Stream<List<ChatMessage>> groupChatMessagesStream(String chatId) =>
      Stream.value(messages);
  @override
  Future<List<ChatMessage>> loadAllLocalMessagesForChat(
    String chatId, {
    required String ownerPhoneNumber,
  }) async => messages;
  @override
  Future<void> cacheChatMessages(
    List<ChatMessage> messages,
    String chatId, {
    required String ownerPhoneNumber,
  }) async {}
  @override
  Future<void> markGroupChatAsRead({
    required String chatId,
    required String phoneNumber,
  }) async {}
  @override
  Future<void> markMessageAsSeen({
    required String chatId,
    required String messageId,
    required String phoneNumber,
  }) async {}
  @override
  Future<void> syncPendingReadReceipts({required String phoneNumber}) async {}
  @override
  Future<void> flushPendingMessages({String? ownerPhoneNumber}) async {}
  @override
  Future<void> sendGroupChatMessage({
    required String chatId,
    required String senderPhone,
    required String senderName,
    required String text,
    required String localId,
    required DateTime sentAt,
    ChatAttachment? attachment,
    SharedCommunityPost? sharedPost,
    Uint8List? attachmentBytes,
    Map<String, dynamic>? attachmentUpload,
  }) async => _deny();
  @override
  Future<int> setCommunityPostLiked({
    required AppSession session,
    required String postId,
    required bool liked,
  }) async => _deny();
  @override
  Future<void> sendBuddyRequest({
    required AppSession session,
    required String buddyPhoneNumber,
  }) async => _deny();
  @override
  Future<void> acceptBuddyRequest({
    required AppSession session,
    required String requesterPhoneNumber,
  }) async => _deny();
  @override
  Future<void> declineBuddyRequest({
    required AppSession session,
    required String requesterPhoneNumber,
  }) async => _deny();
}

class _LocalFeedbackRepository extends FeedbackRepository {
  _LocalFeedbackRepository() : super(currentOwner: () => _phone);
  FeedbackSavedDraft? _saved;
  late final _reports = [
    FeedbackReport(
      id: 'website-demo-report-1',
      data: {
        'category': 'Suggestion',
        'message': 'A clearer reminder before departure would help me prepare.',
        'status': 'In review',
        'platform': 'android',
        'createdAtLocal': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      },
    ),
    FeedbackReport(
      id: 'website-demo-report-2',
      data: {
        'category': 'Problem',
        'message': 'The weather card took longer to load on a weak connection.',
        'status': 'Resolved',
        'platform': 'android',
        'createdAtLocal': DateTime.now()
            .subtract(const Duration(days: 3))
            .toIso8601String(),
      },
    ),
  ];
  @override
  Future<String> draftOwner() async => _phone;
  @override
  Future<void> checkDraftOwner(String owner) async {}
  @override
  Future<FeedbackSavedDraft?> loadSavedDraft({String? expectedOwner}) async =>
      _saved;
  @override
  Future<FeedbackSavedDraft> openSavedDraft({
    String category = 'Problem',
    String message = '',
    Uint8List? screenshot,
    String? expectedOwner,
  }) async => _saved ??= FeedbackSavedDraft(
    id: 'website-demo-draft',
    uid: _phone,
    category: category,
    message: message,
    screenshot: screenshot,
  );
  @override
  Future<FeedbackSavedDraft?> saveSavedDraft(
    FeedbackSavedDraft snapshot,
  ) async => _saved = snapshot;
  @override
  Future<bool> discardSavedDraft(FeedbackSavedDraft expected) async {
    _saved = null;
    return true;
  }

  @override
  Future<void> flushPendingSubmission() async {}
  @override
  Future<void> submit(FeedbackDraft draft) async => _deny();
  @override
  Future<void> sendDraftToCloud(FeedbackDraft draft) async => _deny();
  @override
  Stream<List<FeedbackReport>> reports({
    required bool admin,
    bool force = false,
  }) => Stream.value(_reports);
  @override
  Future<List<FeedbackReport>> loadReports({
    String? owner,
    bool force = false,
    bool cacheOnly = false,
  }) async => _reports;
  @override
  Stream<List<FeedbackReport>> watchAdminReports() => Stream.value(_reports);
  @override
  Future<void> setStatus(String id, String status) async => _deny();
  @override
  Future<Uint8List?> screenshot(String path) async => null;
}

class _AdminCapture extends StatelessWidget {
  const _AdminCapture();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PageHeaderAppBar(title: Text('Admin Overview · Demo')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: AdminAnalyticsDashboard(
        data: _demoAdminSnapshot(),
        loading: false,
        onRetry: () {},
        onSafety: () {},
        onTools: () {},
        onTrailRequests: () {},
        onFeedback: () {},
      ),
    ),
  );
}

Map<String, dynamic> _demoAdminSnapshot() {
  final now = DateTime.now();
  final metrics = <String, dynamic>{
    'completedHikes': 42,
    'abandonedHikes': 3,
    'newUsers': 18,
    'distanceKm': 226.8,
    'distanceSamples': 42,
    'durationSamples': 42,
    'hours': 126,
    'completionRate': 93.3,
    'averageDistanceKm': 5.4,
    'averageHours': 3,
  };
  return {
    'schemaVersion': 3,
    'generatedAtMillis': now.millisecondsSinceEpoch,
    'coverage': {
      for (final source in AdminAnalyticsSnapshot.sourceNames.keys)
        source: {'complete': true, 'analysed': 42},
    },
    'totals': {
      'users': 128,
      'trails': 24,
      'achievementAwards': 184,
      'communityPosts': 67,
    },
    'hikes': {
      'active': 3,
      'completed': 118,
      'distanceKm': 637.2,
      'distanceSamples': 118,
      'durationSamples': 118,
      'hours': 354,
    },
    'teams': {'active': 1},
    'plans': {'upcoming': 8},
    'safety': {
      'pendingHazards': 2,
      'byHazardLifecycle': [
        {'label': 'Reported', 'value': 2},
        {'label': 'Resolved', 'value': 6},
      ],
    },
    'windows': {
      for (final days in [7, 30, 90, 365])
        '$days': {
          'current': metrics,
          'previous': {
            ...metrics,
            'completedHikes': 36,
            'newUsers': 14,
            'distanceKm': 194.4,
          },
        },
    },
    'daily': [
      for (var i = 0; i < 30; i++)
        {
          'date': now
              .subtract(Duration(days: 29 - i))
              .toIso8601String()
              .substring(0, 10),
          'hikes': i % 3 + 1,
          'users': i % 2,
          'distanceKm': (i % 3 + 1) * 5.4,
        },
    ],
  };
}

/// Injects only fictional notification and diagnostic rows; no SQLite is opened.
class _LocalCaptureDatabase extends LocalSessionDatabase {
  final now = DateTime.now();
  late List<DeviceNotificationRecord> _notifications = [
    _notification(
      1,
      'Your hike is tomorrow',
      'Review your gear, weather and safety choices before departure.',
      'hike_reminder',
      15,
      starred: true,
    ),
    _notification(
      2,
      'New trail caution',
      'A demonstration caution is available for Weekend Ridge Walk.',
      'trail_hazard',
      45,
    ),
    _notification(
      3,
      'Jamie Demo sent a message',
      'See you at the trailhead at 7:30.',
      'group_chat',
      90,
      opened: true,
    ),
    _notification(
      4,
      'A new hiking buddy request',
      'Taylor Demo would like to connect with you.',
      'buddy_request',
      150,
    ),
    _notification(
      5,
      'Achievement unlocked',
      'First steps: your first completed hike is part of your story.',
      'achievement_unlocked',
      240,
      opened: true,
    ),
  ];
  DeviceNotificationRecord _notification(
    int id,
    String title,
    String body,
    String type,
    int minutes, {
    bool starred = false,
    bool opened = false,
  }) => DeviceNotificationRecord(
    id: id,
    messageId: 'website-demo-$id',
    title: title,
    body: body,
    type: type,
    deepLink: '',
    data: const {},
    receivedAt: now.subtract(Duration(minutes: minutes)),
    openedAt: opened ? now.subtract(Duration(minutes: minutes - 1)) : null,
    source: 'local',
    isStarred: starred,
  );
  DeviceNotificationRecord _copyNotification(
    DeviceNotificationRecord row, {
    bool? starred,
    bool? opened,
  }) => DeviceNotificationRecord(
    id: row.id,
    messageId: row.messageId,
    title: row.title,
    body: row.body,
    type: row.type,
    deepLink: row.deepLink,
    data: row.data,
    receivedAt: row.receivedAt,
    openedAt: opened == null
        ? row.openedAt
        : opened
        ? now
        : null,
    source: row.source,
    isStarred: starred ?? row.isStarred,
  );
  @override
  Future<List<DeviceNotificationRecord>> loadDeviceNotifications({
    required String ownerPhoneNumber,
    int limit = 500,
    DateTime? asOf,
  }) async => _notifications.take(limit).toList();
  @override
  Future<DateTime?> nextDeviceNotificationAt(
    String ownerPhoneNumber, {
    DateTime? asOf,
  }) async => null;
  @override
  Future<void> setDeviceNotificationStarred({
    required String ownerPhoneNumber,
    required int id,
    required bool isStarred,
  }) async {
    _notifications = [
      for (final row in _notifications)
        row.id == id ? _copyNotification(row, starred: isStarred) : row,
    ];
  }

  @override
  Future<void> markDeviceNotificationOpened({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    _notifications = [
      for (final row in _notifications)
        row.id == id ? _copyNotification(row, opened: true) : row,
    ];
  }

  @override
  Future<void> markDeviceNotificationUnread({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    _notifications = [
      for (final row in _notifications)
        row.id == id ? _copyNotification(row, opened: false) : row,
    ];
  }

  @override
  Future<void> markAllDeviceNotificationsOpened({
    required String ownerPhoneNumber,
  }) async {
    _notifications = [
      for (final row in _notifications) _copyNotification(row, opened: true),
    ];
  }

  @override
  Future<void> deleteDeviceNotification({
    required String ownerPhoneNumber,
    required int id,
  }) async {
    _notifications.removeWhere((row) => row.id == id);
  }

  @override
  Future<void> clearDeviceNotifications({
    required String ownerPhoneNumber,
    bool includeStarred = true,
  }) async {
    _notifications.removeWhere((row) => includeStarred || !row.isStarred);
  }

  late final debugSessions = <Map<String, Object?>>[
    {
      'id': 'website-demo-debug',
      'owner_phone_number': _phone,
      'started_at': now
          .subtract(const Duration(minutes: 20))
          .toUtc()
          .toIso8601String(),
      'ended_at': now
          .subtract(const Duration(minutes: 18))
          .toUtc()
          .toIso8601String(),
      'status': 'completed',
      'end_reason': 'local demonstration',
      'file_path': '',
    },
  ];
  late final debugEntries = [
    ButtonDebugEntry.fromEvent({
      'timestampMillis': now
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch,
      'direction': 'LOCAL',
      'operation': 'capture_preview',
      'deviceId': 'website-demo-button',
      'characteristic': '',
      'status': 'demo',
      'bytes': <int>[],
      'message':
          'Local demonstration only. No BLE capture or device command was performed.',
    }).toRow('website-demo-debug', 1),
    ButtonDebugEntry.fromEvent({
      'timestampMillis': now
          .subtract(const Duration(minutes: 19))
          .millisecondsSinceEpoch,
      'direction': 'RX',
      'operation': 'sample_status',
      'deviceId': 'website-demo-button',
      'characteristic': '',
      'status': 'demo',
      'bytes': <int>[1, 2, 3],
      'message':
          'Fictional sample payload for the current diagnostic inspector.',
    }).toRow('website-demo-debug', 2),
  ];
  @override
  Future<List<Map<String, Object?>>> loadButtonDebugSessions(
    String owner,
  ) async => debugSessions;
  @override
  Future<List<Map<String, Object?>>> loadButtonDebugEntries(
    String owner,
    String id,
  ) async => debugEntries;
  @override
  Future<String?> loadButtonDebugLog(String owner, String id) async =>
      'HikerCircle Button Debugging\nLocal demonstration only; no radio activity was captured.\n';
}

class _LocalCaptureBle extends HikerBleService {
  const _LocalCaptureBle();
  @override
  Future<List<PairedSosButton>> listPairedSosButtons() async => [];
}

class _LocalButtonDebugController extends ButtonDebugController {
  _LocalButtonDebugController({bool signalReceived = false})
    : super(
        owner: _phone,
        database: _LocalCaptureDatabase(),
        ble: const _LocalCaptureBle(),
      ) {
    final sample = database as _LocalCaptureDatabase;
    sessions = sample.debugSessions;
    liveEntries.addAll(sample.debugEntries);
    if (signalReceived) {
      liveEntries.add(
        ButtonDebugEntry.fromEvent({
          'timestampMillis': DateTime.now().millisecondsSinceEpoch,
          'direction': 'RX',
          'operation': 'paired_button_test_pressed',
          'deviceId': 'DE0000000001',
          'characteristic': '',
          'status': 'simulated',
          'bytes': <int>[1],
          'message':
              'SIMULATED test signal received from the dummy button. No physical BLE packet, pairing write or SOS dispatch occurred.',
        }).toRow('website-demo-debug', 3),
      );
    }
    entryCount = liveEntries.length;
  }
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshHistory() async {}
  @override
  Future<void> start() async => _deny();
  @override
  Future<void> stop([String reason = 'manual_stop']) async {}
}

class _LocalHistoryAlerts extends safety.DemoAlerts {
  @override
  Future<Map<SosAlertMode, String>> loadCustomWhatsAppNotes({
    required AppSession session,
    bool cacheOnly = false,
  }) async => {
    SosAlertMode.manual:
        'Local demo: please call me and share the trail plan with my emergency contacts.',
    SosAlertMode.duress:
        'Local demo: I may be unable to speak safely. Please check discreetly.',
  };
  @override
  Future<Map<SosAlertMode, bool>> loadCustomWhatsAppNoteSyncStates({
    required AppSession session,
  }) async => {SosAlertMode.manual: true, SosAlertMode.duress: true};
  @override
  Future<SosCustomNoteChange> saveCustomWhatsAppNote({
    required AppSession session,
    required SosAlertMode mode,
    required String note,
  }) async => _deny();
  @override
  Future<List<SosAlert>> loadAlertLogs({
    required AppSession session,
    int limit = 30,
  }) async => [
    for (final mode in [SosAlertMode.manual, SosAlertMode.duress])
      SosAlert(
        id: 'website-demo-${mode.name}',
        mode: mode,
        status: SosAlertStatus.sent,
        triggeredAt: DateTime.now().subtract(
          Duration(days: mode == SosAlertMode.manual ? 1 : 2),
        ),
        triggeredByPhoneNumber: _phone,
        contactCount: 3,
        sentCount: 3,
        failedCount: 0,
        dispatches: [
          for (final contact in _contacts)
            SosContactDispatch(
              contactName: contact.name,
              phoneNumber: contact.phoneNumber,
              wasSent: true,
              confirmationStatus: 'confirmed',
            ),
        ],
        message: 'Local demonstration only. No real alert or message was sent.',
        triggerLocation: const SosTriggerLocation(
          latitude: 5.4141,
          longitude: 100.3288,
        ),
      ),
  ];
}

/// Explicit simulation host around unmodified production components. The full
/// PairedSosButtonPage cannot be injected, so this is labelled a component preview.
class _SimulatedButtonHost extends StatefulWidget {
  const _SimulatedButtonHost({
    this.openPairing = false,
    this.initialPaired = false,
  });
  final bool openPairing, initialPaired;
  @override
  State<_SimulatedButtonHost> createState() => _SimulatedButtonHostState();
}

class _SimulatedButtonHostState extends State<_SimulatedButtonHost> {
  final _ble = _SimulatedSetupBle();
  late bool _paired = widget.initialPaired;
  bool _testing = false;
  DateTime _seen = DateTime.now();
  Timer? _testTimer;
  String _status =
      'Current production components · fictional button and local events.';

  @override
  void initState() {
    super.initState();
    if (widget.openPairing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPairing());
      });
    }
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    _ble.disposeSimulation();
    super.dispose();
  }

  Future<void> _openPairing() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .96,
      child: Column(
        children: [
          const _HardwareSimulationNotice(),
          Expanded(
            child: SosButtonPairingSheet(
              ble: _ble,
              onPaired: () async {
                if (mounted) {
                  setState(() {
                    _paired = true;
                    _seen = DateTime.now();
                    _status =
                        'Simulated confirmation signal received. No physical button was paired.';
                  });
                }
              },
            ),
          ),
        ],
      ),
    ),
  );

  void _simulateTest() {
    if (_testing) return;
    setState(() {
      _testing = true;
      _status = 'Waiting for the simulated test signal…';
    });
    _testTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _ble.simulateTestSignal();
      setState(() {
        _testing = false;
        _seen = DateTime.now();
        _status = 'Simulated test signal received · no SOS was sent.';
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PageHeaderAppBar(
      title: Text('SOS button · component preview'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _HardwareSimulationNotice(),
        const SizedBox(height: 18),
        if (_paired)
          PairedSosButtonCard(
            button: PairedSosButton(
              deviceId: 'DE0000000001',
              displayName: 'HikerCircle Demo Button',
              pairedAt: _seen.subtract(const Duration(minutes: 2)),
              lastSeenAt: _seen,
            ),
            checkedAt: DateTime.now(),
            testing: _testing,
            onTest: _testing ? null : _simulateTest,
            onLogs: null,
            onUnpair: null,
          ),
        Text(_status, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _openPairing,
          icon: const Icon(Icons.bluetooth_searching_rounded),
          label: const Text('Open pairing simulation'),
        ),
      ],
    ),
  );
}

class _HardwareSimulationNotice extends StatelessWidget {
  const _HardwareSimulationNotice();
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(12),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        'SIMULATED HARDWARE · no BLE writes or SOS messages',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// Emits local typed events only. Every service method used by the production
/// pairing sheet is overridden; none calls the native BLE MethodChannel.
class _SimulatedSetupBle extends HikerBleService {
  final _events = StreamController<HikerBleEvent>.broadcast();
  Timer? _discovery;
  bool _disposed = false;
  @override
  Stream<HikerBleEvent> get events => _events.stream;
  void _emit(HikerBleEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _status(String value, String message) => _emit(
    HikerBleStatusEvent(
      status: value,
      receivedAt: DateTime.now().toUtc(),
      message: message,
    ),
  );
  @override
  Future<void> startPairedButtonSetupScan() async {
    _discovery?.cancel();
    _discovery = Timer(
      const Duration(milliseconds: 1100),
      () => _emit(
        HikerBlePairedButtonSetupEvent(
          address: 'DE:00:00:00:00:01',
          displayName: 'HikerCircle Demo Button',
          rssi: -48,
          receivedAt: DateTime.now().toUtc(),
          setupModeState: 1,
          setupModeRemainingSeconds: 90,
        ),
      ),
    );
  }

  @override
  Future<void> stopPairedButtonSetupScan() async {
    _discovery?.cancel();
  }

  @override
  Future<void> openBluetoothSettings() async {}
  @override
  Future<void> pairSosButton({
    required String address,
    required String displayName,
  }) async {
    _status(
      'paired_button_pairing_connecting',
      'Simulating a local connection. No Bluetooth request is made.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    _status(
      'paired_button_secure_bond_approved',
      'Simulated connection approved. No bond or key was written.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    _status(
      'paired_button_awaiting_confirmation',
      'Waiting for the simulated button press.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    _status(
      'paired_button_paired',
      'Simulated confirmation signal received from the dummy button.',
    );
  }

  void simulateTestSignal() => _status(
    'paired_button_test_pressed',
    'Simulated test signal received. No real BLE packet or SOS dispatch.',
  );
  void disposeSimulation() {
    _disposed = true;
    _discovery?.cancel();
    unawaited(_events.close());
  }
}
