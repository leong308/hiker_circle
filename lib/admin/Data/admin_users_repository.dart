import 'package:cloud_functions/cloud_functions.dart';
import '../../app/Model/app_session.dart';
import '../../core/models/account_role.dart';

/// Minimal directory card data; no profile details or hiking statistics are downloaded.
class AdminHiker {
  /// Creates a card containing only directory fields.
  const AdminHiker({
    required this.id,
    required this.username,
    required this.phone,
    required this.role,
  });
  final String id, username, phone;
  final AccountRole role;

  /// Parses the server's restricted directory projection.
  factory AdminHiker.fromMap(Map<String, dynamic> value) => AdminHiker(
    id: value['userId'] as String,
    username: value['username'] as String? ?? 'Hiker',
    phone: value['phoneNumber'] as String,
    role: AccountRole.fromAccount({'role': value['role']}),
  );

  /// Applies only a role confirmed by the server.
  AdminHiker withRole(AccountRole value) =>
      AdminHiker(id: id, username: username, phone: phone, role: value);
}

/// Uses protected callables for directory reads, role transitions and immutable history.
class AdminUsersRepository {
  /// Uses authenticated callables without storing a private directory locally.
  AdminUsersRepository({FirebaseFunctions? functions}) : _functions = functions;
  final FirebaseFunctions? _functions;

  /// Keeps authorization failures readable without exposing backend implementation details.
  Future<Map<String, dynamic>> _call(
    String name,
    AppSession session,
    Map<String, Object?> args,
  ) async {
    try {
      final result = await (_functions ?? FirebaseFunctions.instance)
          .httpsCallable(name)
          .call({...args, 'expectedOwner': session.phoneNumber});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw Exception(
        error.message ?? 'Unable to complete this request. Try again.',
      );
    }
  }

  /// Loads the next page with only usernames, phone numbers and roles.
  Future<Map<String, dynamic>> list(AppSession session, {String? cursor}) =>
      // Query paginated admin user list
      _call('listAdminUsers', session, {
        'limit': 50,
        if (cursor != null) 'cursor': cursor,
      });

  // Update cloud: change hiker role
  /// Changes hiker/admin membership through an audited server transaction.
  Future<Map<String, dynamic>> change(
    AppSession session,
    AdminHiker hiker,
    AccountRole role,
    String operationId,
  ) => _call('changeHikerRole', session, {
    'targetUserId': hiker.id,
    'role': role.name,
    'expectedRole': hiker.role.name,
    'operationId': operationId,
  });

  /// Loads promotion/demotion records for a current superadmin.
  Future<Map<String, dynamic>> history(AppSession session, {String? cursor}) =>
      // Query role change audit history
      _call('listUserRoleHistory', session, {
        'limit': 50,
        if (cursor != null) 'cursor': cursor,
      });
}
