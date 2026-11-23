// FeedbackRepository validates feedback and uploads one stable draft across retries.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../app/Data/conditional_cloud_cache.dart';
import '../app/Data/firebase_bootstrap.dart';
import '../app/Data/local_session_database.dart';
import 'Data/feedback_draft_store.dart';
import 'Model/feedback_saved_draft.dart';
import 'Model/feedback_report.dart';
export 'Model/feedback_saved_draft.dart' show FeedbackSavedDraft;
export 'Model/feedback_report.dart'
    show feedbackCategories, feedbackStatuses, feedbackImageLimit;

/// Computes feedback submission error.
String feedbackSubmissionError(Object error) {
  if (error is TimeoutException) {
    return 'We could not confirm delivery yet. Retry to check and send the same report without creating a duplicate.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unauthorized':
      case 'permission-denied':
        return 'Firebase denied access to send this report. This is a permission issue, not your connection. Your report is still here; please retry after support resolves it.';
      case 'unauthenticated':
      case 'user-not-authenticated':
        return 'Your sign-in session is unavailable. Please sign in again before sending feedback.';
      case 'unavailable':
      case 'network-request-failed':
      case 'retry-limit-exceeded':
        return 'The feedback service could not be reached. Please retry. Your report is still here.';
    }
  }
  return 'Feedback could not be sent. Please retry. Your report is still here.';
}

/// Validates feedback.
String? validateFeedback(String? value) {
  final text = value?.trim() ?? '';
  if (text.length < 10) return 'Please add at least 10 characters of detail.';
  if (text.length > 4000) {
    return 'Please keep your feedback within 4,000 characters.';
  }
  return null;
}

/// One immutable draft ID is reused on retries, including ambiguous timeouts.
class FeedbackDraft {
  /// Creates feedback draft.
  FeedbackDraft({
    required this.id,
    required this.uid,
    required this.category,
    required this.message,
    this.screenshot,
  });
  final String id;
  final String uid;
  final String category;
  final String message;
  final Uint8List? screenshot;
}

class _FeedbackSubmission {
  const _FeedbackSubmission(this.payloadHash, this.result);
  final String payloadHash;
  final Future<void> result;
}

/// Keep submission validation and upload error mapping outside the feedback screens.
class FeedbackRepository {
  FeedbackRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LocalSessionDatabase? localDatabase,
    ConditionalCloudCache? cache,
    String? Function()? currentOwner,
  }) : _firestore = firestore,
       _functions = functions,
       _localDatabase = localDatabase ?? LocalSessionDatabase(),
       _providedCache = cache,
       _currentOwner = currentOwner;

  static const cacheType = 'my_feedback';
  static const cacheId = 'latest-100';
  static final _submissions = <String, _FeedbackSubmission>{};
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final LocalSessionDatabase _localDatabase;
  final ConditionalCloudCache? _providedCache;
  final String? Function()? _currentOwner;
  late final FeedbackDraftStore _draftStore = FeedbackDraftStore(
    _localDatabase,
  );
  late final ConditionalCloudCache _cache =
      _providedCache ??
      ConditionalCloudCache(
        _localDatabase,
        () => _functions ?? FirebaseFunctions.instance,
        currentOwner: _currentOwner,
      );

  String _owner() {
    final owner = _currentOwner != null
        ? _currentOwner()
        : FirebaseBootstrap.requireAuthenticatedUser().uid;
    if (owner == null || owner.isEmpty) {
      throw StateError('Please sign in before loading feedback.');
    }
    return owner;
  }

  void _requireOwner(String owner) {
    if (_owner() != owner) {
      throw StateError('The signed-in account changed.');
    }
  }

  /// Restoring unfinished writing needs only the account saved on this device.
  Future<String> _localDraftOwner() async {
    String? readAuthenticatedOwner() {
      if (_currentOwner != null) {
        final owner = _currentOwner();
        if (owner == null || owner.isEmpty) {
          throw StateError('Please sign in before writing feedback.');
        }
        return owner;
      }
      try {
        return FirebaseBootstrap.requireAuthenticatedUser().uid;
      } catch (_) {
        // Firebase may not have initialized during an offline app restoration.
        return null;
      }
    }

    final before = readAuthenticatedOwner();
    String? local;
    try {
      local = (await _localDatabase.loadSession())?.phoneNumber;
    } catch (_) {
      // Browser drafts use IndexedDB; the native SQLite session store is absent.
      if (!kIsWeb || before == null) rethrow;
    }
    final authenticated = readAuthenticatedOwner();
    if (before != null && before != authenticated) {
      throw StateError('The signed-in account changed.');
    }
    if (authenticated != null && local != null && authenticated != local) {
      throw StateError('The signed-in account changed.');
    }
    final owner = authenticated ?? local;
    if (owner == null || owner.isEmpty) {
      throw StateError('Please sign in before writing feedback.');
    }
    return owner;
  }

  Future<void> _requireDraftOwner(String owner) async {
    if (await _localDraftOwner() != owner) {
      throw StateError('The signed-in account changed.');
    }
  }

  Future<String> draftOwner() => _localDraftOwner();
  Future<void> checkDraftOwner(String owner) => _requireDraftOwner(owner);

  Future<FeedbackSavedDraft?> loadSavedDraft({String? expectedOwner}) async {
    final owner = await _localDraftOwner();
    if (expectedOwner != null && expectedOwner != owner) {
      throw StateError('The signed-in account changed.');
    }
    final saved = await _draftStore.load(owner);
    await _requireDraftOwner(owner);
    return saved;
  }

  Future<FeedbackSavedDraft> openSavedDraft({
    String category = 'Problem',
    String message = '',
    Uint8List? screenshot,
    String? expectedOwner,
  }) async {
    final owner = await _localDraftOwner();
    if (expectedOwner != null && expectedOwner != owner) {
      throw StateError('The signed-in account changed.');
    }
    final saved = await _draftStore.open(
      owner: owner,
      category: category,
      message: message,
      screenshot: screenshot,
    );
    await _requireDraftOwner(owner);
    return saved;
  }

  Future<FeedbackSavedDraft?> saveSavedDraft(
    FeedbackSavedDraft snapshot,
  ) async {
    await _requireDraftOwner(snapshot.uid);
    final saved = await _draftStore.save(snapshot);
    await _requireDraftOwner(snapshot.uid);
    return saved;
  }

  Future<bool> discardSavedDraft(FeedbackSavedDraft expected) async {
    await _requireDraftOwner(expected.uid);
    return _draftStore.discard(expected);
  }

  /// Validation happens at Send; incomplete local writing remains editable.
  FeedbackDraft submissionForSavedDraft(FeedbackSavedDraft saved) {
    if (!feedbackCategories.contains(saved.category) ||
        validateFeedback(saved.message) != null ||
        (saved.screenshot?.length ?? 0) > feedbackImageLimit) {
      throw ArgumentError('Invalid feedback');
    }
    return FeedbackDraft(
      id: saved.id,
      uid: saved.uid,
      category: saved.category,
      message: saved.message.trim(),
      screenshot: saved.screenshot,
    );
  }

  /// Late acknowledgement can clear only this immutable report, never a newer draft.
  @protected
  Future<void> confirmSavedDraft(FeedbackDraft submitted) async {
    try {
      await _draftStore.acknowledge(
        owner: submitted.uid,
        id: submitted.id,
        category: submitted.category,
        message: submitted.message,
        screenshot: submitted.screenshot,
      );
    } catch (_) {
      // Delivery is confirmed even if this device cannot clear its old copy.
      // A later retry still checks the same report ID before sending.
    }
  }

  /// Returns db.
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Computes draft.
  FeedbackDraft draft(String category, String message, Uint8List? screenshot) {
    if (!feedbackCategories.contains(category) ||
        validateFeedback(message) != null) {
      throw ArgumentError('Invalid feedback');
    }
    if ((screenshot?.length ?? 0) > feedbackImageLimit) {
      throw ArgumentError('Screenshot must be smaller than 5 MB.');
    }
    return FeedbackDraft(
      id: _db.collection('appFeedback').doc().id,
      uid: FirebaseBootstrap.requireAuthenticatedUser().uid,
      category: category,
      message: message.trim(),
      screenshot: screenshot,
    );
  }

  /// Replays only a form explicitly submitted with Send; ordinary drafts remain private.
  Future<void> flushPendingSubmission() async {
    final owner = await _localDraftOwner();
    final saved = await loadSavedDraft(expectedOwner: owner);
    if (saved == null || !saved.submissionAttempted) return;
    await submit(
      submissionForSavedDraft(saved),
    ).timeout(const Duration(seconds: 30));
  }

  /// A UI timeout leaves the original send running; retries join that work.
  Future<void> submit(FeedbackDraft draft) {
    try {
      _requireOwner(draft.uid);
      if ((draft.screenshot?.length ?? 0) > feedbackImageLimit) {
        throw ArgumentError('Screenshot must be smaller than 5 MB.');
      }
      final snapshot = FeedbackDraft(
        id: draft.id,
        uid: draft.uid,
        category: draft.category,
        message: draft.message,
        screenshot: draft.screenshot == null
            ? null
            : Uint8List.fromList(draft.screenshot!).asUnmodifiableView(),
      );
      final key = jsonEncode([snapshot.uid, snapshot.id]);
      final hash = crypto.sha256
          .convert(
            utf8.encode(
              jsonEncode([
                snapshot.uid,
                snapshot.id,
                snapshot.category,
                snapshot.message,
                snapshot.screenshot == null
                    ? null
                    : crypto.sha256.convert(snapshot.screenshot!).toString(),
              ]),
            ),
          )
          .toString();
      final existing = _submissions[key];
      if (existing != null) {
        if (existing.payloadHash != hash) {
          throw StateError(
            'A different payload is already being sent for this report.',
          );
        }
        return existing.result;
      }

      final completion = Completer<void>();
      final submission = _FeedbackSubmission(hash, completion.future);
      _submissions[key] = submission;
      void remove() {
        if (identical(_submissions[key], submission)) _submissions.remove(key);
      }

      unawaited(
        Future<void>.sync(() async {
          _requireOwner(snapshot.uid);
          await sendDraftToCloud(snapshot);
          await confirmSavedDraft(snapshot);
          unawaited(_invalidateReports(snapshot.uid));
        }).then<void>(
          (_) {
            remove();
            completion.complete();
          },
          onError: (Object error, StackTrace stack) {
            remove();
            completion.completeError(error, stack);
          },
        ),
      );
      return completion.future;
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
  }

  /// Performs remote acknowledgement only; the shared wrapper confirms locally.
  @protected
  Future<void> sendDraftToCloud(FeedbackDraft draft) async {
    _requireOwner(draft.uid);
    final doc = _db.collection('appFeedback').doc(draft.id);
    // Query prior feedback submission by ID
    if ((await doc.get(const GetOptions(source: Source.server))).exists) {
      return;
    }
    _requireOwner(draft.uid);
    final path = draft.screenshot == null
        ? ''
        : 'app_feedback/${draft.uid}/${draft.id}/screenshot.png';
    if (draft.screenshot != null) {
      // Update cloud: upload feedback screenshot
      final task = FirebaseStorage.instance
          .ref(path)
          .putData(
            draft.screenshot!,
            SettableMetadata(contentType: 'image/png'),
          );
      try {
        await task.timeout(const Duration(seconds: 20));
      } catch (_) {
        await task.cancel();
        rethrow;
      }
    }
    _requireOwner(draft.uid);
    // Transactions never queue an offline "success"
    await _db.runTransaction((transaction) async {
      // Query existing feedback in transaction
      if ((await transaction.get(doc)).exists) return;
      // Update cloud: create feedback report
      transaction.set(doc, {
        'uid': draft.uid,
        'category': draft.category,
        'message': draft.message,
        'screenshotPath': path,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'status': 'New',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Returns private owner reports locally first and receives batched refreshes.
  Stream<List<FeedbackReport>> reports({
    required bool admin,
    bool force = false,
  }) {
    if (admin) return watchAdminReports();
    final owner = _owner();
    return Stream<List<FeedbackReport>>.multi((output) {
      var closed = false;
      var revision = 0;
      Future<void> publish({bool cacheOnly = false, bool force = false}) async {
        final request = ++revision;
        try {
          final rows = await loadReports(
            owner: owner,
            cacheOnly: cacheOnly,
            force: force,
          );
          if (!closed && request == revision) output.add(rows);
        } catch (error, stack) {
          if (!closed && request == revision) output.addError(error, stack);
        }
      }

      final updates = _cache.updates
          .where(
            (event) =>
                event.owner == owner &&
                event.type == cacheType &&
                event.id == cacheId,
          )
          .listen((event) {
            // Revocation/not-found invalidations clear the visible read model;
            // they must not start an endless permission-denied refresh loop.
            unawaited(publish(cacheOnly: true));
          });
      unawaited(publish(force: force));
      output.onCancel = () {
        closed = true;
        revision++;
        unawaited(updates.cancel());
      };
    });
  }

  /// Loads one owner-scoped snapshot through the shared hash-cache contract.
  Future<List<FeedbackReport>> loadReports({
    String? owner,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    final account = owner ?? _owner();
    _requireOwner(account);
    // Query hiker's submitted feedback
    final data = await _cache.read(
      owner: account,
      type: cacheType,
      id: cacheId,
      callable: 'readMobileResource',
      arguments: const {'resourceType': 'my_feedback'},
      freshness: const Duration(minutes: 2),
      force: force,
      cacheOnly: cacheOnly,
    );
    _requireOwner(account);
    final raw = data['reports'];
    if (raw is! List) return const [];
    return [
      for (final row in raw.whereType<Map>())
        if (row['uid'] == account && row['reportId'] is String)
          FeedbackReport(
            id: row['reportId'] as String,
            data: Map<String, dynamic>.from(row),
          ),
    ];
  }

  /// Privileged review stays a live, server-authorised Firestore query.
  @protected
  // Query admin feedback by creation time
  Stream<List<FeedbackReport>> watchAdminReports() => _db
      .collection('appFeedback')
      .orderBy('createdAt', descending: true)
      .limit(feedbackReportLimit)
      .snapshots(includeMetadataChanges: true)
      .where(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites,
      )
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            FeedbackReport(id: doc.id, data: doc.data()),
        ],
      );

  Future<void> _invalidateReports(String owner) async {
    try {
      await _cache.invalidate(owner: owner, type: cacheType, id: cacheId);
      if (_owner() == owner) {
        await loadReports(owner: owner, force: true);
      }
    } catch (_) {
      // A completed report write is still successful if device caching fails.
    }
  }

  /// Sets status.
  Future<void> setStatus(String id, String status) async {
    if (!feedbackStatuses.contains(status)) {
      throw ArgumentError('Invalid status');
    }
    // Update cloud: update feedback status
    await _db.collection('appFeedback').doc(id).update({'status': status});
    try {
      await _invalidateReports(_owner());
    } catch (_) {
      // A later account change must not recast a confirmed write as a failure.
    }
  }

  /// Computes screenshot.
  Future<Uint8List?> screenshot(String path) async =>
      // Query feedback screenshot bytes
      FirebaseStorage.instance.ref(path).getData(feedbackImageLimit);
}
