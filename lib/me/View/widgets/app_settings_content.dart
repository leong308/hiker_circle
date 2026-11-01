import 'package:flutter/material.dart';
import '../../../app/Data/app_settings_controller.dart';
import '../../../core/widgets/page_header_style.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../home/Data/location_update_interval_controller.dart';
import '../safety_settings_panel.dart';

/// The app settings layout, with preference and navigation actions supplied by its screen.
class AppSettingsContent extends StatelessWidget {
  /// Keeps presentation independent from biometrics, permissions and cloud persistence.
  const AppSettingsContent({
    super.key,
    required this.settings,
    required this.onBack,
    required this.onLoginSecurity,
    required this.onChangePassword,
    required this.onPrivateUnlock,
    required this.onPreciseLocation,
    required this.onHapticFeedback,
    required this.onTimeZone,
    required this.timeZoneLabel,
    this.timeZoneBusy = false,
    this.timeZoneError,
    this.intervals,
  });
  final AppSettingsController settings;
  final LocationUpdateIntervalController? intervals;
  final VoidCallback onBack, onLoginSecurity, onChangePassword, onTimeZone;
  final ValueChanged<bool> onPrivateUnlock, onPreciseLocation, onHapticFeedback;
  final String timeZoneLabel;
  final bool timeZoneBusy;
  final String? timeZoneError;

  /// Presents one consistent card style and initially closed preference drawers.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'App Settings',
                subtitle: 'Preferences and device controls',
                onBack: onBack,
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Account security'),
              const SizedBox(height: 8),
              SettingsNavigationCard(
                icon: Icons.security_rounded,
                title: 'Login security',
                subtitle: 'Manage Authenticator and passkeys',
                onTap: onLoginSecurity,
              ),
              const SizedBox(height: 10),
              SettingsToggleCard(
                icon: Icons.fingerprint_rounded,
                title: 'App biometric unlock',
                subtitle: 'Use biometrics when reopening the app.',
                value: settings.privateScreenUnlockEnabled,
                onChanged: onPrivateUnlock,
              ),
              const SizedBox(height: 10),
              SettingsNavigationCard(
                icon: Icons.password_rounded,
                title: 'Change password',
                subtitle: 'Verify your identity before changing your password',
                onTap: onChangePassword,
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Safety settings'),
              const SizedBox(height: 8),
              SafetySettingsPanel(
                settings: settings,
                intervals: intervals,
                onHapticFeedback: onHapticFeedback,
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Region'),
              const SizedBox(height: 8),
              SettingsNavigationCard(
                icon: Icons.schedule_rounded,
                title: 'SOS message timezone',
                subtitle: timeZoneLabel,
                onTap: timeZoneBusy ? null : onTimeZone,
                trailing: timeZoneBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                footer: timeZoneError == null
                    ? null
                    : Text(
                        timeZoneError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Appearance & theme'),
              const SizedBox(height: 8),
              SettingsDisclosureCard(
                icon: const Icon(Icons.palette_rounded),
                title: 'Theme mode',
                subtitle: settings.themeSetting.label,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final setting in HikerCircleThemeSetting.values)
                        ChoiceChip(
                          label: Text(setting.label),
                          selected: settings.themeSetting == setting,
                          onSelected: (_) => settings.setThemeSetting(setting),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SectionLabel(label: 'Permissions'),
              const SizedBox(height: 8),
              SettingsToggleCard(
                icon: Icons.my_location_rounded,
                title: 'Precise location retrieval',
                subtitle: 'Used for route tracking and emergency map links.',
                value: settings.preciseLocationEnabled,
                onChanged: onPreciseLocation,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
