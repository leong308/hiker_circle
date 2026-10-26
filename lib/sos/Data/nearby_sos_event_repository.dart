// NearbySosEventRepository requests authorized nearby emergency events within the selected radius.
import '../../app/Data/local_session_database.dart';
import '../Model/nearby_sos_event.dart';

/// Represents nearby sos event repository.
class NearbySosEventRepository {
  /// Creates nearby sos event repository.
  NearbySosEventRepository({LocalSessionDatabase? database})
    : _database = database ?? LocalSessionDatabase();

  final LocalSessionDatabase _database;

  /// Saves.
  Future<void> save(NearbySosEvent event) {
    return _database.saveNearbySosEvent(event);
  }

  /// Loads.
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
