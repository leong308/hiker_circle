// launchPrivacyPolicy opens the hosted privacy policy using the shared in-app browser flow.
import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://hiker-circle.web.app/privacy-policy';

final privacyPolicyUri = Uri.parse(privacyPolicyUrl);

/// Computes launch privacy policy.
Future<bool> launchPrivacyPolicy() async {
  try {
    if (!await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
      return false;
    }
    return await launchUrl(
      privacyPolicyUri,
      mode: LaunchMode.inAppBrowserView,
      browserConfiguration: const BrowserConfiguration(showTitle: true),
    );
  } catch (_) {
    return false;
  }
}
