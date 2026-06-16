import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/services/google_routes_service.dart';
import '../../core/services/hiking_route_service.dart';
import '../../core/services/trail_cover_image_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../Model/trail_models.dart';

Future<Trail?> showAddTrailSheet(BuildContext context) {
  return showModalBottomSheet<Trail>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _TrailColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => const _AddTrailSheet(),
  );
}

Future<Trail?> showEditTrailSheet(BuildContext context, Trail trail) {
  return showModalBottomSheet<Trail>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _TrailColors.surfaceFor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => _EditTrailSheet(trail: trail),
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

  void _markDownloaded(Trail trail) {
    setState(() {
      _downloadedTrailIds.add(trail.trailId);
    });
    unawaited(
      widget.hikerCircleRepository.recordOfflineMapDownloaded(
        session: widget.session,
        trail: trail,
      ),
    );
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
          isOfflineDownloaded: _downloadedTrailIds.contains(trail.trailId),
          onMapDownloaded: () => _markDownloaded(trail),
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
    required this.isOfflineDownloaded,
    required this.onMapDownloaded,
    required this.onStartHike,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final Trail trail;
  final bool isOfflineDownloaded;
  final VoidCallback onMapDownloaded;
  final Future<void> Function(Trail trail) onStartHike;

  @override
  State<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends State<TrailDetailPage> {
  late Trail _trail = widget.trail;
  late bool _isOfflineDownloaded = widget.isOfflineDownloaded;
  bool _isLoadingRoute = false;
  bool _isSavingAdminTrail = false;
  GoogleRouteResult? _routeResult;
  String? _routeErrorMessage;

  Future<void> _downloadMap() async {
    final downloaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => OfflineMapDownloadPage(trail: _trail),
      ),
    );

    if (downloaded == true && mounted) {
      setState(() {
        _isOfflineDownloaded = true;
      });
      widget.onMapDownloaded();
    }
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

  Future<void> _editTrail() async {
    if (!widget.session.isAdmin || _isSavingAdminTrail) {
      return;
    }

    final updatedTrail = await showEditTrailSheet(context, _trail);
    if (updatedTrail == null || !mounted) {
      return;
    }

    setState(() {
      _isSavingAdminTrail = true;
    });
    try {
      await widget.hikerCircleRepository.updateTrailByAdmin(
        session: widget.session,
        trail: updatedTrail,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _trail = updatedTrail;
      });
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
          _isSavingAdminTrail = false;
        });
      }
    }
  }

  Future<void> _loadOnlineRoute() async {
    setState(() {
      _isLoadingRoute = true;
      _routeErrorMessage = null;
    });

    try {
      final result = await const HikingRouteService().findHikingRouteForTrail(
        _trail,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _routeResult = result;
      });
    } on HikingRouteServiceException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routeErrorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routeErrorMessage = 'Unable to load a hiking route right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trail = _trail;

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
                  _TrailDetailHero(trail: trail),
                  const SizedBox(height: 14),
                  _MetricGroup(trail: trail),
                  const SizedBox(height: 14),
                  _TrailPlanCard(
                    trail: trail,
                    isOfflineDownloaded: _isOfflineDownloaded,
                    isLoadingRoute: _isLoadingRoute,
                    onStartHike: () => unawaited(widget.onStartHike(trail)),
                    onSaveTrail: () => ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Trail saved to your profile.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
                    onLoadOnlineRoute: _isLoadingRoute
                        ? null
                        : () => unawaited(_loadOnlineRoute()),
                    onDownloadMap:
                        trail.offlineMapAvailable && !_isOfflineDownloaded
                        ? () => unawaited(_downloadMap())
                        : null,
                  ),
                  if (widget.session.isAdmin) ...[
                    const SizedBox(height: 10),
                    _AdminTrailEditCard(
                      isSaving: _isSavingAdminTrail,
                      onEdit: () => unawaited(_editTrail()),
                    ),
                  ],
                  if (_routeResult != null || _routeErrorMessage != null) ...[
                    const SizedBox(height: 10),
                    _GoogleRouteStatusCard(
                      result: _routeResult,
                      errorMessage: _routeErrorMessage,
                    ),
                  ],
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Route Preview'),
                  const SizedBox(height: 8),
                  _RoutePreview(trail: trail),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Checkpoint Flow'),
                  const SizedBox(height: 8),
                  _CheckpointTimeline(trail: trail),
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
                  _SafetyInfoCard(
                    trail: trail,
                    isOfflineDownloaded: _isOfflineDownloaded,
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(label: 'Hazards Reported by Community'),
                  const SizedBox(height: 8),
                  if (trail.hazards.isEmpty)
                    const _EmptyState(
                      message: 'No community hazard reports for this trail.',
                    )
                  else
                    for (final hazard in trail.hazards) ...[
                      _HazardCard(hazard: hazard),
                      const SizedBox(height: 10),
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
        child: Padding(
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

class _AddTrailSheet extends StatefulWidget {
  const _AddTrailSheet();

  @override
  State<_AddTrailSheet> createState() => _AddTrailSheetState();
}

class _AddTrailSheetState extends State<_AddTrailSheet> {
  static const String _defaultRouteFilePath =
      'offline/maps/admin_added_trail.mbtiles';

  final _nameController = TextEditingController();
  final _areaController = TextEditingController();
  final _stateController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _distanceController = TextEditingController();
  final _durationController = TextEditingController(text: '120');
  final _elevationController = TextEditingController();
  final _ratingController = TextEditingController(text: '4.5');
  final _coverImageController = TextEditingController();
  final List<_CheckpointDraft> _checkpoints = [
    _CheckpointDraft(order: 1, name: 'Trailhead'),
    _CheckpointDraft(order: 2, name: 'Summit'),
  ];
  String _difficulty = 'Moderate';
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _stateController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
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

  void _addCheckpoint() {
    setState(() {
      _checkpoints.add(
        _CheckpointDraft(
          order: _checkpoints.length + 1,
          name: 'Checkpoint ${_checkpoints.length + 1}',
        ),
      );
    });
  }

  Future<void> _pickTrailCenter() async {
    final coordinate = await _pickCoordinate(
      title: 'Select trail center',
      latitude: double.tryParse(_latitudeController.text.trim()),
      longitude: double.tryParse(_longitudeController.text.trim()),
    );
    if (coordinate == null || !mounted) {
      return;
    }
    setState(() {
      _latitudeController.text = coordinate.latitude.toStringAsFixed(6);
      _longitudeController.text = coordinate.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _pickCheckpointLocation(_CheckpointDraft draft) async {
    final coordinate = await _pickCoordinate(
      title: 'Select checkpoint location',
      latitude:
          double.tryParse(draft.latitudeController.text.trim()) ??
          double.tryParse(_latitudeController.text.trim()),
      longitude:
          double.tryParse(draft.longitudeController.text.trim()) ??
          double.tryParse(_longitudeController.text.trim()),
    );
    if (coordinate == null || !mounted) {
      return;
    }
    setState(() {
      draft.latitudeController.text = coordinate.latitude.toStringAsFixed(6);
      draft.longitudeController.text = coordinate.longitude.toStringAsFixed(6);
      if (_latitudeController.text.trim().isEmpty ||
          _longitudeController.text.trim().isEmpty) {
        _latitudeController.text = coordinate.latitude.toStringAsFixed(6);
        _longitudeController.text = coordinate.longitude.toStringAsFixed(6);
      }
    });
  }

  Future<maplibre.LatLng?> _pickCoordinate({
    required String title,
    double? latitude,
    double? longitude,
  }) {
    return showModalBottomSheet<maplibre.LatLng>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _TrailColors.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return _AdminCoordinatePickerSheet(
          title: title,
          initialLatitude: latitude,
          initialLongitude: longitude,
        );
      },
    );
  }

  void _removeCheckpoint(int index) {
    if (_checkpoints.length <= 2) {
      return;
    }
    setState(() {
      _checkpoints.removeAt(index).dispose();
      for (var i = 0; i < _checkpoints.length; i++) {
        _checkpoints[i].orderController.text = '${i + 1}';
      }
    });
  }

  void _saveTrail() {
    final name = _nameController.text.trim();
    final area = _areaController.text.trim();
    final state = _stateController.text.trim();
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final distance = double.tryParse(_distanceController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    final elevation = int.tryParse(_elevationController.text.trim());
    final rating = double.tryParse(_ratingController.text.trim());
    final checkpoints = _checkpointModels();

    if (name.isEmpty ||
        area.isEmpty ||
        state.isEmpty ||
        latitude == null ||
        longitude == null ||
        distance == null ||
        duration == null ||
        elevation == null ||
        rating == null ||
        checkpoints.length < 2) {
      setState(() {
        _errorMessage =
            'Fill in trail identity, coordinates, metrics, and at least 2 valid checkpoints.';
      });
      return;
    }

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
      final order =
          int.tryParse(draft.orderController.text.trim()) ?? index + 1;
      if (name.isEmpty || latitude == null || longitude == null) {
        continue;
      }
      checkpoints.add(
        TrailCheckpoint(
          name: name,
          latitude: latitude,
          longitude: longitude,
          order: order,
        ),
      );
    }
    checkpoints.sort((a, b) => a.order.compareTo(b.order));
    return checkpoints;
  }

  @override
  Widget build(BuildContext context) {
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
              'Create a Firebase trail with route metadata and checkpoints.',
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
            const SizedBox(height: 10),
            _CoordinatePickerTile(
              title: 'Trail center',
              subtitle:
                  'Choose the approximate trail center from the map. This is used for discovery and map framing.',
              value: _coordinateLabel(
                _latitudeController.text,
                _longitudeController.text,
              ),
              onPick: _pickTrailCenter,
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _distanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Distance km'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration min',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _elevationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Elevation m'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ratingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Rating 0-5'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _coverImageController,
              decoration: const InputDecoration(
                labelText: 'Cover image URL',
                hintText: 'https://...',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: _SectionTitle(label: 'Checkpoints')),
                TextButton.icon(
                  onPressed: _addCheckpoint,
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _checkpoints.length; index++) ...[
              _CheckpointDraftFields(
                draft: _checkpoints[index],
                canRemove: _checkpoints.length > 2,
                onRemove: () => _removeCheckpoint(index),
                onPickLocation: () =>
                    unawaited(_pickCheckpointLocation(_checkpoints[index])),
              ),
              const SizedBox(height: 10),
            ],
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

class _CheckpointDraft {
  _CheckpointDraft({required int order, required String name})
    : orderController = TextEditingController(text: '$order'),
      nameController = TextEditingController(text: name),
      latitudeController = TextEditingController(),
      longitudeController = TextEditingController();

  final TextEditingController orderController;
  final TextEditingController nameController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;

  void dispose() {
    orderController.dispose();
    nameController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
  }
}

class _CheckpointDraftFields extends StatelessWidget {
  const _CheckpointDraftFields({
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.onPickLocation,
  });

  final _CheckpointDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onPickLocation;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 74,
                  child: TextField(
                    controller: draft.orderController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Order'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                if (canRemove) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Remove checkpoint',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _CoordinatePickerTile(
              title: 'Checkpoint map location',
              subtitle: 'Tap to place this checkpoint on the route map.',
              value: _coordinateLabel(
                draft.latitudeController.text,
                draft.longitudeController.text,
              ),
              onPick: onPickLocation,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinatePickerTile extends StatelessWidget {
  const _CoordinatePickerTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const _Glyph(icon: Icons.map_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _TrailColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: value == 'Not selected'
                          ? _TrailColors.redFor(context)
                          : _TrailColors.green,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Map'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminCoordinatePickerSheet extends StatefulWidget {
  const _AdminCoordinatePickerSheet({
    required this.title,
    this.initialLatitude,
    this.initialLongitude,
  });

  final String title;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<_AdminCoordinatePickerSheet> createState() =>
      _AdminCoordinatePickerSheetState();
}

class _AdminCoordinatePickerSheetState
    extends State<_AdminCoordinatePickerSheet> {
  static const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
  static const _defaultLatitude = 3.1390;
  static const _defaultLongitude = 101.6869;

  late maplibre.LatLng _selected = maplibre.LatLng(
    widget.initialLatitude ?? _defaultLatitude,
    widget.initialLongitude ?? _defaultLongitude,
  );
  maplibre.MapLibreMapController? _mapController;
  bool _styleLoaded = false;

  void _selectCoordinate(maplibre.LatLng coordinate) {
    setState(() {
      _selected = coordinate;
    });
    unawaited(_syncSelectedPin());
    unawaited(
      _mapController?.animateCamera(
        maplibre.CameraUpdate.newLatLng(coordinate),
      ),
    );
  }

  Future<void> _syncSelectedPin() async {
    final controller = _mapController;
    if (!_styleLoaded || controller == null) {
      return;
    }

    await controller.clearCircles();
    await controller.clearSymbols();
    await controller.addCircle(
      maplibre.CircleOptions(
        geometry: _selected,
        circleRadius: 10,
        circleColor: '#E11D48',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    await controller.addSymbol(
      maplibre.SymbolOptions(
        geometry: _selected,
        textField: 'Pin',
        textSize: 12,
        textColor: '#FFFFFF',
        textHaloColor: '#111111',
        textHaloWidth: 0.8,
        textOffset: const Offset(0, 1.35),
        textAnchor: 'top',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          6,
          18,
          18 + MediaQuery.of(context).viewInsets.bottom,
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
                    maplibre.MapLibreMap(
                      styleString: _styleUrl,
                      initialCameraPosition: maplibre.CameraPosition(
                        target: _selected,
                        zoom: 13,
                      ),
                      minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
                        4,
                        21,
                      ),
                      compassEnabled: false,
                      logoEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      trackCameraPosition: true,
                      featureTapsTriggersMapClick: true,
                      annotationConsumeTapEvents: const [
                        maplibre.AnnotationType.fill,
                      ],
                      annotationOrder: const [
                        maplibre.AnnotationType.circle,
                        maplibre.AnnotationType.symbol,
                        maplibre.AnnotationType.line,
                        maplibre.AnnotationType.fill,
                      ],
                      gestureRecognizers: {
                        Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                        ),
                      },
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                      onStyleLoadedCallback: () {
                        _styleLoaded = true;
                        unawaited(_syncSelectedPin());
                      },
                      onMapClick: (_, coordinate) {
                        _selectCoordinate(coordinate);
                      },
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _TrailColors.surfaceFor(
                            context,
                          ).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _coordinateLabel(
                              _selected.latitude.toStringAsFixed(6),
                              _selected.longitude.toStringAsFixed(6),
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: _TrailColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
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

class _TrailFormSwitch extends StatelessWidget {
  const _TrailFormSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: _TrailColors.green,
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _TrailColors.textFor(context),
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
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
    required this.isOfflineDownloaded,
    required this.isLoadingRoute,
    required this.onStartHike,
    required this.onSaveTrail,
    required this.onLoadOnlineRoute,
    required this.onDownloadMap,
  });

  final Trail trail;
  final bool isOfflineDownloaded;
  final bool isLoadingRoute;
  final VoidCallback onStartHike;
  final VoidCallback onSaveTrail;
  final VoidCallback? onLoadOnlineRoute;
  final VoidCallback? onDownloadMap;

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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onLoadOnlineRoute,
                    icon: const Icon(Icons.public_rounded),
                    label: Text(isLoadingRoute ? 'Loading' : 'Online Route'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDownloadMap,
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: Text(
                      isOfflineDownloaded ? 'Downloaded' : 'Route Pack',
                    ),
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

class _AdminTrailEditCard extends StatelessWidget {
  const _AdminTrailEditCard({required this.isSaving, required this.onEdit});

  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const _Glyph(icon: Icons.admin_panel_settings_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin trail controls',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _TrailColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Edit route metadata after reviewing the normal trail detail.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: isSaving ? null : onEdit,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_rounded),
              label: Text(isSaving ? 'Saving' : 'Edit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditTrailSheet extends StatefulWidget {
  const _EditTrailSheet({required this.trail});

  final Trail trail;

  @override
  State<_EditTrailSheet> createState() => _EditTrailSheetState();
}

class _EditTrailSheetState extends State<_EditTrailSheet> {
  late final _nameController = TextEditingController(text: widget.trail.name);
  late final _areaController = TextEditingController(text: widget.trail.area);
  late final _stateController = TextEditingController(text: widget.trail.state);
  late final _distanceController = TextEditingController(
    text: widget.trail.distanceKm.toStringAsFixed(1),
  );
  late final _durationController = TextEditingController(
    text: widget.trail.estimatedDurationMinutes.toString(),
  );
  late final _elevationController = TextEditingController(
    text: widget.trail.elevationGainMeters.toString(),
  );
  late final _ratingController = TextEditingController(
    text: widget.trail.ratingAverage.toStringAsFixed(1),
  );
  late String _difficulty = widget.trail.difficulty;
  late bool _isVerified = widget.trail.isVerifiedTrail;
  late bool _offlineAvailable = widget.trail.offlineMapAvailable;

  @override
  void dispose() {
    _nameController.dispose();
    _areaController.dispose();
    _stateController.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    _elevationController.dispose();
    _ratingController.dispose();
    super.dispose();
  }

  void _save() {
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
      distanceKm:
          double.tryParse(_distanceController.text.trim()) ??
          widget.trail.distanceKm,
      estimatedDurationMinutes:
          int.tryParse(_durationController.text.trim()) ??
          widget.trail.estimatedDurationMinutes,
      elevationGainMeters:
          int.tryParse(_elevationController.text.trim()) ??
          widget.trail.elevationGainMeters,
      ratingAverage:
          double.tryParse(_ratingController.text.trim()) ??
          widget.trail.ratingAverage,
      isVerifiedTrail: _isVerified,
      offlineMapAvailable: _offlineAvailable,
    );
    Navigator.of(context).pop(updatedTrail);
  }

  @override
  Widget build(BuildContext context) {
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
              'Edit Trail',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Trail name'),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _distanceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Distance km'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _elevationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Elevation m'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ratingController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Rating'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _TrailFormSwitch(
              title: 'Verified trail',
              value: _isVerified,
              onChanged: (value) => setState(() => _isVerified = value),
            ),
            _TrailFormSwitch(
              title: 'Offline map available',
              value: _offlineAvailable,
              onChanged: (value) => setState(() => _offlineAvailable = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Trail'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointTimeline extends StatelessWidget {
  const _CheckpointTimeline({required this.trail});

  final Trail trail;

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
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({required this.checkpoint, required this.isLast});

  final TrailCheckpoint checkpoint;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
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
                  color: _TrailColors.greenSoftFor(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${checkpoint.order}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _TrailColors.green,
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
                    'Dummy ETA checkpoint - ${checkpoint.latitude.toStringAsFixed(4)}, ${checkpoint.longitude.toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _TrailColors.secondaryTextFor(context),
                      letterSpacing: 0,
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
  const _RoutePreview({required this.trail});

  final Trail trail;

  @override
  State<_RoutePreview> createState() => _RoutePreviewState();
}

class _RoutePreviewState extends State<_RoutePreview> {
  late Future<GoogleRouteResult> _routeFuture;

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

  Future<GoogleRouteResult> _loadHikingRoute() {
    return const HikingRouteService().findHikingRouteForTrail(widget.trail);
  }

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 240,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<GoogleRouteResult>(
            future: _routeFuture,
            builder: (context, snapshot) {
              final route = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              return _OpenFreeMapRouteMap(
                key: ValueKey(
                  '${widget.trail.trailId}:${route?.encodedPolyline ?? 'checkpoints'}',
                ),
                trail: widget.trail,
                route: route?.encodedPolyline.isEmpty == true ? null : route,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OpenFreeMapRouteMap extends StatefulWidget {
  const _OpenFreeMapRouteMap({super.key, required this.trail, this.route});

  final Trail trail;
  final GoogleRouteResult? route;

  @override
  State<_OpenFreeMapRouteMap> createState() => _OpenFreeMapRouteMapState();
}

class _OpenFreeMapRouteMapState extends State<_OpenFreeMapRouteMap> {
  static const _styleUrls = [
    'https://tiles.openfreemap.org/styles/liberty',
    'https://tiles.openfreemap.org/styles/positron',
    'https://tiles.openfreemap.org/styles/bright',
  ];
  static const _minZoom = 4.2;
  static const _maxZoom = 21.0;
  static const _routeLineWidth = 2.65;

  late final List<maplibre.LatLng> _routePoints;
  late final List<maplibre.LatLng> _checkpointPoints;
  late final maplibre.LatLng _startPoint;
  late final maplibre.LatLng _endPoint;
  late double _currentZoom;
  late double _scaleLatitude;
  maplibre.MapLibreMapController? _mapController;
  var _styleIndex = 0;
  var _styleLoaded = false;
  var _routeRendered = false;

  @override
  void initState() {
    super.initState();
    final checkpoints = [...widget.trail.checkpoints]
      ..sort((a, b) => a.order.compareTo(b.order));
    _startPoint = maplibre.LatLng(
      checkpoints.first.latitude,
      checkpoints.first.longitude,
    );
    _endPoint = maplibre.LatLng(
      checkpoints.last.latitude,
      checkpoints.last.longitude,
    );
    _checkpointPoints = checkpoints
        .map(
          (checkpoint) =>
              maplibre.LatLng(checkpoint.latitude, checkpoint.longitude),
        )
        .toList();
    final route = widget.route;
    _routePoints = route == null
        ? const []
        : _orientRoutePoints(_decodePolyline(route.encodedPolyline));
    final center = _centerFor(_visibleMapPoints);
    _currentZoom = 13.5;
    _scaleLatitude = center.latitude;
  }

  Future<void> _onMapCreated(maplibre.MapLibreMapController controller) async {
    _mapController = controller;
    await _renderRouteIfReady();
    await _syncScaleFromCamera();
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    _routeRendered = false;
    await _renderRouteIfReady();
  }

  Future<void> _renderRouteIfReady() async {
    final controller = _mapController;
    if (controller == null ||
        !_styleLoaded ||
        _routeRendered ||
        _visibleMapPoints.length < 2) {
      return;
    }

    _routeRendered = true;
    await controller.clearLines();
    await controller.clearCircles();
    if (_routePoints.length >= 2) {
      await controller.addLine(
        maplibre.LineOptions(
          geometry: _routePoints,
          lineColor: '#2F8E50',
          lineOpacity: 0.86,
          lineWidth: _routeLineWidth,
          lineJoin: 'round',
        ),
      );
    }
    await controller.addCircles([
      for (final checkpoint
          in _checkpointPoints
              .skip(1)
              .take(math.max(0, _checkpointPoints.length - 2)))
        maplibre.CircleOptions(
          geometry: checkpoint,
          circleColor: '#2F8E50',
          circleOpacity: 0.55,
          circleRadius: 4.2,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 1.2,
        ),
      maplibre.CircleOptions(
        geometry: _startPoint,
        circleColor: '#7BC90E',
        circleRadius: 6.5,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
      maplibre.CircleOptions(
        geometry: _endPoint,
        circleColor: '#E94B42',
        circleRadius: 6.5,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    ]);
    await _fitRoute();
  }

  Future<void> _fitRoute() async {
    final controller = _mapController;
    if (controller == null || _visibleMapPoints.length < 2) {
      return;
    }
    await controller.animateCamera(
      maplibre.CameraUpdate.newLatLngBounds(
        _boundsFor(_visibleMapPoints),
        left: 30,
        top: 42,
        right: 30,
        bottom: 38,
      ),
    );
    await _syncScaleFromCamera();
  }

  Future<void> _zoomBy(double amount) async {
    await _mapController?.animateCamera(maplibre.CameraUpdate.zoomBy(amount));
    await _syncScaleFromCamera();
  }

  void _cycleStyle() {
    setState(() {
      _styleIndex = (_styleIndex + 1) % _styleUrls.length;
      _styleLoaded = false;
      _routeRendered = false;
    });
  }

  void _onCameraMove(maplibre.CameraPosition position) {
    _updateScale(position);
  }

  Future<void> _syncScaleFromCamera() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final position =
        controller.cameraPosition ?? await controller.queryCameraPosition();
    if (position != null) {
      _updateScale(position);
    }
  }

  void _updateScale(maplibre.CameraPosition position) {
    final nextZoom = position.zoom;
    final nextLatitude = position.target.latitude;
    if (!mounted ||
        ((nextZoom - _currentZoom).abs() < 0.005 &&
            (nextLatitude - _scaleLatitude).abs() < 0.0005)) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      _scaleLatitude = nextLatitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    final center = _centerFor(_visibleMapPoints);
    return Stack(
      fit: StackFit.expand,
      children: [
        maplibre.MapLibreMap(
          key: ValueKey(_styleUrls[_styleIndex]),
          styleString: _styleUrls[_styleIndex],
          initialCameraPosition: maplibre.CameraPosition(
            target: center,
            zoom: _currentZoom,
          ),
          minMaxZoomPreference: const maplibre.MinMaxZoomPreference(
            _minZoom,
            _maxZoom,
          ),
          compassEnabled: false,
          logoEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          trackCameraPosition: true,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          onCameraMove: _onCameraMove,
          onCameraIdle: () => unawaited(_syncScaleFromCamera()),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _StatusPill(
              label: widget.route?.sourceLabel ?? 'Checkpoint map',
              color: widget.route == null
                  ? _TrailColors.orange
                  : _TrailColors.blue,
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _MapZoomControls(
              onZoomIn: () => _zoomBy(1),
              onZoomOut: () => _zoomBy(-1),
              onReset: _fitRoute,
              onLayer: _cycleStyle,
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _MapScaleBar(zoom: _currentZoom, latitude: _scaleLatitude),
          ),
        ),
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: _OpenFreeMapAttribution(),
          ),
        ),
      ],
    );
  }

  List<maplibre.LatLng> get _visibleMapPoints {
    if (_routePoints.length >= 2) {
      return [..._routePoints, _startPoint, _endPoint];
    }
    return _checkpointPoints.length >= 2
        ? _checkpointPoints
        : [_startPoint, _endPoint];
  }

  List<maplibre.LatLng> _decodePolyline(String encoded) {
    final points = <maplibre.LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      latitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      longitude += (result & 1) == 1 ? ~(result >> 1) : result >> 1;

      points.add(maplibre.LatLng(latitude / 100000, longitude / 100000));
    }

    return points;
  }

  List<maplibre.LatLng> _orientRoutePoints(List<maplibre.LatLng> points) {
    if (points.length < 2) {
      return points;
    }

    final forwardScore =
        _distanceMeters(points.first, _startPoint) +
        _distanceMeters(points.last, _endPoint);
    final reverseScore =
        _distanceMeters(points.first, _endPoint) +
        _distanceMeters(points.last, _startPoint);

    if (reverseScore < forwardScore) {
      return points.reversed.toList();
    }
    return points;
  }

  maplibre.LatLng _centerFor(List<maplibre.LatLng> points) {
    final bounds = _boundsFor(points);
    return maplibre.LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }

  maplibre.LatLngBounds _boundsFor(List<maplibre.LatLng> points) {
    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;

    for (final point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude);
      maxLatitude = math.max(maxLatitude, point.latitude);
      minLongitude = math.min(minLongitude, point.longitude);
      maxLongitude = math.max(maxLongitude, point.longitude);
    }

    if (minLatitude == maxLatitude) {
      minLatitude -= 0.0005;
      maxLatitude += 0.0005;
    }
    if (minLongitude == maxLongitude) {
      minLongitude -= 0.0005;
      maxLongitude += 0.0005;
    }

    return maplibre.LatLngBounds(
      southwest: maplibre.LatLng(minLatitude, minLongitude),
      northeast: maplibre.LatLng(maxLatitude, maxLongitude),
    );
  }

  double _distanceMeters(maplibre.LatLng a, maplibre.LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(h));
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onLayer,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onLayer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _TrailColors.elevatedSurfaceFor(context).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapZoomButton(
            tooltip: 'Zoom in',
            icon: Icons.add_rounded,
            onPressed: onZoomIn,
          ),
          const _MiniDivider(),
          _MapZoomButton(
            tooltip: 'Zoom out',
            icon: Icons.remove_rounded,
            onPressed: onZoomOut,
          ),
          const _MiniDivider(),
          _MapZoomButton(
            tooltip: 'Fit route',
            icon: Icons.center_focus_strong_rounded,
            onPressed: onReset,
          ),
          const _MiniDivider(),
          _MapZoomButton(
            tooltip: 'Change OpenFreeMap style',
            icon: Icons.layers_rounded,
            onPressed: onLayer,
          ),
        ],
      ),
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        color: _TrailColors.textFor(context),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MiniDivider extends StatelessWidget {
  const _MiniDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _TrailColors.separatorFor(context),
      ),
    );
  }
}

class _MapScaleBar extends StatelessWidget {
  const _MapScaleBar({required this.zoom, required this.latitude});

  final double zoom;
  final double latitude;

  @override
  Widget build(BuildContext context) {
    const targetWidth = 72.0;
    final metersPerPixel =
        156543.03392 *
        math.cos(latitude * math.pi / 180).abs() /
        math.pow(2, zoom);
    final distanceMeters = _niceDistance(targetWidth * metersPerPixel);
    final width = (distanceMeters / metersPerPixel).clamp(34.0, 92.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _TrailColors.elevatedSurfaceFor(context).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x77000000), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _distanceLabel(distanceMeters),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _TrailColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: width,
              height: 8,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Color(0xBB111111), width: 1.4),
                    bottom: BorderSide(color: Color(0xBB111111), width: 1.4),
                    right: BorderSide(color: Color(0xBB111111), width: 1.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _niceDistance(double rawMeters) {
    const distances = [
      1000000.0,
      500000.0,
      200000.0,
      100000.0,
      50000.0,
      20000.0,
      10000.0,
      5000.0,
      2000.0,
      1000.0,
      500.0,
      200.0,
      100.0,
      50.0,
      20.0,
      10.0,
      5.0,
    ];

    for (final distance in distances) {
      if (rawMeters >= distance) {
        return distance;
      }
    }
    return 5;
  }

  String _distanceLabel(double meters) {
    if (meters >= 1000) {
      final kilometers = meters / 1000;
      return kilometers >= 100
          ? '${kilometers.round()} km'
          : '${kilometers.toStringAsFixed(kilometers >= 10 ? 0 : 1)} km';
    }
    return '${meters.round()} m';
  }
}

class _OpenFreeMapAttribution extends StatelessWidget {
  const _OpenFreeMapAttribution();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _TrailColors.elevatedSurfaceFor(context).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Text(
          'OpenFreeMap | OpenMapTiles | OSM',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _TrailColors.secondaryTextFor(context),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
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

class _GoogleRouteStatusCard extends StatelessWidget {
  const _GoogleRouteStatusCard({this.result, this.errorMessage});

  final GoogleRouteResult? result;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final route = result;
    final hasError = errorMessage != null;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(
              icon: hasError
                  ? Icons.error_outline_rounded
                  : Icons.route_rounded,
              color: hasError ? _TrailColors.orange : _TrailColors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasError
                    ? errorMessage!
                    : '${route?.sourceLabel ?? 'Live route'}: ${route?.distanceLabel ?? '-'} in ${route?.durationLabel ?? '-'}.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _TrailColors.textFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyInfoCard extends StatelessWidget {
  const _SafetyInfoCard({
    required this.trail,
    required this.isOfflineDownloaded,
  });

  final Trail trail;
  final bool isOfflineDownloaded;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Column(
        children: [
          _StatusRow(
            label: 'Offline map',
            value: isOfflineDownloaded ? 'Downloaded' : 'Available',
          ),
          const _HorizontalSeparator(),
          const _StatusRow(
            label: 'Emergency coverage reports',
            value: 'Community observed',
          ),
          const _HorizontalSeparator(),
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

String _coordinateLabel(String latitudeText, String longitudeText) {
  final latitude = double.tryParse(latitudeText.trim());
  final longitude = double.tryParse(longitudeText.trim());
  if (latitude == null || longitude == null) {
    return 'Not selected';
  }
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
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
