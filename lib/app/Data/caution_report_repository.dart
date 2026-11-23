part of 'hiker_circle_firebase_repository.dart';

extension CautionReportRepository on HikerCircleFirebaseRepository {
  CautionReportQueue _cautionQueue(
    AppSession session,
  ) => _cautionQueues.putIfAbsent(
    session.phoneNumber,
    () => CautionReportQueue(
      database: _localDatabase,
      owner: session.phoneNumber,
      isOnline: () =>
          NetworkReachabilityService.instance.latest.state !=
          NetworkReachabilityState.offline,
      canSend: () =>
          _firebaseBootstrapResult.isAvailable &&
          _captureAccountUid(session) != null,
      send: (report, media) async {
        final uid = _captureAccountUid(session);
        if (uid == null) throw StateError('The reporting account changed.');
        final uploaded = await TrailCautionService()
            .upload(
              report.reportId,
              media
                  .map(
                    (item) => PendingCautionMedia(
                      file: XFile.fromData(
                        item.bytes,
                        name: item.name,
                        mimeType: item.contentType,
                      ),
                      key: item.key,
                      sizeBytes: item.bytes.length,
                      contentType: item.contentType,
                    ),
                  )
                  .toList(),
              expectedUid: uid,
            )
            .timeout(const Duration(seconds: 30));
        _requireSameAccount(session, uid);
        // Update cloud: upload queued trail caution
        final result = await _resolvedFunctions
            .httpsCallable(
              'submitTrailCaution',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 25),
              ),
            )
            .call({
              ...report.payload,
              'expectedOwnerUid': uid,
              'media': uploaded,
            });
        if (result.data is! Map || result.data['hazardId'] != report.reportId) {
          throw StateError('The server did not confirm this caution report.');
        }
      },
    ),
  );

  Stream<String> get cautionReportChanges => CautionReportQueue.changes;

  Future<List<LocalCautionReport>> loadCautionReportHistory({
    required AppSession session,
  }) => _localDatabase.loadCautionReports(owner: session.phoneNumber);

  Future<void> flushPendingCautionReports({
    required AppSession session,
    bool forceRetry = false,
  }) => _cautionQueue(session).flush(forceRetry: forceRetry);
}
