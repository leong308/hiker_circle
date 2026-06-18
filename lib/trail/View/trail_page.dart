import 'dart:async';


import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../core/services/geoapify_service.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/trail_cover_image_service.dart';
import '../../core/widgets/map_controls.dart';
import '../../core/widgets/map_utils.dart';
import '../../core/widgets/route_preview_map.dart';
import '../../onboarding/Data/google_city_geocoding_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../Model/trail_models.dart';

Future<Trail?> showAddTrailSheet(BuildContext context) {
  return Navigator.of(context).push<Trail>(
    MaterialPageRoute(
      builder: (_) => const _AddTrailSheet(),
    ),
  );
}

Future<Trail?> showEditTrailSheet(BuildContext context, Trail trail) {
  return Navigator.of(context).push<Trail>(
    MaterialPageRoute(
      builder: (_) => _EditTrailPage(trail: trail),
    ),
  );
}

class TrailPage extends StatefulWidget {
  const TrailPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.onStartHike,
    this.initialTrails,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Future<void> Function(Trail trail) onStartHike;
  final List<Trail>? initialTrails;

  @override
  State<TrailPage> createState() => _TrailPageState();
}

class _TrailPageState extends State<TrailPage> {
  late List<Trail> _trails;
  late final Set<String> _downloadedTrailIds;
  String _query = '';
  String _filter = 'Nearby';
  bool _isLoadingTrails = false;

  @override
  void initState() {
    super.initState();
    _trails = List.of(widget.initialTrails ?? const []);
    _downloadedTrailIds = {
      for (final trail in _trails)
        if (trail.offlineMapDownloaded) trail.trailId,
    };
    unawaited(_loadLiveTrails());
  }

  Future<void> _loadLiveTrails() async {
    setState(() {
      _isLoadingTrails = true;
    });
    try {
      if (widget.session.isAdmin) {
        try {
          await widget.hikerCircleRepository.deleteLegacyFirebaseDummyData(
            session: widget.session,
          );
        } catch (_) {
          // Cleanup is best effort; trail loading should still continue.
        }
      }
      final liveTrails = await widget.hikerCircleRepository.loadTrails();
      if (!mounted) {
        return;
      }
      setState(() {
        _trails = liveTrails;
        _downloadedTrailIds
          ..clear()
          ..addAll(
            liveTrails
                .where((trail) => trail.offlineMapDownloaded)
                .map((trail) => trail.trailId),
          );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  List<Trail> get _visibleTrails {
    return _trails.where((trail) {
      final matchesQuery =
          _query.isEmpty ||
          trail.name.toLowerCase().contains(_query) ||
          trail.area.toLowerCase().contains(_query) ||
          trail.state.toLowerCase().contains(_query);
      final matchesFilter = switch (_filter) {
        'Beginner' => trail.difficulty == 'Easy',
        'Offline' => _downloadedTrailIds.contains(trail.trailId),
        'Saved' => trail.isVerifiedTrail,
        'Popular' => trail.ratingAverage >= 4.5,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _addTrail() async {
    if (!widget.session.isAdmin) {
      return;
    }

    final trail = await showAddTrailSheet(context);
    if (trail == null || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await widget.hikerCircleRepository.createTrailByAdmin(
        session: widget.session,
        trail: trail,
      );
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} added to Firebase trails.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  Future<void> _editTrailFromCard(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final updatedTrail = await showEditTrailSheet(context, trail);
    if (updatedTrail == null || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await widget.hikerCircleRepository.updateTrailByAdmin(
        session: widget.session,
        trail: updatedTrail,
      );
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Trail updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  Future<void> _deleteTrail(Trail trail) async {
    if (!widget.session.isAdmin) {
      return;
    }

    final shouldDelete = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Delete trail?'),
          content: Text('${trail.name} will be removed from Firebase trails.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      _isLoadingTrails = true;
    });
    try {
      await widget.hikerCircleRepository.deleteTrailByAdmin(
        session: widget.session,
        trail: trail,
      );
      await _loadLiveTrails();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${trail.name} deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _TrailColors.redFor(context),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrails = false;
        });
      }
    }
  }

  void _openTrail(Trail trail) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrailDetailPage(
          session: widget.session,
          hikerCircleRepository: widget.hikerCircleRepository,
          trail: trail,
          onStartHike: widget.onStartHike,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadedTrails = _trails
        .where((trail) => _downloadedTrailIds.contains(trail.trailId))
        .toList();

    return ColoredBox(
      color: _TrailColors.backgroundFor(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    isAdmin: widget.session.isAdmin,
                    onAddTrail: () => unawaited(_addTrail()),
                  ),
                  if (_isLoadingTrails) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 16),
                  _DiscoverHero(
                    trails: _trails,
                    downloadedCount: downloadedTrails.length,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search trail, hill or area...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value.trim().toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _FilterChips(
                    selectedFilter: _filter,
                    onSelected: (filter) {
                      setState(() {
                        _filter = filter;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  _TrailInsightStrip(
                    visibleCount: _visibleTrails.length,
                    downloadedCount: downloadedTrails.length,
                    hazardCount: _visibleTrails.fold<int>(
                      0,
                      (count, trail) => count + trail.hazards.length,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Best Matches'),
                  const SizedBox(height: 8),
                  if (_visibleTrails.isEmpty)
                    _EmptyState(
                      message: _trails.isEmpty
                          ? 'No Firebase trails are available yet. Add a real trail from the admin tools.'
                          : 'No trails match this filter.',
                    )
                  else
                    for (final trail in _visibleTrails) ...[
                      _TrailCard(
                        trail: trail,
                        isDownloaded: _downloadedTrailIds.contains(
                          trail.trailId,
                        ),
                        onOpenTrail: () => _openTrail(trail),
                        onEditTrail: widget.session.isAdmin
                            ? () => _editTrailFromCard(trail)
                            : null,
                        onDeleteTrail: widget.session.isAdmin
                            ? () => _deleteTrail(trail)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 10),
                  _SectionTitle(label: 'Offline Ready Routes'),
                  const SizedBox(height: 8),
                  if (downloadedTrails.isEmpty)
                    const _EmptyState(
                      message:
                          'No routes are ready offline yet. Open a trail and download its route pack.',
                    )
                  else
                    for (final trail in downloadedTrails) ...[
                      _DownloadedMapCard(trail: trail),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrailDetailPage extends StatefulWidget {
  const TrailDetailPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.trail,
    required this.onStartHike,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Trail trail;
  final Future<void> Function(Trail trail) onStartHike;

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  late Trail _trail = widget.trail;
  final _scrollController = ScrollController();
  final _routePreviewKey = GlobalKey();
  int? _highlightedCheckpointIndex;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _trailSubscription;

  @override
  void initState() {
    super.initState();
    _trailSubscription = widget.hikerCircleRepository.firestore
        .collection('trails')
        .doc(_trail.trailId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final data = snapshot.data();
      if (data == null) return;
      final weatherData = data['weather'];
      if (weatherData == null) return;
      final weather = widget.hikerCircleRepository
          .weatherFromFirestore(weatherData);
      setState(() {
        _trail = _trail.copyWith(weather: weather);
      });
    });
    final weather = _trail.weather;
    if (weather.summary.isEmpty ||
        weather.summary == 'Weather unavailable' ||
        weather.temperatureRange == 'Not provided') {
      unawaited(_refreshWeather());
    }
  }

  @override
  void dispose() {
    _trailSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshWeather() async {
    final updated = await widget.hikerCircleRepository
        .refreshTrailWeatherViaCloud(_trail);
    if (!mounted) return;
    setState(() {
      _trail = updated;
    });
  }

  void _showCheckpointOnMap(int index) {
    setState(() {
      _highlightedCheckpointIndex = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _routePreviewKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _reportHazard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HazardReportPage(
          session: widget.session,
          hikerCircleRepository: widget.hikerCircleRepository,
          trail: _trail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trail = _trail;

    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  _TrailDetailHero(trail: trail),
                  const SizedBox(height: 14),
                  _MetricGroup(trail: trail),
                  const SizedBox(height: 14),
                                    _TrailPlanCard(
                    trail: trail,
                    onStartHike: () => unawaited(widget.onStartHike(trail)),
                    onSaveTrail: () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Trail saved to your profile.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Route Preview'),
                  const SizedBox(height: 8),
                  _RoutePreview(
                    key: _routePreviewKey,
                    trail: trail,
                    highlightedCheckpointIndex: _highlightedCheckpointIndex,
                    onHighlightCleared: () {
                      if (_highlightedCheckpointIndex != null) {
                        setState(() => _highlightedCheckpointIndex = null);
                      }
                    },
                    localDatabase: widget.hikerCircleRepository.localDatabase,
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Checkpoint Flow'),
                  const SizedBox(height: 8),
                  _CheckpointTimeline(
                    trail: trail,
                    highlightedIndex: _highlightedCheckpointIndex,
                    onShowOnMap: _showCheckpointOnMap,
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(
                    label: 'Conditions and Safety',
                    trailing: _WeatherInsightsButton(
                      trail: trail,
                      repository: widget.hikerCircleRepository,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _WeatherCard(trail: trail),
                  const SizedBox(height: 10),
                  _SafetyInfoCard(trail: trail),
                  if (trail.hazards.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    for (final hazard in trail.hazards) ...[
                      _HazardCard(hazard: hazard),
                      const SizedBox(height: 10),
                    ],
                  ],
                  FilledButton.icon(
                    onPressed: _reportHazard,
                    icon: const Icon(Icons.report_rounded),
                    label: const Text('Report Hazard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineMapDownloadPage extends StatefulWidget {
  const OfflineMapDownloadPage({super.key, required this.trail});

  final Trail trail;

  @override
  State<OfflineMapDownloadPage> createState() => _OfflineMapDownloadPageState();
}

class _OfflineMapDownloadPageState extends State<OfflineMapDownloadPage> {
  bool _isDownloaded = false;

  void _download() {
    setState(() {
      _isDownloaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(onBack: () => Navigator.of(context).pop(false)),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TrailCover(trail: widget.trail, height: 150),
                          const SizedBox(height: 14),
                          Text(
                            'Offline Trail Map',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _TrailColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.trail.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _TrailColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          _StatusRow(label: 'Map package', value: 'Prepared'),
                          const _HorizontalSeparator(),
                          _StatusRow(
                            label: 'Route file',
                            value: widget.trail.routeFilePath.isEmpty
                                ? 'Not available'
                                : widget.trail.routeFilePath,
                          ),
                          const _HorizontalSeparator(),
                          const _StatusRow(
                            label: 'Estimated size',
                            value: '42 MB',
                          ),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(
                            value: _isDownloaded ? 1 : 0,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(4),
                            color: _TrailColors.green,
                            backgroundColor: _TrailColors.greenSoftFor(context),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _isDownloaded
                                ? () => Navigator.of(context).pop(true)
                                : _download,
                            icon: Icon(
                              _isDownloaded
                                  ? Icons.check_rounded
                                  : Icons.download_rounded,
                            ),
                            label: Text(
                              _isDownloaded
                                  ? 'Use Downloaded Map'
                                  : 'Download Offline Trail Map',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HazardReportPage extends StatefulWidget {
  const HazardReportPage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    required this.trail,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Trail trail;

  @override
  State<HazardReportPage> createState() => _HazardReportPageState();
}

class _HazardReportPageState extends State<HazardReportPage> {
  final TextEditingController _descriptionController = TextEditingController();
  String _hazardType = 'Slippery pathway';
  String _severity = 'Moderate';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final location = await LocationSnapshotService.instance.refresh();
      await widget.hikerCircleRepository.submitHazardReport(
        session: widget.session,
        trail: widget.trail,
        hazardType: _hazardType,
        description: _descriptionController.text.trim().isEmpty
            ? 'No description provided.'
            : _descriptionController.text,
        severity: _severity,
        location: location,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Hazard report saved to Firebase as Community Report - Not Officially Verified.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to submit hazard report: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    const hazardTypes = [
      'Fallen tree',
      'Landslide',
      'Slippery pathway',
      'Flooded route',
      'Damaged steps or bridge',
      'Wild animal sighting',
      'Blocked route',
      'Unsafe human activity',
      'Other',
    ];

    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(onBack: () => Navigator.of(context).pop()),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Report Trail Hazard',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _TrailColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 14),
                          _ReadOnlyField(
                            label: 'Trail',
                            value: widget.trail.name,
                            icon: Icons.terrain_rounded,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _hazardType,
                            decoration: const InputDecoration(
                              labelText: 'Hazard Type',
                              prefixIcon: Icon(Icons.report_problem_rounded),
                            ),
                            items: [
                              for (final type in hazardTypes)
                                DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(type),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _hazardType = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          const _ReadOnlyField(
                            label: 'Detected Location',
                            value: 'Current GPS location attached',
                            icon: Icons.my_location_rounded,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.photo_camera_rounded),
                            label: const Text('Upload Photo'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final severity in [
                                'Low',
                                'Moderate',
                                'High',
                              ])
                                ChoiceChip(
                                  label: Text(severity),
                                  selected: _severity == severity,
                                  onSelected: (_) {
                                    setState(() {
                                      _severity = severity;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => unawaited(_submit()),
                            icon: const Icon(Icons.send_rounded),
                            label: Text(
                              _isSubmitting
                                  ? 'Submitting'
                                  : 'Submit Hazard Report',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isAdmin, required this.onAddTrail});

  final bool isAdmin;
  final VoidCallback onAddTrail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discover Trails',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _TrailColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  'Pick a route by conditions, safety, and team fit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _TrailColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: isAdmin ? 'Add trail' : 'Trail filters',
            child: IconButton(
              onPressed: isAdmin ? onAddTrail : null,
              icon: Icon(isAdmin ? Icons.add_rounded : Icons.tune_rounded),
              color: _TrailColors.green,
            ),
          ),
        ],
      ),
    );
  }
}

enum _AddTrailStep { pickCheckpoints, loading, form }

class _AddTrailSheet extends StatefulWidget {
  const _AddTrailSheet();

  @override
  State<_AddTrailSheet> createState() => _AddTrailSheetState();
}

class _AddTrailSheetState extends State<_AddTrailSheet> {
  static const String _defaultRouteFilePath =
      'offline/maps/admin_added_trail.mbtiles';

  var _step = _AddTrailStep.pickCheckpoints;
  final _trailPins = <mapbox.Point>[];

  final _nameController = TextEditingController();
  final _areaController = TextEditingController();
  final _stateController = TextEditingController();
  final _distanceController = TextEditingController();
  final _durationController = TextEditingController(text: '120');
  final _elevationController = TextEditingController();
  final _ratingController = TextEditingController(text: '4.5');
  final _coverImageController = TextEditingController();
  final List<_CheckpointDraft> _checkpoints = [];
  String _difficulty = 'Moderate';
  String? _errorMessage;
  bool _hasFetchedRoute = false;
  bool _locationFailed = false;
  HikingRouteResult? _routeResult;

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _stateController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    _elevationController.dispose();
    _ratingController.dispose();
    _coverImageController.dispose();
    for (final checkpoint in _checkpoints) {
      checkpoint.dispose();
    }
    super.dispose();
  }

  void _onPinsConfirmed(List<mapbox.Point> pins) {
    _trailPins
      ..clear()
      ..addAll(pins);

    final pin = pins.first;
    final lat = pin.coordinates[1]!.toDouble();
    final lng = pin.coordinates[0]!.toDouble();

    _checkpoints.clear();
    final draft = _CheckpointDraft(order: 1, name: 'Trailhead');
    draft.latitudeController.text = lat.toStringAsFixed(6);
    draft.longitudeController.text = lng.toStringAsFixed(6);
    _checkpoints.add(draft);

    unawaited(_resolveLocation(lat, lng));
    setState(() {
      _step = _AddTrailStep.form;
      _errorMessage = null;
    });
  }

  Future<void> _addCheckpointsOnMap() async {
    final existingPins = _checkpointModels().map(
      (c) => mapbox.Point(
        coordinates: mapbox.Position(c.longitude, c.latitude),
      ),
    ).toList();
    final confirmed = await Navigator.of(context).push<List<mapbox.Point>>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: _TrailColors.backgroundFor(context),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _MapBasedCheckpointPicker(
            singlePinMode: false,
            pins: existingPins,
            onPinsChanged: (_) {},
            onConfirm: (pins) => Navigator.of(context).pop(pins),
          ),
        ),
      ),
    );
    if (confirmed == null || !mounted) return;
    _checkpoints.clear();
    for (var i = 0; i < confirmed.length; i++) {
      final name = i == 0
          ? 'Trailhead'
          : i == confirmed.length - 1
              ? 'End point'
              : 'Waypoint $i';
      final draft = _CheckpointDraft(order: i + 1, name: name);
      draft.latitudeController.text =
          confirmed[i].coordinates[1]!.toDouble().toStringAsFixed(6);
      draft.longitudeController.text =
          confirmed[i].coordinates[0]!.toDouble().toStringAsFixed(6);
      _checkpoints.add(draft);
    }
    setState(() {});
  }

  void _removeCheckpoint(int index) {
    if (_checkpoints.length <= 2) return;
    setState(() {
      _checkpoints.removeAt(index).dispose();
    });
  }

  Future<HikingRouteResult?> _fetchRoute(
    List<TrailCheckpoint> checkpoints,
  ) async {
    try {
      final trail = Trail(
        trailId: '',
        name: '',
        area: '',
        state: '',
        latitude: checkpoints.first.latitude,
        longitude: checkpoints.first.longitude,
        distanceKm: 0,
        difficulty: _difficulty,
        estimatedDurationMinutes: 0,
        elevationGainMeters: 0,
        ratingAverage: 4.5,
        offlineMapAvailable: false,
        offlineMapDownloaded: false,
        isVerifiedTrail: true,
        routeFilePath: '',
        coverColorValue: 0xFF34A853,
        checkpoints: checkpoints,
        weather: TrailWeather(
          summary: '',
          temperatureRange: '',
          rainProbability: 0,
          cachedAt: DateTime.now().toUtc(),
        ),
        hazards: const [],
      );

      return await HikingRouteService().findHikingRouteForTrail(trail);
    } catch (_) {
      return null;
    }
  }

  void _applyRouteData(HikingRouteResult route, List<TrailCheckpoint>? checkpoints) {
    _distanceController.text =
        (route.distanceMeters / 1000).toStringAsFixed(1);
    _durationController.text = route.duration.inMinutes.toString();
    if (route.elevationGainMeters != null) {
      _elevationController.text =
          route.elevationGainMeters!.round().toString();
    }
    _hasFetchedRoute = true;

    final pts = checkpoints ?? _checkpointModels();
    if (pts.isNotEmpty) {
      unawaited(_resolveLocation(pts.first.latitude, pts.first.longitude));
    }
  }

  Future<void> _resolveLocation(double latitude, double longitude) async {
    try {
      final geocoding = GoogleCityGeocodingService();
      final result = await geocoding.resolveCity(
        latitude: latitude,
        longitude: longitude,
      );
      if (mounted) {
        setState(() {
          if (_areaController.text.isEmpty) {
            _areaController.text = result.city;
          }
          if (_stateController.text.isEmpty) {
            _stateController.text = result.state;
          }
        });
      }
      return;
    } catch (_) {
      try {
        final geoapify = GeoapifyService();
        final result = await geoapify.reverseGeocode(
          latitude: latitude,
          longitude: longitude,
        );
        if (mounted) {
          setState(() {
            if (_areaController.text.isEmpty && result.area.isNotEmpty) {
              _areaController.text = result.area;
            }
            if (_stateController.text.isEmpty && result.state.isNotEmpty) {
              _stateController.text = result.state;
            }
          });
        }
        return;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _locationFailed = true;
      });
    }
  }

  Future<void> _saveTrail() async {
    final name = _nameController.text.trim();
    final area = _areaController.text.trim();
    final state = _stateController.text.trim();
    final checkpoints = _checkpointModels();
    final latitude = checkpoints.isEmpty ? null : checkpoints.first.latitude;
    final longitude = checkpoints.isEmpty ? null : checkpoints.first.longitude;
    final rating = double.tryParse(_ratingController.text.trim()) ?? 4.5;

    if (name.isEmpty ||
        area.isEmpty ||
        state.isEmpty ||
        latitude == null ||
        longitude == null ||
        checkpoints.length < 2) {
      setState(() {
        _errorMessage = 'Fill in trail identity and add at least 2 checkpoints.';
      });
      return;
    }

    if (!_hasFetchedRoute) {
      setState(() {
        _step = _AddTrailStep.loading;
        _errorMessage = null;
      });
      try {
        final route = await _fetchRoute(checkpoints);
        if (!mounted) return;
        if (route != null) {
          _routeResult = route;
          _applyRouteData(route, checkpoints);
        }
      } catch (_) {
        if (!mounted) return;
      }
    }

    final distance = double.tryParse(_distanceController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    final elevation = int.tryParse(_elevationController.text.trim()) ?? 0;

    if (distance == null || distance <= 0 || duration == null || duration <= 0) {
      if (mounted) {
        setState(() {
          _step = _AddTrailStep.form;
          _errorMessage = 'Could not compute a route. Ensure your checkpoints are valid and try again.';
        });
      }
      return;
    }

    if (_hasFetchedRoute && checkpoints.length == 2) {
      _confirmSaveWithTwoCheckpoints(
        name: name,
        area: area,
        state: state,
        latitude: latitude,
        longitude: longitude,
        distance: distance,
        duration: duration,
        elevation: elevation,
        rating: rating,
        checkpoints: checkpoints,
      );
      return;
    }

    _doSaveTrail(
      name: name,
      area: area,
      state: state,
      latitude: latitude,
      longitude: longitude,
      distance: distance,
      duration: duration,
      elevation: elevation,
      rating: rating,
      checkpoints: checkpoints,
    );
  }

  void _confirmSaveWithTwoCheckpoints({
    required String name,
    required String area,
    required String state,
    required double latitude,
    required double longitude,
    required double distance,
    required int duration,
    required int elevation,
    required double rating,
    required List<TrailCheckpoint> checkpoints,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _TrailColors.surfaceFor(context),
        title: Text(
          'Only 2 checkpoints',
          style: TextStyle(color: _TrailColors.textFor(context)),
        ),
        content: Text(
          'A route was found with intermediate waypoints. Adding them '
          'improves navigation for hikers. Save with just trailhead and summit?',
          style: TextStyle(color: _TrailColors.secondaryTextFor(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _doSaveTrail(
                name: name,
                area: area,
                state: state,
                latitude: latitude,
                longitude: longitude,
                distance: distance,
                duration: duration,
                elevation: elevation,
                rating: rating,
                checkpoints: checkpoints,
              );
            },
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  void _doSaveTrail({
    required String name,
    required String area,
    required String state,
    required double latitude,
    required double longitude,
    required double distance,
    required int duration,
    required int elevation,
    required double rating,
    required List<TrailCheckpoint> checkpoints,
  }) {
    final polyline = _routeResult?.encodedPolyline;
    final hash = _routeResult != null
        ? HikingRouteService.checkpointsHash(checkpoints)
        : null;
    Navigator.of(context).pop(
      Trail(
        trailId: '',
        name: name,
        area: area,
        state: state,
        latitude: latitude,
        longitude: longitude,
        distanceKm: distance,
        difficulty: _difficulty,
        estimatedDurationMinutes: duration,
        elevationGainMeters: elevation,
        ratingAverage: rating.clamp(0, 5).toDouble(),
        offlineMapAvailable: false,
        offlineMapDownloaded: false,
        isVerifiedTrail: true,
        routeFilePath: _defaultRouteFilePath,
        coverColorValue: 0xFF34A853,
        coverImageUrl: _coverImageController.text.trim(),
        checkpoints: checkpoints,
        weather: TrailWeather(
          summary: 'Weather unavailable',
          temperatureRange: 'Not provided',
          rainProbability: 0,
          cachedAt: DateTime.now().toUtc(),
        ),
        hazards: const [],
        routeEncodedPolyline: polyline,
        routeCheckpointsHash: hash,
      ),
    );
  }

  List<TrailCheckpoint> _checkpointModels() {
    final checkpoints = <TrailCheckpoint>[];
    for (var index = 0; index < _checkpoints.length; index++) {
      final draft = _checkpoints[index];
      final name = draft.nameController.text.trim();
      final latitude = double.tryParse(draft.latitudeController.text.trim());
      final longitude = double.tryParse(draft.longitudeController.text.trim());
      if (name.isEmpty || latitude == null || longitude == null) {
        continue;
      }
      checkpoints.add(
        TrailCheckpoint(
          name: name,
          latitude: latitude,
          longitude: longitude,
          order: index + 1,
        ),
      );
    }
    return checkpoints;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (_step) {
        _AddTrailStep.pickCheckpoints => _buildCheckpointPicker(),
        _AddTrailStep.loading => _buildLoading(),
        _AddTrailStep.form => _buildForm(),
      },
    );
  }

  Widget _buildCheckpointPicker() {
    return _MapBasedCheckpointPicker(
      singlePinMode: true,
      pins: _trailPins,
      onPinsChanged: (pins) => _trailPins
        ..clear()
        ..addAll(pins),
      onConfirm: _onPinsConfirmed,
    );
  }

  Widget _buildLoading() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              'Finding a route through your checkpoints…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeMetricRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: _TrailColors.secondaryTextFor(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: _TrailColors.textFor(context),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          6,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add Trail',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Creating a new hiking trail. '
              'Route metrics are auto-filled from the routing API.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _TrailFormError(message: _errorMessage!),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Trail name',
                prefixIcon: Icon(Icons.terrain_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _areaController,
                    readOnly: !_locationFailed,
                    decoration: InputDecoration(
                      labelText: 'Area',
                      hintText: _locationFailed ? 'Enter area manually' : null,
                      prefixIcon: _locationFailed
                          ? const Icon(Icons.edit_rounded, size: 18)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    readOnly: !_locationFailed,
                    decoration: InputDecoration(
                      labelText: 'State',
                      hintText: _locationFailed ? 'Enter state manually' : null,
                      prefixIcon: _locationFailed
                          ? const Icon(Icons.edit_rounded, size: 18)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (_locationFailed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFA8B8AE)
                          : const Color(0xFF6E6E73),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Auto location unavailable — you can type area and state',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFA8B8AE)
                            : const Color(0xFF6E6E73),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _difficulty,
              decoration: const InputDecoration(labelText: 'Difficulty'),
              items: const [
                DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                DropdownMenuItem(value: 'Expert', child: Text('Expert')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _difficulty = value;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _coverImageController,
              decoration: const InputDecoration(
                labelText: 'Cover image URL',
                hintText: 'https://...',
              ),
            ),
            if (_hasFetchedRoute) ...[
              const SizedBox(height: 10),
              _InsetGroup(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: _TrailColors.green,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Route found',
                            style: TextStyle(
                              color: _TrailColors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _routeMetricRow(
                        context, 'Distance',
                        '${(double.tryParse(_distanceController.text.trim()) ?? 0).toStringAsFixed(1)} km',
                      ),
                      const SizedBox(height: 4),
                      _routeMetricRow(
                        context, 'Duration',
                        '${_durationController.text.trim()} min',
                      ),
                      if (_elevationController.text.trim().isNotEmpty &&
                          double.tryParse(_elevationController.text.trim()) != 0) ...[
                        const SizedBox(height: 4),
                        _routeMetricRow(
                          context, 'Elevation gain',
                          '${_elevationController.text.trim()} m',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _addCheckpointsOnMap,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add checkpoints on map'),
            ),
            const SizedBox(height: 14),
            const _SectionTitle(label: 'Checkpoints'),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _checkpoints.length,
              onReorderItem: (int oldIndex, int newIndex) {
                setState(() {
                  final draft = _checkpoints.removeAt(oldIndex);
                  _checkpoints.insert(newIndex, draft);
                });
              },
              itemBuilder: (context, index) {
                final draft = _checkpoints[index];
                return Padding(
                  key: ValueKey(draft.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CheckpointDraftFields(
                    draft: draft,
                    index: index,
                    canRemove: _checkpoints.length > 2,
                    onRemove: () => _removeCheckpoint(index),
                  ),
                );
              },
            ),
            FilledButton.icon(
              onPressed: _saveTrail,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Add Trail to Firebase'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapBasedCheckpointPicker extends StatefulWidget {
  const _MapBasedCheckpointPicker({
    required this.pins,
    required this.onPinsChanged,
    required this.onConfirm,
    this.singlePinMode = false,
  });

  final List<mapbox.Point> pins;
  final ValueChanged<List<mapbox.Point>> onPinsChanged;
  final ValueChanged<List<mapbox.Point>> onConfirm;
  final bool singlePinMode;

  @override
  State<_MapBasedCheckpointPicker> createState() =>
      _MapBasedCheckpointPickerState();
}

class _MapBasedCheckpointPickerState
    extends State<_MapBasedCheckpointPicker> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  bool _styleLoaded = false;
  late List<mapbox.Point> _pins;

  @override
  void initState() {
    super.initState();
    _pins = List<mapbox.Point>.of(widget.pins);
  }

  @override
  void didUpdateWidget(_MapBasedCheckpointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.pins, _pins)) {
      _pins = List<mapbox.Point>.of(widget.pins);
      unawaited(_syncPins());
    }
  }

  static bool listEquals(List<mapbox.Point>? a, List<mapbox.Point>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].coordinates[1] != b[i].coordinates[1] ||
          a[i].coordinates[0] != b[i].coordinates[0]) {
        return false;
      }
    }
    return true;
  }

  mapbox.Point _initialCenter() =>
      _pins.isNotEmpty
          ? _pins.first
          : mapbox.Point(coordinates: mapbox.Position(101.6869, 3.1390));

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await mapboxMap.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        rotateEnabled: true,
        pitchEnabled: true,
      ),
    );
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 21),
    );
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _pointManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: _initialCenter(),
        zoom: _pins.isNotEmpty ? 15 : 6,
      ),
      mapbox.MapAnimationOptions(duration: 0),
    );
    await _syncPins();
  }

  Future<void> _onStyleLoaded() async {
    await enableTerrain3D(_mapboxMap!);
    schedulePitch(_mapboxMap!);
    _styleLoaded = true;
    await _syncPins();
  }

  Future<void> _syncPins() async {
    if (!_styleLoaded) return;
    await _circleManager?.deleteAll();
    await _pointManager?.deleteAll();

    for (var i = 0; i < _pins.length; i++) {
      final point = _pins[i];
      await _circleManager?.create(
        mapbox.CircleAnnotationOptions(
          geometry: point,
          circleRadius: 10,
          circleColor: const Color(0xFF34A853).toARGB32(),
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleStrokeWidth: 2.5,
        ),
      );
      await _pointManager?.create(
        mapbox.PointAnnotationOptions(
          geometry: point,
          textField: '${i + 1}',
          textSize: 11,
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xFF111111,
          textHaloWidth: 0.7,
          textAnchor: mapbox.TextAnchor.CENTER,
        ),
      );
    }
  }

  int? _tappedPinIndex(mapbox.Point tapped) {
    for (var i = 0; i < _pins.length; i++) {
      final dlat = (tapped.coordinates[1] ?? 0) - (_pins[i].coordinates[1] ?? 0);
      final dlng = (tapped.coordinates[0] ?? 0) - (_pins[i].coordinates[0] ?? 0);
      if (dlat.abs() + dlng.abs() < 0.001) return i;
    }
    return null;
  }

  void _onMapTap(mapbox.Point coordinate) {
    final tappedIndex = _tappedPinIndex(coordinate);
    if (tappedIndex != null) {
      setState(() => _pins.removeAt(tappedIndex));
    } else {
      setState(() {
        if (widget.singlePinMode && _pins.isNotEmpty) {
          _pins.clear();
        }
        _pins.add(coordinate);
      });
    }
    widget.onPinsChanged(List.of(_pins));
    unawaited(_syncPins());
  }

  Future<void> _zoomBy(double amount) async {
    final map = _mapboxMap;
    if (map == null) return;
    final state = await map.getCameraState();
    await map.flyTo(
      mapbox.CameraOptions(zoom: state.zoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _fitPins() async {
    if (_pins.isEmpty) return;
    if (_pins.length == 1) {
      await _mapboxMap?.flyTo(
        mapbox.CameraOptions(center: _pins.first, zoom: 15),
        mapbox.MapAnimationOptions(duration: 300),
      );
    } else {
      await _mapboxMap?.flyTo(
        mapbox.CameraOptions(center: centerFor(_pins), zoom: 13),
        mapbox.MapAnimationOptions(duration: 300),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DeferredMap(
                  child: mapbox.MapWidget(
                    key: const ValueKey('checkpoint-picker'),
                    styleUri: mapStyleUrls[0],
                    gestureRecognizers: mapGestureRecognizers,
                    onMapCreated: _onMapCreated,
                    onStyleLoadedListener: (_) => _onStyleLoaded(),
                    onTapListener: (context) =>
                        _onMapTap(context.point),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: MapZoomControls(
                      onZoomIn: () => _zoomBy(1),
                      onZoomOut: () => _zoomBy(-1),
                      onReset: _fitPins,
                    ),
                  ),
                ),
                if (_pins.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: MapScaleBar(
                        zoom: 13,
                        latitude: (_pins.first.coordinates[1] ?? 0).toDouble(),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6,
                        ),
                        child: Text(
                          widget.singlePinMode
                              ? 'Tap the map to select a trail location'
                              : 'Tap to add pins · tap pin to remove',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pins.isEmpty
                          ? null
                          : () => widget.onConfirm(List.of(_pins)),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        widget.singlePinMode
                            ? 'Use this location'
                            : 'Confirm ${_pins.length} pin${_pins.length == 1 ? '' : 's'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinglePinPickerSheet extends StatefulWidget {
  const _SinglePinPickerSheet({
    required this.title,
    this.initialLatitude,
    this.initialLongitude,
  });

  final String title;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<_SinglePinPickerSheet> createState() => _SinglePinPickerSheetState();
}

class _SinglePinPickerSheetState extends State<_SinglePinPickerSheet> {
  late mapbox.Point _selected = mapbox.Point(
    coordinates: mapbox.Position(
      widget.initialLongitude ?? 101.6869,
      widget.initialLatitude ?? 3.1390,
    ),
  );
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _pointManager;
  bool _styleLoaded = false;

  void _selectCoordinate(mapbox.Point coordinate) {
    setState(() => _selected = coordinate);
    unawaited(_syncSelectedPin());
    unawaited(
      _mapboxMap?.flyTo(
        mapbox.CameraOptions(center: coordinate),
        mapbox.MapAnimationOptions(duration: 300),
      ),
    );
  }

  Future<void> _syncSelectedPin() async {
    if (!_styleLoaded) return;
    await _circleManager?.deleteAll();
    await _pointManager?.deleteAll();
    await _circleManager?.create(
      mapbox.CircleAnnotationOptions(
        geometry: _selected,
        circleRadius: 10,
        circleColor: const Color(0xFFE11D48).toARGB32(),
        circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        circleStrokeWidth: 3,
      ),
    );
    await _pointManager?.create(
      mapbox.PointAnnotationOptions(
        geometry: _selected,
        textField: 'Pin',
        textSize: 12,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF111111,
        textHaloWidth: 0.8,
        textOffset: const [0.0, 1.35],
        textAnchor: mapbox.TextAnchor.TOP,
      ),
    );
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await mapboxMap.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    await mapboxMap.logo.updateSettings(
      mapbox.LogoSettings(enabled: false),
    );
    await mapboxMap.gestures.updateSettings(
      mapbox.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        rotateEnabled: true,
        pitchEnabled: true,
      ),
    );
    await mapboxMap.setBounds(
      mapbox.CameraBoundsOptions(minZoom: 3, maxZoom: 21),
    );
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _pointManager =
        await mapboxMap.annotations.createPointAnnotationManager();
    await mapboxMap.flyTo(
      mapbox.CameraOptions(center: _selected, zoom: 15),
      mapbox.MapAnimationOptions(duration: 0),
    );
    await _syncSelectedPin();
  }

  Future<void> _zoomBy(double amount) async {
    final map = _mapboxMap;
    if (map == null) return;
    final state = await map.getCameraState();
    await map.flyTo(
      mapbox.CameraOptions(zoom: state.zoom + amount),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18, 6, 18, 18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the map to place the pin, then confirm the selected coordinate.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DeferredMap(
                      child: mapbox.MapWidget(
                        key: const ValueKey('single-pin-picker'),
                        styleUri: mapStyleUrls[0],
                        gestureRecognizers: mapGestureRecognizers,
                        onMapCreated: _onMapCreated,
                        onStyleLoadedListener: (_) {
                          unawaited(enableTerrain3D(_mapboxMap!));
                          schedulePitch(_mapboxMap!);
                          _styleLoaded = true;
                          unawaited(_syncSelectedPin());
                        },
                        onTapListener: (context) {
                          _selectCoordinate(context.point);
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: MapZoomControls(
                          onZoomIn: () => _zoomBy(1),
                          onZoomOut: () => _zoomBy(-1),
                          onReset: () => _mapboxMap?.flyTo(
                            mapbox.CameraOptions(center: _selected, zoom: 15),
                            mapbox.MapAnimationOptions(duration: 300),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use Location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointDraft {
  _CheckpointDraft({required int order, required String name})
    : id = _nextId++,
      nameController = TextEditingController(text: name),
      latitudeController = TextEditingController(),
      longitudeController = TextEditingController();

  static int _nextId = 0;
  final int id;
  final TextEditingController nameController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;

  void dispose() {
    nameController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
  }
}

class _CheckpointDraftFields extends StatelessWidget {
  const _CheckpointDraftFields({
    required this.draft,
    required this.index,
    required this.canRemove,
    this.onRemove,
  });

  final _CheckpointDraft draft;
  final int index;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(
                Icons.drag_handle_rounded,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _TrailColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: draft.nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ),
            if (canRemove && onRemove != null) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Remove checkpoint',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrailFormError extends StatelessWidget {
  const _TrailFormError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _TrailColors.redFor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _TrailColors.redFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DiscoverHero extends StatelessWidget {
  const _DiscoverHero({required this.trails, required this.downloadedCount});

  final List<Trail> trails;
  final int downloadedCount;

  @override
  Widget build(BuildContext context) {
    final topTrail = trails.isEmpty ? null : trails.first;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(icon: Icons.explore_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topTrail == null
                        ? 'Build your next hiking plan'
                        : 'Suggested for today: ${topTrail.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _TrailColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compare difficulty, forecast, hazard reports, and offline readiness before you commit.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        label: '${trails.length} routes',
                        color: _TrailColors.green,
                      ),
                      _StatusPill(
                        label: '$downloadedCount offline',
                        color: _TrailColors.blue,
                      ),
                      const _StatusPill(
                        label: 'Firebase live',
                        color: _TrailColors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailInsightStrip extends StatelessWidget {
  const _TrailInsightStrip({
    required this.visibleCount,
    required this.downloadedCount,
    required this.hazardCount,
  });

  final int visibleCount;
  final int downloadedCount;
  final int hazardCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          Expanded(
            child: _InsightTile(
              label: 'Matches',
              value: '$visibleCount',
              icon: Icons.filter_alt_rounded,
              color: _TrailColors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InsightTile(
              label: 'Offline',
              value: '$downloadedCount',
              icon: Icons.download_done_rounded,
              color: _TrailColors.blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _InsightTile(
              label: 'Hazards',
              value: '$hazardCount',
              icon: Icons.warning_amber_rounded,
              color: _TrailColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 18),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: const _CircleIcon(icon: CupertinoIcons.chevron_back),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Trail',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _TrailColors.textFor(context),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selectedFilter, required this.onSelected});

  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = ['Nearby', 'Popular', 'Beginner', 'Saved', 'Offline'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            ChoiceChip(
              label: Text(filter),
              selected: selectedFilter == filter,
              onSelected: (_) => onSelected(filter),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TrailCard extends StatelessWidget {
  const _TrailCard({
    required this.trail,
    required this.isDownloaded,
    required this.onOpenTrail,
    this.onEditTrail,
    this.onDeleteTrail,
  });

  final Trail trail;
  final bool isDownloaded;
  final VoidCallback onOpenTrail;
  final Future<void> Function()? onEditTrail;
  final Future<void> Function()? onDeleteTrail;

  @override
  Widget build(BuildContext context) {
    final card = _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenTrail,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _TrailCover(trail: trail, height: 94, width: 96),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trail.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _TrailColors.textFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        trail.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TrailColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${trail.distanceLabel} - ${trail.difficulty} - Approx. ${trail.durationLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TrailColors.textFor(context),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatusPill(
                            label:
                                '${trail.ratingAverage.toStringAsFixed(1)} rating',
                            color: _TrailColors.green,
                          ),
                          if (trail.offlineMapAvailable)
                            _StatusPill(
                              label: isDownloaded
                                  ? 'Offline Ready'
                                  : 'Offline Available',
                              color: _TrailColors.blue,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_forward, size: 16),
              ],
            ),
          ),
        ),
      ),
    );

    if (onEditTrail == null || onDeleteTrail == null) {
      return card;
    }

    return Dismissible(
      key: ValueKey('trail-${trail.trailId}-${trail.name}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await onEditTrail?.call();
          return false;
        }

        await onDeleteTrail?.call();
        return false;
      },
      background: const _TrailSwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: _TrailColors.green,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      secondaryBackground: _TrailSwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _TrailColors.redFor(context),
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      child: card,
    );
  }
}

class _TrailSwipeActionBackground extends StatelessWidget {
  const _TrailSwipeActionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment == Alignment.centerLeft;

    return Container(
      color: color,
      alignment: alignment,
      padding: EdgeInsets.only(left: isLeft ? 18 : 0, right: isLeft ? 0 : 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedMapCard extends StatelessWidget {
  const _DownloadedMapCard({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const _Glyph(icon: Icons.offline_bolt_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                trail.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _TrailColors.textFor(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            const _StatusPill(
              label: 'Available Offline',
              color: _TrailColors.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailDetailHero extends StatelessWidget {
  const _TrailDetailHero({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _TrailCover(trail: trail, height: 240),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0x00000000),
                    Color(0xCC000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeroPill(label: trail.difficulty),
                      if (trail.isVerifiedTrail)
                        const _HeroPill(label: 'Verified trail'),
                      _HeroPill(
                        label:
                            '${trail.ratingAverage.toStringAsFixed(1)} rating',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    trail.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trail.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailPlanCard extends StatelessWidget {
  const _TrailPlanCard({
    required this.trail,
    required this.onStartHike,
    required this.onSaveTrail,
  });

  final Trail trail;
  final VoidCallback onStartHike;
  final VoidCallback onSaveTrail;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.route_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan this hike',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _TrailColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        _planSummary(trail),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _TrailColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onStartHike,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSaveTrail,
                    icon: const Icon(Icons.bookmark_add_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditTrailPage extends StatefulWidget {
  const _EditTrailPage({required this.trail});

  final Trail trail;

  @override
  State<_EditTrailPage> createState() => _EditTrailPageState();
}

class _EditTrailPageState extends State<_EditTrailPage> {
  late final _nameController = TextEditingController(text: widget.trail.name);
  late final _areaController = TextEditingController(text: widget.trail.area);
  late final _stateController = TextEditingController(text: widget.trail.state);
  late String _difficulty = widget.trail.difficulty;
  late final List<_CheckpointDraft> _checkpoints = widget.trail.checkpoints
      .map((c) => _CheckpointDraft(order: c.order, name: c.name)
        ..latitudeController.text = c.latitude.toStringAsFixed(6)
        ..longitudeController.text = c.longitude.toStringAsFixed(6))
      .toList();

  HikingRouteResult? _refreshedRoute;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _stateController.dispose();
    for (final c in _checkpoints) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addCheckpointsOnMap() async {
    final models = _buildCheckpointModels();
    final existingPins = models.map(
      (c) => mapbox.Point(
        coordinates: mapbox.Position(c.longitude, c.latitude),
      ),
    ).toList();
    final confirmed = await Navigator.of(context).push<List<mapbox.Point>>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: _TrailColors.backgroundFor(context),
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _MapBasedCheckpointPicker(
            singlePinMode: false,
            pins: existingPins,
            onPinsChanged: (_) {},
            onConfirm: (pins) => Navigator.of(context).pop(pins),
          ),
        ),
      ),
    );
    if (confirmed == null || !mounted) return;
    for (final c in _checkpoints) {
      c.dispose();
    }
    _checkpoints.clear();
    for (var i = 0; i < confirmed.length; i++) {
      final name = i == 0
          ? 'Trailhead'
          : i == confirmed.length - 1
              ? 'End point'
              : 'Waypoint $i';
      final draft = _CheckpointDraft(order: i + 1, name: name);
      draft.latitudeController.text =
          confirmed[i].coordinates[1]!.toDouble().toStringAsFixed(6);
      draft.longitudeController.text =
          confirmed[i].coordinates[0]!.toDouble().toStringAsFixed(6);
      _checkpoints.add(draft);
    }
    setState(() {});
  }

  void _removeCheckpoint(int index) {
    if (_checkpoints.length <= 2) return;
    setState(() {
      _checkpoints.removeAt(index).dispose();
    });
  }

  Future<void> _refreshMetrics() async {
    final models = _buildCheckpointModels();
    if (models.length < 2) return;

    setState(() => _isRefreshing = true);

    try {
      final trail = Trail(
        trailId: widget.trail.trailId,
        name: widget.trail.name,
        area: widget.trail.area,
        state: widget.trail.state,
        latitude: models.first.latitude,
        longitude: models.first.longitude,
        distanceKm: 0,
        difficulty: _difficulty,
        estimatedDurationMinutes: 0,
        elevationGainMeters: 0,
        ratingAverage: widget.trail.ratingAverage,
        offlineMapAvailable: widget.trail.offlineMapAvailable,
        offlineMapDownloaded: widget.trail.offlineMapDownloaded,
        isVerifiedTrail: widget.trail.isVerifiedTrail,
        routeFilePath: widget.trail.routeFilePath,
        coverColorValue: widget.trail.coverColorValue,
        coverImageUrl: widget.trail.coverImageUrl,
        checkpoints: models,
        weather: widget.trail.weather,
        hazards: widget.trail.hazards,
      );

      final route = await HikingRouteService().findHikingRouteForTrail(trail);
      if (mounted) {
        setState(() {
          _refreshedRoute = route;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  List<TrailCheckpoint> _buildCheckpointModels() {
    final models = <TrailCheckpoint>[];
    for (var i = 0; i < _checkpoints.length; i++) {
      final d = _checkpoints[i];
      final name = d.nameController.text.trim();
      final lat = double.tryParse(d.latitudeController.text.trim());
      final lng = double.tryParse(d.longitudeController.text.trim());
      if (name.isNotEmpty && lat != null && lng != null) {
        models.add(TrailCheckpoint(name: name, latitude: lat, longitude: lng, order: i + 1));
      }
    }
    return models;
  }

  void _save() {
    final models = _buildCheckpointModels();

    final updatedTrail = widget.trail.copyWith(
      name: _nameController.text.trim().isEmpty
          ? widget.trail.name
          : _nameController.text.trim(),
      area: _areaController.text.trim().isEmpty
          ? widget.trail.area
          : _areaController.text.trim(),
      state: _stateController.text.trim().isEmpty
          ? widget.trail.state
          : _stateController.text.trim(),
      difficulty: _difficulty,
      checkpoints: models.length >= 2 ? models : widget.trail.checkpoints,
      distanceKm: _refreshedRoute != null
          ? _refreshedRoute!.distanceMeters / 1000
          : widget.trail.distanceKm,
      estimatedDurationMinutes: _refreshedRoute != null
          ? _refreshedRoute!.duration.inMinutes
          : widget.trail.estimatedDurationMinutes,
      elevationGainMeters: _refreshedRoute != null
          ? (_refreshedRoute!.elevationGainMeters ?? widget.trail.elevationGainMeters).round()
          : widget.trail.elevationGainMeters,
    );
    Navigator.of(context).pop(updatedTrail);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TrailColors.backgroundFor(context),
      appBar: AppBar(
        title: const Text('Edit Trail'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle(label: 'Trail Identity'),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Trail name',
                prefixIcon: Icon(Icons.terrain_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _areaController,
                    decoration: const InputDecoration(labelText: 'Area'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _SectionTitle(label: 'Difficulty'),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _difficulty,
              decoration: const InputDecoration(labelText: 'Difficulty'),
              items: const [
                DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                DropdownMenuItem(value: 'Moderate', child: Text('Moderate')),
                DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                DropdownMenuItem(value: 'Expert', child: Text('Expert')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _difficulty = value);
                }
              },
            ),
            const SizedBox(height: 20),
            _InsetGroup(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Route metrics',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: _TrailColors.secondaryTextFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isRefreshing ? null : _refreshMetrics,
                          icon: _isRefreshing
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(_isRefreshing ? 'Refreshing' : 'Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _metricRow(
                      context,
                      Icons.straighten_rounded,
                      'Distance',
                      _refreshedRoute?.distanceLabel ?? widget.trail.distanceLabel,
                    ),
                    const SizedBox(height: 6),
                    _metricRow(
                      context,
                      Icons.access_time_rounded,
                      'Duration',
                      _refreshedRoute?.durationLabel ?? widget.trail.durationLabel,
                    ),
                    const SizedBox(height: 6),
                    _metricRow(
                      context,
                      Icons.trending_up_rounded,
                      'Elevation gain',
                      _refreshedRoute != null
                          ? '${_refreshedRoute!.elevationGainMeters ?? 0} m'
                          : '${widget.trail.elevationGainMeters} m',
                    ),
                    const SizedBox(height: 6),
                    _metricRow(
                      context,
                      Icons.star_rounded,
                      'Rating',
                      widget.trail.ratingAverage.toStringAsFixed(1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Route metrics are determined by the routing API and '
                      'cannot be edited manually.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _TrailColors.secondaryTextFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => unawaited(_addCheckpointsOnMap()),
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add checkpoints on map'),
            ),
            const SizedBox(height: 14),
            const _SectionTitle(label: 'Checkpoints'),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _checkpoints.length,
              onReorderItem: (int oldIndex, int newIndex) {
                setState(() {
                  final draft = _checkpoints.removeAt(oldIndex);
                  _checkpoints.insert(newIndex, draft);
                });
              },
              itemBuilder: (context, index) {
                final draft = _checkpoints[index];
                return Padding(
                  key: ValueKey(draft.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CheckpointDraftFields(
                    draft: draft,
                    index: index,
                    canRemove: _checkpoints.length > 2,
                    onRemove: () => _removeCheckpoint(index),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _TrailColors.secondaryTextFor(context)),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CheckpointTimeline extends StatelessWidget {
  const _CheckpointTimeline({
    required this.trail,
    required this.highlightedIndex,
    required this.onShowOnMap,
  });

  final Trail trail;
  final int? highlightedIndex;
  final void Function(int index) onShowOnMap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Column(
          children: [
            for (var index = 0; index < trail.checkpoints.length; index++)
              _CheckpointRow(
                checkpoint: trail.checkpoints[index],
                isLast: index == trail.checkpoints.length - 1,
                index: index,
                isHighlighted: highlightedIndex == index,
                onShowOnMap: () => onShowOnMap(index),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({
    required this.checkpoint,
    required this.isLast,
    required this.index,
    required this.isHighlighted,
    required this.onShowOnMap,
  });

  final TrailCheckpoint checkpoint;
  final bool isLast;
  final int index;
  final bool isHighlighted;
  final VoidCallback onShowOnMap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isHighlighted
              ? _TrailColors.greenSoftFor(context)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? _TrailColors.green
                        : _TrailColors.greenSoftFor(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${checkpoint.order}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isHighlighted
                          ? Colors.white
                          : _TrailColors.green,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: _TrailColors.separatorFor(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      checkpoint.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _TrailColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${checkpoint.latitude.toStringAsFixed(5)}, ${checkpoint.longitude.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _TrailColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: IconButton(
                onPressed: onShowOnMap,
                icon: Icon(
                  Icons.near_me_rounded,
                  size: 20,
                  color: isHighlighted
                      ? _TrailColors.green
                      : _TrailColors.secondaryTextFor(context),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                tooltip: 'Show on map',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TrailCover extends StatelessWidget {
  const _TrailCover({required this.trail, required this.height, this.width});

  final Trail trail;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<String>(
              future: TrailCoverImageService.instance.imageUrlForTrail(trail),
              builder: (context, snapshot) {
                final imageUrl = snapshot.data ?? '';
                if (imageUrl.isEmpty) {
                  return _TrailCoverFallback(trail: trail);
                }

                return Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return _TrailCoverFallback(trail: trail);
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return _TrailCoverFallback(trail: trail);
                  },
                );
              },
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x11000000),
                    Color(0x05000000),
                    Color(0xAA000000),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Text(
                trail.locationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  shadows: const [
                    Shadow(
                      color: Color(0xAA000000),
                      offset: Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailCoverFallback extends StatelessWidget {
  const _TrailCoverFallback({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrailCoverPainter(color: Color(trail.coverColorValue)),
    );
  }
}

class _MetricGroup extends StatelessWidget {
  const _MetricGroup({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Expanded(
              child: _MetricCell(label: 'Distance', value: trail.distanceLabel),
            ),
            const _VerticalSeparator(),
            Expanded(
              child: _MetricCell(
                label: 'Elevation',
                value: '${trail.elevationGainMeters} m',
              ),
            ),
            const _VerticalSeparator(),
            Expanded(
              child: _MetricCell(
                label: 'Typical Time',
                value: trail.durationLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _TrailColors.textFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _RoutePreview extends StatefulWidget {
  const _RoutePreview({
    super.key,
    required this.trail,
    this.highlightedCheckpointIndex,
    this.onHighlightCleared,
    this.localDatabase,
  });

  final Trail trail;
  final int? highlightedCheckpointIndex;
  final VoidCallback? onHighlightCleared;
  final LocalSessionDatabase? localDatabase;

  @override
  State<_RoutePreview> createState() => _RoutePreviewState();
}

class _RoutePreviewState extends State<_RoutePreview> {
  late Future<HikingRouteResult> _routeFuture;

  @override
  void initState() {
    super.initState();
    _routeFuture = _loadHikingRoute();
  }

  @override
  void didUpdateWidget(covariant _RoutePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trail.trailId != widget.trail.trailId) {
      _routeFuture = _loadHikingRoute();
    }
  }

  Future<HikingRouteResult> _loadHikingRoute() {
    final service = HikingRouteService(
      localDatabase: widget.localDatabase,
    );
    return service.findHikingRouteForTrailWithCache(widget.trail);
  }

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 240,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<HikingRouteResult>(
            future: _routeFuture,
            builder: (context, snapshot) {
              final route = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              return RoutePreviewMap(
                key: ValueKey(
                  '${widget.trail.trailId}:${route?.encodedPolyline ?? 'checkpoints'}',
                ),
                trail: widget.trail,
                route: route?.encodedPolyline.isEmpty == true ? null : route,
                highlightedCheckpointIndex:
                    widget.highlightedCheckpointIndex,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WeatherInsightsButton extends StatelessWidget {
  const _WeatherInsightsButton({
    required this.trail,
    required this.repository,
  });

  final Trail trail;
  final HikerCircleFirebaseRepository repository;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: () => showWeatherInsightsSheet(
          context,
          trail: trail,
          repository: repository,
        ),
        icon: const Icon(Icons.analytics_rounded, size: 18),
        padding: EdgeInsets.zero,
        color: _TrailColors.secondaryTextFor(context),
        tooltip: 'Weather insights',
      ),
    );
  }
}

void showWeatherInsightsSheet(
  BuildContext context, {
  required Trail trail,
  required HikerCircleFirebaseRepository repository,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _TrailColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => _WeatherInsightsSheet(
      trail: trail,
      repository: repository,
    ),
  );
}

class _WeatherInsightsSheet extends StatefulWidget {
  const _WeatherInsightsSheet({
    required this.trail,
    required this.repository,
  });

  final Trail trail;
  final HikerCircleFirebaseRepository repository;

  @override
  State<_WeatherInsightsSheet> createState() => _WeatherInsightsSheetState();
}

class _WeatherInsightsSheetState extends State<_WeatherInsightsSheet> {
  late final Trail _trail = widget.trail;

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final weather = _trail.weather;
    final hourlyForecasts = weather.hourlyForecast;
    final hasExtraDetails = weather.feelsLike != null ||
        weather.windSpeed != null ||
        weather.humidity != null ||
        weather.uvIndex != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Forecast',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _TrailColors.textFor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Last refreshed ${_timeAgo(weather.cachedAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _TrailColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasExtraDetails) ...[
                    _ExtraDetailCard(weather: weather, uvLabel: _uvLabel),
                    const SizedBox(height: 16),
                  ],
                  if (hourlyForecasts.isNotEmpty) ...[
                    Text(
                      'HOURLY FORECAST',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _TrailColors.secondaryTextFor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < hourlyForecasts.length;
                                i++) ...[
                              if (i > 0) const _HorizontalSeparator(),
                              _HourlyForecastRow(
                                  forecast: hourlyForecasts[i]),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _uvLabel(double uvIndex) {
    if (uvIndex < 3) return '${uvIndex.toStringAsFixed(1)} (Low)';
    if (uvIndex < 6) return '${uvIndex.toStringAsFixed(1)} (Moderate)';
    if (uvIndex < 8) return '${uvIndex.toStringAsFixed(1)} (High)';
    if (uvIndex < 11) return '${uvIndex.toStringAsFixed(1)} (Very High)';
    return '${uvIndex.toStringAsFixed(1)} (Extreme)';
  }
}

class _ExtraDetailCard extends StatelessWidget {
  const _ExtraDetailCard({
    required this.weather,
    required this.uvLabel,
  });

  final TrailWeather weather;
  final String Function(double uvIndex) uvLabel;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void addRow(String label, String value) {
      if (rows.isNotEmpty) {
        rows.add(const _HorizontalSeparator());
      }
      rows.add(_StatusRow(label: label, value: value));
    }

    if (weather.feelsLike != null) {
      addRow('Feels like', '${weather.feelsLike!.round()} °C');
    }
    if (weather.humidity != null) {
      addRow('Humidity', '${weather.humidity}%');
    }
    if (weather.windSpeed != null) {
      addRow('Wind', '${weather.windSpeed!.toStringAsFixed(1)} km/h');
    }
    if (weather.uvIndex != null) {
      addRow('UV Index', uvLabel(weather.uvIndex!));
    }

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: rows),
      ),
    );
  }
}

class _HourlyForecastRow extends StatelessWidget {
  const _HourlyForecastRow({required this.forecast});

  final HourlyForecast forecast;

  @override
  Widget build(BuildContext context) {
    final hour = forecast.time.hour.toString().padLeft(2, '0');
    final minute = forecast.time.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '$hour:$minute',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            _weatherIcon(forecast.weatherCode),
            size: 18,
            color: _TrailColors.secondaryTextFor(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              forecast.weatherLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ),
          Text(
            '${forecast.temperature.round()}°C',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _TrailColors.textFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '${forecast.precipitationProbability}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: forecast.precipitationProbability > 50
                    ? _TrailColors.orange
                    : _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.light_mode_rounded;
    if (code <= 2) return Icons.cloud_rounded;
    if (code <= 3) return Icons.cloud_queue_rounded;
    if (code <= 48) return Icons.foggy;
    if (code <= 67) return Icons.water_drop_rounded;
    if (code <= 77) return Icons.ac_unit_rounded;
    if (code <= 86) return Icons.umbrella_rounded;
    return Icons.thunderstorm_rounded;
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    final weather = trail.weather;
    final cachedAt = weather.cachedAt;
    final diff = DateTime.now().toUtc().difference(cachedAt.toUtc());
    final refreshedText = diff.inMinutes < 1
        ? 'Just now'
        : diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : '${diff.inDays}d ago';

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _StatusRow(label: 'Today', value: weather.summary),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Temperature',
              value: weather.temperatureRange,
            ),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Rain Probability',
              value: '${weather.rainProbability}%',
            ),
            if (weather.windSpeed != null) ...[
              const _HorizontalSeparator(),
              _StatusRow(
                label: 'Wind',
                value: '${weather.windSpeed!.toStringAsFixed(0)} km/h',
              ),
            ],
            if (weather.humidity != null) ...[
              const _HorizontalSeparator(),
              _StatusRow(
                label: 'Humidity',
                value: '${weather.humidity}%',
              ),
            ],
            const _HorizontalSeparator(),
            _StatusRow(label: 'Refreshed', value: refreshedText),
          ],
        ),
      ),
    );
  }
}

class _SafetyInfoCard extends StatelessWidget {
  const _SafetyInfoCard({required this.trail});

  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Column(
        children: [
          _StatusRow(
            label: 'Recent hazards',
            value: '${trail.hazards.length} reports',
          ),
        ],
      ),
    );
  }
}

class _HazardCard extends StatelessWidget {
  const _HazardCard({required this.hazard});

  final TrailHazard hazard;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(
              icon: Icons.warning_amber_rounded,
              color: _TrailColors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hazard.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _TrailColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Community Report - Not Officially Verified',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.orange,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reported ${_formatDate(hazard.reportedAt)} at ${hazard.locationLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      child: Text(
        value,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: _TrailColors.textFor(context),
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _TrailColors.secondaryTextFor(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _TrailColors.secondaryTextFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          if (trailing != null) const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _TrailColors.secondaryTextFor(context),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _TrailColors.surfaceFor(context),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _TrailColors.green, size: 20),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.color = _TrailColors.green});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _TrailColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _TrailColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _TrailColors.separatorFor(context),
      ),
    );
  }
}

class _TrailCoverPainter extends CustomPainter {
  const _TrailCoverPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawRect(Offset.zero & size, paint);

    final ridgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final foregroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;

    final backRidge = Path()
      ..moveTo(0, size.height * 0.74)
      ..lineTo(size.width * 0.24, size.height * 0.38)
      ..lineTo(size.width * 0.50, size.height * 0.70)
      ..lineTo(size.width * 0.72, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.72)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backRidge, ridgePaint);

    final frontRidge = Path()
      ..moveTo(0, size.height * 0.84)
      ..lineTo(size.width * 0.34, size.height * 0.56)
      ..lineTo(size.width * 0.58, size.height * 0.78)
      ..lineTo(size.width * 0.82, size.height * 0.52)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontRidge, foregroundPaint);
  }

  @override
  bool shouldRepaint(covariant _TrailCoverPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

String _formatDate(DateTime dateTime) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
}

String _planSummary(Trail trail) {
  final hazardText = trail.hazards.isEmpty
      ? 'no active hazard reports'
      : '${trail.hazards.length} hazard report${trail.hazards.length == 1 ? '' : 's'}';
  return '${trail.distanceLabel}, ${trail.durationLabel}, $hazardText, ${trail.weather.rainProbability}% rain probability.';
}

abstract final class _TrailColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color blue = Color(0xFF2563EB);
  static const Color orange = Color(0xFFF59E0B);
  static const Color red = Color(0xFFE11D48);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color elevatedSurfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF1B261F) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;
}
