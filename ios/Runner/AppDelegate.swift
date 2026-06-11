import Flutter
import UIKit
import AVFoundation
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private let sosDeviceAlertChannel = "hiker_circle/sos_device_alerts"
  private let alarmAsset = "assets/audios/sos_alarm.mp3"
  private var audioPlayer: AVAudioPlayer?
  private var torchTimer: Timer?
  private var torchPatternIndex = 0
  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?
  private var pendingAllowLastKnownLocation = false
  private var locationTimeoutTimer: Timer?
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
    configureSosDeviceAlertChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
          try self.startManualSosPattern()
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
      case "getCurrentTriggerLocation":
        self.getCurrentTriggerLocation(call, result)
      case "shareText":
        self.shareText(call, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startManualSosPattern() throws {
    try startAlarm()
    startTorchPattern()
  }

  private func stopManualSosPattern() {
    stopAlarm()
    stopTorchPattern()
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

    manager.desiredAccuracy = kCLLocationAccuracyBest
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

  private func startAlarm() throws {
    if audioPlayer?.isPlaying == true {
      return
    }

    let assetKey = FlutterDartProject.lookupKey(forAsset: alarmAsset)
    guard let alarmUrl = Bundle.main.url(forResource: assetKey, withExtension: nil) else {
      throw SosDeviceAlertError.alarmAssetMissing
    }

    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.playback, mode: .default)
    try audioSession.setActive(true)

    let player = try AVAudioPlayer(contentsOf: alarmUrl)
    player.numberOfLoops = -1
    player.prepareToPlay()
    player.play()
    audioPlayer = player
  }

  private func stopAlarm() {
    audioPlayer?.stop()
    audioPlayer = nil
    try? AVAudioSession.sharedInstance().setActive(false)
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

  var errorDescription: String? {
    switch self {
    case .alarmAssetMissing:
      return "Unable to find the SOS alarm asset."
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
