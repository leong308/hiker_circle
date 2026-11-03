/// One confirmed upload batch, counting distinct hikes rather than writes.
class UpcomingHikeSyncNotice {
  UpcomingHikeSyncNotice({
    required this.ownerPhoneNumber,
    required Iterable<String> hikeIds,
  }) : hikeIds = Set.unmodifiable(hikeIds);
  final String ownerPhoneNumber;
  final Set<String> hikeIds;
  String get message =>
      '${hikeIds.length} upcoming ${hikeIds.length == 1 ? 'hike' : 'hikes'} synced to Firebase';
}
