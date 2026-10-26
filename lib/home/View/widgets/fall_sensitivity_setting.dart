import '../../Model/fall_detection_test_policy.dart';
export '../../Model/fall_detection_test_policy.dart'
    show fallTestImpactThreshold;
import 'package:flutter/material.dart';
import '../../Model/hike_session_models.dart';

const lowBatterySafetyHint =
    'When battery drops below 30%, footprint record will change to 1 minute interval and fall sensitivity will back to 5/10 default scale.';

/// Displays the fall sensitivity setting.
class FallSensitivitySetting extends StatelessWidget {
  /// Creates fall sensitivity setting.
  const FallSensitivitySetting({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.showImpactThreshold = false,
  });
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final bool showImpactThreshold;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final settings = FallDetectionSettings(sensorSensitivity: value);
    final colors = Theme.of(context).colorScheme;
    final threshold =
        fallTestImpactThreshold(value) /
        FallDetectionSettings.gravityMetersPerSecondSquared;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.sensors_rounded, color: colors.primary),
          title: const Text('Fall sensor sensitivity'),
          subtitle: Text('${settings.sensitivityLabel} · ${value.round()}/10'),
        ),
        Slider(
          key: const ValueKey('fall-sensitivity-slider'),
          value: value.clamp(1, 10),
          min: 1,
          max: 10,
          divisions: 9,
          label: '${value.round()}/10',
          onChanged: enabled ? onChanged : null,
        ),
        if (showImpactThreshold) ...[
          Text(
            'Impact threshold: ${threshold.toStringAsFixed(2)} g',
            key: const ValueKey('fall-impact-threshold'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'Higher sensitivity checks smaller impacts and may cause more false alarms. A possible fall still needs a stillness check.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
