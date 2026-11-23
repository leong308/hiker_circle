part of '../find_hike_page_feature.dart';

/// Shows upcoming hike popup.
Future<void> showUpcomingHikePopup(
  BuildContext context, {
  required UpcomingHike hike,
  required AppSession session,
  required HikerCircleFirebaseRepository repository,
  double? userLat,
  double? userLng,
  VoidCallback? onJoin,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        child: UpcomingHikeCard(
          hike: hike,
          userLat: userLat,
          userLng: userLng,
          session: session,
          repository: repository,
          onJoin: onJoin ?? () {},
          onDeleted: () {
            Navigator.of(context).pop();
            onJoin?.call();
          },
        ),
      ),
    ),
  );
}

/// Displays the find hike page.
class FindHikePage extends StatefulWidget {
  /// Creates find hike page.
  const FindHikePage({
    super.key,
    required this.session,
    required this.repository,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;

  /// Creates the presentation state for this widget.
  @override
  State<FindHikePage> createState() => _FindHikePageState();
}

/// Manages the find hike page presentation and lifecycle.
class _FindHikePageState extends State<FindHikePage>
    with WidgetsBindingObserver {
  late final _FindHikePageStateViewModel _screenModel;

  /// Returns hikes.
  List<UpcomingHike> get _hikes => _screenModel.stateHikes;

  /// Updates hikes.
  set _hikes(List<UpcomingHike> value) => _screenModel.stateHikes = value;

  /// Returns user lat.
  double? get _userLat => _screenModel.stateUserLat;

  /// Updates user lat.
  set _userLat(double? value) => _screenModel.stateUserLat = value;

  /// Returns user lng.
  double? get _userLng => _screenModel.stateUserLng;

  /// Updates user lng.
  set _userLng(double? value) => _screenModel.stateUserLng = value;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  bool _isLoading = true;

  String? _error;
  Timer? _refreshTimer;
  bool _isRefreshingSilently = false;

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _FindHikePageStateViewModel()
      ..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      // An empty or ordinary list must still learn about hikes created by
      // another account. The previous conditional made those lists stale.
      if (mounted) unawaited(_load(silent: true));
    });
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(silent: true));
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Loads.
  Future<void> _load({bool silent = false}) async {
    if (silent && _isRefreshingSilently) return;
    if (silent) {
      _isRefreshingSilently = true;
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      // Discovery must never wait on GPS. A slow or unresolved location
      // permission previously prevented this account from seeing a hike until
      // a later refresh happened to complete.
      if (!silent) unawaited(_refreshLocationAndResort());
      final hikes = await _FindHikePageDataActions.loadUpcomingHikes(
        widget.repository,
      )();
      if (!mounted) return;
      final owner = widget.session.phoneNumber;
      var hidden = const <String>{};
      if (hikes.any((h) => h.isParticipant(owner))) {
        try {
          hidden = await widget.repository.loadLocallyHiddenUpcomingHikeIds(
            owner,
          );
        } catch (error) {
          debugPrint('Upcoming hike cancellation cache unavailable: $error');
        }
      }
      if (!mounted) return;
      final userLat = _userLat;
      final userLng = _userLng;

      final now = DateTime.now();
      final active = hikes
          .where(
            (h) =>
                !(h.isParticipant(owner) && hidden.contains(h.id)) &&
                !now.isAfter(h.departureTime.add(const Duration(minutes: 15))),
          )
          .toList();

      List<UpcomingHike> sorted;
      if (userLat != null && userLng != null) {
        sorted = List.of(active)
          ..sort(
            (a, b) => a
                .distanceFrom(userLat, userLng)
                .compareTo(b.distanceFrom(userLat, userLng)),
          );
      } else {
        sorted = active;
      }
      setState(() {
        _hikes = sorted;
        _userLat = userLat;
        _userLng = userLng;
        if (!silent) _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _error = 'Unable to load upcoming hikes.';
        _isLoading = false;
      });
    } finally {
      _isRefreshingSilently = false;
    }
  }

  /// Delegates refresh location and resort to the ViewModel.
  Future<void> _refreshLocationAndResort() =>
      _screenModel.commandRefreshLocationAndResort();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.backgroundFor(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailHeader(
                      title: 'Find a Hike',
                      subtitle: _isLoading
                          ? 'Loading...'
                          : _error != null
                          ? 'Something went wrong'
                          : '${_hikes.length} hike${_hikes.length == 1 ? '' : 's'} near you',
                      onBack: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 16),
                    _buildBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds body.
  Widget _buildBody() {
    if (_isLoading) {
      return const _InsetGroup(
        child: HikerCircleLoadingView(
          message: 'Finding upcoming hikes…',
          detail: 'Checking nearby solo and group hikes.',
          compact: true,
          padding: EdgeInsets.all(14),
        ),
      );
    }
    if (_error != null) {
      return _InsetGroup(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AppColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_hikes.isEmpty) {
      return _EmptyState(
        message: 'No upcoming hikes near you yet.\nBe the first to start one!',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _hikes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final hike = _hikes[index];
        return UpcomingHikeCard(
          key: ValueKey(hike.id),
          hike: hike,
          userLat: _userLat,
          userLng: _userLng,
          session: widget.session,
          repository: widget.repository,
          onJoin: () => unawaited(_load(silent: true)),
          onDeleted: () => setState(
            () => _hikes = _hikes.where((h) => h.id != hike.id).toList(),
          ),
        );
      },
    );
  }
}

/// Displays the vibrating hike bell.
class _VibratingHikeBell extends StatelessWidget {
  /// Creates vibrating hike bell.
  const _VibratingHikeBell({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final wave = math.sin(animation.value * math.pi * 2);
        return Transform.translate(
          offset: Offset(wave * 1.8, 0),
          child: Transform.rotate(angle: wave * 0.09, child: child),
        );
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.86),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.34),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.notifications_active_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

/// Displays the glyph.
class _Glyph extends StatelessWidget {
  /// Creates glyph.
  const _Glyph({required this.icon});

  final IconData icon;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _AppColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
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
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _AppColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
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
      color: _AppColors.separatorFor(context),
    );
  }
}

/// Represents app colors.
abstract final class _AppColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color surface = Colors.white;
  static const Color green = Color(0xFF34A853);
  static const Color orange = Color(0xFFF59E0B);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chipBackground = Color(0xFFF2F2F7);

  /// Checks whether dark.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Computes background for.
  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  /// Computes surface for.
  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : surface;

  /// Computes separator for.
  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  /// Computes text for.
  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  /// Computes secondary text for.
  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  /// Computes chip background for.
  static Color chipBackgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF1B261F) : chipBackground;
}
