part of 'hiker_circle_firebase_repository.dart';

final _chatQueueUploads = <String, Future<void>>{};
final _chatRetryTimers = <String, Timer>{};

/// Durable owner writes remain separate from cloud-owned downloaded snapshots.
extension OfflineSyncRepository on HikerCircleFirebaseRepository {
  /// Keeps completed plans and pending cancellations hidden across cached or live snapshots.
  Future<Set<String>> loadLocallyHiddenUpcomingHikeIds(String owner) async {
    final states = await _localDatabase.loadPlannedHikeStates(
      ownerPhoneNumber: owner,
    );
    final dirty = await _localDatabase.loadDirtyLocalPreferences(
      ownerPhoneNumber: owner,
    );
    final hidden = {
      for (final state in states)
        if (state.isConsumed) state.upcomingHike.id,
    };
    // A restored active team session also fences an older offline plan cache.
    final active = await _localDatabase.loadActiveHikeSession(
      phoneNumber: owner,
    );
    if (active != null &&
        active.teamHikeSessionId.isNotEmpty &&
        active.sourceUpcomingHikeId.isNotEmpty) {
      hidden.add(active.sourceUpcomingHikeId);
    }
    for (final entry in dirty.entries) {
      if (!entry.key.startsWith('pending_hike_cancellation:') ||
          entry.value is! Map) {
        continue;
      }
      final intent = entry.value as Map;
      final hikeId = intent['hikeId'];
      if (hikeId is String && hikeId.isNotEmpty) hidden.add(hikeId);
      final creationKey = intent['creationKey'];
      if (creationKey is String && creationKey.isNotEmpty) {
        hidden.add(
          'upcoming_${crypto.sha256.convert(utf8.encode('$owner:$creationKey')).toString().substring(0, 40)}',
        );
      }
    }
    return hidden;
  }

  /// Stops scheduled attempts when the owning account or test lifecycle ends.
  @visibleForTesting
  void cancelQueuedChatRetries(String owner) {
    _chatRetryTimers.remove(owner)?.cancel();
  }

  /// Hides a cancelled plan locally before any network attempt, retaining a replayable intent.
  Future<void> _queuePlanCancellation(
    String hikeId,
    bool withdrawSelf,
    String? hazardId,
    UpcomingHike? snapshot,
  ) async {
    final session = await _localDatabase.loadSession();
    if (session == null) throw _accountChangedForChat();
    if (snapshot != null &&
        await _localPlanningState(session, hikeId) == null) {
      await _localDatabase.saveUpcomingHikesForPlanning(
        ownerPhoneNumber: session.phoneNumber,
        upcomingHikes: [snapshot],
      );
    }
    final resolvedId = await _localDatabase.resolvePlannedHikeId(
      ownerPhoneNumber: session.phoneNumber,
      hikeId: hikeId,
    );
    final state = await _localPlanningState(session, resolvedId);
    final archive = !withdrawSelf;
    if (archive &&
        state != null &&
        state.upcomingHike.creatorPhone != session.phoneNumber) {
      throw const HikerCircleFirebaseRepositoryException(
        'Only the host can remove this hike.',
      );
    }
    final intent = <String, Object?>{
      'hikeId': resolvedId,
      'withdrawSelf': withdrawSelf,
      if (archive) 'archiveAsExpired': true,
      if (archive && state?.scheduleSyncPending == true)
        'uploadCancelledHistory': true,
      if (hazardId != null) 'hazardId': hazardId,
      'wasConsumed': state?.isConsumed ?? false,
      if (archive &&
          state != null &&
          state.creationKey.isNotEmpty &&
          (state.scheduleSyncPending ||
              resolvedId ==
                  'upcoming_${crypto.sha256.convert(utf8.encode('${session.phoneNumber}:${state.creationKey}')).toString().substring(0, 40)}'))
        'creationKey': state.creationKey,
      if (archive && state?.upcomingHike.draft != null) ...{
        'draft': state!.upcomingHike.draft!.toPersistence(),
        'createdAtLocal': state.upcomingHike.createdAt
            .toUtc()
            .toIso8601String(),
        'joinPolicy': state.joinPolicy,
      },
    };
    await _localDatabase.queuePlannedHikeCancellation(
      owner: session.phoneNumber,
      hikeId: resolvedId,
      intent: intent,
      archiveAsExpired: archive,
    );
    HikerCircleFirebaseRepository._planningChanges.add(session.phoneNumber);
    if (_firebaseBootstrapResult.isAvailable) {
      unawaited(_flushPlanCancellations(session).catchError((Object _) {}));
    }
  }

  /// Cloud lifecycle decisions override a pending cancellation if the hike already started.
  Future<void> _flushPlanCancellations(
    AppSession session, {
    Set<String>? confirmedHikes,
  }) async {
    final synced = confirmedHikes ?? <String>{};
    try {
      final owner = session.phoneNumber;
      final dirty = await _localDatabase.loadDirtyLocalPreferences(
        ownerPhoneNumber: owner,
      );
      for (final entry in dirty.entries.where(
        (e) => e.key.startsWith('pending_hike_cancellation:'),
      )) {
        if (entry.value is! Map) continue;
        final intent = Map<String, dynamic>.from(entry.value as Map);
        final localId = intent['hikeId'] as String;
        final creationKey = intent['creationKey'] as String?;
        final cloudId = creationKey == null
            ? localId
            : 'upcoming_${crypto.sha256.convert(utf8.encode('$owner:$creationKey')).toString().substring(0, 40)}';
        var cancellationCommitted = false;
        try {
          final cancellation = await _syncWrite('cancelUpcomingHike', owner, {
            'hikeId': cloudId,
            'withdrawSelf': intent['withdrawSelf'],
            if (intent['archiveAsExpired'] == true) 'archiveAsExpired': true,
            if (intent['cancelledAtLocal'] != null)
              'cancelledAtLocal': intent['cancelledAtLocal'],
            if (creationKey != null) 'creationKey': creationKey,
            if (intent['hazardId'] != null) 'hazardId': intent['hazardId'],
          });
          cancellationCommitted = true;
          // A cancellation tombstone fences any in-flight ordinary creation.
          // Then create the full offline plan directly in its cancelled state.
          if (creationKey != null &&
              intent['archiveAsExpired'] == true &&
              (intent['uploadCancelledHistory'] == true ||
                  cancellation['needsHistoryUpload'] == true)) {
            if (intent['draft'] is! Map) {
              throw StateError('Saved cancelled plan is incomplete.');
            }
            final payload = <String, dynamic>{
              'creationKey': creationKey,
              'draft': intent['draft'],
              'joinPolicy': intent['joinPolicy'] ?? 'approval',
              'cancelledRecovery': true,
              'offlineRecovery': {'createdAtLocal': intent['createdAtLocal']},
            };
            final request = _scheduleHikeRequest;
            final confirmedId =
                await (request != null
                        ? request(payload)
                        : _resolvedFunctions
                              .httpsCallable('scheduleUpcomingHike')
                              .call<Map<String, dynamic>>(payload)
                              .then(
                                (result) => _stringFrom(result.data['hikeId']),
                              ))
                    .timeout(
                      HikerCircleFirebaseRepository._firebaseReadTimeout,
                    );
            if (confirmedId != cloudId) {
              throw StateError('Cancelled schedule identity changed.');
            }
            if (await _cloudReadOwner() != owner) {
              throw _accountChangedForChat();
            }
            await _localDatabase.confirmScheduledHike(
              ownerPhoneNumber: owner,
              creationKey: creationKey,
              cloudHikeId: confirmedId,
            );
          }
          final acknowledged = await _localDatabase.clearLocalPreferenceIfValue(
            ownerPhoneNumber: owner,
            key: entry.key,
            expectedValue: entry.value,
          );
          if (acknowledged) synced.add(cloudId);
          await _invalidateReadModel(owner, 'my_upcoming_hikes');
          await _conditionalCache.invalidateTypes(
            owner: owner,
            types: {'expired_hike_history_page'},
          );
        } on FirebaseFunctionsException catch (error) {
          if (cancellationCommitted &&
              creationKey != null &&
              intent['archiveAsExpired'] == true) {
            rethrow;
          }
          if (!{
            'permission-denied',
            'failed-precondition',
            'not-found',
          }.contains(error.code)) {
            rethrow;
          }
          await _localDatabase.saveLocalPreference(
            ownerPhoneNumber: owner,
            key: entry.key,
            value: null,
          );
          if (error.code != 'not-found') {
            await _localDatabase.restoreRejectedPlannedCancellation(
              owner: owner,
              hikeId: localId,
              intent: intent,
            );
          }
        }
        HikerCircleFirebaseRepository._planningChanges.add(owner);
      }
    } finally {
      if (confirmedHikes == null) _publishUpcomingHikeSync(session, synced);
    }
  }

  /// Bounds an attempt and prevents responses for a displaced account from acknowledging data.
  Future<Map<String, dynamic>> _syncWrite(
    String name,
    String owner,
    Map<String, Object?> data,
  ) async {
    if (await _cloudReadOwner() != owner) throw _accountChangedForChat();
    final request = _syncRequest;
    final result =
        await (request != null
                ? request(name, {...data, 'expectedOwner': owner})
                : _resolvedFunctions
                      .httpsCallable(
                        name,
                        options: HttpsCallableOptions(
                          timeout: const Duration(seconds: 10),
                        ),
                      )
                      .call<Map<String, dynamic>>({
                        ...data,
                        'expectedOwner': owner,
                      })
                      .then((r) => r.data))
            .timeout(const Duration(seconds: 12));
    if (await _cloudReadOwner() != owner) throw _accountChangedForChat();
    return result;
  }

  /// Stores the original content, timestamp and attachment before any network operation.
  Future<void> _queueChatMessage({
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
  }) async {
    if (await _cloudReadOwner() != senderPhone) throw _accountChangedForChat();
    if ((attachmentBytes?.length ?? 0) > 25 * 1024 * 1024) {
      throw const HikerCircleFirebaseRepositoryException(
        'Attachments must be 25 MB or smaller.',
      );
    }
    await _localDatabase.insertPendingMessage(
      localId: localId,
      chatId: chatId,
      senderPhone: senderPhone,
      senderName: senderName.isEmpty ? 'Hiker' : senderName,
      text: text,
      sentAt: sentAt,
      ownerPhoneNumber: senderPhone,
      firestoreDocId: _firestoreMessageIdForLocalId(localId),
      sharedPost: sharedPost?.toMap(),
      attachment: attachment?.url.startsWith('pending://') == true
          ? null
          : attachment?.toFirestore(),
      attachmentBytes: attachmentBytes,
      attachmentUpload: attachmentUpload,
    );
    unawaited(_flushQueuedChats(senderPhone).catchError((Object _) {}));
  }

  /// Coalesces chat retries per account without holding the shared read cache.
  Future<void> _flushQueuedChats(String? requestedOwner) async {
    if (!_firebaseBootstrapResult.isAvailable && _syncRequest == null) return;
    final owner = requestedOwner ?? await _cloudReadOwner();
    if (await _cloudReadOwner() != owner) return;
    _chatRetryTimers.remove(owner)?.cancel();
    final existing = _chatQueueUploads[owner];
    if (existing != null) return existing;
    final work = _uploadQueuedChats(owner);
    _chatQueueUploads[owner] = work;
    try {
      await work;
    } finally {
      final remaining = await _localDatabase.loadPendingMessages(
        ownerPhoneNumber: owner,
      );
      if (remaining.any(
        (row) => !{
          'permission-denied',
          'already-exists',
          'invalid-argument',
        }.contains(row['last_error']),
      )) {
        final retries = remaining
            .map((row) => (row['retry_count'] as num).toInt())
            .reduce(math.min);
        final delay = retries == 0
            ? Duration.zero
            : Duration(
                seconds: math
                    .min(300, 30 * math.pow(2, math.min(4, retries - 1)))
                    .toInt(),
              );
        _chatRetryTimers[owner] = Timer(delay, () {
          unawaited(_flushQueuedChats(owner).catchError((Object _) {}));
        });
      }
      if (identical(_chatQueueUploads[owner], work)) {
        _chatQueueUploads.remove(owner);
      }
    }
  }

  /// Appends stable identities and clears bytes only after a matching cloud acknowledgement.
  Future<void> _uploadQueuedChats(String owner) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    for (final row in await _localDatabase.loadPendingMessages(
      ownerPhoneNumber: owner,
    )) {
      if (DateTime.now().isAfter(deadline) ||
          await _cloudReadOwner() != owner) {
        break;
      }
      final id = row['local_id'] as String, chatId = row['chat_id'] as String;
      final cloudId = (row['firestore_doc_id'] as String?)?.isNotEmpty == true
          ? row['firestore_doc_id'] as String
          : id;
      try {
        var attachment = _attachmentFromLocalRow(row);
        if ((attachment == null || attachment.url.startsWith('pending://')) &&
            row['attachment_bytes'] is Uint8List &&
            (row['attachment_upload_json'] as String? ?? '').isNotEmpty) {
          final upload = Map<String, dynamic>.from(
            jsonDecode(row['attachment_upload_json'] as String) as Map,
          );
          attachment = await uploadGroupChatAttachment(
            chatId: chatId,
            senderPhone: owner,
            type: ChatAttachmentType.values.byName(upload['type'] as String),
            bytes: row['attachment_bytes'] as Uint8List,
            fileName: upload['fileName'] as String,
            contentType: upload['contentType'] as String,
            stableMessageId: id,
          );
          await _localDatabase.saveUploadedChatAttachment(
            owner,
            chatId,
            id,
            attachment.toFirestore(),
          );
        }
        final message = ChatMessage(
          id: id,
          chatId: chatId,
          senderPhone: owner,
          senderName: row['sender_name'] as String,
          text: row['text'] as String,
          sentAt: DateTime.parse(row['created_at'] as String),
          attachment: attachment,
          sharedPost: _sharedPostFromLocalRow(row),
        );
        final response = await _syncWrite('appendChatMessage', owner, {
          'chatId': chatId,
          'messageId': cloudId,
          'message': message.toFirestore(),
        });
        if (response['confirmed'] != true ||
            response['messageId'] != (cloudId)) {
          throw const FormatException('The message was not acknowledged.');
        }
        await _localDatabase.updateLocalMessageStatus(
          id,
          'sent',
          ownerPhoneNumber: owner,
          chatId: chatId,
          firestoreDocId: response['messageId'] as String,
          attachment: attachment?.toFirestore(),
          sentAt: DateTime.tryParse(response['sentAtLocal'] as String? ?? ''),
        );
      } catch (error) {
        await _localDatabase.updateLocalMessageStatus(
          id,
          'failed',
          ownerPhoneNumber: owner,
          chatId: chatId,
          lastError: error is FirebaseFunctionsException
              ? error.code
              : error.runtimeType.toString(),
        );
        await _localDatabase.incrementPendingMessageRetry(
          id,
          ownerPhoneNumber: owner,
          chatId: chatId,
        );
        // A failed connection should not produce one timeout for every queued message.
        if (error is! FirebaseFunctionsException ||
            !{
              'permission-denied',
              'already-exists',
              'invalid-argument',
            }.contains(error.code)) {
          break;
        }
      }
    }
  }

  /// A late receipt acknowledgement cannot mark a newer local read as synchronized.
  Future<void> _uploadChatReceipt(
    String chatId,
    String owner,
    DateTime read,
  ) async {
    if (!_firebaseBootstrapResult.isAvailable && _syncRequest == null) return;
    try {
      final response = await _syncWrite('acknowledgeChatRead', owner, {
        'chatId': chatId,
        'readAtLocal': read.toUtc().toIso8601String(),
      });
      if (response['confirmed'] == true) {
        await _localDatabase.markChatReadReceiptSynced(
          chatId,
          ownerPhoneNumber: owner,
          expectedLastReadAt: read,
        );
      }
    } catch (_) {
      /* Keep the exact receipt pending after an unavailable attempt. */
    }
  }
}
