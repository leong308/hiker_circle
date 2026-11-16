part of '../signup_privacy_consent_feature.dart';

/// Collects an explicit local choice before the registration request is made.
class SignupPrivacyConsentDialog extends StatefulWidget {
  const SignupPrivacyConsentDialog({
    super.key,
    required this.ownerPhoneNumber,
    required this.repository,
  });

  final String ownerPhoneNumber;
  final PrivacyConsentRepository repository;

  @override
  State<SignupPrivacyConsentDialog> createState() =>
      _SignupPrivacyConsentDialogState();
}

class _SignupPrivacyConsentDialogState
    extends State<SignupPrivacyConsentDialog> {
  late final _SignupPrivacyConsentViewModel _model;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _model = _SignupPrivacyConsentViewModel(
      widget.repository,
      widget.ownerPhoneNumber,
    )..addListener(_refresh);
    unawaited(_model.load());
  }

  void _refresh() {
    if (!mounted) return;
    if (_model.accepted && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _model.removeListener(_refresh);
    _model.dispose();
    super.dispose();
  }

  Widget _data(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_model.saving,
      child: Dialog(
        key: const Key('privacy-consent-dialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height - 100,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 36,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your privacy in HikerCircle',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                if (_model.loading)
                  const HikerCircleLoadingView(
                    message: 'Preparing your privacy notice…',
                  )
                else if (_model.loadFailed) ...[
                  const Text(
                    'We could not read your saved privacy choice. Please try again.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _model.load,
                    child: const Text('Try again'),
                  ),
                ] else ...[
                  const Text(
                    'Before you submit your phone number to sign up, please review how HikerCircle collects and uses information for the services you request. After you agree, your number will be submitted for account registration and WhatsApp verification.',
                  ),
                  const SizedBox(height: 18),
                  _data(
                    Icons.account_circle_outlined,
                    'Account and profile: phone number, profile details, hiking preferences and security records.',
                  ),
                  _data(
                    Icons.route_outlined,
                    'Hikes and location: planned routes, GPS footprints, times and battery level when relevant features are used.',
                  ),
                  _data(
                    Icons.health_and_safety_outlined,
                    'Safety: emergency-contact details, SOS events, your selected messages and dispatch status.',
                  ),
                  _data(
                    Icons.forum_outlined,
                    'Community and feedback: posts, chats, ratings, reports and media you choose to submit.',
                  ),
                  _data(
                    Icons.devices_outlined,
                    'Device and service data: notification tokens, connection status and permitted motion or Bluetooth information.',
                  ),
                  Container(
                    key: const Key('consent-overseas-processing'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Processing outside Malaysia',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Information needed for the services you request may be transferred to, processed or stored outside Malaysia by these providers:',
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Firebase / Google Cloud: account and saved feature records for sign-in, cloud storage and notifications.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Mapbox and other map providers: selected coordinates and route points for maps and directions.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Open-Meteo: requested coordinates for weather forecasts.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'GREEN-API / WhatsApp: recipient numbers and message details for verification, SOS and contact notifications.',
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Processing locations vary by service and configuration. The Privacy Policy explains these transfers and how to contact us about your information.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A live-location link can be opened by anyone who has it while it remains active.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Optional features still require their own choices and device permissions. Agreeing here does not turn on tracking or live sharing, import contacts, or send an SOS. Tell your emergency contacts and obtain their agreement before adding them.',
                  ),
                  const PrivacyPolicyLink(
                    key: Key('consent-privacy-policy-link'),
                    label: 'Read the Privacy Policy',
                    languageCode: 'en',
                  ),
                  CheckboxListTile(
                    key: const Key('privacy-consent-checkbox'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _model.checked,
                    onChanged: _model.saving
                        ? null
                        : (value) => _model.setChecked(value == true),
                    title: const Text(
                      'I agree to the collection and use described above, including the transfer and processing of my information outside Malaysia by the listed providers for the HikerCircle services I request.',
                    ),
                  ),
                  if (_model.saveFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Your choice was not saved. Please try again.',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  FilledButton(
                    key: const Key('privacy-consent-accept'),
                    onPressed: !_model.checked || _model.saving
                        ? null
                        : _model.accept,
                    child: _model.saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: HikerCircleMinorLoadingIndicator(size: 24),
                          )
                        : const Text('Agree & continue'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'If you do not agree, choose Not now. Your phone number will not be submitted for registration.',
                    textAlign: TextAlign.center,
                  ),
                ],
                TextButton(
                  key: const Key('privacy-consent-not-now'),
                  onPressed: _model.saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
