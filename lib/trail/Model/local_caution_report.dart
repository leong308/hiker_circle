import 'dart:convert';
import 'dart:typed_data';

/// A report is pending until the caution backend confirms its stable identity.
class LocalCautionReport {
  const LocalCautionReport({
    required this.ownerPhoneNumber,
    required this.reportId,
    required this.payload,
    required this.createdAt,
    required this.status,
    required this.mediaCount,
    this.attempts = 0,
    this.lastError = '',
    this.nextRetryAt,
    this.sentAt,
  });

  factory LocalCautionReport.fromRow(Map<String, Object?> row) =>
      LocalCautionReport(
        ownerPhoneNumber: row['owner'] as String,
        reportId: row['report_id'] as String,
        payload: Map<String, dynamic>.from(
          jsonDecode(row['payload'] as String) as Map,
        ),
        createdAt: DateTime.parse(row['created_at'] as String),
        status: row['status'] as String,
        mediaCount: row['media_count'] as int,
        attempts: row['attempts'] as int,
        lastError: row['last_error'] as String? ?? '',
        nextRetryAt: DateTime.tryParse(row['next_retry_at'] as String? ?? ''),
        sentAt: DateTime.tryParse(row['sent_at'] as String? ?? ''),
      );

  final String ownerPhoneNumber;
  final String reportId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String status;
  final int mediaCount;
  final int attempts;
  final String lastError;
  final DateTime? nextRetryAt;
  final DateTime? sentAt;
  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';
  String get trailName => payload['trailName'] as String? ?? 'Hiking trail';
  String get hazardType => payload['hazardType'] as String? ?? 'Caution';
  String get description => payload['description'] as String? ?? '';
}

class LocalCautionMedia {
  const LocalCautionMedia({
    required this.key,
    required this.name,
    required this.contentType,
    required this.bytes,
  });
  final String key;
  final String name;
  final String contentType;
  final Uint8List bytes;
}
