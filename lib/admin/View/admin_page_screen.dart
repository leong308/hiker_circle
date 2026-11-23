part of '../admin_page_feature.dart';

/// Defines the admin section choices.
enum AdminSection { overview, hazards, users, tools }

/// Defines the debug section choices.
enum _DebugSection { firestore, local, runtime }

/// Displays the admin page.
class AdminPage extends StatefulWidget {
  /// Creates admin page.
  const AdminPage({
    super.key,
    required this.session,
    this.hikerCircleRepository,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
    this.runtimeDebugData = const {},
    this.initialSection = AdminSection.overview,
    this.onExit,
    this.exitTooltip = 'Back',
  });

  final AppSession session;
  final HikerCircleFirebaseRepository? hikerCircleRepository;
  final FirebaseBootstrapResult firebaseBootstrapResult;
  final Map<String, Object?> runtimeDebugData;
  final AdminSection initialSection;
  final VoidCallback? onExit;
  final String exitTooltip;

  /// Creates the presentation state for this widget.
  @override
  State<AdminPage> createState() => _AdminPageState();
}

/// Manages the admin page presentation and lifecycle.
class _AdminPageState extends State<AdminPage> {
  /// Returns admin data revision.
  int get _adminDataRevision => _screenModel.stateAdminDataRevision;

  /// Updates admin data revision.
  set _adminDataRevision(int value) =>
      _screenModel.stateAdminDataRevision = value;

  late final _AdminPageStateViewModel _screenModel;

  /// Returns is saving.
  bool get _isSaving => _screenModel.stateIsSaving;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  late final HikerCircleFirebaseRepository _repository =
      widget.hikerCircleRepository ??
      HikerCircleFirebaseRepository(
        firebaseBootstrapResult: widget.firebaseBootstrapResult,
      );

  late final AdminSafetyViewModel _safetyModel;
  late final AdminUsersViewModel _usersModel;
  bool _isLoading = false;

  /// Returns error message.
  String? get _errorMessage => _screenModel.commandErrorMessage;
  late AdminSection _selectedSection;

  /// Drops superadmin-only controls when the shell receives a new account role.
  @override
  void didUpdateWidget(covariant AdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _usersModel.updateSession(widget.session);
  }

  final _pageScroll = ScrollController();
  String _search = '';
  Map<String, dynamic>? _analytics;
  String? _analyticsError;
  bool _analyticsLoading = false;
  int _analyticsRevision = 0;

  /// Loads analytics.
  Future<void> _loadAnalytics({bool forceRefresh = false}) async {
    if (!widget.session.isAdmin) return;
    final revision = ++_analyticsRevision;
    setState(() {
      _analyticsLoading = true;
      _analyticsError = null;
    });
    try {
      final data = await _AdminPageDataActions.loadAdminDashboardAnalytics(
        _repository,
      )(session: widget.session, forceRefresh: forceRefresh);
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

  /// Selects section.
  void _selectSection(AdminSection section) {
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
    _safetyModel.setQuery('');
    if (section == AdminSection.hazards &&
        !_safetyModel.hasData &&
        !_safetyModel.loading) {
      unawaited(_safetyModel.refresh());
    }
    setState(() {
      _selectedSection = section;
      _search = '';
    });
  }

  bool _debugMode = false;
  // Retains diagnostics for explicitly enabled builds while hiding its card by default.
  static const _showDataDiagnosticsCard = bool.fromEnvironment(
    'HC_SHOW_DATA_DIAGNOSTICS',
  );
  _DebugSection? _selectedDebugSection;
  Map<String, List<Map<String, dynamic>>> _localDbData = const {};
  List<_FirestoreCollection> _firestoreData = const [];
  Map<String, Map<String, Object?>> _runtimeData = const {};
  bool _isDebugLoading = false;
  String? _debugError;

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _pageScroll.dispose();
    _safetyModel.removeListener(_renderScreenModel);
    _safetyModel.dispose();
    _usersModel.dispose();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _AdminPageStateViewModel(
      effectLoadAdminData: _loadAdminData,
      effectShowSnack: _showSnack,
    )..addListener(_renderScreenModel);

    _safetyModel = AdminSafetyViewModel(
      repository: FirebaseAdminSafetyRepository(_repository, widget.session),
    )..addListener(_renderScreenModel);
    _usersModel = AdminUsersViewModel(
      session: widget.session,
      repository: AdminUsersRepository(),
    );
    _selectedSection = widget.initialSection;
    if (widget.session.isAdmin) unawaited(_loadAdminData());
  }

  /// Publish each response independently so one unavailable collection does not
  /// hide the rest of the workspace. Older refreshes cannot overwrite new data.
  Future<void> _loadAdminData() async {
    if (!widget.session.isAdmin) return;
    final revision = ++_adminDataRevision;
    setState(() {
      _isLoading = true;
    });
    await Future.wait<void>([
      _loadAnalytics(forceRefresh: _analytics != null),
      if (_selectedSection == AdminSection.hazards || _safetyModel.hasData)
        _safetyModel.refresh(),
      _usersModel.refresh(),
    ]);
    if (mounted && revision == _adminDataRevision) {
      setState(() => _isLoading = false);
    }
  }

  /// Shows snack.
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

  /// Opens the existing protected trail review page from dashboard findings.
  Future<void> _openTrailSubmissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordedTrailRequestsPage(
          session: widget.session,
          repository: _repository,
        ),
      ),
    );
    if (mounted) unawaited(_loadAnalytics(forceRefresh: true));
  }

  /// Opens diagnostics.
  void _openDiagnostics() {
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
    setState(() {
      _debugMode = true;
      _selectedDebugSection = null;
      _debugError = null;
    });
  }

  /// Loads firestore debug data.
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
          // Query sample Firestore documents
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
          // Query sample documents by collection group
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
      final data = await _AdminPageDataActions.dumpAllTables(
        _repository.localDatabase,
      )();
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

  /// Loads runtime debug data.
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
          'loadedHazardReports': _safetyModel.reports
              .map((report) => report.data)
              .toList(),
          'loadedUsers': _usersModel.users.length,
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

  /// Computes exit debug mode.
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

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    if (!widget.session.isAdmin) {
      return const _AdminLockedState();
    }

    final content = switch (_selectedSection) {
      AdminSection.overview => AdminAnalyticsDashboard(
        data: _analytics,
        loading: _analyticsLoading,
        error: _analyticsError,
        onRetry: () => unawaited(_loadAnalytics(forceRefresh: true)),
        onTools: () => _selectSection(AdminSection.tools),
        onTrailRequests: _openTrailSubmissions,
        onFeedback: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const FeedbackInboxPage(admin: true),
          ),
        ),
        onSafety: () => _selectSection(AdminSection.hazards),
      ),
      AdminSection.hazards => AdminSafetySection(model: _safetyModel),
      AdminSection.users => AdminUsersSection(model: _usersModel),
      AdminSection.tools => _AdminTileGrid(
        children: [
          _AdminDashboardCard(
            title: 'Hiker feedback',
            icon: Icons.feedback_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FeedbackInboxPage(admin: true),
              ),
            ),
          ),
          _AdminDashboardCard(
            title: 'Button Debugging',
            icon: Icons.bluetooth_searching_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ButtonDebuggingPage(session: widget.session),
              ),
            ),
          ),
          if (_showDataDiagnosticsCard)
            _AdminDashboardCard(
              title: 'Data diagnostics',
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
                            title: 'Dashboard',
                            isLoading: _isLoading,
                            onRefresh: () => unawaited(_loadAdminData()),
                            onBack:
                                widget.onExit ??
                                (_selectedSection == AdminSection.overview
                                    ? null
                                    : () => _selectSection(
                                        AdminSection.overview,
                                      )),
                            backTooltip: widget.onExit != null
                                ? widget.exitTooltip
                                : 'Back to admin dashboard',
                          ),
                        if (!_debugMode) ...[
                          const SizedBox(height: 16),
                          _AdminNavigation(
                            selected: _selectedSection,
                            onSelect: _selectSection,
                          ),
                          if (_selectedSection == AdminSection.hazards) ...[
                            const SizedBox(height: 18),
                            TextField(
                              key: ValueKey(
                                'admin-search-${_selectedSection.name}',
                              ),
                              onChanged: (value) {
                                setState(
                                  () => _search = value.trim().toLowerCase(),
                                );
                                if (_selectedSection == AdminSection.hazards) {
                                  _safetyModel.setQuery(value);
                                }
                              },
                              decoration: InputDecoration(
                                hintText:
                                    'Search ${switch (_selectedSection) {
                                      AdminSection.hazards => 'reports',
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
          if (_isDebugLoading)
            HikerCircleLoadingToastOverlay(
              message: 'Loading diagnostics…',
              detail: 'Fetching the latest information securely.',
              timeout: const Duration(seconds: 30),
              onTimeout: () {
                if (mounted) {
                  setState(() {
                    _isDebugLoading = false;
                    _debugError = 'The request timed out. Please try again.';
                  });
                }
              },
            ),
        ],
      ),
    );
  }
}

/// Displays the admin locked state.
class _AdminLockedState extends StatelessWidget {
  /// Creates admin locked state.
  const _AdminLockedState();

  /// Builds this widget from its current presentation state.
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

/// Displays the admin navigation.
class _AdminNavigation extends StatefulWidget {
  /// Creates admin navigation.
  const _AdminNavigation({required this.selected, required this.onSelect});
  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  /// Creates the presentation state for this widget.
  @override
  State<_AdminNavigation> createState() => _AdminNavigationState();
}

/// Manages the admin navigation presentation and lifecycle.
class _AdminNavigationState extends State<_AdminNavigation> {
  final _scroll = ScrollController();
  final _keys = {
    for (final section in AdminSection.values) section: GlobalKey(),
  };

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  /// Computes reveal selected.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final selectedContext = _keys[widget.selected]?.currentContext;
      if (selectedContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            selectedContext,
            alignment: .5,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
          ),
        );
      }
    });
  }

  /// Updates bindings when the parent changes this widget.
  @override
  void didUpdateWidget(covariant _AdminNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _revealSelected();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth >= 380 &&
          MediaQuery.textScalerOf(context).scale(12) <= 17;
      return AdminPanel(
        padding: const EdgeInsets.all(5),
        child: compact
            ? Row(
                children: [
                  for (final section in AdminSection.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _tab(section, compact: true),
                      ),
                    ),
                ],
              )
            : SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final section in AdminSection.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _tab(section, compact: false),
                      ),
                  ],
                ),
              ),
      );
    },
  );

  /// Computes tab.
  Widget _tab(AdminSection section, {required bool compact}) {
    final selected = widget.selected == section;
    final color = selected ? AdminUi.green(context) : AdminUi.muted(context);
    final icon = Icon(
      switch (section) {
        AdminSection.overview => Icons.grid_view_rounded,
        AdminSection.hazards => Icons.shield_outlined,
        AdminSection.users => Icons.people_outline_rounded,
        AdminSection.tools => Icons.tune_rounded,
      },
      size: 19,
      color: color,
    );
    final label = Text(
      switch (section) {
        AdminSection.overview => 'Overview',
        AdminSection.hazards => 'Safety',
        AdminSection.users => 'Users',
        AdminSection.tools => 'Tools',
      },
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: compact ? 10.5 : 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: color,
      ),
    );
    return Semantics(
      key: _keys[section],
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? AdminUi.green(context).withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('admin-nav-${section.name}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onSelect(section),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 2 : 12,
              vertical: compact ? 10 : 13,
            ),
            child: compact
                ? Column(children: [icon, const SizedBox(height: 5), label])
                : Row(children: [icon, const SizedBox(width: 7), label]),
          ),
        ),
      ),
    );
  }
}

/// Natural-height tiles avoid clipping when system text size is increased.
class _AdminTileGrid extends StatelessWidget {
  /// Creates admin tile grid.
  const _AdminTileGrid({required this.children});
  final List<Widget> children;

  /// Builds this widget from its current presentation state.
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

/// Displays the admin notice.
class _AdminNotice extends StatelessWidget {
  /// Creates admin notice.
  const _AdminNotice({required this.message});

  final String message;

  /// Builds this widget from its current presentation state.
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

/// Displays the inset group.
class _InsetGroup extends StatelessWidget {
  /// Creates inset group.
  const _InsetGroup({required this.child});

  final Widget child;

  /// Builds this widget from its current presentation state.
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

/// Displays the horizontal separator.
class _HorizontalSeparator extends StatelessWidget {
  /// Creates horizontal separator.
  const _HorizontalSeparator();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _AdminColors.separatorFor(context),
    );
  }
}

/// Displays the debug content.
class _DebugContent extends StatelessWidget {
  /// Creates debug content.
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

  /// Builds this widget from its current presentation state.
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

/// Displays the debug section picker.
class _DebugSectionPicker extends StatelessWidget {
  /// Creates debug section picker.
  const _DebugSectionPicker({
    required this.onSelectFirestore,
    required this.onSelectLocal,
    required this.onSelectRuntime,
  });

  final VoidCallback onSelectFirestore;
  final VoidCallback onSelectLocal;
  final VoidCallback onSelectRuntime;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        SectionLabel(label: 'All Debug Data Sources'),
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
          icon: Icons.cloud_rounded,
          onTap: onSelectFirestore,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Local SQLite Database',
          icon: Icons.storage_rounded,
          onTap: onSelectLocal,
        ),
        const SizedBox(height: 12),
        _AdminDashboardCard(
          title: 'Runtime & Temporary State',
          icon: Icons.memory_rounded,
          onTap: onSelectRuntime,
        ),
      ],
    );
  }
}

/// Displays the debug source notice.
class _DebugSourceNotice extends StatelessWidget {
  /// Creates debug source notice.
  const _DebugSourceNotice({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  /// Builds this widget from its current presentation state.
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

/// Displays the firestore debug view.
class _FirestoreDebugView extends StatelessWidget {
  /// Creates firestore debug view.
  const _FirestoreDebugView({required this.data});

  final List<_FirestoreCollection> data;

  /// Builds this widget from its current presentation state.
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
        SectionLabel(
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

/// Displays the local db debug view.
class _LocalDbDebugView extends StatelessWidget {
  /// Creates local db debug view.
  const _LocalDbDebugView({required this.data});

  final Map<String, List<Map<String, dynamic>>> data;

  /// Builds this widget from its current presentation state.
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
        SectionLabel(
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

/// Displays the runtime debug view.
class _RuntimeDebugView extends StatelessWidget {
  /// Creates runtime debug view.
  const _RuntimeDebugView({required this.data});

  final Map<String, Map<String, Object?>> data;

  /// Builds this widget from its current presentation state.
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
        SectionLabel(label: '${data.length} runtime state groups'),
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

/// Shares the existing dashboard palette across admin sections.
abstract final class _AdminColors {
  static const Color green = Color(0xFF3C8964);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color red = Color(0xFFE11D48);
  static const Color orange = Color(0xFFF59E0B);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      AdminUi.background(context);

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) => AdminUi.surface(context);

  /// Computes green for.
  static Color greenFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF83C9A4) : green;

  /// Computes green soft for.
  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) => AdminUi.border(context);

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes red for.
  static Color redFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B88) : red;

  /// Computes orange for.
  static Color orangeFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFBBF24) : orange;
}
