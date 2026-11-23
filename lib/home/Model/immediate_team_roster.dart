import 'hike_session_models.dart';
import 'team_hike_identity.dart';

/// Client guidance before requesting a new immediate team from the server.
/// The server still owns account, buddy membership and capacity validation.
abstract final class ImmediateTeamRoster {
  static const maximumInvitees = TeamHikeIdentity.maximumHikers - 1;

  static String? validationError(
    Iterable<TeamHikeBuddy> buddies, {
    required String ownerPhoneNumber,
  }) {
    final phones = <String>{};
    final owner = TeamHikeIdentity.key(ownerPhoneNumber);
    for (final buddy in buddies) {
      final phone = buddy.normalizedPhoneNumber;
      if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone) ||
          TeamHikeIdentity.key(phone) == owner) {
        return 'Choose another hiking buddy from the list.';
      }
      phones.add(TeamHikeIdentity.key(phone));
    }
    if (phones.isEmpty) {
      return 'Choose at least one hiking buddy before starting a team hike.';
    }
    if (phones.length > maximumInvitees) {
      return 'Choose up to $maximumInvitees buddies, plus you as the host.';
    }
    return null;
  }
}
