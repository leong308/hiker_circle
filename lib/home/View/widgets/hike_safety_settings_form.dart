// Shared per-hike safety controls for immediate and scheduled hikes.
import 'dart:async';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../sos/View/fall_detection_test_dialog.dart';
import '../../Model/hike_session_models.dart';
import '../../Model/hike_safety_preferences.dart';
import 'fall_sensitivity_setting.dart';
import 'footprint_interval_setting.dart';
import 'path_deviation_distance_setting.dart';

/// Displays the hike safety settings form.
class HikeSafetySettingsForm extends StatelessWidget {
  /// Creates hike safety settings form.
  const HikeSafetySettingsForm({
    super.key,
    required this.draft,
    required this.onChanged,
    this.onEditContacts,
  });

  final HikeSessionDraft draft;
  final ValueChanged<HikeSessionDraft> onChanged;
  final VoidCallback? onEditContacts;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final fallDetectionSettings = draft.fallDetectionSettings;
    final androidNativeSafety =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final responseOptions = androidNativeSafety
        ? const [Duration(seconds: 15)]
        : HikeSafetyPreferences.responseOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Emergency contacts',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (onEditContacts != null)
              TextButton.icon(
                onPressed: onEditContacts,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Manage'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          draft.emergencyContactNames.isEmpty
              ? 'No emergency contacts saved. Add someone you trust before starting.'
              : draft.emergencyContactNames.join(', '),
        ),
        const SizedBox(height: 12),
        _SafetySwitchRow(
          label: 'Share live location with SOS contacts when hike starts',
          value: draft.shareLiveLocation,
          onChanged: (value) =>
              onChanged(draft.copyWith(shareLiveLocation: value)),
        ),
        _SafetySwitchRow(
          label: 'Fall and Stillness Detection',
          value: draft.fallDetectionEnabled,
          onChanged: (value) {
            if (!value) {
              unawaited(_showFallDetectionWarning(context));
            }
            onChanged(draft.copyWith(fallDetectionEnabled: value));
          },
        ),
        const SizedBox(height: 16),
        FallSensitivitySetting(
          enabled: draft.fallDetectionEnabled,
          value: fallDetectionSettings.sensorSensitivity,
          onChanged: (value) => onChanged(
            draft.copyWith(
              fallDetectionSettings: FallDetectionSettings(
                sensorSensitivity: value,
                fallResponseDuration:
                    fallDetectionSettings.fallResponseDuration,
                longestRestDuration: fallDetectionSettings.longestRestDuration,
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => showFallDetectionTest(
            context,
            sensitivity: fallDetectionSettings.sensorSensitivity,
          ),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Fall detection test'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Duration>(
          isExpanded: true,
          initialValue:
              responseOptions.contains(
                fallDetectionSettings.fallResponseDuration,
              )
              ? fallDetectionSettings.fallResponseDuration
              : responseOptions.first,
          decoration: InputDecoration(
            labelText: androidNativeSafety
                ? 'Safety warning response window'
                : 'Longest response time after a fall',
            prefixIcon: const Icon(Icons.personal_injury_rounded),
          ),
          items: [
            for (final duration in responseOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text(_durationLabel(duration)),
              ),
          ],
          onChanged: draft.fallDetectionEnabled && !androidNativeSafety
              ? (duration) {
                  if (duration == null) {
                    return;
                  }
                  onChanged(
                    draft.copyWith(
                      fallDetectionSettings: FallDetectionSettings(
                        sensorSensitivity:
                            fallDetectionSettings.sensorSensitivity,
                        fallResponseDuration: duration,
                        longestRestDuration:
                            fallDetectionSettings.longestRestDuration,
                      ),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          androidNativeSafety
              ? 'Android vibrates, speaks an “Are you okay?” prompt, and shows a lock-screen warning for 15 seconds. No SOS is sent during this warning window.'
              : 'After a fall and fixed stillness check, this is how long you have to cancel before Fall SOS is sent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          isExpanded: true,
          initialValue:
              HikeSafetyPreferences.restOptions.contains(
                fallDetectionSettings.longestRestDuration,
              )
              ? fallDetectionSettings.longestRestDuration
              : HikeSafetyPreferences.restOptions.first,
          decoration: const InputDecoration(
            labelText: 'Longest time for a rest',
            prefixIcon: Icon(Icons.self_improvement_rounded),
          ),
          items: [
            for (final duration in HikeSafetyPreferences.restOptions)
              DropdownMenuItem<Duration>(
                value: duration,
                child: Text(_durationLabel(duration)),
              ),
          ],
          onChanged: draft.fallDetectionEnabled
              ? (duration) {
                  if (duration == null) {
                    return;
                  }
                  onChanged(
                    draft.copyWith(
                      fallDetectionSettings: FallDetectionSettings(
                        sensorSensitivity:
                            fallDetectionSettings.sensorSensitivity,
                        fallResponseDuration:
                            fallDetectionSettings.fallResponseDuration,
                        longestRestDuration: duration,
                      ),
                    ),
                  );
                }
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          'If your location stays within 5 m for this long, HikerCircle checks for phone movement and asks you to respond before sending a prolonged-stillness SOS.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        FootprintIntervalSetting(
          value: draft.locationRecordingInterval,
          onChanged: (value) =>
              onChanged(draft.copyWith(locationRecordingInterval: value)),
        ),
        if (draft.trail.isUnlisted)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Path deviation alerts are unavailable because this hike has no planned route. GPS recording and safety monitoring remain enabled.',
            ),
          )
        else
          _SafetySwitchRow(
            label: 'Path Deviation Alert',
            value: draft.pathDeviationEnabled,
            onChanged: (value) {
              if (!value) {
                unawaited(_showPathDeviationWarning(context));
              }
              onChanged(draft.copyWith(pathDeviationEnabled: value));
            },
          ),
        if (!draft.trail.isUnlisted) ...[
          const SizedBox(height: 12),
          PathDeviationDistanceSetting(
            value: draft.pathDeviationDistanceMeters,
            enabled: draft.pathDeviationEnabled,
            onChanged: (distance) => onChanged(
              draft.copyWith(pathDeviationDistanceMeters: distance),
            ),
          ),
        ],
      ],
    );
  }

  /// Explains which automatic protections are disabled with fall detection.
  Future<void> _showFallDetectionWarning(
    BuildContext context,
  ) => _showSafetyDisabledWarning(
    context,
    title: 'Fall and Stillness Detection Off',
    message:
        'HikerCircle will stop detecting falls and prolonged stillness during this hike. Automatic SOS alerts for these events will be disabled. You can still send an SOS manually.',
  );

  /// Shows the existing path deviation warning with the shared dialog style.
  Future<void> _showPathDeviationWarning(
    BuildContext context,
  ) => _showSafetyDisabledWarning(
    context,
    title: 'Path Deviation Alert Off',
    message:
        'HikerCircle will stop warning you when your recorded route moves away from the selected trail. This can reduce safety on unfamiliar hikes.',
  );

  /// Presents an acknowledgement after a safety feature is switched off.
  Future<void> _showSafetyDisabledWarning(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

/// Displays the safety switch row.
class _SafetySwitchRow extends StatelessWidget {
  /// Creates safety switch row.
  const _SafetySwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SafetyAnimatedToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Displays the safety animated toggle.
class _SafetyAnimatedToggle extends StatelessWidget {
  /// Creates safety animated toggle.
  const _SafetyAnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    return AnimatedToggleSwitch<bool>.size(
      current: value,
      values: const [false, true],
      height: 38,
      spacing: 2,
      indicatorSize: const Size.square(32),
      borderWidth: 2,
      style: ToggleStyle(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        borderColor: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(999),
        indicatorBorderRadius: BorderRadius.circular(999),
      ),
      styleBuilder: (enabled) => ToggleStyle(
        indicatorColor: enabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
      iconBuilder: (enabled) => Icon(
        enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        size: 17,
      ),
      foregroundIndicatorIconBuilder: (context, global) {
        final enabled = global.current;
        return Icon(
          enabled ? Icons.check_rounded : Icons.close_rounded,
          color: Theme.of(context).colorScheme.surface,
          size: 18,
        );
      },
      iconOpacity: 0.72,
      selectedIconOpacity: 0,
      selectedIconScale: 1,
      animationDuration: const Duration(milliseconds: 260),
      animationCurve: Curves.easeOutCubic,
      onChanged: onChanged,
    );
  }
}

/// Computes duration label.
String _durationLabel(Duration duration) => duration.inSeconds < 60
    ? '${duration.inSeconds} sec'
    : '${duration.inMinutes} min';
