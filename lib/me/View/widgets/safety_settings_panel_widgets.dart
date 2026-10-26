part of '../../safety_settings_panel_feature.dart';

/// Displays the safety settings panel.
class SafetySettingsPanel extends StatelessWidget {
  /// Creates safety settings panel.
  const SafetySettingsPanel({super.key, this.settings, this.intervals});
  final AppSettingsController? settings;
  final LocationUpdateIntervalController? intervals;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final prefs = settings ?? AppSettingsController.instance;
    final cadence = intervals ?? LocationUpdateIntervalController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, cadence]),
      builder: (context, _) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FallSensitivitySetting(
                value: prefs.fallSensorSensitivity,
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
              const Divider(height: 28),
              PathDeviationDistanceSetting(
                value: prefs.pathDeviationDistanceMeters,
                onChanged: prefs.setPathDeviationDistanceMeters,
              ),
              const Divider(height: 28),
              FootprintIntervalSetting(
                value: cadence.preferredInterval,
                onChanged: (value) => unawaited(
                  cadence
                      .setInterval(value)
                      .then((saved) {
                        if (!saved) throw StateError('No signed-in hiker');
                      })
                      .catchError((Object _) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Unable to save the footprint interval. Try again.',
                              ),
                            ),
                          );
                        }
                      }),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.vibration_rounded),
                title: const Text('Haptic safety feedback'),
                subtitle: const Text(
                  'Use vibrations for pins and SOS countdown actions.',
                ),
                value: prefs.hapticSafetyFeedbackEnabled,
                onChanged: prefs.setHapticSafetyFeedbackEnabled,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.battery_alert_rounded),
                title: const Text('Low battery safety warnings'),
                subtitle: const Text('Warn before a hike when charge is low.'),
                value: prefs.lowBatterySafetyWarningEnabled,
                onChanged: prefs.setLowBatterySafetyWarningEnabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
