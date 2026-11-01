part of '../first_aid_guide_page_feature.dart';

/// Owns the state and non-visual actions of FirstAidGuidePage.
class _FirstAidGuidePageStateViewModel extends ChangeNotifier {
  /// Creates first aid guide page state view model.
  _FirstAidGuidePageStateViewModel({required this.effectShowDialError});
  final void Function(String number) effectShowDialError;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Resolves from an available location; the service owns offline country/number recovery.
  Future<EmergencyDialTarget> commandResolveEmergencyTarget({
    double? latitude,
    double? longitude,
    EmergencyNumberResolver? resolver,
  }) async {
    if (!_hasValidCoordinate(latitude, longitude)) {
      try {
        final location =
            LocationSnapshotService.instance.latestLocation ??
            await LocationSnapshotService.instance.refresh();
        latitude = location?.latitude;
        longitude = location?.longitude;
      } catch (_) {
        latitude = null;
        longitude = null;
      }
    }
    return (resolver ?? EmergencyNumberService()).resolve(
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Rejects incomplete or invalid coordinates before requesting a device snapshot.
  static bool _hasValidCoordinate(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Loads topics.
  Future<List<FirstAidTopic>> commandLoadTopics() async {
    try {
      final rawJson = await rootBundle.loadString(
        'assets/guides/first_aid_guide.json',
      );
      final data = jsonDecode(rawJson);
      final topics = data is Map<String, dynamic> ? data['topics'] : null;
      if (topics is List) {
        unawaited(commandRemoveRetiredTutorialCache());
        return topics
            .whereType<Map<String, dynamic>>()
            .map(FirstAidTopic.fromJson)
            .toList();
      }
    } catch (_) {
      unawaited(commandRemoveRetiredTutorialCache());
      return FirstAidTopic.defaults;
    }

    unawaited(commandRemoveRetiredTutorialCache());
    return FirstAidTopic.defaults;
  }

  /// Removes retired tutorial cache.
  Future<void> commandRemoveRetiredTutorialCache() async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      final tutorialDirectory = Directory(
        '${supportDirectory.path}${separator}first_aid${separator}videos',
      );
      if (await tutorialDirectory.exists()) {
        await tutorialDirectory.delete(recursive: true);
      }
    } catch (_) {
      // Retired media cleanup must never prevent the offline guide from opening.
    }
  }

  /// Computes call emergency services.
  Future<void> commandCallEmergencyServices(EmergencyDialTarget target) async {
    try {
      final launched = await launchUrl(
        Uri(scheme: 'tel', path: target.number),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        effectShowDialError(target.number);
      }
    } catch (_) {
      if (mounted) effectShowDialError(target.number);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Owns the state and non-visual actions of _ScenarioActionSheet.
class _ScenarioActionSheetStateViewModel extends ChangeNotifier {
  /// Creates scenario action sheet state view model.
  _ScenarioActionSheetStateViewModel({required this.readScenario});
  final FirstAidScenario Function() readScenario;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Opens reference.
  Future<void> commandOpenReference() async {
    final uri = Uri.tryParse(readScenario().referenceUrl);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
