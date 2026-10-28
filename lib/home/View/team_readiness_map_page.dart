import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../core/widgets/colored_location_map.dart';
import '../../core/widgets/page_header_style.dart';
import '../Model/hike_session_models.dart';
import '../Model/team_hike_identity.dart';
import '../ModelView/team_readiness_location_view_model.dart';

/// Displays only the current team's latest recorded positions using its saved colour identities.
class TeamReadinessMapPage extends StatefulWidget {
  /// Receives the same roster stream as readiness; no profile-location lookup or hike tracking is started.
  const TeamReadinessMapPage({
    super.key,
    required this.initialTeam,
    required this.teams,
    required this.currentPhoneNumber,
    this.mapBuilder,
  });
  final TeamHikeSession initialTeam;
  final Stream<TeamHikeSession?> teams;
  final String currentPhoneNumber;
  final Widget Function(mapbox.MapWidget configuration)? mapBuilder;

  /// Owns only the page's displayed age clock.
  @override
  State<TeamReadinessMapPage> createState() => _TeamReadinessMapPageState();
}

/// Keeps capture-age labels current while Firestore supplies recorded location updates.
class _TeamReadinessMapPageState extends State<TeamReadinessMapPage> {
  Timer? _ticker;
  late TeamHikeSession _latest = widget.initialTeam;

  /// Refreshes age labels independently of new GPS records.
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Stops the age clock when returning to readiness.
  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Uses the common map controls and a scrollable, colour-matched roster legend.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: PageHeader(
              title: 'Team locations',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: StreamBuilder<TeamHikeSession?>(
              initialData: widget.initialTeam,
              stream: widget.teams,
              builder: (context, snapshot) {
                final candidate = snapshot.data;
                if (candidate != null &&
                    (_latest.updatedAt == null ||
                        candidate.updatedAt != null &&
                            !candidate.updatedAt!.isBefore(_latest.updatedAt!))) {
                  _latest = candidate;
                }
                final team = _latest;
                final member = team.participants.any(
                  (p) =>
                      TeamHikeIdentity.key(p.phoneNumber) ==
                          TeamHikeIdentity.key(widget.currentPhoneNumber) &&
                      p.status != TeamHikeParticipantStatus.ended,
                );
                if (snapshot.hasError || !member) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Team locations are unavailable. Return to readiness to check your membership.',
                      ),
                    ),
                  );
                }
                final now = DateTime.now().toUtc(),
                    located = TeamReadinessLocations.located(team, now: now);
                final points = located
                    .map(
                      (p) => ColoredLocationPoint(
                        id: TeamHikeIdentity.key(p.phoneNumber),
                        label:
                            TeamHikeIdentity.key(p.phoneNumber) ==
                                TeamHikeIdentity.key(widget.currentPhoneNumber)
                            ? '${p.buddy.shortName} (You)'
                            : p.buddy.shortName,
                        latitude: p.latestLocation!.latitude,
                        longitude: p.latestLocation!.longitude,
                        color: p.buddy.avatarColorValue,
                        stale: !p.hasFreshLocationAt(now),
                      ),
                    )
                    .toList();
                final trail = team.sharedDraft?.trail;
                final fallback = points.isNotEmpty
                    ? points.first.geometry
                    : mapbox.Point(
                        coordinates: mapbox.Position(
                          trail?.longitude ?? 101.97,
                          trail?.latitude ?? 4.21,
                        ),
                      );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ColoredLocationMap(
                        points: points,
                        fallback: fallback,
                        mapBuilder: widget.mapBuilder,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                      child: Text(
                        points.isEmpty
                            ? 'Waiting for recorded GPS locations.'
                            : 'Latest recorded GPS fixes · ${points.length}/${team.participants.length} hikers located. Older fixes are faded.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * .28,
                      child: Scrollbar(
                        child: ListView.builder(
                          key: const ValueKey('team-location-legend'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: team.participants.length,
                          itemBuilder: (context, index) {
                            final person = team.participants[index];
                            final self =
                                TeamHikeIdentity.key(person.phoneNumber) ==
                                TeamHikeIdentity.key(widget.currentPhoneNumber);
                            return ListTile(
                              dense: true,
                              leading: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Color(person.buddy.avatarColorValue),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: .6),
                                  ),
                                ),
                              ),
                              title: Text(
                                self
                                    ? '${person.buddy.name} (You)'
                                    : person.buddy.name,
                              ),
                              subtitle: Text(
                                TeamReadinessLocations.label(person, now),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
