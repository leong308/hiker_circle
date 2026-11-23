import 'package:flutter/material.dart';

import '../Model/hike_session_models.dart';
import '../Model/immediate_team_roster.dart';
import '../Model/team_hike_identity.dart';

/// Select accepted buddies before an immediate team is created.
class TeamHikeBuddySelection extends StatefulWidget {
  const TeamHikeBuddySelection({
    super.key,
    required this.loadBuddies,
    required this.selectedBuddies,
    required this.onChanged,
    this.canSchedule = true,
  });

  final Future<List<TeamHikeBuddy>> Function() loadBuddies;
  final List<TeamHikeBuddy> selectedBuddies;
  final ValueChanged<List<TeamHikeBuddy>> onChanged;
  final bool canSchedule;

  @override
  State<TeamHikeBuddySelection> createState() => _TeamHikeBuddySelectionState();
}

class _TeamHikeBuddySelectionState extends State<TeamHikeBuddySelection> {
  late Future<List<TeamHikeBuddy>> _buddies = widget.loadBuddies();
  String _query = '';

  void _retry() {
    final buddies = widget.loadBuddies();
    setState(() {
      _buddies = buddies;
    });
  }

  void _select(TeamHikeBuddy buddy, bool selected) {
    final key = TeamHikeIdentity.key(buddy.phoneNumber);
    final updated = widget.selectedBuddies
        .where((value) => TeamHikeIdentity.key(value.phoneNumber) != key)
        .toList();
    if (selected) {
      if (updated.length >= ImmediateTeamRoster.maximumInvitees) return;
      updated.add(buddy);
    }
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TeamHikeBuddy>>(
    future: _buddies,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: 'Loading hiking buddies',
                ),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Loading hiking buddies…')),
            ],
          ),
        );
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Unable to load your hiking buddies. Try again.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry buddies'),
              ),
            ),
          ],
        );
      }
      final buddies = snapshot.data ?? const <TeamHikeBuddy>[];
      if (buddies.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No hiking buddies are available yet. Add buddies in Circle, '
              'then retry here.',
            ),
            if (widget.canSchedule) ...[
              const SizedBox(height: 8),
              const Text(
                'You can also go Back and choose Schedule Time to create a hike '
                'that others can request to join.',
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh buddies'),
              ),
            ),
          ],
        );
      }
      final selectedKeys = widget.selectedBuddies
          .map((value) => TeamHikeIdentity.key(value.phoneNumber))
          .toSet();
      final visible = buddies.where(
        (value) => '${value.name} ${value.handle} ${value.phoneNumber}'
            .toLowerCase()
            .contains(_query.toLowerCase().trim()),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${selectedKeys.length} of ${ImmediateTeamRoster.maximumInvitees} buddies selected',
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search hiking buddies',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No buddies match your search.'),
            ),
          for (final buddy in visible)
            Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                key: ValueKey(
                  'team-buddy-${TeamHikeIdentity.key(buddy.phoneNumber)}',
                ),
                contentPadding: EdgeInsets.zero,
                title: Text(buddy.name),
                subtitle: Text(
                  buddy.handle.trim().isNotEmpty
                      ? '${buddy.handle}\n${buddy.phoneNumber}'
                      : buddy.phoneNumber,
                ),
                value: selectedKeys.contains(
                  TeamHikeIdentity.key(buddy.phoneNumber),
                ),
                onChanged:
                    !selectedKeys.contains(
                          TeamHikeIdentity.key(buddy.phoneNumber),
                        ) &&
                        selectedKeys.length >=
                            ImmediateTeamRoster.maximumInvitees
                    ? null
                    : (value) => _select(buddy, value == true),
              ),
            ),
        ],
      );
    },
  );
}
