part of '../hiker_home_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _HikerHomePageDataActions {
  /// Binds ensure active hike session in cloud to the selected data source.
  static Future<ActiveHikeCloudRestoreResult> Function({
    required ActiveHikeSession activeHike,
    required AppSession session,
  })
  ensureActiveHikeSessionInCloud(HikerCircleFirebaseRepository receiver) =>
      receiver.ensureActiveHikeSessionInCloud;

  /// Binds watch pending trail requests to the selected data source.
  static Stream<bool> Function({required AppSession session})
  watchPendingTrailRequests(HikerCircleFirebaseRepository receiver) =>
      receiver.watchPendingTrailRequests;

  /// Binds flush pending upcoming hikes to the selected data source.
  static Future<void> Function({required AppSession session})
  flushPendingUpcomingHikes(HikerCircleFirebaseRepository receiver) =>
      receiver.flushPendingUpcomingHikes;

  /// Binds flush pending hike ends to the selected data source.
  static Future<int> Function({int limit, required AppSession session})
  flushPendingHikeEnds(HikerCircleFirebaseRepository receiver) =>
      receiver.flushPendingHikeEnds;

  /// Binds mark formed hike group naming prompt shown to the selected data source.
  static Future<bool> Function({
    required String chatId,
    required String defaultName,
  })
  markFormedHikeGroupNamingPromptShown(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.markFormedHikeGroupNamingPromptShown;

  /// Binds load group chat by id to the selected data source.
  static Future<GroupChat?> Function(String) loadGroupChatById(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadGroupChatById;

  /// Binds flush footprints to the selected data source.
  static Future<int> Function({
    required ActiveHikeSession activeHike,
    int limit,
    required AppSession session,
  })
  flushFootprints(HikerCircleFirebaseRepository receiver) =>
      receiver.flushFootprints;

  /// Binds migrate active hike session id to the selected data source.
  static Future<ActiveHikeSession> Function({
    required ActiveHikeSession activeHike,
    required String newSessionId,
    required String ownerPhoneNumber,
  })
  migrateActiveHikeSessionId(LocalSessionDatabase receiver) =>
      receiver.migrateActiveHikeSessionId;

  /// Binds load active hike session to the selected data source.
  static Future<ActiveHikeSession?> Function({required String phoneNumber})
  loadActiveHikeSession(LocalSessionDatabase receiver) =>
      receiver.loadActiveHikeSession;

  /// Binds load my upcoming hikes to the selected data source.
  static Future<List<UpcomingHike>> Function(String) loadMyUpcomingHikes(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadMyUpcomingHikes;

  /// Binds load cached achievement progress to the selected data source.
  static Future<LocalAchievementProgressCache?> Function({
    required AppSession session,
  })
  loadCachedAchievementProgress(HikerCircleFirebaseRepository receiver) =>
      receiver.loadCachedAchievementProgress;

  /// Binds load achievement notification to the selected data source.
  static Future<Map<String, dynamic>?> Function(String, String)
  loadAchievementNotification(LocalSessionDatabase receiver) =>
      receiver.loadAchievementNotification;

  /// Binds load planned hike states to the selected data source.
  static Future<List<LocalPlannedHikeState>> Function({
    required String ownerPhoneNumber,
  })
  loadPlannedHikeStates(LocalSessionDatabase receiver) =>
      receiver.loadPlannedHikeStates;

  /// Binds load upcoming hike by id to the selected data source.
  static Future<UpcomingHike?> Function(String) loadUpcomingHikeById(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadUpcomingHikeById;

  /// Binds load participant upcoming hike for safety to the selected data source.
  static Future<UpcomingHike?> Function({
    required String hikeId,
    required AppSession session,
  })
  loadParticipantUpcomingHikeForSafety(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadParticipantUpcomingHikeForSafety;

  /// Binds load trails to the selected data source.
  static Future<List<Trail>> Function() loadTrails(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadTrails;

  /// Binds load upcoming hike join request to the selected data source.
  static Future<UpcomingHikeJoinRequestReview> Function(String)
  loadUpcomingHikeJoinRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.loadUpcomingHikeJoinRequest;

  /// Binds resolve upcoming hike join request to the selected data source.
  static Future<UpcomingHikeJoinRequestReview> Function({
    required bool accept,
    required String requestId,
  })
  resolveUpcomingHikeJoinRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.resolveUpcomingHikeJoinRequest;

  /// Binds set upcoming hike join policy to the selected data source.
  static Future<void> Function({
    required String hikeId,
    required String joinPolicy,
  })
  setUpcomingHikeJoinPolicy(HikerCircleFirebaseRepository receiver) =>
      receiver.setUpcomingHikeJoinPolicy;

  /// Binds current buddy relationships to the selected data source.
  static Future<BuddyRelationships> Function({
    required AppSession session,
    bool force,
  })
  loadBuddyRelationships(HikerCircleFirebaseRepository receiver) =>
      receiver.loadBuddyRelationships;

  /// Binds send buddy request to the selected data source.
  static Future<void> Function({
    required String buddyPhoneNumber,
    required AppSession session,
  })
  sendBuddyRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.sendBuddyRequest;

  /// Binds create trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  createTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.createTrailByAdmin;

  /// Binds update trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  updateTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.updateTrailByAdmin;

  /// Binds delete trail by admin to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required Trail trail,
  })
  deleteTrailByAdmin(HikerCircleFirebaseRepository receiver) =>
      receiver.deleteTrailByAdmin;

  /// Binds create active hike session to the selected data source.
  static Future<ActiveHikeSession> Function({
    required HikeSessionDraft draft,
    required AppSession session,
    String sourceUpcomingHikeId,
    TeamHikeSession? teamHikeSession,
    String teamHikeSessionId,
  })
  createActiveHikeSession(HikerCircleFirebaseRepository receiver) =>
      receiver.createActiveHikeSession;

  /// Binds create team hike session to the selected data source.
  static Future<TeamHikeSession> Function({
    required HikeSessionDraft draft,
    required AppSession session,
    String sourceUpcomingHikeId,
  })
  createTeamHikeSession(HikerCircleFirebaseRepository receiver) =>
      receiver.createTeamHikeSession;

  /// Binds begin team hike readiness to the selected data source.
  static Future<TeamHikeSession> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  beginTeamHikeReadiness(HikerCircleFirebaseRepository receiver) =>
      receiver.beginTeamHikeReadiness;

  /// Binds cancel team hike session to the selected data source.
  static Future<void> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  cancelTeamHikeSession(HikerCircleFirebaseRepository receiver) =>
      receiver.cancelTeamHikeSession;

  /// Binds ping team participant to the selected data source.
  static Future<TeamHikeSession> Function({
    required String participantPhoneNumber,
    required AppSession session,
    required String teamHikeSessionId,
  })
  pingTeamParticipant(HikerCircleFirebaseRepository receiver) =>
      receiver.pingTeamParticipant;

  /// Binds load trail hazard assessment to the selected data source.
  static Future<TrailHazardAssessment> Function(String)
  loadTrailHazardAssessment(HikerCircleFirebaseRepository receiver) =>
      receiver.loadTrailHazardAssessment;

  /// Binds cancel upcoming hike to the selected data source.
  static Future<void> Function({
    String? hazardId,
    required String hikeId,
    bool withdrawSelf,
    UpcomingHike? snapshot,
  })
  cancelUpcomingHike(HikerCircleFirebaseRepository receiver) =>
      receiver.cancelUpcomingHike;

  /// Binds mark planned hike consumed to the selected data source.
  static Future<void> Function({
    required String ownerPhoneNumber,
    required String upcomingHikeId,
  })
  markPlannedHikeConsumed(LocalSessionDatabase receiver) =>
      receiver.markPlannedHikeConsumed;

  /// Binds load team hike session to the selected data source.
  static Future<TeamHikeSession?> Function(String) loadTeamHikeSession(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.loadTeamHikeSession;

  /// Binds accept team hike invite to the selected data source.
  static Future<TeamHikeSession> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  acceptTeamHikeInvite(HikerCircleFirebaseRepository receiver) =>
      receiver.acceptTeamHikeInvite;

  /// Binds respond to team ping to the selected data source.
  static Future<TeamHikeSession> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  respondToTeamPing(HikerCircleFirebaseRepository receiver) =>
      receiver.respondToTeamPing;

  /// Binds end hike session to the selected data source.
  static Future<ActiveHikeEndResult> Function({
    required ActiveHikeSession activeHike,
    required AppSession session,
    HikeSummaryReport? summary,
  })
  endHikeSession(HikerCircleFirebaseRepository receiver) =>
      receiver.endHikeSession;

  /// Binds record path deviation alert to the selected data source.
  static Future<void> Function({
    required ActiveHikeSession activeHike,
    required HikeCoordinate coordinate,
    required double distanceMeters,
    required AppSession session,
  })
  recordPathDeviationAlert(HikerCircleFirebaseRepository receiver) =>
      receiver.recordPathDeviationAlert;

  /// Binds record footprint to the selected data source.
  static Future<int> Function({
    required ActiveHikeSession activeHike,
    int? batteryLevel,
    required SosTriggerLocation location,
    required String pointType,
    DateTime? recordedAt,
    required AppSession session,
  })
  recordFootprint(HikerCircleFirebaseRepository receiver) =>
      receiver.recordFootprint;

  /// Binds migrate hike telemetry session id to the selected data source.
  static Future<void> Function({
    required String newSessionId,
    required String oldSessionId,
    required String ownerPhoneNumber,
  })
  migrateHikeTelemetrySessionId(LocalSessionDatabase receiver) =>
      receiver.migrateHikeTelemetrySessionId;

  /// Binds name formed hike group chat to the selected data source.
  static Future<void> Function({required String chatId, required String name})
  nameFormedHikeGroupChat(HikerCircleFirebaseRepository receiver) =>
      receiver.nameFormedHikeGroupChat;

  /// Binds rating persistence with its local hike completion to the data source.
  static Future<void> Function({
    required String difficulty,
    required int rating,
    required AppSession session,
    required ActiveHikeSession activeHike,
    required HikeSummaryReport summary,
  })
  submitEndedHikeRating(HikerCircleFirebaseRepository receiver) =>
      receiver.submitEndedHikeRating;

  /// Binds create ended hike post to the selected data source.
  static Future<void> Function({
    required ActiveHikeSession activeHike,
    required String caption,
    required ActiveHikeEndResult endResult,
    List<CommunityPostImageUpload> images,
    String? postId,
    required AppSession session,
    required HikeSummaryReport summary,
  })
  createEndedHikePost(HikerCircleFirebaseRepository receiver) =>
      receiver.createEndedHikePost;

  /// Binds watch team hike session to the selected data source.
  static Stream<TeamHikeSession?> Function(String) watchTeamHikeSession(
    HikerCircleFirebaseRepository receiver,
  ) => receiver.watchTeamHikeSession;

  /// Binds load community profile to the selected data source.
  static Future<Map<String, dynamic>?> Function({
    String phoneNumber,
    String userId,
  })
  loadCommunityProfile(HikerCircleFirebaseRepository receiver) =>
      receiver.loadCommunityProfile;

  /// Binds mark team participant ready to the selected data source.
  static Future<TeamHikeSession> Function({
    required Map<String, dynamic> safetySettings,
    required AppSession session,
    required String teamHikeSessionId,
  })
  markTeamParticipantReady(HikerCircleFirebaseRepository receiver) =>
      receiver.markTeamParticipantReady;

  /// Binds remove pending team invitees to the selected data source.
  static Future<TeamHikeSession> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  removePendingTeamInvitees(HikerCircleFirebaseRepository receiver) =>
      receiver.removePendingTeamInvitees;

  /// Binds activate team hike session to the selected data source.
  static Future<TeamHikeSession> Function({
    required AppSession session,
    required String teamHikeSessionId,
  })
  activateTeamHikeSession(HikerCircleFirebaseRepository receiver) =>
      receiver.activateTeamHikeSession;

  /// Binds load team safety preferences to the selected data source.
  static Future<Map<String, dynamic>?> Function({required AppSession session})
  loadTeamSafetyPreferences(HikerCircleFirebaseRepository receiver) =>
      receiver.loadTeamSafetyPreferences;

  /// Binds save team safety preferences to the selected data source.
  static Future<void> Function({
    required Map<String, dynamic> preferences,
    required AppSession session,
  })
  saveTeamSafetyPreferences(HikerCircleFirebaseRepository receiver) =>
      receiver.saveTeamSafetyPreferences;
}
