// FeedbackRepository validates feedback and uploads one stable draft across retries.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../app/Data/firebase_bootstrap.dart';

const feedbackCategories = ['Problem', 'Suggestion', 'Other'];
const feedbackStatuses = ['New', 'In review', 'Resolved'];
const feedbackImageLimit = 5 * 1024 * 1024;

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

/// Keep submission validation and upload error mapping outside the feedback screens.
class FeedbackRepository {
  /// Returns db.
  FirebaseFirestore get _db => FirebaseFirestore.instance;

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

  /// Computes submit.
  Future<void> submit(FeedbackDraft draft) async {
    if (FirebaseBootstrap.requireAuthenticatedUser().uid != draft.uid) {
      throw StateError('Please sign in again before sending feedback.');
    }
    final doc = _db.collection('appFeedback').doc(draft.id);
    if ((await doc.get(const GetOptions(source: Source.server))).exists) return;
    final path = draft.screenshot == null
        ? ''
        : 'app_feedback/${draft.uid}/${draft.id}/screenshot.png';
    if (draft.screenshot != null) {
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
    // Transactions never queue an offline "success", and retries cannot duplicate reports.
    await _db.runTransaction((transaction) async {
      if ((await transaction.get(doc)).exists) return;
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

  /// Computes reports.
  Stream<QuerySnapshot<Map<String, dynamic>>> reports({
    required bool admin,
  }) async* {
    Query<Map<String, dynamic>> query = _db.collection('appFeedback');
    if (!admin) {
      query = query.where(
        'uid',
        isEqualTo: FirebaseBootstrap.requireAuthenticatedUser().uid,
      );
    }
    yield* query.orderBy('createdAt', descending: true).limit(100).snapshots();
  }

  /// Sets status.
  Future<void> setStatus(String id, String status) {
    if (!feedbackStatuses.contains(status)) {
      throw ArgumentError('Invalid status');
    }
    return _db.collection('appFeedback').doc(id).update({'status': status});
  }

  /// Computes screenshot.
  Future<Uint8List?> screenshot(String path) async =>
      FirebaseStorage.instance.ref(path).getData(feedbackImageLimit);
}
