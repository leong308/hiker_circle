import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';

enum _AdminSection { overview, trails, hazards, community }
enum _DebugSection { firestore, local }

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.session,
    this.hikerCircleRepository,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final HikerCircleFirebaseRepository? hikerCircleRepository;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final HikerCircleFirebaseRepository _repository =
      widget.hikerCircleRepository ??
      HikerCircleFirebaseRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );

  List<Map<String, dynamic>> _hazardReports = const [];
  List<Map<String, dynamic>> _communityPosts = const [];
  List<Trail> _trails = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  _AdminSection _selectedSection = _AdminSection.overview;

  int _debugTapCount = 0;
  bool _debugMode = false;
  _DebugSection? _selectedDebugSection;
  Map<String, List<Map<String, dynamic>>> _localDbData = const {};
  List<_FirestoreCollection> _firestoreData = const [];
  bool _isDebugLoading = false;
  String? _debugError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAdminData());
  }

  Future<void> _loadAdminData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object>([
        _repository.loadAdminTrails(session: widget.session),
        _repository.loadAdminHazardReports(session: widget.session),
        _repository.loadAdminCommunityPosts(session: widget.session),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _trails = results[0] as List<Trail>;
        _hazardReports = results[1] as List<Map<String, dynamic>>;
        _communityPosts = results[2] as List<Map<String, dynamic>>;
      });
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to load admin data: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addTrail() async {
    if (!widget.session.isAdmin || _isSaving) {
      return;
    }

    final trail = await showAddTrailSheet(context);
    if (trail == null || !mounted) {
      return;
    }

    await _runAdminAction(
      successMessage: '${trail.name} added to Firebase trails.',
      action: () async {
        await _repository.createTrailByAdmin(
          session: widget.session,
          trail: trail,
        );
      },
    );
  }

  Future<void> _toggleTrailVerification(Trail trail) async {
    await _runAdminAction(
      successMessage: trail.isVerifiedTrail
          ? '${trail.name} marked unverified.'
          : '${trail.name} verified.',
      action: () async {
        await _repository.updateTrailByAdmin(
          session: widget.session,
          trail: trail.copyWith(isVerifiedTrail: !trail.isVerifiedTrail),
        );
      },
    );
  }

  Future<void> _editTrail(Trail trail) async {
    if (!widget.session.isAdmin || _isSaving) {
      return;
    }

    final updatedTrail = await showEditTrailSheet(context, trail);
    if (updatedTrail == null || !mounted) {
      return;
    }

    await _runAdminAction(
      successMessage: 'Trail updated.',
      action: () async {
        await _repository.updateTrailByAdmin(
          session: widget.session,
          trail: updatedTrail,
        );
      },
    );
  }

  Future<void> _deleteTrail(Trail trail) async {
    if (!widget.session.isAdmin || _isSaving) {
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

    await _runAdminAction(
      successMessage: '${trail.name} deleted.',
      action: () async {
        await _repository.deleteTrailByAdmin(
          session: widget.session,
          trail: trail,
        );
      },
    );
  }

  Future<void> _openTrail(Trail trail) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TrailDetailPage(
          session: widget.session,
          hikerCircleRepository: _repository,
          trail: trail,
          isOfflineDownloaded: trail.offlineMapDownloaded,
          onMapDownloaded: () {},
          onStartHike: (_) async {
            _showSnack('Start hikes from the Home tab.');
          },
        ),
      ),
    );

    if (mounted) {
      unawaited(_loadAdminData());
    }
  }

  Future<void> _reviewHazard(
    Map<String, dynamic> report, {
    required bool approved,
  }) async {
    await _runAdminAction(
      successMessage: approved
          ? 'Hazard report approved.'
          : 'Hazard report rejected.',
      action: () async {
        await _repository.reviewHazardReport(
          session: widget.session,
          report: report,
          approved: approved,
        );
      },
    );
  }

  Future<void> _moderatePost(
    Map<String, dynamic> post, {
    required String status,
  }) async {
    await _runAdminAction(
      successMessage: 'Community post marked $status.',
      action: () async {
        await _repository.moderateCommunityPost(
          session: widget.session,
          postId: _stringFrom(post['postId']),
          moderationStatus: status,
        );
      },
    );
  }

  Future<void> _runAdminAction({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await action();
      await _loadAdminData();
      if (!mounted) {
        return;
      }
      _showSnack(successMessage);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      _showSnack(error.message, isError: true);
    } catch (_) {
      _showSnack('Admin action failed. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? _AdminColors.redFor(context)
              : _AdminColors.green,
        ),
      );
  }

  void _onDebugTitleTap() {
    _debugTapCount++;
    if (_debugTapCount >= 5) {
      _debugTapCount = 0;
      setState(() {
        _debugMode = true;
        _selectedDebugSection = null;
        _localDbData = const {};
        _firestoreData = const [];
        _debugError = null;
      });
    }
  }

  Future<void> _loadFirestoreDebugData() async {
    setState(() {
      _isDebugLoading = true;
      _debugError = null;
    });

    try {
      final firestore = _repository.firestore;
      final collections = [
        'trails',
        'users',
        'hazardReports',
        'communityPosts',
        'sosAlerts',
        'hikeSessions',
        'localLocationPoints',
        'checkIns',
        'teams',
        'teamHikeSessions',
        'fcmOutbox',
        'whatsAppMessageLogs',
        'achievements',
        'userAchievements',
        'networkObservations',
        'downloadedMaps',
        'hikeRouteCaptures',
      ];

      final results = <_FirestoreCollection>[];
      for (final name in collections) {
        try {
          final snapshot = await firestore.collection(name).limit(50).get();
          results.add(_FirestoreCollection(
            name: name,
            documents: snapshot.docs.map((d) {
              return <String, dynamic>{
                'id': d.id,
                ...d.data(),
              };
            }).toList(),
          ));
        } catch (e) {
          results.add(_FirestoreCollection(
            name: name,
            documents: const [],
            error: e.toString(),
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _firestoreData = results;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _debugError = 'Failed to load Firestore data: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDebugLoading = false;
        });
      }
    }
  }

  Future<void> _loadLocalDbDebugData() async {
    setState(() {
      _isDebugLoading = true;
      _debugError = null;
    });

    try {
      final data = await _repository.localDatabase.dumpAllTables();
      if (!mounted) return;
      setState(() {
        _localDbData = data;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _debugError = 'Failed to load local database data: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDebugLoading = false;
        });
      }
    }
  }

  void _exitDebugMode() {
    setState(() {
      _debugMode = false;
      _selectedDebugSection = null;
      _localDbData = const {};
      _firestoreData = const [];
      _debugError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const _AdminLockedState();
    }

    final verifiedTrails = _trails
        .where((trail) => trail.isVerifiedTrail)
        .length;
    final pendingHazards = _hazardReports.where((report) {
      final status = _stringFrom(report['status']).toLowerCase();
      return status.isEmpty || status == 'unverified' || status == 'pending';
    }).length;
    final moderatedPosts = _communityPosts.where((post) {
      final visibility = _stringFrom(post['visibility']).toLowerCase();
      return visibility == 'hidden' || visibility == 'removed';
    }).length;
    final title = switch (_selectedSection) {
      _AdminSection.overview => 'Admin Dashboard',
      _AdminSection.trails => 'Trail Management',
      _AdminSection.hazards => 'Hazard Reports',
      _AdminSection.community => 'Community Moderation',
    };
    final subtitle = switch (_selectedSection) {
      _AdminSection.overview =>
        'Manage Firebase content and safety moderation.',
      _AdminSection.trails => 'Create, review, and update Firebase trails.',
      _AdminSection.hazards => 'Verify or reject community safety reports.',
      _AdminSection.community => 'Review public community posts.',
    };
    final content = switch (_selectedSection) {
      _AdminSection.overview => _AdminOverviewDashboard(
        trailCount: _trails.length,
        verifiedTrailCount: verifiedTrails,
        pendingHazardCount: pendingHazards,
        communityPostCount: _communityPosts.length,
        moderatedPostCount: moderatedPosts,
        onOpenTrails: () {
          setState(() {
            _selectedSection = _AdminSection.trails;
          });
        },
        onOpenHazards: () {
          setState(() {
            _selectedSection = _AdminSection.hazards;
          });
        },
        onOpenCommunity: () {
          setState(() {
            _selectedSection = _AdminSection.community;
          });
        },
      ),
      _AdminSection.trails => _TrailManagementSection(
        trails: _trails,
        isLoading: _isLoading,
        isSaving: _isSaving,
        onAddTrail: () => unawaited(_addTrail()),
        onOpenTrail: (trail) => unawaited(_openTrail(trail)),
        onEditTrail: _editTrail,
        onDeleteTrail: _deleteTrail,
        onToggleVerification: (trail) =>
            unawaited(_toggleTrailVerification(trail)),
      ),
      _AdminSection.hazards => _HazardReportsSection(
        hazardReports: _hazardReports,
        isSaving: _isSaving,
        onApprove: (report) => unawaited(_reviewHazard(report, approved: true)),
        onReject: (report) => unawaited(_reviewHazard(report, approved: false)),
      ),
      _AdminSection.community => _CommunityModerationSection(
        communityPosts: _communityPosts,
        isSaving: _isSaving,
        onApprove: (post) => unawaited(_moderatePost(post, status: 'approved')),
        onHide: (post) => unawaited(_moderatePost(post, status: 'hidden')),
        onRemove: (post) => unawaited(_moderatePost(post, status: 'removed')),
      ),
    };

    return ColoredBox(
      color: _AdminColors.backgroundFor(context),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _debugMode
              ? () async {
                  if (_selectedDebugSection == _DebugSection.firestore) {
                    await _loadFirestoreDebugData();
                  } else if (_selectedDebugSection == _DebugSection.local) {
                    await _loadLocalDbDebugData();
                  }
                }
              : _loadAdminData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_debugMode)
                      _AdminHeader(
                        title: 'Debug Mode',
                        subtitle: _selectedDebugSection == null
                            ? 'Select a data source to inspect'
                            : _selectedDebugSection == _DebugSection.firestore
                                ? 'Firestore - ${_firestoreData.where((c) => c.documents.isNotEmpty).length}/${_firestoreData.length} collections populated'
                                : 'Local Database - ${_localDbData.entries.where((e) => e.value.isNotEmpty).length}/${_localDbData.length} tables populated',
                        isLoading: _isDebugLoading,
                        onRefresh: () {
                          if (_selectedDebugSection == _DebugSection.firestore) {
                            unawaited(_loadFirestoreDebugData());
                          } else if (_selectedDebugSection ==
                              _DebugSection.local) {
                            unawaited(_loadLocalDbDebugData());
                          }
                        },
                        onBack: _selectedDebugSection == null
                            ? _exitDebugMode
                            : () {
                                setState(() {
                                  _selectedDebugSection = null;
                                  _localDbData = const {};
                                  _firestoreData = const [];
                                  _debugError = null;
                                });
                              },
                      )
                    else
                      _AdminHeader(
                        title: title,
                        subtitle: subtitle,
                        isLoading: _isLoading,
                        onRefresh: () => unawaited(_loadAdminData()),
                        onBack: _selectedSection == _AdminSection.overview
                            ? null
                            : () {
                                setState(() {
                                  _selectedSection = _AdminSection.overview;
                                });
                              },
                        onTitleTap: _onDebugTitleTap,
                      ),
                    if (_debugError != null) ...[
                      const SizedBox(height: 12),
                      _AdminNotice(message: _debugError!),
                    ] else if (_errorMessage != null && !_debugMode) ...[
                      const SizedBox(height: 12),
                      _AdminNotice(message: _errorMessage!),
                    ],
                    const SizedBox(height: 16),
                    if (_debugMode)
                      _DebugContent(
                        selectedSection: _selectedDebugSection,
                        firestoreData: _firestoreData,
                        localDbData: _localDbData,
                        isLoading: _isDebugLoading,
                        onSelectFirestore: () {
                          setState(() {
                            _selectedDebugSection = _DebugSection.firestore;
                          });
                          unawaited(_loadFirestoreDebugData());
                        },
                        onSelectLocal: () {
                          setState(() {
                            _selectedDebugSection = _DebugSection.local;
                          });
                          unawaited(_loadLocalDbDebugData());
                        },
                      )
                    else
                      content,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLockedState extends StatelessWidget {
  const _AdminLockedState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _AdminColors.backgroundFor(context),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Admin privilege is required.'),
        ),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onRefresh,
    this.onBack,
    this.onTitleTap,
  });

  final String title;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack == null)
          const _CircleIcon(icon: Icons.admin_panel_settings_rounded)
        else
          _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back to admin dashboard',
            onPressed: onBack!,
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTitleTap,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _AdminColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AdminColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Refresh admin data',
          child: IconButton(
            onPressed: isLoading ? null : onRefresh,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    );
  }
}

class _AdminOverviewDashboard extends StatelessWidget {
  const _AdminOverviewDashboard({
    required this.trailCount,
    required this.verifiedTrailCount,
    required this.pendingHazardCount,
    required this.communityPostCount,
    required this.moderatedPostCount,
    required this.onOpenTrails,
    required this.onOpenHazards,
    required this.onOpenCommunity,
  });

  final int trailCount;
  final int verifiedTrailCount;
  final int pendingHazardCount;
  final int communityPostCount;
  final int moderatedPostCount;
  final VoidCallback onOpenTrails;
  final VoidCallback onOpenHazards;
  final VoidCallback onOpenCommunity;

  @override
  Widget build(BuildContext context) {
    final unverifiedTrailCount = trailCount - verifiedTrailCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _AdminMetric(
                label: 'Trails',
                value: '$trailCount',
                icon: Icons.terrain_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AdminMetric(
                label: 'Pending Hazards',
                value: '$pendingHazardCount',
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AdminMetric(
                label: 'Moderated Posts',
                value: '$moderatedPostCount',
                icon: Icons.shield_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle(label: 'Main Admin Sections'),
        const SizedBox(height: 8),
        _AdminDashboardCard(
          title: 'Trails',
          subtitle:
              'Manage Firebase trails, route metadata, checkpoints, and verification.',
          metric: '$trailCount total',
          detail: '$verifiedTrailCount verified - $unverifiedTrailCount draft',
          icon: Icons.terrain_rounded,
          isPrimary: true,
          onTap: onOpenTrails,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Hazard Reports',
          subtitle: 'Review community-submitted safety reports.',
          metric: '$pendingHazardCount pending',
          detail: 'Approve reports to attach hazards to trails',
          icon: Icons.report_problem_rounded,
          onTap: onOpenHazards,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Community Posts',
          subtitle: 'Moderate public feed posts and unsafe content.',
          metric: '$communityPostCount posts',
          detail: '$moderatedPostCount hidden or removed',
          icon: Icons.forum_rounded,
          onTap: onOpenCommunity,
        ),
      ],
    );
  }
}

class _AdminDashboardCard extends StatelessWidget {
  const _AdminDashboardCard({
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.detail,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String title;
  final String subtitle;
  final String metric;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final iconBackground = isPrimary
        ? _AdminColors.green
        : _AdminColors.greenSoftFor(context);
    final iconColor = isPrimary ? Colors.white : _AdminColors.green;

    return _InsetGroup(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(isPrimary ? 16 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isPrimary ? 48 : 42,
                  height: isPrimary ? 48 : 42,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: isPrimary ? 26 : 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _AdminColors.textFor(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AdminColors.secondaryTextFor(context),
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _AdminColors.secondaryTextFor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      metric,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: _AdminColors.green,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _AdminColors.secondaryTextFor(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailManagementSection extends StatelessWidget {
  const _TrailManagementSection({
    required this.trails,
    required this.isLoading,
    required this.isSaving,
    required this.onAddTrail,
    required this.onOpenTrail,
    required this.onEditTrail,
    required this.onDeleteTrail,
    required this.onToggleVerification,
  });

  final List<Trail> trails;
  final bool isLoading;
  final bool isSaving;
  final VoidCallback onAddTrail;
  final ValueChanged<Trail> onOpenTrail;
  final Future<void> Function(Trail trail) onEditTrail;
  final Future<void> Function(Trail trail) onDeleteTrail;
  final ValueChanged<Trail> onToggleVerification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle(label: 'Firebase Trails')),
            FilledButton.icon(
              onPressed: isSaving ? null : onAddTrail,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Trail'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading && trails.isEmpty) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
        ],
        _InsetGroup(
          child: Column(
            children: [
              if (trails.isEmpty)
                const _EmptyState(
                  message: 'No Firebase trails found. Add the first trail.',
                )
              else
                for (var index = 0; index < trails.length; index++) ...[
                  _TrailAdminRow(
                    trail: trails[index],
                    isSaving: isSaving,
                    onOpen: () => onOpenTrail(trails[index]),
                    onEdit: () => onEditTrail(trails[index]),
                    onDelete: () => onDeleteTrail(trails[index]),
                    onToggleVerification: () =>
                        onToggleVerification(trails[index]),
                  ),
                  if (index != trails.length - 1) const _HorizontalSeparator(),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailAdminRow extends StatelessWidget {
  const _TrailAdminRow({
    required this.trail,
    required this.isSaving,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleVerification,
  });

  final Trail trail;
  final bool isSaving;
  final VoidCallback onOpen;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final VoidCallback onToggleVerification;

  @override
  Widget build(BuildContext context) {
    final checkpointLabel = trail.checkpoints.length == 1
        ? '1 checkpoint'
        : '${trail.checkpoints.length} checkpoints';

    final row = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.terrain_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: trail.name,
                  subtitle:
                      '${trail.locationLabel} - ${trail.distanceLabel} - ${trail.difficulty}',
                  body:
                      '$checkpointLabel - ${trail.durationLabel} - Rating ${trail.ratingAverage.toStringAsFixed(1)}',
                ),
              ),
              const SizedBox(width: 8),
              _AdminStatusPill(
                label: trail.isVerifiedTrail ? 'Verified' : 'Draft',
                color: trail.isVerifiedTrail
                    ? _AdminColors.green
                    : _AdminColors.orangeFor(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.edit_location_alt_rounded),
                label: const Text('Manage'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onToggleVerification,
                icon: Icon(
                  trail.isVerifiedTrail
                      ? Icons.visibility_off_rounded
                      : Icons.verified_rounded,
                ),
                label: Text(
                  trail.isVerifiedTrail ? 'Mark Draft' : 'Verify Trail',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('admin-trail-${trail.trailId}-${trail.name}'),
      confirmDismiss: (direction) async {
        if (isSaving) {
          return false;
        }

        if (direction == DismissDirection.startToEnd) {
          await onEdit();
          return false;
        }

        await onDelete();
        return false;
      },
      background: const _AdminSwipeActionBackground(
        alignment: Alignment.centerLeft,
        color: _AdminColors.green,
        icon: Icons.edit_rounded,
        label: 'Edit',
      ),
      secondaryBackground: _AdminSwipeActionBackground(
        alignment: Alignment.centerRight,
        color: _AdminColors.redFor(context),
        icon: Icons.delete_rounded,
        label: 'Delete',
      ),
      child: row,
    );
  }
}

class _AdminSwipeActionBackground extends StatelessWidget {
  const _AdminSwipeActionBackground({
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

class _HazardReportsSection extends StatelessWidget {
  const _HazardReportsSection({
    required this.hazardReports,
    required this.isSaving,
    required this.onApprove,
    required this.onReject,
  });

  final List<Map<String, dynamic>> hazardReports;
  final bool isSaving;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Hazard Reports'),
        const SizedBox(height: 8),
        _InsetGroup(
          child: Column(
            children: [
              if (hazardReports.isEmpty)
                const _EmptyState(message: 'No hazard reports to review.')
              else
                for (var index = 0; index < hazardReports.length; index++) ...[
                  _HazardAdminRow(
                    report: hazardReports[index],
                    isSaving: isSaving,
                    onApprove: () => onApprove(hazardReports[index]),
                    onReject: () => onReject(hazardReports[index]),
                  ),
                  if (index != hazardReports.length - 1)
                    const _HorizontalSeparator(),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityModerationSection extends StatelessWidget {
  const _CommunityModerationSection({
    required this.communityPosts,
    required this.isSaving,
    required this.onApprove,
    required this.onHide,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> communityPosts;
  final bool isSaving;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onHide;
  final ValueChanged<Map<String, dynamic>> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Community Moderation'),
        const SizedBox(height: 8),
        _InsetGroup(
          child: Column(
            children: [
              if (communityPosts.isEmpty)
                const _EmptyState(message: 'No community posts to moderate.')
              else
                for (var index = 0; index < communityPosts.length; index++) ...[
                  _PostAdminRow(
                    post: communityPosts[index],
                    isSaving: isSaving,
                    onApprove: () => onApprove(communityPosts[index]),
                    onHide: () => onHide(communityPosts[index]),
                    onRemove: () => onRemove(communityPosts[index]),
                  ),
                  if (index != communityPosts.length - 1)
                    const _HorizontalSeparator(),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: _AdminColors.green, size: 22),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _AdminColors.textFor(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _AdminColors.secondaryTextFor(context),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardAdminRow extends StatelessWidget {
  const _HazardAdminRow({
    required this.report,
    required this.isSaving,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> report;
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final status = _stringFrom(report['status']).isEmpty
        ? 'unverified'
        : _stringFrom(report['status']);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.report_problem_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: _stringFrom(report['hazardType']).isEmpty
                      ? 'Hazard report'
                      : _stringFrom(report['hazardType']),
                  subtitle:
                      '${_stringFrom(report['trailName'])} - ${_stringFrom(report['severity']).toUpperCase()} - $status',
                  body: _stringFrom(report['description']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSaving ? null : onApprove,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSaving ? null : onReject,
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAdminRow extends StatelessWidget {
  const _PostAdminRow({
    required this.post,
    required this.isSaving,
    required this.onApprove,
    required this.onHide,
    required this.onRemove,
  });

  final Map<String, dynamic> post;
  final bool isSaving;
  final VoidCallback onApprove;
  final VoidCallback onHide;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final visibility = _stringFrom(post['visibility']).isEmpty
        ? 'public'
        : _stringFrom(post['visibility']);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CircleIcon(icon: Icons.forum_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminTextBlock(
                  title: _stringFrom(post['authorHandle']).isEmpty
                      ? _stringFrom(post['authorPhoneNumber'])
                      : _stringFrom(post['authorHandle']),
                  subtitle:
                      '${_stringFrom(post['trailName']).isEmpty ? 'General' : _stringFrom(post['trailName'])} - $visibility',
                  body: _stringFrom(post['caption']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isSaving ? null : onApprove,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onHide,
                icon: const Icon(Icons.visibility_off_rounded),
                label: const Text('Hide'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onRemove,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminTextBlock extends StatelessWidget {
  const _AdminTextBlock({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? 'Untitled' : title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _AdminColors.textFor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AdminColors.secondaryTextFor(context),
            letterSpacing: 0,
          ),
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _AdminColors.textFor(context),
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _AdminColors.redFor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AdminColors.redFor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _AdminColors.secondaryTextFor(context),
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: _AdminColors.secondaryTextFor(context),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
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
        color: _AdminColors.greenSoftFor(context),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: _AdminColors.green, size: 20),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _AdminColors.greenSoftFor(context),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, color: _AdminColors.green, size: 20),
          ),
        ),
      ),
    );
  }
}

class _AdminStatusPill extends StatelessWidget {
  const _AdminStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(color: _AdminColors.surfaceFor(context)),
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
      color: _AdminColors.separatorFor(context),
    );
  }
}

class _FirestoreCollection {
  const _FirestoreCollection({
    required this.name,
    required this.documents,
    this.error,
  });

  final String name;
  final List<Map<String, dynamic>> documents;
  final String? error;
}

class _DebugContent extends StatelessWidget {
  const _DebugContent({
    required this.selectedSection,
    required this.firestoreData,
    required this.localDbData,
    required this.isLoading,
    required this.onSelectFirestore,
    required this.onSelectLocal,
  });

  final _DebugSection? selectedSection;
  final List<_FirestoreCollection> firestoreData;
  final Map<String, List<Map<String, dynamic>>> localDbData;
  final bool isLoading;
  final VoidCallback onSelectFirestore;
  final VoidCallback onSelectLocal;

  @override
  Widget build(BuildContext context) {
    if (selectedSection == null) {
      return _DebugSectionPicker(
        onSelectFirestore: onSelectFirestore,
        onSelectLocal: onSelectLocal,
      );
    }

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (selectedSection == _DebugSection.firestore) {
      return _FirestoreDebugView(data: firestoreData);
    }

    return _LocalDbDebugView(data: localDbData);
  }
}

class _DebugSectionPicker extends StatelessWidget {
  const _DebugSectionPicker({
    required this.onSelectFirestore,
    required this.onSelectLocal,
  });

  final VoidCallback onSelectFirestore;
  final VoidCallback onSelectLocal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _SectionTitle(label: 'Choose Data Source'),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Firestore',
          subtitle: 'Browse all Firestore collections and documents.',
          metric: 'Cloud',
          detail: 'Read-only view of Firebase Firestore data',
          icon: Icons.cloud_rounded,
          onTap: onSelectFirestore,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Local Database',
          subtitle: 'Inspect local SQLite tables and rows.',
          metric: 'Device',
          detail: 'Read-only view of on-device database',
          icon: Icons.storage_rounded,
          onTap: onSelectLocal,
        ),
      ],
    );
  }
}

class _FirestoreDebugView extends StatelessWidget {
  const _FirestoreDebugView({required this.data});

  final List<_FirestoreCollection> data;

  @override
  Widget build(BuildContext context) {
    final populated = data.where((c) => c.documents.isNotEmpty).length;
    final totalDocuments =
        data.fold<int>(0, (total, c) => total + c.documents.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          label:
              '$populated/${data.length} collections • $totalDocuments documents',
        ),
        const SizedBox(height: 8),
        if (data.isEmpty)
          const _EmptyState(message: 'No collections found.')
        else
          _InsetGroup(
            child: Column(
              children: [
                for (var i = 0; i < data.length; i++) ...[
                  _CollectionCard(collection: data[i]),
                  if (i != data.length - 1) const _HorizontalSeparator(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CollectionCard extends StatefulWidget {
  const _CollectionCard({required this.collection});

  final _FirestoreCollection collection;

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final color = collection.error != null
        ? _AdminColors.redFor(context)
        : collection.documents.isEmpty
            ? _AdminColors.secondaryTextFor(context)
            : _AdminColors.green;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: collection.documents.isEmpty
            ? null
            : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    collection.error != null
                        ? Icons.error_outline_rounded
                        : collection.documents.isEmpty
                            ? Icons.inbox_rounded
                            : Icons.folder_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      collection.name,
                      style:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: _AdminColors.textFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: collection.error != null
                        ? 'Error'
                        : '${collection.documents.length}',
                    color: color,
                  ),
                ],
              ),
              if (collection.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  collection.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AdminColors.redFor(context),
                        letterSpacing: 0,
                      ),
                ),
              ],
              if (_expanded && collection.documents.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var docIndex = 0;
                    docIndex < collection.documents.length;
                    docIndex++) ...[
                  _DocCard(
                    index: docIndex,
                    data: collection.documents[docIndex],
                  ),
                  if (docIndex != collection.documents.length - 1)
                    const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.index, required this.data});

  final int index;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final id = data['id']?.toString() ?? 'unknown';

    return Container(
      decoration: BoxDecoration(
        color: _AdminColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '[$index] $id',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _AdminColors.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 6),
          for (final entry in data.entries)
            if (entry.key != 'id')
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _KeyValueRow(key_: entry.key, value: entry.value),
              ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required String key_, required Object? value})
      : _key = key_,
        _value = value;

  final String _key;
  final Object? _value;

  @override
  Widget build(BuildContext context) {
    if (_value is List) {
      final list = _value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _key,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
            ),
          ),
          if (list.isEmpty)
            Text(
              '[]',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.textFor(context),
                    letterSpacing: 0,
                  ),
            )
          else
            Container(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < list.length; i++)
                    _listItemWidget(context, list[i], i),
                ],
              ),
            ),
        ],
      );
    }

    final displayValue = _formatValue(_value);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            _key,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AdminColors.secondaryTextFor(context),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            displayValue,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AdminColors.textFor(context),
                  letterSpacing: 0,
                ),
          ),
        ),
      ],
    );
  }

  Widget _listItemWidget(BuildContext context, Object? item, int index) {
    if (item is Map) {
      if (item.isEmpty) return const Text('{}');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          decoration: BoxDecoration(
            color: _AdminColors.greenSoftFor(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[$index]',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AdminColors.green,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 3),
              for (final entry in item.entries)
                _KeyValueRow(key_: entry.key, value: entry.value),
            ],
          ),
        ),
      );
    }

    if (item is List) {
      final inner = item;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(
          '[$index] ${_formatValue(inner)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AdminColors.textFor(context),
                letterSpacing: 0,
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '[$index] ${_formatValue(item)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AdminColors.textFor(context),
              letterSpacing: 0,
            ),
      ),
    );
  }

  String _formatValue(Object? value) {
    if (value == null) return 'null';
    if (value is double) return value.toStringAsFixed(6);
    if (value is List) {
      if (value.isEmpty) return '[]';
      return '[${value.length} items]';
    }
    if (value is Map) {
      if (value.isEmpty) return '{}';
      return '{${value.length} keys}';
    }
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    return value.toString();
  }
}

class _LocalDbDebugView extends StatelessWidget {
  const _LocalDbDebugView({required this.data});

  final Map<String, List<Map<String, dynamic>>> data;

  @override
  Widget build(BuildContext context) {
    final populated =
        data.entries.where((e) => e.value.isNotEmpty).length;
    final totalRows = data.entries
        .fold<int>(0, (total, e) => total + e.value.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          label:
              '$populated/${data.length} tables • $totalRows rows',
        ),
        const SizedBox(height: 8),
        if (data.isEmpty)
          const _EmptyState(message: 'No tables found.')
        else
          _InsetGroup(
            child: Column(
              children: [
                for (var i = 0; i < data.entries.length; i++) ...[
                  _LocalTableCard(
                    name: data.entries.elementAt(i).key,
                    rows: data.entries.elementAt(i).value,
                  ),
                  if (i != data.entries.length - 1)
                    const _HorizontalSeparator(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LocalTableCard extends StatefulWidget {
  const _LocalTableCard({required this.name, required this.rows});

  final String name;
  final List<Map<String, dynamic>> rows;

  @override
  State<_LocalTableCard> createState() => _LocalTableCardState();
}

class _LocalTableCardState extends State<_LocalTableCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.rows.isEmpty
        ? _AdminColors.secondaryTextFor(context)
        : _AdminColors.green;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            widget.rows.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    widget.rows.isEmpty
                        ? Icons.table_chart_outlined
                        : Icons.table_chart_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style:
                          Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: _AdminColors.textFor(context),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: '${widget.rows.length}',
                    color: color,
                  ),
                ],
              ),
              if (_expanded && widget.rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var rowIndex = 0;
                    rowIndex < widget.rows.length;
                    rowIndex++) ...[
                  _DocCard(
                    index: rowIndex,
                    data: widget.rows[rowIndex],
                  ),
                  if (rowIndex != widget.rows.length - 1)
                    const SizedBox(height: 6),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _stringFrom(Object? value) {
  return value is String ? value : '';
}

abstract final class _AdminColors {
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color background = Color(0xFFF2F8F4);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color separator = Color(0xFFE5EFE8);
  static const Color red = Color(0xFFE11D48);
  static const Color orange = Color(0xFFF59E0B);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

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

  static Color orangeFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFBBF24) : orange;
}
