import '../Model/route_gear_assessment.dart';
import '../../trail/Model/trail_models.dart';
import '../Model/hike_weather_briefing.dart';
import '../../core/widgets/page_header_style.dart';
import 'trail_gear_checklist.dart';
import 'package:flutter/material.dart';
import '../Model/hike_session_models.dart';

/// Full-page final pack and safety review before a session can start.
class FinalPreparationReviewPage extends StatefulWidget {
  const FinalPreparationReviewPage({
    super.key,
    required this.hike,
    required this.isHost,
    required this.canStart,
    this.plan,
    this.onPlanChanged,
    this.onCancel,
    this.loadRouteAnalysis,
    this.loadWeather,
    this.onReady,
    this.immediate = false,
    this.primaryActionLabel,
  });
  final UpcomingHike hike;
  final bool immediate;
  final String? primaryActionLabel;
  final ValueChanged<PlannedHike>? onReady;
  final Future<TrailWeather> Function()? loadWeather;
  final bool isHost, canStart;
  final PlannedHike? plan;
  final Future<void> Function(PlannedHike)? onPlanChanged;
  final Future<void> Function()? onCancel;
  final Future<RouteGearAssessment> Function(bool force)? loadRouteAnalysis;
  @override
  State<FinalPreparationReviewPage> createState() => _PreparationState();
}

class _PreparationState extends State<FinalPreparationReviewPage> {
  late PlannedHike? _plan = widget.plan;
  bool _busy = false;
  String? _error;
  bool _analyzing = false;
  bool _checkingWeather = false;
  String? _weatherNotice;
  @override
  void initState() {
    super.initState();
    _analyzeRoute();
    _refreshWeather();
  }

  Future<void> _refreshWeather() async {
    if (_plan == null || widget.loadWeather == null) return;
    setState(() => _checkingWeather = true);
    try {
      final weather = await widget.loadWeather!();
      if (!mounted) return;
      setState(() {
        _plan = _plan!
            .copyWith(trail: _plan!.trail.copyWith(weather: weather))
            .withGearProgress();
        final forecast = HikeWeatherBriefing.fromWeather(
          weather,
          _plan!.plannedStartTime,
          _plan!.expectedReturnTime,
        );
        _weatherNotice =
            !forecast.covered ||
                forecast.minTemperature == null ||
                forecast.peakRainChance == null
            ? 'Forecast coverage is incomplete. Cold and wet requirements may need extra checking.'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _weatherNotice =
              'Weather could not be refreshed. Check current conditions before departure.',
        );
      }
    } finally {
      if (mounted) setState(() => _checkingWeather = false);
    }
  }

  Future<void> _analyzeRoute({bool force = false}) async {
    if (_analyzing || widget.loadRouteAnalysis == null || _plan == null) return;
    setState(() => _analyzing = true);
    try {
      final result = await widget.loadRouteAnalysis!(force);
      if (mounted) {
        setState(
          () => _plan = _plan!
              .copyWith(gearAssessment: result)
              .withGearProgress(),
        );
      }
    } catch (_) {
      // The recommendation card retains its unavailable-data explanation.
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _saveGear(Set<String> items) async {
    final plan = _plan;
    if (plan == null || widget.onPlanChanged == null || _busy) return;
    final updated = plan
        .copyWith(
          completedChecklistItems: items,
          checklistCompleted: items.length,
          checklistTotal: GearChecklistCatalog.itemCount,
        )
        .withGearProgress();
    setState(() {
      _busy = true;
      _error = null;
      _plan = updated;
    });
    try {
      await widget.onPlanChanged!(updated);
      if (mounted) {
        setState(
          () => _plan = updated
              .copyWith(
                gearAssessment: _plan?.gearAssessment,
                trail: _plan?.trail,
              )
              .withGearProgress(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _plan = plan
              .copyWith(
                gearAssessment: _plan?.gearAssessment,
                trail: _plan?.trail,
              )
              .withGearProgress();
          _error = 'Could not save your checklist. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || widget.onCancel == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this hike?'),
        content: Text(
          'Remove ${widget.hike.trailName} from upcoming hikes for everyone joining. Your past hikes will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep hike'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel hike'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCancel!();
      if (mounted) Navigator.pop(context, 'cancelled');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(DateTime date) {
    final d = date.toLocal();
    return '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final hike = widget.hike, plan = _plan;
    final checking = _analyzing || _checkingWeather;
    final missing = plan?.missingRequiredGear ?? <String>{};
    final ready =
        plan != null &&
        missing.isEmpty &&
        !checking &&
        !_busy &&
        widget.canStart;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLow,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    PageHeaderAction(
                      tooltip: 'Back',
                      icon: Icons.arrow_back_rounded,
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      color: scheme.primary,
                      surface: scheme.surface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Final preparation review',
                        style: PageHeaderStyle.title(context, scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hike.trailName,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 26,
                            runSpacing: 12,
                            children: [
                              _schedule('Departure', _time(hike.departureTime)),
                              _schedule(
                                'Estimated finish',
                                _time(hike.expectedReturnTime),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${hike.distanceKm.toStringAsFixed(1)} km · ${plan?.trail.difficultyDisplayLabel ?? 'Difficulty not rated'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_weatherNotice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _weatherNotice!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                    if (plan != null)
                      TrailGearChecklist(
                        plan: plan,
                        analyzing: _analyzing,
                        onRetryAnalysis: () => _analyzeRoute(force: true),
                        busy: _busy,
                        onChanged: widget.onPlanChanged == null
                            ? null
                            : _saveGear,
                        safetyReadiness: _safetyReadiness(plan),
                      ),
                    if (plan == null)
                      const Text(
                        'The trail preparation could not be loaded. Please return and try again.',
                      ),
                    if (widget.isHost && widget.onCancel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: TextButton.icon(
                          onPressed: _busy ? null : _cancel,
                          icon: const Icon(Icons.event_busy_outlined),
                          label: const Text('Cancel upcoming hike'),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    Text(
                      checking
                          ? 'Checking route and forecast…'
                          : missing.isNotEmpty
                          ? '${missing.length} required item${missing.length == 1 ? '' : 's'} left · complete the marked tabs'
                          : widget.isHost
                          ? 'Required items ready. Start when you reach the trailhead.'
                          : 'Your pack is ready. The organizer starts the session.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: ready
                          ? () {
                              widget.onReady?.call(plan);
                              Navigator.pop(context, 'start');
                            }
                          : null,
                      icon: _busy || checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        _busy
                            ? 'Saving…'
                            : widget.primaryActionLabel != null
                            ? widget.primaryActionLabel!
                            : !widget.immediate && hike.isLocalPendingSync
                            ? 'Waiting for sync'
                            : !widget.isHost
                            ? 'Waiting for organizer'
                            : hike.participantCount > 1
                            ? 'Start team readiness'
                            : 'Start hike',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _safetyReadiness(PlannedHike plan) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    Widget card(IconData icon, String title, String subtitle) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 5),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          Icons.contact_phone_outlined,
          'Emergency contacts',
          plan.emergencyContactsSelected
              ? 'Registration contacts are available. No packing check is needed.'
              : 'Contacts are unavailable. Review your emergency contacts in SOS before departure.',
        ),
        card(
          Icons.battery_std_rounded,
          plan.hasKnownBatteryLevel
              ? 'Phone battery · ${plan.phoneBatteryLevel}%'
              : 'Phone battery unavailable',
          'Charge your phone and consider a power bank for longer hikes.',
        ),
        card(
          Icons.my_location_rounded,
          'Live location',
          plan.liveLocationConfigured
              ? 'Sharing is configured for this hike.'
              : 'Review your sharing preference in the hike safety settings.',
        ),
        card(
          Icons.cloud_outlined,
          'Weather and terrain',
          _checkingWeather || _analyzing
              ? 'Checking the conditions used for your pack.'
              : _weatherNotice ??
                    'Required items reflect available route and session forecast data. Check local conditions too.',
        ),
      ],
    );
  }

  Widget _schedule(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}
