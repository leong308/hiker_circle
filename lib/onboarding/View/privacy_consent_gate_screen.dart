part of '../privacy_consent_gate_feature.dart';

/// A one-time, account-scoped popup between completed onboarding and the home screen.
class PrivacyConsentGate extends StatefulWidget {
  const PrivacyConsentGate({
    super.key,
    required this.ownerPhoneNumber,
    required this.homeBuilder,
    required this.onNotNow,
    this.repository,
  });

  final String ownerPhoneNumber;
  final WidgetBuilder homeBuilder;
  final VoidCallback onNotNow;
  final PrivacyConsentRepository? repository;

  @override
  State<PrivacyConsentGate> createState() => _PrivacyConsentGateState();
}

class _PrivacyConsentGateState extends State<PrivacyConsentGate> {
  late final _PrivacyConsentGateViewModel _model;

  @override
  void initState() {
    super.initState();
    _model = _PrivacyConsentGateViewModel(
      widget.repository ?? PrivacyConsentRepository(),
      widget.ownerPhoneNumber,
    )..addListener(_refresh);
    unawaited(_model.load());
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    if (_model.accepted) return widget.homeBuilder(context);
    final scheme = Theme.of(context).colorScheme;
    if (_model.loading) {
      return const Scaffold(
        body: SafeArea(
          child: HikerCircleLoadingView(
            message: 'Preparing your privacy notice…',
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Color.alphaBlend(
          scheme.scrim.withValues(alpha: .15),
          scheme.surface,
        ),
        body: SafeArea(
          child: Center(
            child: Dialog(
              key: const Key('privacy-consent-dialog'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      if (_model.loadFailed) ...[
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
                          'Your setup is complete. Before you continue, please review how HikerCircle collects and uses information for the services you request:',
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
                        const Text(
                          'Feature data is processed by providers such as Firebase, map/weather services and GREEN-API/WhatsApp. Processing may take place outside Malaysia. A live-location link can be opened by anyone who has it while it remains active.',
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
                            'I agree to the collection and use described above for the HikerCircle services I request, including the stated service-provider processing.',
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
                                  child: HikerCircleMinorLoadingIndicator(
                                    size: 24,
                                  ),
                                )
                              : const Text('Agree & continue'),
                        ),
                      ],
                      TextButton(
                        key: const Key('privacy-consent-not-now'),
                        onPressed: _model.saving ? null : widget.onNotNow,
                        child: const Text('Not now — sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
