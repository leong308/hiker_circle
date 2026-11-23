import 'package:url_launcher/url_launcher.dart';

import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../trail/Model/trail_models.dart';

/// Reads a fresh device fix and opens Waze for the selected trailhead.
class TrailheadNavigationService {
  /// Allows platform boundaries to be replaced in focused tests.
  const TrailheadNavigationService({
    this.device = const SosDeviceAlertService(),
    this.launchExternal = _launchExternal,
  });

  final SosDeviceAlertService device;
  final Future<bool> Function(Uri) launchExternal;

  /// Requests a new accurate fix without using the passive location cache.
  Future<SosTriggerLocation?> fetchLocation() => device
      .getCurrentTriggerLocation(allowLastKnown: false, requirePrecise: true);

  /// Tries the installed Waze app first; its website is the fallback.
  Future<bool> openDirections(Trail trail) async {
    final parameters = {
      'll': '${trail.latitude},${trail.longitude}',
      'navigate': 'yes',
      'utm_source': 'hikercircle',
    };
    try {
      // API: Waze trailhead directions
      if (await launchExternal(
        Uri.parse('waze://').replace(queryParameters: parameters),
      )) {
        return true;
      }
    } catch (_) {
      // Waze may be absent, so allow its universal link to handle the request.
    }
    try {
      return await launchExternal(Uri.https('waze.com', '/ul', parameters));
    } catch (_) {
      return false;
    }
  }

  /// Launches outside HikerCircle without opening an in-app browser.
  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
