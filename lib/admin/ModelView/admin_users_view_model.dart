import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../app/Model/app_session.dart';
import '../../core/models/account_role.dart';
import '../Data/admin_users_repository.dart';

/// Owns pagination and confirmed role changes without granting privileges optimistically.
class AdminUsersViewModel extends ChangeNotifier {
  /// Binds the current actor and the protected users data source.
  AdminUsersViewModel({
    required AppSession session,
    required AdminUsersRepository repository,
  }) : _session = session,
       _repository = repository;
  AppSession _session;
  final AdminUsersRepository _repository;
  List<AdminHiker> users = [];
  List<Map<String, dynamic>> history = [];
  String? cursor, historyCursor, error, historyError, changingUser;
  bool loading = false,
      historyLoading = false,
      loaded = false,
      _disposed = false;
  int _revision = 0, _historyRevision = 0;

  /// Only a current superadmin sees management and audit controls.
  bool get canManage => !_disposed && _session.isSuperAdmin;

  /// Removes privileged history immediately when the signed-in role changes.
  void updateSession(AppSession session) {
    if (_session.phoneNumber == session.phoneNumber &&
        _session.isAdmin == session.isAdmin &&
        _session.isSuperAdmin == session.isSuperAdmin) {
      return;
    }
    _session = session;
    _revision++;
    _historyRevision++;
    loading = false;
    historyLoading = false;
    changingUser = null;
    history = [];
    historyCursor = null;
    historyError = null;
    if (!session.isAdmin) {
      users = [];
      cursor = null;
      loaded = false;
    }
    _notify();
  }

  /// Publishes only while this tab is still alive.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads a complete directory page and retains previously confirmed cards on failure.
  Future<void> refresh({bool more = false}) async {
    if (loading ||
        changingUser != null ||
        !_session.isAdmin ||
        (more && cursor == null)) {
      return;
    }
    final revision = ++_revision;
    loading = true;
    error = null;
    _notify();
    try {
      final data = await _repository.list(
        _session,
        cursor: more ? cursor : null,
      );
      if (_disposed || revision != _revision) return;
      final rows = (data['users'] as List)
          .map((v) => AdminHiker.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList();
      users = more
          ? [
              ...users,
              ...rows.where((u) => !users.any((old) => old.id == u.id)),
            ]
          : rows;
      cursor = data['nextCursor'] as String?;
      loaded = true;
    } catch (e) {
      if (revision == _revision) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (revision == _revision) {
        loading = false;
        _notify();
      }
    }
  }

  /// Changes only hiker/admin roles, then updates the card from the server acknowledgement.
  Future<bool> changeRole(AdminHiker hiker) async {
    if (!canManage ||
        loading ||
        changingUser != null ||
        hiker.role == AccountRole.superadmin) {
      return false;
    }
    final revision = _revision;
    changingUser = hiker.id;
    error = null;
    _notify();
    final desired = hiker.role == AccountRole.hiker
        ? AccountRole.admin
        : AccountRole.hiker;
    final operation =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    try {
      final data = await _repository.change(
        _session,
        hiker,
        desired,
        operation,
      );
      if (_disposed || revision != _revision || !canManage) return false;
      final role = AccountRole.fromAccount({'role': data['role']});
      users = users
          .map((u) => u.id == hiker.id ? u.withRole(role) : u)
          .toList();
      if (role != desired) {
        error = 'This role changed. Refresh the list and try again.';
        return false;
      }
      history = [];
      historyCursor = null;
      _historyRevision++;
      historyLoading = false;
      return true;
    } catch (e) {
      if (revision == _revision) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
      return false;
    } finally {
      if (revision == _revision) {
        changingUser = null;
        _notify();
      }
    }
  }

  /// Keeps audit history separate from ordinary administrator cards.
  Future<void> loadHistory({bool more = false}) async {
    if (!canManage || historyLoading || (more && historyCursor == null)) return;
    final revision = ++_historyRevision;
    historyLoading = true;
    historyError = null;
    _notify();
    try {
      final data = await _repository.history(
        _session,
        cursor: more ? historyCursor : null,
      );
      if (_disposed || revision != _historyRevision || !canManage) return;
      final rows = (data['history'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      history = more ? [...history, ...rows] : rows;
      historyCursor = data['nextCursor'] as String?;
    } catch (e) {
      if (revision == _historyRevision) {
        historyError = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      if (revision == _historyRevision) {
        historyLoading = false;
        _notify();
      }
    }
  }

  /// Prevents late responses from updating an exited or demoted administrator.
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _historyRevision++;
    super.dispose();
  }
}
