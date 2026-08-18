import '../../app/Data/local_session_database.dart';
import '../Model/nearby_sos_event.dart';

class NearbySosEventRepository {
  NearbySosEventRepository({LocalSessionDatabase? database})
    : _database = database ?? LocalSessionDatabase();

  final LocalSessionDatabase _database;

  Future<void> save(NearbySosEvent event) {
    return _database.saveNearbySosEvent(event);
  }

  Future<List<NearbySosEvent>> load({
    required String ownerPhoneNumber,
    int limit = 200,
  }) {
    return _database.loadNearbySosEvents(
      ownerPhoneNumber: ownerPhoneNumber,
      limit: limit,
    );
  }
}
