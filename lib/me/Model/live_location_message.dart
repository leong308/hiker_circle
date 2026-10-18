import '../../app/Model/preferred_time_zone.dart';
import 'live_location_models.dart';

/// Keep manually shared links as informative as the saved-contact notice.
String composeStandaloneLiveLocationMessage({
  required String ownerPhone,
  required LiveLocationShare share,
  required String timeZoneId,
}) {
  final phone = ownerPhone.replaceAll(RegExp(r'[\r\n\u2028\u2029]'), '').trim();
  final startedAt = PreferredTimeZone.formatInstant(
    share.startedAt,
    timeZoneId,
  );
  return [
    '📍 *HikerCircle Live Location*',
    '',
    'I have started sharing my live location.',
    'User phone: $phone',
    'Started: $startedAt',
    '',
    '📍 Follow my live location:',
    share.shareUrl,
    '',
    'This is a live location update, not an SOS alert. The link stops when sharing is turned off or expires 24 hours after sharing started.',
  ].join('\n');
}
