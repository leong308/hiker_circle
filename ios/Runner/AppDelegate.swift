import Flutter
import UIKit
import AVFoundation
import AudioToolbox
import CoreLocation
import Contacts
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private let sosDeviceAlertChannel = "hiker_circle/sos_device_alerts"
  private let deepLinkChannelName = "hiker_circle/deeplinks"
  private let activeHikeLiveStatusChannelName = "hiker_circle/active_hike_live_status"
  private let sosShortcutDeepLinks = [
    "com.leongziqi.hikercircle.instantSos": "hikercircle://sos/instant?source=ios_quick_action",
    "com.leongziqi.hikercircle.medicalSos": "hikercircle://sos/medical?source=ios_quick_action",
    "com.leongziqi.hikercircle.duressSos": "hikercircle://sos/duress?source=ios_quick_action",
  ]
  private let alarmAsset = "assets/audios/sos_alarm.mp3"
  private let medicalAlarmAsset = "assets/audios/med_alarm.mp3"
  private var audioPlayer: AVAudioPlayer?
  private var activeAlarmAsset: String?
  private var isOutputVolumeMonitoringActive = false
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var torchTimer: Timer?
  private var fallStillnessVibrationTimer: Timer?
  private var torchPatternIndex = 0
  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?
  private var pendingAllowLastKnownLocation = false
  private var isPreciseLocationEnabled = true
  private var locationTimeoutTimer: Timer?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?
  private var activeHikeLiveActivitySessionId: String?
  private let sosTorchPattern: [(enabled: Bool, duration: TimeInterval)] = [
    (true, 0.22),
    (false, 0.18),
    (true, 0.22),
    (false, 0.18),
    (true, 0.22),
    (false, 0.42),
    (true, 0.65),
    (false, 0.22),
    (true, 0.65),
    (false, 0.22),
    (true, 0.65),
    (false, 0.42),
    (true, 0.22),
    (false, 0.18),
    (true, 0.22),
    (false, 0.18),
    (true, 0.22),
    (false, 1.40),
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "QrScannerPlugin") {
      let factory = QrScannerPlatformViewFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "hiker_circle/qr_scanner")
    }
    configureSosDeviceAlertChannel()
    configureDeepLinkChannel()
    configureActiveHikeLiveStatusChannel()
    if let url = launchOptions?[.url] as? URL {
      pendingDeepLink = url.absoluteString
    }
    if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      _ = handleShortcutItem(shortcutItem, notifyFlutter: false)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    let handledByFlutter = super.application(app, open: url, options: options)
    pendingDeepLink = url.absoluteString
    deepLinkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
    return handledByFlutter || url.scheme == "hikercircle"
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(handleShortcutItem(shortcutItem, notifyFlutter: true))
  }

  private func handleShortcutItem(
    _ shortcutItem: UIApplicationShortcutItem,
    notifyFlutter: Bool
  ) -> Bool {
    guard let deepLink = sosShortcutDeepLinks[shortcutItem.type] else {
      return false
    }

    let wasAlreadyPending = pendingDeepLink == deepLink
    pendingDeepLink = deepLink
    if notifyFlutter && !wasAlreadyPending {
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: deepLink)
    }
    return true
  }

  private func configureSosDeviceAlertChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: sosDeviceAlertChannel,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "sos_device_alert_unavailable",
          message: "SOS device alert service is unavailable.",
          details: nil
        ))
        return
      }

      switch call.method {
      case "startManualSosPattern":
        do {
          let arguments = call.arguments as? [String: Any]
          let requestedAlarmAsset = arguments?["alarmAsset"] as? String
          try self.startManualSosPattern(alarmAsset: requestedAlarmAsset)
          result(nil)
        } catch {
          result(FlutterError(
            code: "sos_device_alert_start_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "stopManualSosPattern":
        self.stopManualSosPattern()
        result(nil)
      case "startSirenOnly":
        do {
          let arguments = call.arguments as? [String: Any]
          let requestedAlarmAsset = arguments?["alarmAsset"] as? String
          self.stopTorchPattern()
          try self.startAlarm(alarmAsset: self.normalizedAlarmAsset(requestedAlarmAsset))
          result(nil)
        } catch {
          result(FlutterError(
            code: "siren_test_start_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "startFlashlightPattern":
        self.startTorchPattern()
        result(nil)
      case "stopFlashlightPattern":
        self.stopTorchPattern()
        result(nil)
      case "startFallStillnessCountdownVibration":
        self.startFallStillnessCountdownVibration()
        result(nil)
      case "stopFallStillnessCountdownVibration":
        self.stopFallStillnessCountdownVibration()
        result(nil)
      case "getBatteryLevel":
        result(self.currentBatteryLevel())
      case "getDeviceContacts":
        self.getDeviceContacts(result)
      case "beginOutputVolumeMonitoring":
        do {
          try self.beginOutputVolumeMonitoring()
          result(nil)
        } catch {
          result(FlutterError(
            code: "sos_volume_monitoring_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "endOutputVolumeMonitoring":
        self.endOutputVolumeMonitoring()
        result(nil)
      case "speakFallStillnessPrompt":
        let arguments = call.arguments as? [String: Any]
        let message = arguments?["message"] as? String
        self.speakFallStillnessPrompt(
          message ?? "Are you okay? Do you need help? Please respond by tapping the phone to cancel SOS."
        )
        result(nil)
      case "stopSpokenPrompt":
        self.stopSpokenPrompt()
        result(nil)
      case "getOutputVolumeStatus":
        self.getOutputVolumeStatus(call, result)
      case "getCurrentTriggerLocation":
        self.getCurrentTriggerLocation(call, result)
      case "setPreciseLocationEnabled":
        let arguments = call.arguments as? [String: Any]
        self.isPreciseLocationEnabled = arguments?["enabled"] as? Bool ?? true
        result(nil)
      case "shareText":
        self.shareText(call, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureDeepLinkChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: deepLinkChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    deepLinkChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

      switch call.method {
      case "consumeInitialDeepLink":
        result(self.pendingDeepLink)
        self.pendingDeepLink = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureActiveHikeLiveStatusChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: activeHikeLiveStatusChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "active_hike_live_status_unavailable",
          message: "Active hike live status service is unavailable.",
          details: nil
        ))
        return
      }

      switch call.method {
      case "startOrUpdateActiveHikeLiveStatus":
        guard let status = ManualHikeLiveStatus(arguments: call.arguments) else {
          result(FlutterError(
            code: "active_hike_live_status_invalid",
            message: "Active hike status payload is invalid.",
            details: nil
          ))
          return
        }

        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
          Task { @MainActor in
            do {
              try await self.startOrUpdateManualHikeLiveActivity(status)
              result(nil)
            } catch {
              result(FlutterError(
                code: "active_hike_live_activity_failed",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        } else {
          result(FlutterError(
            code: "active_hike_live_activity_unavailable",
            message: "Live Activities require iOS 16.1 or later.",
            details: nil
          ))
        }
        #else
        result(FlutterError(
          code: "active_hike_live_activity_unavailable",
          message: "ActivityKit is not available in this build.",
          details: nil
        ))
        #endif
      case "stopActiveHikeLiveStatus":
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
          Task { @MainActor in
            await self.stopManualHikeLiveActivity()
            result(nil)
          }
        } else {
          self.activeHikeLiveActivitySessionId = nil
          result(nil)
        }
        #else
        self.activeHikeLiveActivitySessionId = nil
        result(nil)
        #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  #if canImport(ActivityKit)
  @available(iOS 16.1, *)
  @MainActor
  private func startOrUpdateManualHikeLiveActivity(
    _ status: ManualHikeLiveStatus
  ) async throws {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw ManualHikeLiveActivityError.activitiesDisabled
    }

    let contentState = status.toContentState()
    if let activity = Activity<ManualHikeAttributes>.activities.first(
      where: { $0.attributes.sessionId == status.sessionId }
    ) {
      await activity.update(using: contentState)
      activeHikeLiveActivitySessionId = status.sessionId
      return
    }

    for activity in Activity<ManualHikeAttributes>.activities {
      await activity.end(using: nil, dismissalPolicy: .immediate)
    }

    let attributes = ManualHikeAttributes(sessionId: status.sessionId)
    let activity = try Activity<ManualHikeAttributes>.request(
      attributes: attributes,
      contentState: contentState,
      pushType: nil
    )
    activeHikeLiveActivitySessionId = activity.attributes.sessionId
  }

  @available(iOS 16.1, *)
  @MainActor
  private func stopManualHikeLiveActivity() async {
    let matchingSessionId = activeHikeLiveActivitySessionId
    for activity in Activity<ManualHikeAttributes>.activities {
      if matchingSessionId == nil || activity.attributes.sessionId == matchingSessionId {
        await activity.end(using: nil, dismissalPolicy: .immediate)
      }
    }
    activeHikeLiveActivitySessionId = nil
  }
  #endif

  private func startManualSosPattern(alarmAsset requestedAlarmAsset: String? = nil) throws {
    try startAlarm(alarmAsset: normalizedAlarmAsset(requestedAlarmAsset))
    startTorchPattern()
  }

  private func stopManualSosPattern() {
    stopAlarm()
    stopTorchPattern()
    stopFallStillnessCountdownVibration()
  }

  private func startFallStillnessCountdownVibration() {
    stopFallStillnessCountdownVibration()
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    fallStillnessVibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.95, repeats: true) {
      _ in
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
  }

  private func stopFallStillnessCountdownVibration() {
    fallStillnessVibrationTimer?.invalidate()
    fallStillnessVibrationTimer = nil
  }

  private func currentBatteryLevel() -> Int? {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    guard level >= 0 else {
      return nil
    }
    return Int((level * 100).rounded())
  }

  private func getDeviceContacts(_ result: @escaping FlutterResult) {
    let store = CNContactStore()
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized, .limited:
      result(fetchDeviceContacts(store: store))
    case .notDetermined:
      store.requestAccess(for: .contacts) { [weak self] granted, _ in
        DispatchQueue.main.async {
          guard granted, let self else {
            result([])
            return
          }
          result(self.fetchDeviceContacts(store: store))
        }
      }
    case .denied, .restricted:
      result([])
    @unknown default:
      result([])
    }
  }

  private func fetchDeviceContacts(store: CNContactStore) -> [[String: Any]] {
    let keys: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.sortOrder = .givenName
    var contacts: [[String: Any]] = []

    do {
      try store.enumerateContacts(with: request) { contact, _ in
        let phoneNumbers = contact.phoneNumbers.map {
          $0.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !phoneNumbers.isEmpty else {
          return
        }

        let fullName = CNContactFormatter.string(from: contact, style: .fullName)
          ?? [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        contacts.append([
          "firstName": contact.givenName,
          "lastName": contact.familyName,
          "fullName": fullName,
          "phoneNumbers": phoneNumbers,
        ])
      }
    } catch {
      return []
    }

    return contacts
  }

  private func getOutputVolumeStatus(
    _ call: FlutterMethodCall,
    _ result: FlutterResult
  ) {
    if !isOutputVolumeMonitoringActive && audioPlayer?.isPlaying != true {
      try? beginOutputVolumeMonitoring()
    }
    let arguments = call.arguments as? [String: Any]
    let requestedMinimum =
      (arguments?["minimumRequiredVolume"] as? NSNumber)?.doubleValue ?? 0.2
    let minimumRequiredVolume = max(0.0, min(1.0, requestedMinimum))
    let outputVolume = Double(AVAudioSession.sharedInstance().outputVolume)

    result([
      "platform": "ios",
      "isIos": true,
      "canMeasureOutputVolume": true,
      "outputVolume": outputVolume,
      "minimumRequiredVolume": minimumRequiredVolume,
      "isAudible": outputVolume >= minimumRequiredVolume
    ])
  }

  private func beginOutputVolumeMonitoring() throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try audioSession.setActive(true)
    try? audioSession.overrideOutputAudioPort(.speaker)
    isOutputVolumeMonitoringActive = true
  }

  private func endOutputVolumeMonitoring() {
    isOutputVolumeMonitoringActive = false
    guard audioPlayer?.isPlaying != true else {
      return
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func getCurrentTriggerLocation(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard pendingLocationResult == nil else {
      result(FlutterError(
        code: "location_request_in_progress",
        message: "A trigger location request is already in progress.",
        details: nil
      ))
      return
    }

    guard CLLocationManager.locationServicesEnabled() else {
      result(nil)
      return
    }

    let manager = locationManager ?? CLLocationManager()
    locationManager = manager
    manager.delegate = self
    pendingLocationResult = result
    if let arguments = call.arguments as? [String: Any],
       let allowLastKnown = arguments["allowLastKnown"] as? Bool {
      pendingAllowLastKnownLocation = allowLastKnown
    } else {
      pendingAllowLastKnownLocation = false
    }

    switch CLLocationManager.authorizationStatus() {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      requestOneShotLocation()
    case .denied, .restricted:
      completePendingLocation(nil)
    @unknown default:
      completePendingLocation(nil)
    }
  }

  private func requestOneShotLocation() {
    guard let manager = locationManager else {
      completePendingLocation(nil)
      return
    }

    manager.desiredAccuracy = isPreciseLocationEnabled ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) {
      [weak self] _ in
      self?.completePendingLocation(self?.lastKnownLocationFallback())
    }
    manager.requestLocation()
  }

  private func shareText(
    _ call: FlutterMethodCall,
    _ result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any],
          let text = arguments["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(
        code: "share_text_missing",
        message: "Share text is missing.",
        details: nil
      ))
      return
    }

    let activityController = UIActivityViewController(
      activityItems: [text],
      applicationActivities: nil
    )

    if let popover = activityController.popoverPresentationController,
       let sourceView = window?.rootViewController?.view {
      popover.sourceView = sourceView
      popover.sourceRect = CGRect(
        x: sourceView.bounds.midX,
        y: sourceView.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }

    window?.rootViewController?.present(activityController, animated: true)
    result(nil)
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    handleLocationAuthorizationChange(manager)
  }

  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    handleLocationAuthorizationChange(manager)
  }

  private func handleLocationAuthorizationChange(_ manager: CLLocationManager) {
    guard pendingLocationResult != nil else {
      return
    }

    switch CLLocationManager.authorizationStatus() {
    case .authorizedAlways, .authorizedWhenInUse:
      requestOneShotLocation()
    case .denied, .restricted:
      completePendingLocation(lastKnownLocationFallback())
    case .notDetermined:
      break
    @unknown default:
      completePendingLocation(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    completePendingLocation(locations.last)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    completePendingLocation(lastKnownLocationFallback())
  }

  private func completePendingLocation(_ location: CLLocation?) {
    guard let result = pendingLocationResult else {
      return
    }

    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = nil
    pendingLocationResult = nil
    pendingAllowLastKnownLocation = false
    result(location?.toFlutterMap())
  }

  private func lastKnownLocationFallback() -> CLLocation? {
    guard pendingAllowLastKnownLocation else {
      return nil
    }

    return locationManager?.location
  }

  private func startAlarm(alarmAsset requestedAlarmAsset: String) throws {
    if audioPlayer?.isPlaying == true && activeAlarmAsset == requestedAlarmAsset {
      return
    }
    stopAlarm()

    let assetKey = FlutterDartProject.lookupKey(forAsset: requestedAlarmAsset)
    guard let alarmUrl = Bundle.main.url(forResource: assetKey, withExtension: nil) else {
      throw SosDeviceAlertError.alarmAssetMissing
    }

    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
    try audioSession.setActive(true)
    try? audioSession.overrideOutputAudioPort(.speaker)
    isOutputVolumeMonitoringActive = false

    let player = try AVAudioPlayer(contentsOf: alarmUrl)
    player.numberOfLoops = -1
    player.volume = 1.0
    player.prepareToPlay()
    guard player.play() else {
      throw SosDeviceAlertError.alarmPlaybackFailed
    }
    audioPlayer = player
    activeAlarmAsset = requestedAlarmAsset
  }

  private func stopAlarm() {
    audioPlayer?.stop()
    audioPlayer = nil
    activeAlarmAsset = nil
    if !isOutputVolumeMonitoringActive {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func normalizedAlarmAsset(_ requestedAlarmAsset: String?) -> String {
    return requestedAlarmAsset == medicalAlarmAsset ? medicalAlarmAsset : alarmAsset
  }

  private func speakFallStillnessPrompt(_ message: String) {
    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utterance.volume = 1.0
    speechSynthesizer.speak(utterance)
  }

  private func stopSpokenPrompt() {
    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }
  }

  private func startTorchPattern() {
    guard torchTimer == nil else {
      return
    }

    torchPatternIndex = 0
    scheduleNextTorchStep()
  }

  private func stopTorchPattern() {
    torchTimer?.invalidate()
    torchTimer = nil
    setTorch(false)
  }

  private func scheduleNextTorchStep() {
    let step = sosTorchPattern[torchPatternIndex]
    setTorch(step.enabled)
    torchPatternIndex = (torchPatternIndex + 1) % sosTorchPattern.count

    torchTimer = Timer.scheduledTimer(withTimeInterval: step.duration, repeats: false) {
      [weak self] _ in
      self?.scheduleNextTorchStep()
    }
  }

  private func setTorch(_ enabled: Bool) {
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera,
      for: .video,
      position: .back
    ), device.hasTorch else {
      return
    }

    do {
      try device.lockForConfiguration()
      device.torchMode = enabled ? .on : .off
      device.unlockForConfiguration()
    } catch {
      torchTimer?.invalidate()
      torchTimer = nil
    }
  }
}

enum SosDeviceAlertError: LocalizedError {
  case alarmAssetMissing
  case alarmPlaybackFailed

  var errorDescription: String? {
    switch self {
    case .alarmAssetMissing:
      return "Unable to find the SOS alarm asset."
    case .alarmPlaybackFailed:
      return "Unable to start SOS alarm playback."
    }
  }
}

extension CLLocation {
  func toFlutterMap() -> [String: Any] {
    var data: [String: Any] = [
      "latitude": coordinate.latitude,
      "longitude": coordinate.longitude,
      "capturedAtMillis": Int(timestamp.timeIntervalSince1970 * 1000),
    ]

    if horizontalAccuracy >= 0 {
      data["accuracyMeters"] = horizontalAccuracy
    }

    return data
  }
}

private struct ManualHikeLiveStatus {
  let sessionId: String
  let trailName: String
  let startedAtMillis: Double
  let expectedReturnAtMillis: Double
  let checkIns: Int
  let manualPins: Int
  let queuedUpdates: Int
  let batteryLevel: Int
  let distanceKm: Double
  let routePointCount: Int

  init?(arguments: Any?) {
    guard let data = arguments as? [String: Any],
          let sessionId = data["sessionId"] as? String,
          let startedAtMillis = Self.doubleValue(data["startedAtMillis"]) else {
      return nil
    }

    let rawTrailName = (data["trailName"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.sessionId = sessionId
    if let trailName = rawTrailName, !trailName.isEmpty {
      self.trailName = trailName
    } else {
      self.trailName = "Active hike"
    }
    self.startedAtMillis = startedAtMillis
    self.expectedReturnAtMillis = Self.doubleValue(data["expectedReturnAtMillis"]) ?? 0
    self.checkIns = Self.intValue(data["checkIns"])
    self.manualPins = Self.intValue(data["manualPins"])
    self.queuedUpdates = Self.intValue(data["queuedUpdates"])
    self.batteryLevel = min(100, max(0, Self.intValue(data["batteryLevel"])))
    self.distanceKm = max(0, Self.doubleValue(data["distanceKm"]) ?? 0)
    self.routePointCount = Self.intValue(data["routePointCount"])
  }

  private static func intValue(_ value: Any?) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let int = value as? Int {
      return int
    }
    return 0
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let double = value as? Double {
      return double
    }
    if let int = value as? Int {
      return Double(int)
    }
    return nil
  }

  #if canImport(ActivityKit)
  @available(iOS 16.1, *)
  func toContentState() -> ManualHikeAttributes.ContentState {
    let expectedReturnAt = expectedReturnAtMillis > 0
      ? Date(timeIntervalSince1970: expectedReturnAtMillis / 1000)
      : nil

    return ManualHikeAttributes.ContentState(
      trailName: trailName,
      startedAt: Date(timeIntervalSince1970: startedAtMillis / 1000),
      expectedReturnAt: expectedReturnAt,
      checkIns: checkIns,
      manualPins: manualPins,
      queuedUpdates: queuedUpdates,
      batteryLevel: batteryLevel,
      distanceKm: distanceKm,
      routePointCount: routePointCount
    )
  }
  #endif
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct ManualHikeAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var trailName: String
    var startedAt: Date
    var expectedReturnAt: Date?
    var checkIns: Int
    var manualPins: Int
    var queuedUpdates: Int
    var batteryLevel: Int
    var distanceKm: Double
    var routePointCount: Int
  }

  var sessionId: String
}

@available(iOS 16.1, *)
private enum ManualHikeLiveActivityError: LocalizedError {
  case activitiesDisabled

  var errorDescription: String? {
    switch self {
    case .activitiesDisabled:
      return "Live Activities are disabled for HikerCircle. Enable them in iOS Settings to show active hike status."
    }
  }
}
#endif
