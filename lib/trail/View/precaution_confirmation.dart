// confirmHikePrecautions presents the trail's safety observations and records acknowledgement.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';
import '../Model/trail_precautions.dart';
import '../Model/precaution_check_service.dart';
import '../Model/trail_models.dart';
import 'weather_presentation.dart';

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

class HikePrecautionDialog extends StatelessWidget {
  const HikePrecautionDialog({super.key, required this.precautions});
  final Future<List<TrailPrecaution>> precautions;

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

Color _precautionColor(BuildContext context, int priority) {
  final theme = Theme.of(context);
  if (priority >= 3) return theme.colorScheme.error;
  if (priority == 2) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFFF0BF6A)
        : const Color(0xFF95620E);
  }
  return theme.colorScheme.primary;
}

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

class _PrecautionOverview extends StatefulWidget {
  const _PrecautionOverview({required this.cautions});
  final List<TrailPrecaution> cautions;

  @override
  State<_PrecautionOverview> createState() => _PrecautionOverviewState();
}

class _PrecautionOverviewState extends State<_PrecautionOverview>
    with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  bool _started = false;

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

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final cautions = widget.cautions;
    final priority = cautions.fold<int>(0, (p, c) => math.max(p, c.priority));
    final accent = _precautionColor(context, priority);
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                        height: 1.15,
                      ),
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
                        child: _PrecautionCard(
                          key: ValueKey('precaution-${cautions[i].id}'),
                          caution: cautions[i],
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

class _EmptyPrecautions extends StatelessWidget {
  const _EmptyPrecautions({required this.accent});
  final Color accent;

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

class _PrecautionEntrance extends StatelessWidget {
  const _PrecautionEntrance({
    required this.animation,
    required this.index,
    required this.child,
  });
  final Animation<double> animation;
  final int index;
  final Widget child;

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

class _PrecautionCard extends StatefulWidget {
  const _PrecautionCard({super.key, required this.caution});
  final TrailPrecaution caution;

  @override
  State<_PrecautionCard> createState() => _PrecautionCardState();
}

class _PrecautionCardState extends State<_PrecautionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final caution = widget.caution;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final accent = _precautionColor(context, caution.priority);
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      precautionIcon(caution),
                      color: accent,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shortTitle(caution),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          caution.priority >= 3
                              ? 'Important'
                              : caution.priority == 2
                              ? 'Caution'
                              : 'Prepare',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    children: [
                      AnimatedRotation(
                        turns: _expanded ? .5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 19,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _expanded ? 'Less' : 'Details',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (caution.quickFacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final fact in caution.quickFacts)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          fact,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 9),
              Text(
                caution.quickAction ?? caution.message,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 1, color: scheme.outlineVariant),
                            const SizedBox(height: 10),
                            Text(
                              caution.title,
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              caution.message,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
