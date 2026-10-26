part of '../disclaimer_page_feature.dart';

/// Bundled with the app so these limitations remain readable without a connection.
class DisclaimerPage extends StatelessWidget {
  /// Creates disclaimer page.
  const DisclaimerPage({super.key});

  /// Builds this widget from its current presentation state.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: 'Disclaimer',
                    subtitle: 'Know before you hike',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Use your judgment, check local conditions and keep a backup plan. HikerCircle cannot guarantee your safety.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _DisclaimerSection(
                    icon: Icons.map_outlined,
                    title: 'Maps and routes',
                    paragraphs: [
                      'Maps, routes and GPS locations may be inaccurate or outdated. A mapped trail may be closed or unsafe. Follow official signs and access rules, and carry backup navigation.',
                    ],
                  ),
                  const _DisclaimerSection(
                    icon: Icons.warning_amber_rounded,
                    title: 'Hazard reports and weather',
                    paragraphs: [
                      'Reports may be unverified or outdated, and forecasts may differ from actual weather. No hazard report does not mean a trail is safe. Check official warnings and local conditions.',
                    ],
                  ),
                  const _DisclaimerSection(
                    icon: Icons.sos_rounded,
                    title: 'SOS and connectivity',
                    paragraphs: [
                      'Weak signal, low battery or phone restrictions can delay or prevent SOS delivery. An alarm or “sent” status does not confirm that anyone received the alert or that help is coming. For urgent help, use a direct emergency call or another rescue channel when possible.',
                    ],
                  ),
                  const _DisclaimerSection(
                    icon: Icons.battery_saver_outlined,
                    title: 'Safety settings and battery',
                    paragraphs: [
                      'Fall detection can miss falls or raise false alarms. During a hike, battery below 30% temporarily changes footprint recording to 1 minute and sensitivity to 5/10. Original settings return above 30%, including after an app restart. Route detail may be reduced; battery savings vary by phone.',
                    ],
                  ),
                  const _DisclaimerSection(
                    icon: Icons.location_on_outlined,
                    title: 'Location sharing',
                    paragraphs: [
                      'Shared locations may be delayed or inaccurate. Check the update time. Anyone with the link may view or forward it, so share only with trusted people.',
                      'If you stop sharing offline, earlier locations may remain visible until the stop is processed or the link expires.',
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
