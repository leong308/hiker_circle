import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../app/Data/local_session_database.dart';
import '../../core/services/content_hash.dart';
import '../Model/local_caution_report.dart';
import '../Model/trail_hazard_categories.dart';
import 'trail_caution_service.dart';

typedef CautionReportSender =
    Future<void> Function(
      LocalCautionReport report,
      List<LocalCautionMedia> media,
    );

/// Durable local submission, independent of the page, with one retry worker.
class CautionReportQueue {
  CautionReportQueue({
    required this.database,
    required this.owner,
    required this.send,
    required this.canSend,
    bool Function()? isOnline,
    DateTime Function()? now,
  }) : isOnline = isOnline ?? (() => true),
       now = now ?? DateTime.now;

  static final _changes = StreamController<String>.broadcast();
  static Stream<String> get changes => _changes.stream;
  final LocalSessionDatabase database;
  final String owner;
  final CautionReportSender send;
  final bool Function() canSend;
  final bool Function() isOnline;
  final DateTime Function() now;
  Future<void> _work = Future<void>.value();

  Future<LocalCautionReport> enqueue({
    required Map<String, dynamic> payload,
    List<PendingCautionMedia> media = const [],
  }) async {
    final id = payload['hazardId'];
    final lat = payload['latitude'], lon = payload['longitude'];
    final description = payload['description'];
    final trailName = payload['trailName'];
    final observedAt = payload['observedAtMillis'];
    if (owner.isEmpty ||
        observedAt is! int ||
        observedAt <= 0 ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,180}$').hasMatch(id) ||
        payload['trailId'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,180}$',
        ).hasMatch(payload['trailId'] as String) ||
        trailName is! String ||
        trailName.length > 180 ||
        !trailHazardReportCategories.values.any(
          (entry) => entry.$2.contains(payload['hazardType']),
        ) ||
        description is! String ||
        description.length > 1000 ||
        lat is! num ||
        !lat.isFinite ||
        lat.abs() > 90 ||
        lon is! num ||
        !lon.isFinite ||
        lon.abs() > 180) {
      throw StateError(
        'Choose a caution, a valid GPS location and a note under 1,000 characters.',
      );
    }
    if (media.length > 6 ||
        media.fold<int>(0, (total, item) => total + item.sizeBytes) >
            cautionMediaLimit) {
      throw StateError(
        'Choose up to six photos or videos, totaling at most 50 MB.',
      );
    }
    final saved = <LocalCautionMedia>[];
    final mediaHashes = <Map<String, Object>>[];
    for (final item in media) {
      if (!cautionMediaTypes.containsValue(item.contentType)) {
        throw StateError('This media file is not supported.');
      }
      final bytes = await item.file.readAsBytes();
      if (bytes.isEmpty || bytes.length != item.sizeBytes) {
        throw StateError('The selected file changed. Please choose it again.');
      }
      saved.add(
        LocalCautionMedia(
          key: item.key,
          name: item.file.name,
          contentType: item.contentType,
          bytes: bytes,
        ),
      );
      mediaHashes.add({
        'key': item.key,
        'name': item.file.name,
        'type': item.contentType,
        'hash': sha256.convert(bytes).toString(),
      });
    }
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      observedAt,
      isUtc: true,
    );
    final report = await database.queueCautionReport(
      owner: owner,
      reportId: id,
      payload: payload,
      contentHash: stableContentHash([payload, mediaHashes]),
      media: saved,
      createdAt: createdAt,
    );
    _changes.add(owner);
    // Return after the SQLite transaction, never after a network request.
    if (isOnline()) unawaited(flush());
    return report;
  }

  Future<void> flush({bool forceRetry = false}) {
    // Queue every wake-up behind the active pass. A connectivity event arriving
    // as an offline pass finishes must not be lost during worker cleanup.
    _work = _work.then((_) => _drain(force: forceRetry)).catchError((
      Object error,
    ) {
      // Storage/auth/network recovery must never escape as an unhandled Future.
      debugPrint('Caution report retry remains pending: ${error.runtimeType}');
    });
    return _work;
  }

  Future<void> _drain({required bool force}) async {
    if (!canSend() || (!force && !isOnline())) return;
    final reports = await database.loadCautionReports(
      owner: owner,
      pendingOnly: true,
    );
    for (final report in reports) {
      if (!canSend()) return;
      final at = now().toUtc();
      if (!force && report.nextRetryAt?.isAfter(at) == true) continue;
      try {
        final media = await database.loadCautionMedia(
          owner: owner,
          reportId: report.reportId,
        );
        if (media.length != report.mediaCount) {
          throw const FormatException(
            'Saved caution attachments are incomplete.',
          );
        }
        if (!canSend()) return;
        await database.recordCautionAttempt(
          owner: owner,
          reportId: report.reportId,
          at: at,
        );
        await send(report, media);
        await database.setCautionOutcome(
          owner: owner,
          reportId: report.reportId,
          status: 'sent',
          sentAt: now(),
        );
      } catch (error) {
        final code = error is FirebaseException ? error.code : '';
        final permanent =
            error is FormatException ||
            const {
              'invalid-argument',
              'failed-precondition',
              'not-found',
            }.contains(code);
        // Auth/permission failures retain the report for a refreshed session.
        final message = error is FirebaseFunctionsException && permanent
            ? (error.message ??
                  'This report needs attention before it can be sent.')
            : permanent
            ? 'Saved attachments could not be read. Please submit the caution again.'
            : 'Waiting for network retry.';
        await database.setCautionOutcome(
          owner: owner,
          reportId: report.reportId,
          status: permanent ? 'failed' : 'pending',
          error: message,
          nextRetryAt: permanent
              ? null
              : at.add(
                  Duration(
                    seconds: math.min(
                      300,
                      15 * (1 << math.min(report.attempts, 5)),
                    ),
                  ),
                ),
        );
      }
      _changes.add(owner);
    }
  }
}
