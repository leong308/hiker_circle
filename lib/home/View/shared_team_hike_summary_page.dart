import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../core/widgets/page_header_style.dart';
import '../Model/hike_session_models.dart';
import '../Model/shared_team_hike_summary.dart';
import '../ModelView/shared_team_hike_summary_view_model.dart';
import 'widgets/team_hike_summary_panel.dart';

/// Opens the saved result immediately and follows the common team's completion snapshots.
class SharedTeamHikeSummaryPage extends StatefulWidget {
  /// Retains an offline end snapshot until this member's completion reaches the server.
  const SharedTeamHikeSummaryPage({
    super.key,
    required this.initialSummary,
    required this.teams,
    required this.ownerPhone,
    this.onShare,
    this.mapBuilder,
  });
  final SharedTeamHikeSummary initialSummary;
  final Stream<TeamHikeSession?> teams;
  final String ownerPhone;
  final VoidCallback? onShare;
  final Widget Function(mapbox.MapWidget)? mapBuilder;

  /// Owns only the monotonic selection of the shared summary stream.
  @override
  State<SharedTeamHikeSummaryPage> createState() =>
      _SharedTeamHikeSummaryPageState();
}

/// Binds common team snapshots without allowing old cached results to replace a final map.
class _SharedTeamHikeSummaryPageState extends State<SharedTeamHikeSummaryPage> {
  late final _model = SharedTeamHikeSummaryViewModel(
    widget.initialSummary,
    widget.ownerPhone,
  );

  /// Uses one layout for provisional and final common team results.
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: StreamBuilder<TeamHikeSession?>(
        stream: widget.teams,
        builder: (context, snapshot) {
          final summary = _model.resolve(snapshot.data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              PageHeader(
                title: 'Team hike summary',
                subtitle: summary.trailName,
                onBack: () => Navigator.pop(context),
              ),
              const SizedBox(height: 14),
              TeamHikeSummaryPanel(
                summary: summary,
                mapBuilder: widget.mapBuilder,
              ),
              const SizedBox(height: 18),
              if (widget.onShare != null)
                FilledButton.icon(
                  onPressed: widget.onShare,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share your hike'),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to Home'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
