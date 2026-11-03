part of 'local_session_database.dart';

extension LocalCautionDatabase on LocalSessionDatabase {
  Future<LocalCautionReport> queueCautionReport({
    required String owner,
    required String reportId,
    required Map<String, dynamic> payload,
    required String contentHash,
    required List<LocalCautionMedia> media,
    required DateTime createdAt,
  }) async {
    final database = await _openDatabase();
    return database.transaction((tx) async {
      final previous = await tx.query(
        'caution_report_outbox',
        where: 'owner = ? AND report_id = ?',
        whereArgs: [owner, reportId],
      );
      if (previous.isNotEmpty) {
        if (previous.single['content_hash'] != contentHash) {
          throw StateError(
            'This saved caution already has different contents.',
          );
        }
        return LocalCautionReport.fromRow(previous.single);
      }
      await tx.insert('caution_report_outbox', {
        'owner': owner,
        'report_id': reportId,
        'payload': jsonEncode(payload),
        'content_hash': contentHash,
        'created_at': createdAt.toUtc().toIso8601String(),
        'status': 'pending',
        'media_count': media.length,
      });
      for (final item in media) {
        await tx.insert('caution_report_media', {
          'owner': owner,
          'report_id': reportId,
          'media_key': item.key,
          'name': item.name,
          'content_type': item.contentType,
          'bytes': item.bytes,
        });
      }
      return LocalCautionReport.fromRow(
        (await tx.query(
          'caution_report_outbox',
          where: 'owner = ? AND report_id = ?',
          whereArgs: [owner, reportId],
        )).single,
      );
    });
  }

  Future<List<LocalCautionReport>> loadCautionReports({
    required String owner,
    bool pendingOnly = false,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'caution_report_outbox',
      where: pendingOnly ? "owner = ? AND status = 'pending'" : 'owner = ?',
      whereArgs: [owner],
      orderBy: pendingOnly ? 'created_at ASC' : 'created_at DESC',
    );
    return rows.map(LocalCautionReport.fromRow).toList();
  }

  Future<List<LocalCautionMedia>> loadCautionMedia({
    required String owner,
    required String reportId,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'caution_report_media',
      where: 'owner = ? AND report_id = ?',
      whereArgs: [owner, reportId],
      orderBy: 'rowid ASC',
    );
    return rows
        .map(
          (row) => LocalCautionMedia(
            key: row['media_key'] as String,
            name: row['name'] as String,
            contentType: row['content_type'] as String,
            bytes: Uint8List.fromList(row['bytes'] as List<int>),
          ),
        )
        .toList();
  }

  Future<void> recordCautionAttempt({
    required String owner,
    required String reportId,
    required DateTime at,
  }) async {
    final database = await _openDatabase();
    await database.rawUpdate(
      '''UPDATE caution_report_outbox
      SET attempts = attempts + 1, last_attempt_at = ?
      WHERE owner = ? AND report_id = ? AND status = 'pending' ''',
      [at.toUtc().toIso8601String(), owner, reportId],
    );
  }

  Future<void> setCautionOutcome({
    required String owner,
    required String reportId,
    required String status,
    String error = '',
    DateTime? nextRetryAt,
    DateTime? sentAt,
  }) async {
    final database = await _openDatabase();
    await database.transaction((tx) async {
      await tx.update(
        'caution_report_outbox',
        {
          'status': status,
          'last_error': error,
          'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
          'sent_at': sentAt?.toUtc().toIso8601String(),
        },
        where: status == 'sent'
            ? 'owner = ? AND report_id = ?'
            : "owner = ? AND report_id = ? AND status = 'pending'",
        whereArgs: [owner, reportId],
      );
      if (status == 'sent') {
        // Keep the history entry; confirmed uploads no longer need local blobs.
        await tx.delete(
          'caution_report_media',
          where: 'owner = ? AND report_id = ?',
          whereArgs: [owner, reportId],
        );
      }
    });
  }
}
