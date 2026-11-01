import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/account_role.dart';
import '../../core/widgets/page_header_style.dart';
import '../Data/admin_users_repository.dart';
import '../ModelView/admin_users_view_model.dart';
import 'admin_ui.dart';

/// Displays non-navigating hiker cards and superadmin-only management controls.
class AdminUsersSection extends StatelessWidget {
  /// Reuses the dashboard's panel layout for a non-navigating directory.
  const AdminUsersSection({super.key, required this.model});
  final AdminUsersViewModel model;

  /// Confirms the specific account and transition before committing it to the cloud.
  Future<void> _change(BuildContext context, AdminHiker user) async {
    final promote = user.role == AccountRole.hiker;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(promote ? 'Promote to admin?' : 'Demote to hiker?'),
        content: Text(
          '${user.username}\n${user.phone}\n\n${promote ? 'This hiker will receive administrator access.' : 'Administrator access will be removed.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(promote ? 'Promote' : 'Demote'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final success = await model.changeRole(user);
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            promote ? 'Hiker promoted to admin.' : 'Admin demoted to hiker.',
          ),
        ),
      );
    }
  }

  /// Opens the audit list without exposing it to ordinary admins.
  void _history(BuildContext context) {
    unawaited(model.loadHistory());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListenableBuilder(
          listenable: model,
          builder: (context, _) => !model.canManage
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Role history',
                              style: PageHeaderStyle.title(
                                context,
                                Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (model.historyLoading) const LinearProgressIndicator(),
                      if (model.historyError != null) Text(model.historyError!),
                      Expanded(
                        child: ListView(
                          children: [
                            if (!model.historyLoading && model.history.isEmpty)
                              const AdminEmptyState(
                                title: 'No role changes yet',
                                message:
                                    'Promotions and demotions will appear here.',
                              ),
                            for (final row in model.history)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: AdminPanel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${row['targetUsername']}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${row['targetPhoneNumber']}',
                                        style: TextStyle(
                                          color: AdminUi.muted(context),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      AdminTag(
                                        label:
                                            '${row['fromRole'] == 'admin' ? 'Admin' : 'Hiker'} → ${row['toRole'] == 'admin' ? 'Admin' : 'Hiker'}',
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'By ${row['actorUsername']} · ${row['actorPhoneNumber']}',
                                        style: TextStyle(
                                          color: AdminUi.muted(context),
                                        ),
                                      ),
                                      Text(
                                        _date(
                                          context,
                                          row['changedAt'] as String?,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (model.historyError != null)
                              TextButton(
                                onPressed: () => unawaited(model.loadHistory()),
                                child: const Text('Retry'),
                              ),
                            if (model.historyCursor != null)
                              TextButton(
                                onPressed: model.historyLoading
                                    ? null
                                    : () => unawaited(
                                        model.loadHistory(more: true),
                                      ),
                                child: const Text('Load more'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Formats audit timestamps in the phone's locale and timezone.
  String _date(BuildContext context, String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return '';
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatMediumDate(date)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  /// Matches the dashboard's panel, spacing and role-label styling.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${model.users.length} hikers',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            if (model.canManage)
              IconButton(
                tooltip: 'Role history',
                onPressed: () => _history(context),
                icon: const Icon(Icons.history_rounded),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (model.loading || model.changingUser != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(),
          ),
        if (model.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.error!),
                  TextButton(
                    onPressed: () => unawaited(model.refresh()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        if (model.loaded && model.users.isEmpty)
          const AdminEmptyState(
            title: 'No hikers yet',
            message: 'Registered hikers will appear here.',
          ),
        for (final user in model.users)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AdminPanel(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AdminUi.green(context).withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: AdminUi.green(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.phone,
                          style: TextStyle(color: AdminUi.muted(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AdminTag(label: user.role.label),
                  if (model.canManage && user.role != AccountRole.superadmin)
                    PopupMenuButton<String>(
                      tooltip: 'Change role',
                      enabled: model.changingUser == null && !model.loading,
                      onSelected: (_) => unawaited(_change(context, user)),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'change',
                          child: Text(
                            user.role == AccountRole.hiker
                                ? 'Promote to admin'
                                : 'Demote to hiker',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (model.cursor != null)
          OutlinedButton(
            onPressed: model.loading
                ? null
                : () => unawaited(model.refresh(more: true)),
            child: const Text('Load more hikers'),
          ),
      ],
    ),
  );
}
