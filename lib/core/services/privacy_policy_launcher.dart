import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://hiker-circle.web.app/privacy-policy';

final privacyPolicyUri = Uri.parse(privacyPolicyUrl);

Future<bool> launchPrivacyPolicy() async {
  try {
    return await launchUrl(
      privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
