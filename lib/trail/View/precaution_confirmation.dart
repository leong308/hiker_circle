// confirmHikePrecautions presents the trail's safety observations and records acknowledgement.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../Model/trail_precautions.dart';
import '../Model/precaution_check_service.dart';
import '../Model/trail_models.dart';
import '../../core/widgets/page_header_style.dart';
import 'trail_precaution_card.dart';

/// Return the hiker's explicit precaution acknowledgement to the caller's start/preparation flow.
Future<bool> confirmHikePrecautions(BuildContext context, Trail trail) async {
  final check = PrecautionCheckService.check(trail);
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => HikePrecautionDialog(precautions: check),
      ) ??
      false;
}

/// Displays the hike precaution dialog.
class HikePrecautionDialog extends StatelessWidget {
  /// Creates hike precaution dialog.
  const HikePrecautionDialog({super.key, required this.precautions});
  final Future<List<TrailPrecaution>> precautions;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: FutureBuilder<List<TrailPrecaution>>(
        future: precautions,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HikerCircleLoadingToast(
                  message: 'Checking your hike…',
                  detail: 'Latest weather and daylight',
                  compact: true,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Go back'),
                  ),
                ),
              ],
            );
          }
          return _PrecautionOverview(
            cautions:
                snapshot.data ??
                const [
                  TrailPrecaution(
                    'data',
                    3,
                    'Conditions could not be checked',
                    'Check local conditions and official warnings before continuing.',
                    quickAction: 'Check local conditions and official alerts.',
                    quickFacts: ['Forecast unavailable'],
                  ),
                ],
          );
        },
      ),
    ),
  );
}

/// Computes short title.
String _shortTitle(TrailPrecaution caution) => switch (caution.id) {
  'storm' => 'Thunderstorms',
  'rain' => caution.priority >= 3 ? 'Heavy rain' : 'Wet trail',
  'heat' => 'Heat strain',
  'cold' => 'Cold & wet conditions',
  'wind' => 'Strong winds',
  'uv' => 'Sun exposure',
  'visibility' => 'Low visibility',
  'data' => 'Check the forecast',
  'daylight-data' => 'Check daylight times',
  'duration' => 'Longer hike',
  'sunset' => 'Little daylight to spare',
  _ => caution.title,
};

/// Displays the precaution overview.
class _PrecautionOverview extends StatefulWidget {
  /// Creates precaution overview.
  const _PrecautionOverview({required this.cautions});
  final List<TrailPrecaution> cautions;

  /// Creates the presentation state for this widget.
  @override
  State<_PrecautionOverview> createState() => _PrecautionOverviewState();
}

/// Manages the precaution overview presentation and lifecycle.
class _PrecautionOverviewState extends State<_PrecautionOverview>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  bool _started = false;

  /// Refreshes presentation dependencies.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _entrance.forward();
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final cautions = widget.cautions;
    final priority = cautions.fold<int>(0, (p, c) => math.max(p, c.priority));
    final accent = precautionAccentColor(context, priority);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _entrance,
                builder: (_, child) => Transform.scale(
                  scale:
                      .88 +
                      .12 * Curves.easeOutCubic.transform(_entrance.value),
                  child: child,
                ),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: .18),
                        accent.withValues(alpha: .05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: accent.withValues(alpha: .15)),
                  ),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: accent,
                    size: 27,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Before you set off',
                      style: PageHeaderStyle.title(context, scheme.onSurface),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cautions.isEmpty
                          ? 'No forecast alerts found'
                          : '${cautions.length} ${cautions.length == 1 ? 'check' : 'checks'} for this hike',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cautions.isEmpty)
                  _EmptyPrecautions(accent: accent)
                else
                  for (var i = 0; i < cautions.length; i++)
                    _PrecautionEntrance(
                      animation: _entrance,
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TrailPrecautionCard(
                          key: ValueKey('precaution-${cautions[i].id}'),
                          caution: cautions[i],
                          title: _shortTitle(cautions[i]),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Forecast guidance · check official alerts & trail closures.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final back = TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Go back'),
                  );
                  final proceed = FilledButton.icon(
                    key: const ValueKey('confirm-hike-precautions'),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    label: const Text('Continue'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  );
                  if (constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [proceed, back],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: back),
                      const SizedBox(width: 10),
                      Expanded(child: proceed),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Displays the empty precautions.
class _EmptyPrecautions extends StatelessWidget {
  /// Creates empty precautions.
  const _EmptyPrecautions({required this.accent});
  final Color accent;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Icon(Icons.cloud_outlined, size: 36, color: accent),
        const SizedBox(height: 12),
        const Text(
          'Conditions can change. Check the trail locally.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

/// Displays the precaution entrance.
class _PrecautionEntrance extends StatelessWidget {
  /// Creates precaution entrance.
  const _PrecautionEntrance({
    required this.animation,
    required this.index,
    required this.child,
  });
  final Animation<double> animation;
  final int index;
  final Widget child;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (_, child) {
      final start = math.min(index, 7) * .06;
      final progress = Interval(
        start,
        start + .56,
        curve: Curves.easeOutCubic,
      ).transform(animation.value);
      return Opacity(
        opacity: progress,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * 12),
          child: child,
        ),
      );
    },
  );
}
