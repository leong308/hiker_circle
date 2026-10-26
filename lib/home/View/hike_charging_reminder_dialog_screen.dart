part of '../hike_charging_reminder_dialog_feature.dart';

/// Shows hike charging reminder.
Future<void> showHikeChargingReminder(
  BuildContext context, {
  required Future<int?> Function() loadBatteryLevel,
}) => showDialog<void>(
  context: context,
  routeSettings: const RouteSettings(name: 'hike-charging-reminder'),
  builder: (_) =>
      HikeChargingReminderDialog(loadBatteryLevel: loadBatteryLevel),
);

/// Reads the current device battery when opened, rather than a saved hike value.
class HikeChargingReminderDialog extends StatefulWidget {
  /// Creates hike charging reminder dialog.
  const HikeChargingReminderDialog({super.key, required this.loadBatteryLevel});

  final Future<int?> Function() loadBatteryLevel;

  /// Creates the presentation state for this widget.
  @override
  State<HikeChargingReminderDialog> createState() =>
      _HikeChargingReminderDialogState();
}

/// Manages the hike charging reminder dialog presentation and lifecycle.
class _HikeChargingReminderDialogState extends State<HikeChargingReminderDialog>
    with WidgetsBindingObserver {
  late final _HikeChargingReminderDialogStateViewModel _screenModel;

  /// Returns battery level.
  int? get _batteryLevel => _screenModel.stateBatteryLevel;

  /// Returns loading.
  bool get _loading => _screenModel.stateLoading;

  /// Rebuilds the view after its ViewModel changes.
  void _renderScreenModel() {
    if (mounted) setState(() {});
  }

  static const _green = Color(0xFF34A853);

  /// Initializes bindings and starts the screen lifecycle.
  @override
  void initState() {
    super.initState();
    _screenModel = _HikeChargingReminderDialogStateViewModel(
      readLoadBatteryLevel: () => widget.loadBatteryLevel,
    )..addListener(_renderScreenModel);

    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBattery());
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _screenModel.removeListener(_renderScreenModel);
    _screenModel.dispose();
    super.dispose();
  }

  /// Responds to foreground and background transitions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_refreshBattery());
    }
  }

  /// Delegates refresh battery to the ViewModel.
  Future<void> _refreshBattery() => _screenModel.commandRefreshBattery();

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF141C17) : Colors.white;
    final foreground = dark ? const Color(0xFFEAF4EE) : const Color(0xFF15251B);
    final secondary = dark ? const Color(0xFFA8B8AE) : const Color(0xFF66736B);
    final accent = dark ? const Color(0xFF7AD99A) : _green;
    final level = _batteryLevel;
    final message = level == 100
        ? 'Your phone is fully charged. Keep it topped up before you head out.'
        : 'Remember to charge your phone to 100% before your hike.';
    final media = MediaQuery.of(context);

    return Dialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: math.max(
            0,
            media.size.height -
                media.padding.vertical -
                media.viewInsets.vertical -
                48,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: dark ? 0.13 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bolt_rounded, color: accent, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Charge your phone',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 23,
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 245 ||
                      MediaQuery.textScalerOf(context).scale(16) > 25;
                  final current = _BatteryLevelCard(
                    label: 'Current battery',
                    value: _loading && level == null
                        ? 'Checking…'
                        : level == null
                        ? 'Unavailable'
                        : '$level%',
                    icon: level == null
                        ? Icons.battery_unknown_rounded
                        : level == 100
                        ? Icons.battery_full_rounded
                        : Icons.battery_std_rounded,
                    color: foreground,
                    secondary: secondary,
                    fill: dark
                        ? const Color(0xFF202C24)
                        : const Color(0xFFF2F5F3),
                  );
                  final goal = _BatteryLevelCard(
                    label: 'Before your hike',
                    value: '100%',
                    icon: Icons.battery_charging_full_rounded,
                    color: accent,
                    secondary: secondary,
                    fill: accent.withValues(alpha: dark ? 0.12 : 0.08),
                  );
                  final arrow = Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: stacked ? 0 : 8,
                      vertical: stacked ? 8 : 0,
                    ),
                    child: Icon(
                      stacked ? Icons.south_rounded : Icons.east_rounded,
                      color: secondary,
                      size: 22,
                      semanticLabel: 'Charge to',
                    ),
                  );
                  return stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [current, arrow, goal],
                        )
                      : Row(
                          children: [
                            Expanded(child: current),
                            arrow,
                            Expanded(child: goal),
                          ],
                        );
                },
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: level == null ? 0 : level / 100,
                  minHeight: 7,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.13),
                  semanticsLabel: level == null
                      ? 'Battery level unavailable'
                      : 'Current battery $level percent; target 100 percent',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
