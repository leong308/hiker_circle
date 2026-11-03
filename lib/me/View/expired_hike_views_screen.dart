part of '../expired_hike_views_feature.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Computes expired hike date.
String expiredHikeDate(DateTime value) {
  final d = value.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Computes expired hike month.
String expiredHikeMonth(DateTime value) {
  final d = value.toLocal();
  return '${_months[d.month - 1]} ${d.year}';
}

/// Computes name.
String _name(UpcomingHike hike) =>
    hike.trailName.trim().isEmpty ? 'Scheduled hike' : hike.trailName;

/// Computes place.
String _place(UpcomingHike hike) => [
  hike.area,
  hike.state,
  hike.country,
].map((p) => p.trim()).where((p) => p.isNotEmpty).join(', ');

/// Computes type.
String _type(UpcomingHike hike) =>
    hike.hikeType == 'team' ? 'Group hike' : 'Solo hike';

/// Computes distance.
String _distance(UpcomingHike hike) => hike.distanceKm > 0
    ? '${hike.distanceKm.toStringAsFixed(1)} km'
    : 'Not saved';

/// Computes duration.
String _duration(UpcomingHike hike) {
  final minutes = hike.durationMinutes;
  if (minutes <= 0) return 'Not saved';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}m'}';
}

/// Computes background.
Color _background(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF0C120F)
    : const Color(0xFFF2F2F7);

/// Computes surface.
Color _surface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF141C17)
    : Colors.white;

/// Displays the expired hikes overview.
class ExpiredHikesOverview extends StatelessWidget {
  /// Creates expired hikes overview.
  const ExpiredHikesOverview({super.key});

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history_rounded,
            color: colors.onPrimaryContainer,
            size: 27,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plans kept for reference',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Hikes were not started 15 minutes after scheduled time.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: colors.onPrimaryContainer,
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

/// Displays the trail cover.
class _TrailCover extends StatelessWidget {
  /// Creates trail cover.
  const _TrailCover({required this.hike});
  final UpcomingHike hike;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final images = hike.draft?.trail.coverImageUrls ?? const <String>[];

    /// Computes fallback.
    Widget fallback() => Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      alignment: Alignment.center,
      child: Icon(
        Icons.landscape_rounded,
        size: 33,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: SizedBox(
        width: 66,
        height: 84,
        child: images.isEmpty
            ? fallback()
            : CachedTrailImage(
                imageUrl: images.first,
                width: 66,
                height: 84,
                fit: BoxFit.cover,
                semanticLabel: '${_name(hike)} trail cover',
                fallbackBuilder: (_) => fallback(),
              ),
      ),
    );
  }
}

/// Displays the expired hike detail page.
class ExpiredHikeDetailPage extends StatefulWidget {
  /// Creates expired hike detail page.
  const ExpiredHikeDetailPage({
    super.key,
    required this.hike,
    this.onReschedule,
  });
  final UpcomingHike hike;
  final Future<void> Function(UpcomingHike)? onReschedule;

  /// Creates the presentation state for this widget.
  @override
  State<ExpiredHikeDetailPage> createState() => _ExpiredHikeDetailPageState();
}

/// Manages the expired hike detail page presentation and lifecycle.
class _ExpiredHikeDetailPageState extends State<ExpiredHikeDetailPage> {
  bool _rescheduling = false;

  /// Computes reschedule.
  Future<void> _reschedule() async {
    if (_rescheduling || widget.onReschedule == null) return;
    setState(() => _rescheduling = true);
    try {
      await widget.onReschedule!(widget.hike);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is HikerCircleFirebaseRepositoryException
                  ? error.message
                  : 'Unable to reschedule this hike. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _rescheduling = false);
    }
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final hike = widget.hike;
    return Scaffold(
      backgroundColor: _background(context),
      appBar: PageHeaderAppBar(
        backgroundColor: _background(context),
        title: const Text('Expired hike'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PlanHero(
                    hike: hike,
                    onReschedule: widget.onReschedule == null
                        ? null
                        : _reschedule,
                    rescheduling: _rescheduling,
                  ),
                  const SizedBox(height: 14),
                  _PlanSection(
                    title: 'Schedule',
                    icon: Icons.calendar_month_outlined,
                    children: [
                      _PlanRow(
                        label: 'Planned departure',
                        value: expiredHikeDate(hike.departureTime),
                      ),
                      _PlanRow(
                        label: hike.isCancelledForHistory
                            ? 'Removed on'
                            : 'Start window closed',
                        value: expiredHikeDate(
                          hike.isCancelledForHistory
                              ? hike.deletedAt ?? hike.createdAt
                              : hike.visibleUntil,
                        ),
                        emphasized: true,
                      ),
                      _PlanRow(
                        label: 'Expected return',
                        value: expiredHikeDate(hike.expectedReturnTime),
                      ),
                    ],
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

/// Displays the plan hero.
class _PlanHero extends StatelessWidget {
  /// Creates plan hero.
  const _PlanHero({
    required this.hike,
    this.onReschedule,
    required this.rescheduling,
  });
  final UpcomingHike hike;
  final VoidCallback? onReschedule;
  final bool rescheduling;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      gradient: const LinearGradient(
        colors: [Color(0xFF143D29), Color(0xFF287348)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.event_busy_rounded,
              size: 20,
              color: Color(0xFFBFEBCB),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'EXPIRED PLAN',
                style: TextStyle(
                  color: Color(0xFFBFEBCB),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const ValueKey('expired-hike-reschedule'),
              onPressed: rescheduling ? null : onReschedule,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                backgroundColor: Colors.white.withValues(alpha: .13),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: rescheduling ? 0 : 1,
                    child: const Text(
                      'Reschedule',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (rescheduling)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Text(
          _name(hike),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        if (_place(hike).isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            _place(hike),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: .75),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 17),
        Text(
          'This hike was not started within ${UpcomingHike.visibleAfterDepartureGrace.inMinutes} minutes of departure.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: .9),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
