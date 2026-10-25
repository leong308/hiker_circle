// RecordedTrailRequestsPage reviews proposed trails derived from recorded hikes.
import 'package:flutter/material.dart';
import '../../app/Model/app_session.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../home/Model/hike_session_models.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/Model/recorded_trail_request.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'admin_ui.dart';

/// Separate the request list from the detailed recorded-route review and approval flow.
class RecordedTrailRequestsPage extends StatefulWidget {
  const RecordedTrailRequestsPage({
    super.key,
    required this.session,
    required this.repository,
    this.recordedMapBuilder,
  });
  final Widget Function(Trail, List<HikeCoordinate>)? recordedMapBuilder;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  @override
  State<RecordedTrailRequestsPage> createState() =>
      _RecordedTrailRequestsPageState();
}

class _RecordedTrailRequestsPageState extends State<RecordedTrailRequestsPage> {
  List<Map<String, dynamic>>? rows;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final data = await widget.repository.loadAdminTrailRequests(
        session: widget.session,
      );
      if (mounted) {
        setState(() => rows = data);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Trail requests could not load. Refresh to retry.',
        );
      }
    }
  }

  Future<void> open(Map<String, dynamic> request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RecordedTrailReviewPage(
          session: widget.session,
          repository: widget.repository,
          request: request,
          recordedMapBuilder: widget.recordedMapBuilder,
        ),
      ),
    );
    if (mounted) {
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminUi.background(context),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            AdminHeading(
              title: 'Undiscovered trail requests',
              subtitle:
                  'Review a hiker’s full recording before adding a route.',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 18),
            if (error != null)
              AdminPanel(
                child: Column(
                  children: [
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Retry')),
                  ],
                ),
              )
            else if (rows == null)
              const Center(child: CircularProgressIndicator())
            else if (rows!.isEmpty)
              const AdminEmptyState(
                title: 'No requests awaiting review',
                message: 'New recorded-route submissions will appear here.',
                icon: Icons.route_outlined,
              )
            else
              for (final request in rows!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminPanel(
                    onTap: () => open(request),
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_rounded,
                          color: AdminUi.green(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (request['proposed'] as Map)['name'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${request['pointCount']} GPS samples · ${(request['checkpoints'] as List).length} checkpoints',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AdminUi.muted(context),
                                ),
                              ),
                              Text(
                                '${(request['proposed'] as Map)['area']} · ${(request['proposed'] as Map)['state']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AdminUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class _RecordedTrailReviewPage extends StatefulWidget {
  const _RecordedTrailReviewPage({
    required this.session,
    required this.repository,
    required this.request,
    this.recordedMapBuilder,
  });
  final Widget Function(Trail, List<HikeCoordinate>)? recordedMapBuilder;
  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final Map<String, dynamic> request;
  @override
  State<_RecordedTrailReviewPage> createState() =>
      _RecordedTrailReviewPageState();
}

class _RecordedTrailReviewPageState extends State<_RecordedTrailReviewPage> {
  List<HikeCoordinate>? points;
  List<mapbox.Point>? mapPoints;
  Trail? candidate;
  String? error;
  bool saving = false, verified = false;
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      area = TextEditingController(),
      state = TextEditingController(),
      country = TextEditingController(),
      duration = TextEditingController(),
      elevation = TextEditingController(),
      note = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [name, area, state, country, duration, elevation, note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      final loaded = await widget.repository.loadRecordedTrailRequestPoints(
        session: widget.session,
        requestId: widget.request['requestId'] as String,
      );
      final trail = recordedTrailCandidate(widget.request, loaded);
      if (!mounted) {
        return;
      }
      setState(() {
        points = loaded;
        mapPoints = [
          for (final p in loaded)
            mapbox.Point(coordinates: mapbox.Position(p.longitude, p.latitude)),
        ];
        candidate = trail;
        name.text = trail.name;
        area.text = trail.area;
        state.text = trail.state;
        country.text = trail.country;
        duration.text = '${trail.estimatedDurationMinutes}';
        elevation.text = '${trail.elevationGainMeters}';
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is HikerCircleFirebaseRepositoryException
              ? e.message
              : 'The full recording could not load. Reopen this request to retry.',
        );
      }
    }
  }

  Future<void> publish() async {
    if (saving || candidate == null || form.currentState?.validate() != true) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.approveRecordedTrailRequest(
        session: widget.session,
        requestId: widget.request['requestId'] as String,
        points: points!,
        trail: candidate!.copyWith(
          name: name.text.trim(),
          area: area.text.trim(),
          state: state.text.trim(),
          country: country.text.trim(),
          estimatedDurationMinutes: int.parse(duration.text),
          elevationGainMeters: int.parse(elevation.text),
          isVerifiedTrail: verified,
        ),
      );
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is HikerCircleFirebaseRepositoryException
              ? e.message
              : 'Unable to add this trail. The request remains available; retry after checking your connection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> reject() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this trail request?'),
        content: TextField(
          controller: note,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Review note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject request'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    setState(() => saving = true);
    try {
      await widget.repository.rejectRecordedTrailRequest(
        session: widget.session,
        requestId: widget.request['requestId'] as String,
        note: note.text,
      );
      if (mounted) {
        setState(() => saving = false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'The decision could not save. Retry before leaving this request.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      backgroundColor: AdminUi.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminHeading(
                  title: 'Review undiscovered trail',
                  subtitle:
                      'Full GPS pathway with the hiker’s chosen checkpoints.',
                  onBack: saving ? null : () => Navigator.pop(context),
                ),
                const SizedBox(height: 18),
                if (candidate == null && error == null)
                  const Center(child: CircularProgressIndicator()),
                if (candidate != null) ...[
                  SizedBox(
                    height: 300,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child:
                          widget.recordedMapBuilder?.call(
                            candidate!,
                            points!,
                          ) ??
                          RoutePreviewMap(
                            trail: candidate!,
                            recordedTrackPoints: mapPoints!,
                            pinnedPoints: [
                              for (final c in candidate!.checkpoints)
                                mapbox.Point(
                                  coordinates: mapbox.Position(
                                    c.longitude,
                                    c.latitude,
                                  ),
                                ),
                            ],
                            animateRoute: false,
                            captureAllGestures: true,
                          ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AdminPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${points!.length} GPS samples · ${candidate!.distanceKm.toStringAsFixed(2)} km recorded',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The pathway comes from this hiker’s GPS recording. No routing API will redraw it through checkpoints. Review gaps, permissions and terrain before publishing. Typical duration below is editable; the recorded hike duration is only an initial estimate.',
                        ),
                        const SizedBox(height: 8),
                        for (final c in candidate!.checkpoints)
                          Text(
                            '${c.order}. ${c.name} · ${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final pair in [
                    ('Trail name', name),
                    ('Area / locality', area),
                    ('State / region', state),
                    ('Country', country),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: pair.$2,
                        enabled: !saving,
                        maxLength: 160,
                        decoration: InputDecoration(
                          labelText: pair.$1,
                          counterText: '',
                        ),
                        validator: (v) =>
                            v?.trim().isNotEmpty == true ? null : 'Required',
                      ),
                    ),
                  TextFormField(
                    controller: duration,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Typical duration (minutes)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 15 && n <= 10080
                          ? null
                          : 'Enter 15–10080 minutes';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: elevation,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Elevation gain (m)',
                      helperText:
                          'Verify this estimate from recorded GPS altitude.',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n != null && n >= 0
                          ? null
                          : 'Enter a non-negative elevation gain';
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark trail as verified'),
                    value: verified,
                    onChanged: saving
                        ? null
                        : (v) => setState(() => verified = v),
                  ),
                  FilledButton.icon(
                    onPressed: saving ? null : publish,
                    icon: const Icon(Icons.add_road_rounded),
                    label: const Text('Add to trail library'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: saving ? null : reject,
                    child: const Text('Reject request'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
