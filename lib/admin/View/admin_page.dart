// AdminPage routes administrator management, analytics and device debugging sections.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/loading_toast.dart';
import '../../core/widgets/page_header_style.dart';
import '../../feedback/feedback_page.dart';
import '../../me/Data/live_location_sharing_service.dart';
import '../../sos/Data/location_snapshot_service.dart';
import '../../trail/Model/trail_models.dart';
import '../../trail/View/trail_page.dart';
import 'button_debugging_page.dart';
import 'admin_ui.dart';
import 'admin_analytics_dashboard.dart';
import 'recorded_trail_requests_page.dart';
import 'community_integrity_panel.dart';
import 'community_post_management_page.dart';

enum _AdminSection { overview, trails, hazards, community, achievements, tools }

enum _DebugSection { firestore, local, runtime }

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.session,
    this.hikerCircleRepository,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.runtimeDebugData = const {},
  });

  final AppSession session;
  final HikerCircleFirebaseRepository? hikerCircleRepository;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final Map<String, Object?> runtimeDebugData;

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
  List<Map<String, dynamic>> _achievements = const [];
  List<Trail> _trails = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  _AdminSection _selectedSection = _AdminSection.overview;

  final _pageScroll = ScrollController();
  String _search = '';
  DateTime? _lastLoadedAt;
  Map<String, dynamic>? _analytics;
  String? _analyticsError;
  bool _analyticsLoading = false;
  int _analyticsRevision = 0;

  Future<void> _loadAnalytics({bool forceRefresh = false}) async {
    final revision = ++_analyticsRevision;
    setState(() {
      _analyticsLoading = true;
      _analyticsError = null;
    });
    try {
      final data = await _repository.loadAdminDashboardAnalytics(
        session: widget.session,
        forceRefresh: forceRefresh,
      );
      if (mounted && revision == _analyticsRevision) {
        setState(() => _analytics = data);
      }
    } catch (error) {
      if (mounted && revision == _analyticsRevision) {
        setState(
          () =>
              _analyticsError = error is HikerCircleFirebaseRepositoryException
              ? error.message
              : 'Statistics could not load. Refresh to retry.',
        );
      }
    } finally {
      if (mounted && revision == _analyticsRevision) {
        setState(() => _analyticsLoading = false);
      }
    }
  }

  void _selectSection(_AdminSection section) {
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
    setState(() {
      _selectedSection = section;
      _search = '';
    });
  }

  bool _debugMode = false;
  _DebugSection? _selectedDebugSection;
  Map<String, List<Map<String, dynamic>>> _localDbData = const {};
  List<_FirestoreCollection> _firestoreData = const [];
  Map<String, Map<String, Object?>> _runtimeData = const {};
  bool _isDebugLoading = false;
  String? _debugError;

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.session.isAdmin) unawaited(_loadAdminData());
  }

  /// Load the selected management data while retaining the current admin section and error state.
  Future<void> _loadAdminData() async {
    unawaited(_loadAnalytics(forceRefresh: _analytics != null));
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<Object>([
        _repository.loadAdminTrails(session: widget.session),
        _repository.loadAdminHazardReports(session: widget.session),
        _repository.loadAdminCommunityPosts(session: widget.session),
        _repository.loadAdminAchievements(session: widget.session),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastLoadedAt = DateTime.now();
        _trails = results[0] as List<Trail>;
        _hazardReports = results[1] as List<Map<String, dynamic>>;
        _communityPosts = results[2] as List<Map<String, dynamic>>;
        _achievements = results[3] as List<Map<String, dynamic>>;
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

  Future<void> _openTrailRequests() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordedTrailRequestsPage(
          session: widget.session,
          repository: _repository,
        ),
      ),
    );
    if (mounted) unawaited(_loadAdminData());
  }

  Future<void> _addTrail() async {
    if (!widget.session.isAdmin || _isSaving) {
      return;
    }

    final trail = await showAddTrailSheet(
      context,
      session: widget.session,
      repository: _repository,
    );
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
          onStartHike: (_) async {
            _showSnack('Create hikes from the Home tab.');
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

  Future<void> _openCommunityPosts() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityPostManagementPage(
          session: widget.session,
          repository: _repository,
        ),
      ),
    );
    if (mounted) unawaited(_loadAdminData());
  }

  /// Wait for the mutation and refreshed server state before showing an administrator success message.
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

  void _openDiagnostics() {
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
    setState(() {
      _debugMode = true;
      _selectedDebugSection = null;
      _debugError = null;
    });
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
        'footprints',
        'checkIns',
        'upcomingHikes',
        'teams',
        'teamHikeSessions',
        'fcmOutbox',
        'sosWhatsAppDispatches',
        'achievements',
        'userAchievements',
        'networkObservations',
        'downloadedMaps',
        'hikeRouteCaptures',
        'groupChats',
        'live_location_shares',
      ];

      final results = <_FirestoreCollection>[];
      for (final name in collections) {
        try {
          final snapshot = await firestore.collection(name).limit(50).get();
          results.add(
            _FirestoreCollection(
              name: name,
              documents: snapshot.docs.map((d) {
                return <String, dynamic>{'id': d.id, ...d.data()};
              }).toList(),
            ),
          );
        } catch (e) {
          results.add(
            _FirestoreCollection(
              name: name,
              documents: const [],
              error: e.toString(),
            ),
          );
        }
      }
      for (final entry in const {
        'communityPosts/*/comments': 'comments',
        'groupChats/*/messages': 'messages',
      }.entries) {
        try {
          final snapshot = await firestore
              .collectionGroup(entry.value)
              .limit(50)
              .get();
          results.add(
            _FirestoreCollection(
              name: entry.key,
              documents: snapshot.docs.map((document) {
                return <String, dynamic>{
                  'id': document.id,
                  'documentPath': document.reference.path,
                  ...document.data(),
                };
              }).toList(),
            ),
          );
        } catch (error) {
          results.add(
            _FirestoreCollection(
              name: entry.key,
              documents: const [],
              error: error.toString(),
            ),
          );
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

  /// Build the local SQLite inspection snapshot through the repository's diagnostics interface.
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

  Future<void> _addAchievement() async {
    final values = await _showAchievementEditor();
    if (values == null || !mounted) {
      return;
    }
    await _runAdminAction(
      successMessage: 'Achievement added.',
      action: () async {
        await _repository.saveAchievementByAdmin(
          session: widget.session,
          achievement: values,
        );
      },
    );
  }

  Future<void> _editAchievement(Map<String, dynamic> achievement) async {
    final values = await _showAchievementEditor(initial: achievement);
    if (values == null || !mounted) {
      return;
    }
    await _runAdminAction(
      successMessage: 'Achievement updated.',
      action: () async {
        await _repository.saveAchievementByAdmin(
          session: widget.session,
          achievementId: _stringFrom(achievement['achievementId']),
          achievement: values,
        );
      },
    );
  }

  Future<void> _toggleAchievement(Map<String, dynamic> achievement) async {
    final nextActive = achievement['isActive'] == false;
    await _runAdminAction(
      successMessage: nextActive
          ? 'Achievement activated.'
          : 'Achievement archived.',
      action: () async {
        await _repository.setAchievementActiveByAdmin(
          session: widget.session,
          achievementId: _stringFrom(achievement['achievementId']),
          isActive: nextActive,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _showAchievementEditor({
    Map<String, dynamic>? initial,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AchievementEditorSheet(initial: initial),
    );
  }

  void _loadRuntimeDebugData() {
    final session = widget.session;
    setState(() {
      _debugError = null;
      _runtimeData = {
        'Current authenticated app session': {
          'storageType': 'In-memory session with a SQLite mirror',
          'persistence':
              'Current process; persisted copy is shown under Local SQLite',
          'phoneNumber': session.phoneNumber,
          'username': session.username,
          'signedInAt': session.signedInAt.toUtc().toIso8601String(),
          'createdAt': session.createdAt.toUtc().toIso8601String(),
          'appInstanceId': session.appInstanceId,
          'isAdmin': session.isAdmin,
          'requiresOnboarding': session.requiresOnboarding,
          'isOnboardingProfileComplete': session.isOnboardingProfileComplete,
        },
        'Firebase bootstrap state': {
          'storageType': 'Process runtime configuration',
          'persistence': 'Re-created on app launch',
          'isAvailable': widget.firebaseBootstrapResult.isAvailable,
          'errorMessage': widget.firebaseBootstrapResult.errorMessage,
        },
        'App settings singleton': AppSettingsController.instance.debugSnapshot,
        'Location snapshot singleton':
            LocationSnapshotService.instance.debugSnapshot,
        'Live-location sharing singleton':
            LiveLocationSharingService.instance.debugSnapshot,
        'Trail cover image cache': {
          'storageType': 'Firebase Storage covers with persistent device cache',
          'persistence':
              'Up to 1,000 files; cached files stay fresh for 365 days',
        },
        'Admin screen memory': {
          'storageType': 'Widget state',
          'persistence': 'Exists only while this AdminPage is mounted',
          'selectedAdminSection': _selectedSection.name,
          'debugMode': _debugMode,
          'selectedDebugSection': _selectedDebugSection?.name,
          'isLoading': _isLoading,
          'isSaving': _isSaving,
          'isDebugLoading': _isDebugLoading,
          'loadedTrails': _trails.map((trail) => trail.toFirestore()).toList(),
          'loadedHazardReports': _hazardReports,
          'loadedCommunityPosts': _communityPosts,
          'loadedAchievements': _achievements,
          'adminError': _errorMessage,
          'debugError': _debugError,
        },
        for (final entry in widget.runtimeDebugData.entries)
          entry.key: entry.value is Map
              ? Map<String, Object?>.from(entry.value as Map)
              : {
                  'storageType': 'Parent runtime value',
                  'persistence': 'Process lifetime only',
                  'value': entry.value,
                },
      };
    });
  }

  void _exitDebugMode() {
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
    setState(() {
      _debugMode = false;
      _selectedDebugSection = null;
      _localDbData = const {};
      _firestoreData = const [];
      _runtimeData = const {};
      _debugError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const _AdminLockedState();
    }

    final title = switch (_selectedSection) {
      _AdminSection.overview => 'Dashboard',
      _AdminSection.trails => 'Trail Management',
      _AdminSection.hazards => 'Hazard Reports',
      _AdminSection.community => 'Community Moderation',
      _AdminSection.achievements => 'Achievements',
      _AdminSection.tools => 'Admin tools',
    };
    final subtitle = switch (_selectedSection) {
      _AdminSection.overview =>
        'System statistics and your management workspace.',
      _AdminSection.trails =>
        'Manage routes, checkpoints and trail verification.',
      _AdminSection.hazards => 'Verify or reject community safety reports.',
      _AdminSection.community =>
        'Review detected flags and manage community content.',
      _AdminSection.achievements =>
        'Create rewards and milestones for your hikers.',
      _AdminSection.tools => 'Support hikers and inspect app activity.',
    };
    final content = switch (_selectedSection) {
      _AdminSection.overview => AdminAnalyticsDashboard(
        data: _analytics,
        loading: _analyticsLoading,
        error: _analyticsError,
        onRetry: () => unawaited(_loadAnalytics(forceRefresh: true)),
        onTools: () => _selectSection(_AdminSection.tools),
        onTrails: () => _selectSection(_AdminSection.trails),
        onTrailRequests: () => unawaited(_openTrailRequests()),
        onSafety: () => _selectSection(_AdminSection.hazards),
        onCommunity: () => _selectSection(_AdminSection.community),
        onRewards: () => _selectSection(_AdminSection.achievements),
      ),
      _AdminSection.trails => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminPanel(
            onTap: () => unawaited(_openTrailRequests()),
            child: const Row(
              children: [
                Icon(Icons.add_road_rounded),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Review recorded trail requests',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _TrailManagementSection(
            trails: _trails
                .where(
                  (trail) => '${trail.name} ${trail.locationLabel}'
                      .toLowerCase()
                      .contains(_search),
                )
                .toList(),
            isLoading: _isLoading,
            isSaving: _isSaving,
            onAddTrail: () => unawaited(_addTrail()),
            onOpenTrail: (trail) => unawaited(_openTrail(trail)),
            onEditTrail: _editTrail,
            onDeleteTrail: _deleteTrail,
            onToggleVerification: (trail) =>
                unawaited(_toggleTrailVerification(trail)),
          ),
        ],
      ),
      _AdminSection.hazards => _HazardReportsSection(
        hazardReports: _hazardReports
            .where(
              (row) => row.values.join(' ').toLowerCase().contains(_search),
            )
            .toList(),
        isSaving: _isSaving,
        onApprove: (report) => unawaited(_reviewHazard(report, approved: true)),
        onReject: (report) => unawaited(_reviewHazard(report, approved: false)),
      ),
      _AdminSection.community => _CommunityModerationSection(
        onReviewed: () => unawaited(_loadAdminData()),
        onManagePosts: () => unawaited(_openCommunityPosts()),
      ),
      _AdminSection.achievements => _AchievementManagementSection(
        achievements: _achievements
            .where(
              (row) => row.values.join(' ').toLowerCase().contains(_search),
            )
            .toList(),
        isSaving: _isSaving,
        onAdd: () => unawaited(_addAchievement()),
        onEdit: (achievement) => unawaited(_editAchievement(achievement)),
        onToggleActive: (achievement) =>
            unawaited(_toggleAchievement(achievement)),
      ),
      _AdminSection.tools => _AdminTileGrid(
        children: [
          _AdminDashboardCard(
            title: 'Hiker feedback',
            subtitle: 'Read feedback and follow up on reported issues.',
            metric: 'Support',
            detail: 'Feedback inbox',
            icon: Icons.feedback_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FeedbackInboxPage(admin: true),
              ),
            ),
          ),
          _AdminDashboardCard(
            title: 'Button Debugging',
            subtitle: 'Capture button activity and inspect decoded HEX logs.',
            metric: 'Device tools',
            detail: 'Live capture & saved sessions',
            icon: Icons.bluetooth_searching_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ButtonDebuggingPage(session: widget.session),
              ),
            ),
          ),
          _AdminDashboardCard(
            title: 'Data diagnostics',
            subtitle: 'Inspect cloud records, local storage and runtime state.',
            metric: 'Diagnostics',
            detail: 'Read-only inspection',
            icon: Icons.storage_outlined,
            onTap: _openDiagnostics,
          ),
        ],
      ),
    };

    return ColoredBox(
      color: _AdminColors.backgroundFor(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _debugMode
                  ? () async {
                      if (_selectedDebugSection == _DebugSection.firestore) {
                        await _loadFirestoreDebugData();
                      } else if (_selectedDebugSection == _DebugSection.local) {
                        await _loadLocalDbDebugData();
                      } else if (_selectedDebugSection ==
                          _DebugSection.runtime) {
                        _loadRuntimeDebugData();
                      }
                    }
                  : _loadAdminData,
              child: SingleChildScrollView(
                controller: _pageScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_debugMode)
                          _AdminHeader(
                            title: 'Debug Mode',
                            subtitle: _selectedDebugSection == null
                                ? 'Select a data source to inspect'
                                : _selectedDebugSection ==
                                      _DebugSection.firestore
                                ? 'Firestore - ${_firestoreData.where((c) => c.documents.isNotEmpty).length}/${_firestoreData.length} collections populated'
                                : _selectedDebugSection == _DebugSection.local
                                ? 'Local SQLite - ${_localDbData.entries.where((e) => e.value.isNotEmpty).length}/${_localDbData.length} tables populated'
                                : 'Runtime & temporary state - ${_runtimeData.length} groups',
                            isLoading: _isDebugLoading,
                            onRefresh: () {
                              if (_selectedDebugSection ==
                                  _DebugSection.firestore) {
                                unawaited(_loadFirestoreDebugData());
                              } else if (_selectedDebugSection ==
                                  _DebugSection.local) {
                                unawaited(_loadLocalDbDebugData());
                              } else if (_selectedDebugSection ==
                                  _DebugSection.runtime) {
                                _loadRuntimeDebugData();
                              }
                            },
                            onBack: _selectedDebugSection == null
                                ? _exitDebugMode
                                : () {
                                    setState(() {
                                      _selectedDebugSection = null;
                                      _localDbData = const {};
                                      _firestoreData = const [];
                                      _runtimeData = const {};
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
                                : () => _selectSection(_AdminSection.overview),
                          ),
                        if (!_debugMode) ...[
                          const SizedBox(height: 16),
                          _AdminNavigation(
                            selected: _selectedSection,
                            onSelect: _selectSection,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isLoading
                                ? 'Refreshing workspace…'
                                : _errorMessage != null
                                ? 'Unable to refresh workspace'
                                : _lastLoadedAt == null
                                ? 'No data loaded'
                                : 'Updated at ${_lastLoadedAt!.hour.toString().padLeft(2, '0')}:${_lastLoadedAt!.minute.toString().padLeft(2, '0')}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _AdminColors.secondaryTextFor(context),
                                ),
                          ),
                          if (_selectedSection != _AdminSection.overview &&
                              _selectedSection != _AdminSection.tools &&
                              _selectedSection != _AdminSection.community) ...[
                            const SizedBox(height: 18),
                            TextField(
                              key: ValueKey(
                                'admin-search-${_selectedSection.name}',
                              ),
                              onChanged: (value) => setState(
                                () => _search = value.trim().toLowerCase(),
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search ${switch (_selectedSection) {
                                      _AdminSection.trails => 'trails',
                                      _AdminSection.hazards => 'reports',
                                      _AdminSection.community => 'posts',
                                      _ => 'achievements',
                                    }}',
                                prefixIcon: const Icon(Icons.search_rounded),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: AdminUi.border(context),
                                  ),
                                ),
                                filled: true,
                                fillColor: _AdminColors.surfaceFor(context),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _AdminColors.separatorFor(context),
                                  ),
                                ),
                              ),
                            ),
                            if (_search.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Showing matching records. Clear the search to see all.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ],
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
                            runtimeData: _runtimeData,
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
                            onSelectRuntime: () {
                              setState(() {
                                _selectedDebugSection = _DebugSection.runtime;
                              });
                              _loadRuntimeDebugData();
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
          if (_isLoading || _isDebugLoading)
            HikerCircleLoadingToastOverlay(
              message: _isDebugLoading
                  ? 'Loading diagnostics…'
                  : 'Loading admin data…',
              detail: 'Fetching the latest information securely.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _isDebugLoading = false;
                    _errorMessage = 'The request timed out. Please try again.';
                  });
                }
              },
            ),
        ],
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
  });
  final String title, subtitle;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
    child: Row(
      children: [
        if (onBack != null) ...[
          PageHeaderAction(
            tooltip: 'Back to admin dashboard',
            icon: Icons.arrow_back_rounded,
            onPressed: onBack,
            color: _AdminColors.greenFor(context),
            surface: _AdminColors.surfaceFor(context),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PageHeaderStyle.title(
                  context,
                  _AdminColors.textFor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: PageHeaderStyle.subtitle(
                  context,
                  _AdminColors.secondaryTextFor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PageHeaderAction(
          tooltip: 'Refresh admin data',
          icon: Icons.refresh_rounded,
          onPressed: isLoading ? null : onRefresh,
          color: _AdminColors.greenFor(context),
          surface: _AdminColors.surfaceFor(context),
        ),
      ],
    ),
  );
}

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({required this.selected, required this.onSelect});
  final _AdminSection selected;
  final ValueChanged<_AdminSection> onSelect;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(12) > 17;
      final columns = constraints.maxWidth >= 760 && !largeText
          ? 6
          : largeText
          ? 2
          : 3;
      return AdminPanel(
        padding: const EdgeInsets.all(5),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final section in _AdminSection.values)
              SizedBox(
                width:
                    (constraints.maxWidth - 10 - (columns - 1) * 4) / columns,
                child: Semantics(
                  selected: selected == section,
                  button: true,
                  child: Material(
                    color: selected == section
                        ? AdminUi.green(context).withValues(alpha: .09)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: ValueKey('admin-nav-${section.name}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(section),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              switch (section) {
                                _AdminSection.overview =>
                                  Icons.grid_view_rounded,
                                _AdminSection.trails => Icons.route_rounded,
                                _AdminSection.hazards => Icons.shield_outlined,
                                _AdminSection.community => Icons.forum_outlined,
                                _AdminSection.achievements =>
                                  Icons.emoji_events_outlined,
                                _AdminSection.tools => Icons.tune_rounded,
                              },
                              size: 19,
                              color: selected == section
                                  ? AdminUi.green(context)
                                  : AdminUi.muted(context),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              switch (section) {
                                _AdminSection.overview => 'Overview',
                                _AdminSection.trails => 'Trails',
                                _AdminSection.hazards => 'Safety',
                                _AdminSection.community => 'Community',
                                _AdminSection.achievements => 'Rewards',
                                _AdminSection.tools => 'Tools',
                              },
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected == section
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected == section
                                    ? AdminUi.green(context)
                                    : AdminUi.muted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Natural-height tiles avoid clipping when system text size is increased.
class _AdminTileGrid extends StatelessWidget {
  const _AdminTileGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 640 && scale < 1.5 ? 2 : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 12) / columns,
              child: child,
            ),
        ],
      );
    },
  );
}

class _AdminDashboardCard extends StatelessWidget {
  const _AdminDashboardCard({
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle, metric, detail;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AdminPanel(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminUi.blue(context).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AdminUi.blue(context), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AdminUi.muted(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AdminUi.muted(context),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AdminTag(label: metric, color: AdminUi.blue(context)),
            Text(
              detail,
              style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );
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
            const Expanded(child: _SectionTitle(label: 'Trail library')),
            FilledButton.icon(
              onPressed: isSaving ? null : onAddTrail,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Trail'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading && trails.isEmpty) ...[
          const HikerCircleLoadingView(
            message: 'Loading trail records…',
            detail: 'Getting trails and verification status.',
            compact: true,
            padding: EdgeInsets.symmetric(vertical: 4),
          ),
          const SizedBox(height: 8),
        ],
        Column(
          children: [
            if (trails.isEmpty)
              const _EmptyState(message: 'No trails to display.')
            else
              for (var index = 0; index < trails.length; index++) ...[
                AdminPanel(
                  padding: EdgeInsets.zero,
                  child: _TrailAdminRow(
                    trail: trails[index],
                    isSaving: isSaving,
                    onOpen: () => onOpenTrail(trails[index]),
                    onEdit: () => onEditTrail(trails[index]),
                    onDelete: () => onDeleteTrail(trails[index]),
                    onToggleVerification: () =>
                        onToggleVerification(trails[index]),
                  ),
                ),
                if (index != trails.length - 1) const SizedBox(height: 12),
              ],
          ],
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
                  subtitle: [
                    trail.locationLabel,
                    trail.distanceLabel,
                    if (trail.hasCommunityDifficulty) trail.difficulty,
                  ].join(' - '),
                  body:
                      '$checkpointLabel - ${trail.durationLabel} - Rating ${trail.ratingAverage.toStringAsFixed(1)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            children: [
              _AdminStatusPill(
                label: trail.isVerifiedTrail ? 'Verified' : 'Unverified',
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
              PopupMenuButton<String>(
                tooltip: 'Trail actions',
                enabled: !isSaving,
                onSelected: (action) {
                  if (action == 'edit') {
                    unawaited(onEdit());
                  } else {
                    unawaited(onDelete());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit trail')),
                  PopupMenuItem(value: 'delete', child: Text('Delete trail')),
                ],
                icon: const Icon(Icons.more_horiz_rounded),
              ),
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
                label: Text(trail.isVerifiedTrail ? 'Unverify' : 'Verify'),
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
        Column(
          children: [
            if (hazardReports.isEmpty)
              const _EmptyState(message: 'No hazard reports to review.')
            else
              for (var index = 0; index < hazardReports.length; index++) ...[
                AdminPanel(
                  padding: EdgeInsets.zero,
                  child: _HazardAdminRow(
                    report: hazardReports[index],
                    isSaving: isSaving,
                    onApprove: () => onApprove(hazardReports[index]),
                    onReject: () => onReject(hazardReports[index]),
                  ),
                ),
                if (index != hazardReports.length - 1)
                  const SizedBox(height: 12),
              ],
          ],
        ),
      ],
    );
  }
}

class _CommunityModerationSection extends StatelessWidget {
  const _CommunityModerationSection({
    required this.onReviewed,
    required this.onManagePosts,
  });

  final VoidCallback onReviewed;
  final VoidCallback onManagePosts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CommunityIntegrityPanel(onReviewed: onReviewed),
      const SizedBox(height: 16),
      AdminPanel(
        onTap: onManagePosts,
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.edit_note_rounded),
          title: Text('Manage community posts'),
          subtitle: Text('Browse, edit, restore, hide or remove posts.'),
          trailing: Icon(Icons.chevron_right_rounded),
        ),
      ),
    ],
  );
}

class _AchievementManagementSection extends StatelessWidget {
  const _AchievementManagementSection({
    required this.achievements,
    required this.isSaving,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
  });

  final List<Map<String, dynamic>> achievements;
  final bool isSaving;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final active = achievements
        .where((item) => item['isActive'] != false)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle(label: 'Achievement Rules')),
            FilledButton.icon(
              onPressed: isSaving ? null : onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add rule'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AdminNotice(
          isError: false,
          message:
              '$active active of ${achievements.length}. Rewards are granted once; accumulation rules track progress until their target is reached.',
        ),
        const SizedBox(height: 10),
        Column(
          children: [
            if (achievements.isEmpty)
              const _EmptyState(message: 'No achievement rules configured.')
            else
              for (var index = 0; index < achievements.length; index++) ...[
                AdminPanel(
                  padding: EdgeInsets.zero,
                  child: _AchievementAdminRow(
                    achievement: achievements[index],
                    isSaving: isSaving,
                    onEdit: () => onEdit(achievements[index]),
                    onToggleActive: () => onToggleActive(achievements[index]),
                  ),
                ),
                if (index != achievements.length - 1)
                  const SizedBox(height: 12),
              ],
          ],
        ),
      ],
    );
  }
}

class _AchievementAdminRow extends StatelessWidget {
  const _AchievementAdminRow({
    required this.achievement,
    required this.isSaving,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> achievement;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final isActive = achievement['isActive'] != false;
    final isCumulative = _stringFrom(achievement['rewardType']) == 'cumulative';
    final target = isCumulative
        ? 'Target ${_intFrom(achievement['targetCount'])}'
        : 'One-time';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? _AdminColors.greenSoftFor(context)
                  : _AdminColors.separatorFor(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: isActive
                  ? _AdminColors.green
                  : _AdminColors.secondaryTextFor(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _stringFrom(achievement['title']),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _AdminColors.textFor(context),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    _AdminStatusPill(
                      label: isActive ? 'Active' : 'Archived',
                      color: isActive
                          ? _AdminColors.green
                          : _AdminColors.secondaryTextFor(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _stringFrom(achievement['condition']),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.secondaryTextFor(context),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _AdminStatusPill(
                      label: '${_intFrom(achievement['rewardPoints'])} pts',
                      color: _AdminColors.green,
                    ),
                    _AdminStatusPill(label: target, color: Colors.blueAccent),
                    _AdminStatusPill(
                      label: _stringFrom(achievement['metricKey']),
                      color: _AdminColors.orangeFor(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: 'Edit achievement',
                onPressed: isSaving ? null : onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
              IconButton(
                tooltip: isActive
                    ? 'Archive achievement'
                    : 'Activate achievement',
                onPressed: isSaving ? null : onToggleActive,
                icon: Icon(
                  isActive ? Icons.archive_rounded : Icons.unarchive_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AchievementEditorSheet extends StatefulWidget {
  const _AchievementEditorSheet({this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_AchievementEditorSheet> createState() =>
      _AchievementEditorSheetState();
}

class _AchievementEditorSheetState extends State<_AchievementEditorSheet> {
  static const _metrics = <String, String>{
    'hike_started': 'Hike started',
    'hike_completed': 'Hike completed',
    'checklist_completed': 'Gear checklist completed',
    'check_in_completed': 'Safety check-in completed',
    'manual_pin_added': 'Location pinned',
    'hazard_report_approved': 'Hazard report approved',
    'team_hike_completed': 'Team hike completed',
    'community_post_created': 'Community post created',
    'distinct_trail_completed': 'Different trail completed',
    'malaysia_state_hiked': 'Malaysian state visited by hike',
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _conditionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _pointsController;
  late final TextEditingController _targetController;
  late final TextEditingController _sortController;
  late String _rewardType;
  late String _metricKey;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    _titleController = TextEditingController(
      text: _stringFrom(initial['title']),
    );
    _conditionController = TextEditingController(
      text: _stringFrom(initial['condition']),
    );
    _categoryController = TextEditingController(
      text: _stringFrom(initial['category']).isEmpty
          ? 'Hiking'
          : _stringFrom(initial['category']),
    );
    _pointsController = TextEditingController(
      text:
          (_intFrom(initial['rewardPoints']) == 0
                  ? 100
                  : _intFrom(initial['rewardPoints']))
              .toString(),
    );
    _targetController = TextEditingController(
      text:
          (_intFrom(initial['targetCount']) == 0
                  ? 1
                  : _intFrom(initial['targetCount']))
              .toString(),
    );
    _sortController = TextEditingController(
      text:
          (_intFrom(initial['sortOrder']) == 0
                  ? 100
                  : _intFrom(initial['sortOrder']))
              .toString(),
    );
    _rewardType = _stringFrom(initial['rewardType']) == 'cumulative'
        ? 'cumulative'
        : 'one_time';
    final initialMetric = _stringFrom(initial['metricKey']);
    _metricKey = _metrics.containsKey(initialMetric)
        ? initialMetric
        : _metrics.keys.first;
    _isActive = initial['isActive'] != false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _conditionController.dispose();
    _categoryController.dispose();
    _pointsController.dispose();
    _targetController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'title': _titleController.text.trim(),
      'condition': _conditionController.text.trim(),
      'category': _categoryController.text.trim(),
      'iconName': _stringFrom(widget.initial?['iconName']).isEmpty
          ? 'emoji_events'
          : _stringFrom(widget.initial?['iconName']),
      'rewardPoints': int.parse(_pointsController.text),
      'rewardType': _rewardType,
      'metricKey': _metricKey,
      'targetCount': _rewardType == 'one_time'
          ? 1
          : int.parse(_targetController.text),
      'sortOrder': int.parse(_sortController.text),
      'accentColorValue': _intFrom(widget.initial?['accentColorValue']) == 0
          ? 0xFF34A853
          : _intFrom(widget.initial?['accentColorValue']),
      'isActive': _isActive,
    });
  }

  String? _positiveIntegerValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? 'Enter a positive number.' : null;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _InsetGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.initial == null
                        ? 'Add achievement'
                        : 'Edit achievement',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _AdminColors.textFor(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter an achievement title.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _conditionController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'User-facing requirement',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Describe how this is earned.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _rewardType,
                    decoration: const InputDecoration(labelText: 'Reward type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'one_time',
                        child: Text('One-time reward'),
                      ),
                      DropdownMenuItem(
                        value: 'cumulative',
                        child: Text('Accumulation based'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _rewardType = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _metricKey,
                    decoration: const InputDecoration(
                      labelText: 'Tracked activity',
                    ),
                    items: _metrics.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _metricKey = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pointsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Reward points',
                          ),
                          validator: _positiveIntegerValidator,
                        ),
                      ),
                      if (_rewardType == 'cumulative') ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _targetController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Target count',
                            ),
                            validator: _positiveIntegerValidator,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sort order'),
                    validator: _positiveIntegerValidator,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    subtitle: const Text(
                      'Inactive achievements remain in historical records but cannot progress.',
                    ),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save achievement'),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isSaving ? null : onApprove,
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                onPressed: isSaving ? null : onReject,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Reject'),
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
  const _AdminNotice({required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            (isError
                    ? _AdminColors.redFor(context)
                    : _AdminColors.secondaryTextFor(context))
                .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: (isError
                ? _AdminColors.redFor(context)
                : _AdminColors.secondaryTextFor(context)),
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
  Widget build(BuildContext context) =>
      AdminEmptyState(title: 'Nothing to show', message: message);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: _AdminColors.secondaryTextFor(context),
        fontSize: 16,
        fontWeight: FontWeight.w700,
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

class _AdminStatusPill extends StatelessWidget {
  const _AdminStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color == _AdminColors.green
        ? _AdminColors.greenFor(context)
        : color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: effectiveColor,
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
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _AdminColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _AdminColors.separatorFor(context)),
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
    required this.runtimeData,
    required this.isLoading,
    required this.onSelectFirestore,
    required this.onSelectLocal,
    required this.onSelectRuntime,
  });

  final _DebugSection? selectedSection;
  final List<_FirestoreCollection> firestoreData;
  final Map<String, List<Map<String, dynamic>>> localDbData;
  final Map<String, Map<String, Object?>> runtimeData;
  final bool isLoading;
  final VoidCallback onSelectFirestore;
  final VoidCallback onSelectLocal;
  final VoidCallback onSelectRuntime;

  @override
  Widget build(BuildContext context) {
    if (selectedSection == null) {
      return _DebugSectionPicker(
        onSelectFirestore: onSelectFirestore,
        onSelectLocal: onSelectLocal,
        onSelectRuntime: onSelectRuntime,
      );
    }

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: HikerCircleLoadingView(
          message: 'Loading diagnostic records…',
          detail: 'Preparing the selected app data.',
          compact: true,
        ),
      );
    }

    if (selectedSection == _DebugSection.firestore) {
      return _FirestoreDebugView(data: firestoreData);
    }

    if (selectedSection == _DebugSection.local) {
      return _LocalDbDebugView(data: localDbData);
    }

    return _RuntimeDebugView(data: runtimeData);
  }
}

class _DebugSectionPicker extends StatelessWidget {
  const _DebugSectionPicker({
    required this.onSelectFirestore,
    required this.onSelectLocal,
    required this.onSelectRuntime,
  });

  final VoidCallback onSelectFirestore;
  final VoidCallback onSelectLocal;
  final VoidCallback onSelectRuntime;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        _SectionTitle(label: 'All Debug Data Sources'),
        const SizedBox(height: 8),
        const _DebugSourceNotice(
          title: 'Inspect app data',
          message:
              'Choose a source to inspect its current records. These views are read-only and available to administrators.',
          icon: Icons.visibility_rounded,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Cloud Firestore',
          subtitle:
              'Persistent shared cloud documents, including known nested subcollections.',
          metric: 'Persistent cloud',
          detail: 'Survives sign-out, app restarts, and device changes',
          icon: Icons.cloud_rounded,
          onTap: onSelectFirestore,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Local SQLite Database',
          subtitle:
              'Every application table discovered from the device database schema.',
          metric: 'Persistent device',
          detail: 'Survives app restarts on this device',
          icon: Icons.storage_rounded,
          onTap: onSelectLocal,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Runtime & Temporary State',
          subtitle:
              'Current session, active hike, timers, loaded lists, settings, service snapshots, and memory caches.',
          metric: 'Temporary memory',
          detail: 'Usually cleared when widgets close or the app process exits',
          icon: Icons.memory_rounded,
          onTap: onSelectRuntime,
        ),
      ],
    );
  }
}

class _DebugSourceNotice extends StatelessWidget {
  const _DebugSourceNotice({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AdminColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AdminColors.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _AdminColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _AdminColors.textFor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AdminColors.secondaryTextFor(context),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirestoreDebugView extends StatelessWidget {
  const _FirestoreDebugView({required this.data});

  final List<_FirestoreCollection> data;

  @override
  Widget build(BuildContext context) {
    final populated = data.where((c) => c.documents.isNotEmpty).length;
    final totalDocuments = data.fold<int>(
      0,
      (total, c) => total + c.documents.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DebugSourceNotice(
          title: 'Persistent cloud data',
          message:
              'Firebase Firestore documents are shared across devices. Each collection query is capped at 50 documents for this read-only preview.',
          icon: Icons.cloud_done_rounded,
        ),
        const SizedBox(height: 12),
        _SectionTitle(
          label:
              '$populated/${data.length} collections / $totalDocuments documents',
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                for (
                  var docIndex = 0;
                  docIndex < collection.documents.length;
                  docIndex++
                ) ...[
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

    if (_value is Map) {
      final map = Map<Object?, Object?>.from(_value);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _key,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AdminColors.secondaryTextFor(context),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          if (map.isEmpty)
            Text(
              '{}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _AdminColors.textFor(context),
                letterSpacing: 0,
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _AdminColors.greenSoftFor(
                  context,
                ).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                children: [
                  for (final entry in map.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: _KeyValueRow(
                        key_: entry.key.toString(),
                        value: entry.value,
                      ),
                    ),
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
    final populated = data.entries.where((e) => e.value.isNotEmpty).length;
    final totalRows = data.entries.fold<int>(
      0,
      (total, e) => total + e.value.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DebugSourceNotice(
          title: 'Persistent on-device data',
          message:
              'Tables are discovered directly from SQLite metadata, so current and future app tables are included automatically. This data is local to this device.',
          icon: Icons.phone_android_rounded,
        ),
        const SizedBox(height: 12),
        _SectionTitle(
          label: '$populated/${data.length} tables / $totalRows rows',
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

class _RuntimeDebugView extends StatelessWidget {
  const _RuntimeDebugView({required this.data});

  final Map<String, Map<String, Object?>> data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DebugSourceNotice(
          title: 'Temporary app-scoped state',
          message:
              'This is a live snapshot of centralized runtime state. It is separate from Firestore and SQLite and may disappear when a screen closes or the app process exits.',
          icon: Icons.memory_rounded,
        ),
        const SizedBox(height: 12),
        _SectionTitle(label: '${data.length} runtime state groups'),
        const SizedBox(height: 8),
        if (data.isEmpty)
          const _EmptyState(message: 'No runtime state snapshot loaded.')
        else
          _InsetGroup(
            child: Column(
              children: [
                for (var index = 0; index < data.entries.length; index++) ...[
                  _RuntimeStateCard(
                    name: data.entries.elementAt(index).key,
                    data: data.entries.elementAt(index).value,
                  ),
                  if (index != data.entries.length - 1)
                    const _HorizontalSeparator(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RuntimeStateCard extends StatefulWidget {
  const _RuntimeStateCard({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;

  @override
  State<_RuntimeStateCard> createState() => _RuntimeStateCardState();
}

class _RuntimeStateCardState extends State<_RuntimeStateCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.memory_rounded,
                    size: 20,
                    color: _AdminColors.orangeFor(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _AdminColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  _AdminStatusPill(
                    label: '${widget.data.length}',
                    color: _AdminColors.orangeFor(context),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                _DocCard(index: 0, data: widget.data),
              ],
            ],
          ),
        ),
      ),
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
        onTap: widget.rows.isEmpty
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                for (
                  var rowIndex = 0;
                  rowIndex < widget.rows.length;
                  rowIndex++
                ) ...[
                  _DocCard(index: rowIndex, data: widget.rows[rowIndex]),
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

int _intFrom(Object? value) {
  return value is num && value.isFinite
      ? value.toInt()
      : int.tryParse('$value') ?? 0;
}

abstract final class _AdminColors {
  static const Color green = Color(0xFF3C8964);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color red = Color(0xFFE11D48);
  static const Color orange = Color(0xFFF59E0B);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      AdminUi.background(context);

  static Color surfaceFor(BuildContext context) => AdminUi.surface(context);

  static Color greenFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF83C9A4) : green;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) => AdminUi.border(context);

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;

  static Color orangeFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFBBF24) : orange;
}
