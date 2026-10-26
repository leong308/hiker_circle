import '../../home/Model/hike_session_models.dart';

/// Expiry is the end of the start window, regardless of cleanup-worker timing.
bool isExpiredScheduledHikeData(
  Map<String, dynamic> data, {
  required String ownerPhoneNumber,
  required DateTime now,
}) {
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
  final status = '${data['status'] ?? ''}'.toLowerCase();
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
