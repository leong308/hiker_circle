part of '../../safety_settings_panel_feature.dart';

/// Presents saved safety preferences as closed drawers and direct toggle cards.
class SafetySettingsPanel extends StatelessWidget {
  /// Uses the existing preference controllers without changing their persistence.
  const SafetySettingsPanel({
    super.key,
    this.settings,
    this.intervals,
    required this.onHapticFeedback,
  });
  final AppSettingsController? settings;
  final LocationUpdateIntervalController? intervals;
  final ValueChanged<bool> onHapticFeedback;

  /// Reports a failed cadence save without changing its existing save semantics.
  Future<void> _saveInterval(
    BuildContext context,
    LocationUpdateIntervalController cadence,
    Duration value,
  ) async {
    try {
      if (!await cadence.setInterval(value)) {
        throw StateError('No signed-in hiker');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save the footprint interval. Try again.'),
          ),
        );
      }
    }
  }

  /// Keeps all adjustable details collapsed until the user opens their card.
  @override
  Widget build(BuildContext context) {
    final prefs = settings ?? AppSettingsController.instance;
    final cadence = intervals ?? LocationUpdateIntervalController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, cadence]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsDisclosureCard(
            icon: const Icon(Icons.sensors_rounded),
            title: 'Fall sensor sensitivity',
            subtitle:
                '${FallDetectionSettings(sensorSensitivity: prefs.fallSensorSensitivity).sensitivityLabel} · ${prefs.fallSensorSensitivity.round()}/10',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FallSensitivitySetting(
                  value: prefs.fallSensorSensitivity,
                  showHeading: false,
                  showImpactThreshold: true,
                  onChanged: prefs.setFallSensorSensitivity,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showFallDetectionTest(
                      context,
                      sensitivity: prefs.fallSensorSensitivity,
                    ),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Fall detection test'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SettingsDisclosureCard(
            icon: const Icon(Icons.alt_route_rounded),
            title: 'Path deviation alert',
            subtitle:
                'Maximum deviation · ${prefs.pathDeviationDistanceMeters} m',
            child: PathDeviationDistanceSetting(
              value: prefs.pathDeviationDistanceMeters,
              onChanged: prefs.setPathDeviationDistanceMeters,
            ),
          ),
          const SizedBox(height: 10),
          SettingsDisclosureCard(
            icon: const FootprintIcon(),
            title: 'Footprint record interval',
            subtitle: LocationUpdateInterval.label(cadence.preferredInterval),
            child: FootprintIntervalSetting(
              value: cadence.preferredInterval,
              onChanged: (value) =>
                  unawaited(_saveInterval(context, cadence, value)),
            ),
          ),
          const SizedBox(height: 10),
          SettingsToggleCard(
            icon: Icons.vibration_rounded,
            title: 'Haptic safety feedback',
            subtitle: 'Use vibrations for safety alerts and SOS countdowns.',
            value: prefs.hapticSafetyFeedbackEnabled,
            onChanged: onHapticFeedback,
          ),
          const SizedBox(height: 10),
          SettingsToggleCard(
            icon: Icons.battery_alert_rounded,
            title: 'Low battery safety warnings',
            subtitle: 'Warn before a hike when charge is low.',
            value: prefs.lowBatterySafetyWarningEnabled,
            onChanged: prefs.setLowBatterySafetyWarningEnabled,
          ),
        ],
      ),
    );
  }
}
