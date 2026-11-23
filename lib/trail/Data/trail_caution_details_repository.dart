import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../Model/caution_update.dart';
import '../Model/community_hazard.dart';
import 'trail_caution_service.dart';

/// Supplies live caution data and account-scoped confirmations to the ViewModel.
abstract class TrailCautionDetailsRepository {
  /// Watches the signed-in account rather than inferring ownership from names.
  Stream<String?> watchViewer();

  /// Watches the authoritative report, emitting null when it is unavailable.
  Stream<CommunityHazard?> watchReport(String hazardId);

  /// Watches the same thirty most recent hiker updates as the existing sheet.
  Stream<List<CautionUpdate>> watchUpdates(String hazardId);

  /// Watches only votes owned by the viewer in the current report cycle.
  Stream<CautionViewerVotes> watchVotes(String hazardId, String uid, int cycle);

  /// Sends a confirmation through the existing server-owned caution workflow.
  Future<bool> confirm(String hazardId, String action);
}

/// Reads existing caution documents without changing the cloud schema or rules.
class FirebaseTrailCautionDetailsRepository
    implements TrailCautionDetailsRepository {
  /// Creates the Firebase-backed caution reader.
  const FirebaseTrailCautionDetailsRepository();

  /// Watches Firebase account changes while the sheet is open.
  @override
  Stream<String?> watchViewer() => Firebase.apps.isEmpty
      ? Stream.value(null)
      : FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  /// Keeps the initial report usable when Firebase is unavailable.
  @override
  Stream<CommunityHazard?> watchReport(String hazardId) => Firebase.apps.isEmpty
      ? const Stream.empty()
      // Query live trail hazard by ID
      : FirebaseFirestore.instance
            .collection('hazardReports')
            .doc(hazardId)
            .snapshots()
            .map(
              (snapshot) => snapshot.exists
                  ? CommunityHazard.fromMap(
                      hazardId,
                      snapshot.data() ?? {},
                      includeExpired: true,
                    )
                  : null,
            );

  /// Decodes updates independently of widget rendering.
  @override
  Stream<List<CautionUpdate>> watchUpdates(String hazardId) =>
      Firebase.apps.isEmpty
      ? Stream.value(const [])
      // Query live trail hazard updates
      : FirebaseFirestore.instance
            .collection('hazardReports')
            .doc(hazardId)
            .collection('updates')
            .orderBy('createdAt', descending: true)
            .limit(30)
            .snapshots()
            .map(
              (snapshot) => [
                for (final document in snapshot.docs)
                  CautionUpdate.fromMap(document.id, document.data()),
              ],
            );

  /// Uses the existing uid read rule and avoids querying anyone else's votes.
  @override
  Stream<CautionViewerVotes> watchVotes(
    String hazardId,
    String uid,
    int cycle,
  ) => Firebase.apps.isEmpty
      ? Stream.value(const CautionViewerVotes())
      // Query hiker's trail hazard votes
      : FirebaseFirestore.instance
            .collection('hazardReports')
            .doc(hazardId)
            .collection('votes')
            .where('uid', isEqualTo: uid)
            .snapshots(includeMetadataChanges: true)
            .map((snapshot) {
              final votes = snapshot.docs
                  .map((document) => document.data())
                  .where(
                    (data) => data['uid'] == uid && data['cycle'] == cycle,
                  );
              return CautionViewerVotes(
                confirmed: votes.any((data) => data['kind'] == 'confirm'),
                resolutionConfirmed: votes.any(
                  (data) => data['kind'] == 'resolution',
                ),
                authoritative: !snapshot.metadata.isFromCache,
              );
            });

  /// Retains server-side duplicate handling and stable request identities.
  @override
  Future<bool> confirm(String hazardId, String action) => TrailCautionService()
      .update(hazardId, action, requestId: newCautionUpdateId());
}

/// Creates the same request identity format for evidence and confirmation actions.
String newCautionUpdateId() =>
    'update_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
