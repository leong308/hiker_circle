import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../trail/Model/caution_update.dart';
import '../Model/admin_hazard_report.dart';

/// Read-only data needed by the admin Safety workspace.
abstract interface class AdminSafetyRepository {
  /// Watches all lifecycle metadata, including reports that have expired.
  Stream<List<AdminHazardReport>> watchReports();

  /// Watches the latest evidence and confirmations for one report.
  Stream<List<CautionUpdate>> watchUpdates(String hazardId);
}

/// Scopes the Safety streams to the currently signed-in administrator.
class FirebaseAdminSafetyRepository implements AdminSafetyRepository {
  /// Reuses the app repository's authorization and account guards.
  const FirebaseAdminSafetyRepository(this.repository, this.session);
  final HikerCircleFirebaseRepository repository;
  final AppSession session;

  /// Decodes report metadata without modifying the community workflow.
  @override
  Stream<List<AdminHazardReport>> watchReports() => repository
      .watchAdminHazardReports(session: session)
      .map(
        (rows) => rows
            .map((row) => AdminHazardReport(row['hazardId'] as String, row))
            .toList(),
      );

  /// Keeps the report's update history live while its details are open.
  @override
  Stream<List<CautionUpdate>> watchUpdates(String hazardId) => repository
      .watchAdminHazardUpdates(session: session, hazardId: hazardId)
      .map(
        (rows) => rows
            .map((row) => CautionUpdate.fromMap(row['id'] as String, row))
            .toList(),
      );
}
