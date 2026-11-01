/// Canonical role shared by session updates and the administrator directory.
enum AccountRole {
  hiker('Hiker'),
  admin('Admin'),
  superadmin('Superadmin');

  const AccountRole(this.label);
  final String label;

  /// Accepts existing role flags and aliases while giving superadmin precedence.
  static AccountRole fromAccount(Map<String, dynamic> account) {
    final roles =
        [
              account['role'],
              if (account['roles'] is Iterable) ...account['roles'] as Iterable,
            ]
            .whereType<String>()
            .map(
              (value) => value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), ''),
            )
            .toSet();
    if (account['isSuperAdmin'] == true || roles.contains('superadmin')) {
      return superadmin;
    }
    return account['isAdmin'] == true || roles.contains('admin')
        ? admin
        : hiker;
  }
}
