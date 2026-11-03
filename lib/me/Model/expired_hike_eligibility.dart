import '../../home/Model/hike_session_models.dart';

/// Expiry is the end of the start window, regardless of cleanup-worker timing.
bool isExpiredScheduledHikeData(
  Map<String, dynamic> data, {
  required String ownerPhoneNumber,
  required DateTime now,
}) {
  if (data['teamLaunchConsumed'] == true) return false;
  final status = '${data['status'] ?? ''}'.toLowerCase();
  final removed =
      data['isDeleted'] == true &&
      data['expired'] == true &&
      data['historyCategory'] == 'expired' &&
      status == 'cancelled';
  if (removed &&
      ![
        'startedAt',
        'startedAtLocal',
        'endedAt',
        'endedAtLocal',
      ].any((key) => data[key] != null && '${data[key]}'.isNotEmpty) &&
      !(data['startedParticipantPhones'] is List &&
          (data['startedParticipantPhones'] as List).contains(
            ownerPhoneNumber,
          ))) {
    return true;
  }
  final departure = DateTime.tryParse(
    '${data['departureTimeLocal'] ?? data['departureTime'] ?? ''}',
  );
  if (departure == null ||
      departure
          .toUtc()
          .add(UpcomingHike.visibleAfterDepartureGrace)
          .isAfter(now.toUtc())) {
    return false;
  }
  if (const {
    'active',
    'started',
    'ended',
    'completed',
    'cancelled',
    'canceled',
    'abandoned',
    'rejected',
    'deleted',
  }.contains(status)) {
    return false;
  }
  if ([
    'startedAt',
    'startedAtLocal',
    'endedAt',
    'endedAtLocal',
  ].any((key) => data[key] != null && '${data[key]}'.isNotEmpty)) {
    return false;
  }
  final started = data['startedParticipantPhones'];
  if (started is List &&
      started.any((phone) => '$phone'.trim() == ownerPhoneNumber)) {
    return false;
  }
  return data['isDeleted'] != true ||
      data['expired'] == true ||
      data['deletedReason'] == 'departure_time_expired' ||
      status == 'expired';
}
