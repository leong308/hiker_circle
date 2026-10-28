// AppDelegate bridges iOS safety monitoring, native location, widgets, alarms, and deep links.
import Flutter
import FirebaseAppCheck
import UIKit
import AVFoundation
import AudioToolbox
import CoreLocation
import CoreMotion
import Contacts
import UserNotifications
import WidgetKit
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
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
  private var hikeSpeechUtterance: AVSpeechUtterance?
  private var hikeSpeechRequestId: String?
  private var hikeSpeechResult: FlutterResult?
  private var safetySpeechUtterance: AVSpeechUtterance?
  private var torchTimer: Timer?
  private var fallStillnessVibrationTimer: Timer?
  private var torchPatternIndex = 0
  private var locationManager: CLLocationManager?
  private var pendingLocationResult: FlutterResult?
  private var pendingAllowLastKnownLocation = false
  private var pendingRequirePreciseLocation = false
  private var pendingBestLocation: CLLocation?
  private var isPreciseLocationEnabled = true
  private var locationTimeoutTimer: Timer?
  private var motionAuthorizationManager: CMMotionActivityManager?
  private var deepLinkChannel: FlutterMethodChannel?
  private var mobileSecurityBridge: MobileSecurityBridge?
  private var pendingDeepLink: String?
  private var activeHikeLiveActivitySessionId: String?
  private var activeHikeLiveStatusChannel: FlutterMethodChannel?
  private var arrivalSafetyChannel: FlutterMethodChannel?
  private var latestManualHikeStatus: ManualHikeLiveStatus?
  private var hikerBleBridge: HikerBleBridge?
  private lazy var iosHikeSafetyMonitor: IOSHikeSafetyMonitor = IOSHikeSafetyMonitor(
    warningStarted: { [weak self] in
      guard let self else { return }
      self.startFallStillnessCountdownVibration()
      self.speakFallStillnessPrompt(
        "Are you okay? Respond to the safety notification or open the safety alert in the app within 15 seconds."
      )
      self.updateLiveActivitySafetyState()
      // Foreground iOS users need the in-app, non-dismissable countdown as
      // soon as the warning begins. Previously Flutter was notified only
      // after escalation, so there was nothing visible to cancel in time.
      self.activeHikeLiveStatusChannel?.invokeMethod(
        "onNativeSafetyEvent",
        arguments: nil
      )
    },
    escalationStarted: { [weak self] in
      self?.handleNativeSosEscalationStarted()
    },
    monitoringReset: { [weak self] in
      guard let self else { return }
      self.stopSpokenPrompt()
      self.stopFallStillnessCountdownVibration()
      self.stopManualSosPattern()
      self.updateLiveActivitySafetyState()
    }
  )

  private func handleNativeSosEscalationStarted() {
    stopSpokenPrompt()
    let pendingId = iosHikeSafetyMonitor.currentEventIdentifier
    activeHikeLiveStatusChannel?.invokeMethod(
      "onNativeSafetyEvent",
      arguments: nil
    )
    updateLiveActivitySafetyState()
    // Publish the response surface before potentially blocking audio setup.
    DispatchQueue.main.async { [weak self] in
      guard let self, let pendingId,
            self.iosHikeSafetyMonitor.currentEventIdentifier == pendingId,
            !self.iosHikeSafetyMonitor.localAlarmStopped else { return }
      try? self.startManualSosPattern()
    }
  }

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
    // FlutterFire installs its own factory during registration. Override it
    // afterwards, before Firebase is configured, so native/headless calls use
    // the same signing-aware provider as Flutter.
    AppCheck.setAppCheckProviderFactory(HikerCircleAppCheckFactory())
    speechSynthesizer.delegate = self
    if let registrar = registrar(forPlugin: "QrScannerPlugin") {
      let factory = QrScannerPlatformViewFactory(messenger: registrar.messenger())
      registrar.register(factory, withId: "hiker_circle/qr_scanner")
    }
    configureSosDeviceAlertChannel()
    if let window, let controller = window.rootViewController as? FlutterViewController {
      mobileSecurityBridge = MobileSecurityBridge(window: window, messenger: controller.binaryMessenger)
    }
    configureDeepLinkChannel()
    configureHomeWidgetsChannel()
    configureSafetyNotifications()
    configureActiveHikeLiveStatusChannel()
    configureArrivalSafetyChannel()
    iosHikeSafetyMonitor.restorePersistedSessionIfNeeded()
    configureHikerBleBridge()
    if let url = launchOptions?[.url] as? URL {
      pendingDeepLink = url.absoluteString
    }
    if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      _ = handleShortcutItem(shortcutItem, notifyFlutter: false)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    iosHikeSafetyMonitor.handleAppWillTerminate()
    super.applicationWillTerminate(application)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    let handledByFlutter = super.application(app, open: url, options: options)
    if url.scheme == "hikercircle" {
      pendingDeepLink = url.absoluteString
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: url.absoluteString)
      return true
    }
    return handledByFlutter
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
      case "speakHikePrecaution":
        let arguments = call.arguments as? [String: Any]
        guard let requestId = arguments?["requestId"] as? String,
              let message = arguments?["message"] as? String else {
          result(false)
          return
        }
        self.speakHikePrecaution(requestId, message: message, result: result)
      case "stopHikePrecaution":
        let arguments = call.arguments as? [String: Any]
        if let requestId = arguments?["requestId"] as? String,
           requestId == self.hikeSpeechRequestId {
          self.completeHikeSpeech(false)
          self.speechSynthesizer.stopSpeaking(at: .immediate)
        }
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
      case "shareHike":
        self.shareHike(call, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureHomeWidgetsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "hiker_circle/home_widgets", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
      guard let json = call.arguments as? String,
            let bytes = json.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else {
        result(FlutterError(code: "invalid_widget_snapshot", message: "Invalid widget snapshot", details: nil))
        return
      }
      guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.leongziqi.hikercircle.widgets") != nil,
            let defaults = UserDefaults(suiteName: "group.com.leongziqi.hikercircle.widgets") else {
        result(FlutterError(code: "widget_app_group_unavailable", message: "Widget App Group is not configured", details: nil))
        return
      }
      defaults.set(json, forKey: "hikeWidgetSnapshot")
      WidgetCenter.shared.reloadTimelines(ofKind: "NextHikeHomeWidget")
      WidgetCenter.shared.reloadTimelines(ofKind: "HikeWeatherHomeWidget")
      WidgetCenter.shared.reloadTimelines(ofKind: "UpcomingHikesHomeWidget")
      result(nil)
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

  private func configureSafetyNotifications() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let safeAction = UNNotificationAction(
      identifier: IOSHikeSafetyMonitor.safeActionIdentifier,
      title: "I'm Safe",
      options: []
    )
    let openAction = UNNotificationAction(
      identifier: IOSHikeSafetyMonitor.openActionIdentifier,
      title: "Open HikerCircle",
      options: [.foreground]
    )
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: IOSHikeSafetyMonitor.warningCategoryIdentifier,
        actions: [safeAction, openAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: IOSHikeSafetyMonitor.monitoringStoppedCategoryIdentifier,
        actions: [openAction],
        intentIdentifiers: [],
        options: []
      ),
    ])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier.hasPrefix(HikeArrivalSafety.notificationPrefix),
       let link = response.notification.request.content.userInfo["deepLink"] as? String {
      pendingDeepLink = link
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: link)
      completionHandler()
      return
    }
    if response.actionIdentifier == IOSHikeSafetyMonitor.safeActionIdentifier {
      let eventId = response.notification.request.content.userInfo["eventId"] as? String ?? ""
      _ = iosHikeSafetyMonitor.stopTriggeredAlarm(eventId: eventId)
      var components = URLComponents()
      components.scheme = "hikercircle"
      components.host = "hike"
      components.path = "/safety-alarm-stopped"
      components.queryItems = [URLQueryItem(name: "eventId", value: eventId)]
      let deepLink = components.string ?? "hikercircle://hike/safety"
      pendingDeepLink = deepLink
      deepLinkChannel?.invokeMethod("onDeepLink", arguments: deepLink)
      completionHandler()
      return
    }
    super.userNotificationCenter(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  /// Delivers the spoken local warning in the foreground as well as while the app is backgrounded.
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier.hasPrefix(HikeArrivalSafety.notificationPrefix) {
      arrivalSafetyChannel?.invokeMethod("onArrivalSafetyChanged", arguments: nil)
      completionHandler([.banner, .list, .sound])
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  /// Keeps arrival confirmation separate from fall countdown cancellation and SOS alarm controls.
  private func configureArrivalSafetyChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "hiker_circle/arrival_safety", binaryMessenger: controller.binaryMessenger)
    arrivalSafetyChannel = channel
    HikeArrivalSafety.shared.onChanged = { [weak self] in
      self?.arrivalSafetyChannel?.invokeMethod("onArrivalSafetyChanged", arguments: nil)
    }
    channel.setMethodCallHandler { call, result in
      let data = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure": result(HikeArrivalSafety.shared.configure(data))
      case "read": result(HikeArrivalSafety.shared.read(owner: data["owner"] as? String ?? ""))
      case "confirmSafe": result(HikeArrivalSafety.shared.confirmSafe(owner: data["owner"] as? String ?? "", trackingKey: data["trackingKey"] as? String ?? ""))
      case "stop": HikeArrivalSafety.shared.stop(owner: data["owner"] as? String ?? ""); result(nil)
      default: result(FlutterMethodNotImplemented)
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
    activeHikeLiveStatusChannel = channel

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
      case "remapNativeLocationSession":
        let arguments = call.arguments as? [String: Any]
        let oldSession = arguments?["oldSessionId"] as? String ?? ""
        let newSession = arguments?["newSessionId"] as? String ?? ""
        let owner = Auth.auth().currentUser?.uid ?? ""
        do {
          let moved = try NativeLocationSampleBuffer.shared.remapSession(oldSessionId: oldSession, newSessionId: newSession, ownerUid: owner)
          self.iosHikeSafetyMonitor.remapSession(oldSession: oldSession, newSession: newSession, owner: owner)
          result(moved)
        } catch {
          result(FlutterError(code: "native_location_buffer_remap_failed", message: error.localizedDescription, details: nil))
        }
      case "getNativeLocationBufferSessions":
        do {
          result(try NativeLocationSampleBuffer.shared.pendingSessions(ownerUid: Auth.auth().currentUser?.uid ?? ""))
        } catch {
          result(FlutterError(code: "native_location_buffer_read_failed", message: error.localizedDescription, details: nil))
        }
      case "getPendingNativeLocationSamples":
        let arguments = call.arguments as? [String: Any]
        do {
          result(try NativeLocationSampleBuffer.shared.pending(
            sessionId: arguments?["sessionId"] as? String ?? "",
            ownerUid: Auth.auth().currentUser?.uid ?? "",
            limit: (arguments?["limit"] as? NSNumber)?.intValue ?? 500
          ))
        } catch {
          result(FlutterError(code: "native_location_buffer_read_failed", message: error.localizedDescription, details: nil))
        }
      case "acknowledgeNativeLocationSamples", "markNativeLocationSamplesCloudAcknowledged":
        let arguments = call.arguments as? [String: Any]
        let sessionId = arguments?["sessionId"] as? String ?? ""
        let cloud = call.method == "markNativeLocationSamplesCloudAcknowledged"
        let ids = cloud
          ? ((arguments?["sampledAtMillis"] as? [NSNumber]) ?? []).map { "\(sessionId):\($0.int64Value)" }
          : arguments?["sampleIds"] as? [String] ?? []
        do {
          result(try NativeLocationSampleBuffer.shared.acknowledge(
            sessionId: sessionId, ownerUid: Auth.auth().currentUser?.uid ?? "", sampleIds: ids, cloud: cloud
          ))
        } catch {
          result(FlutterError(code: "native_location_buffer_ack_failed", message: error.localizedDescription, details: nil))
        }
      case "getActiveHikePowerSettings":
        result(self.iosHikeSafetyMonitor.powerSettings(owner: Auth.auth().currentUser?.uid ?? ""))
      case "startOrUpdateActiveHikeLiveStatus":
        guard let status = ManualHikeLiveStatus(arguments: call.arguments) else {
          result(FlutterError(
            code: "active_hike_live_status_invalid",
            message: "Active hike status payload is invalid.",
            details: nil
          ))
          return
        }
        self.latestManualHikeStatus = status
        self.iosHikeSafetyMonitor.startOrUpdate(arguments: call.arguments)

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
        self.iosHikeSafetyMonitor.stop()
        self.latestManualHikeStatus = nil
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
      case "consumePendingSafetyEvent":
        let arguments = call.arguments as? [String: Any]
        result(self.iosHikeSafetyMonitor.pendingEvent(
          preferCurrent: arguments?["preferCurrent"] as? Bool ?? false
        ))
      case "acknowledgeSafetyEvent":
        let arguments = call.arguments as? [String: Any]
        self.iosHikeSafetyMonitor.acknowledgeEvent(
          eventId: arguments?["eventId"] as? String
        )
        result(nil)
      case "cancelNativeSafetyAlert":
        self.iosHikeSafetyMonitor.cancelAlert(reason: "Safe response received")
        result(nil)
      case "markSafetyEventDispatched":
        let arguments = call.arguments as? [String: Any]
        self.iosHikeSafetyMonitor.markDispatched(
          eventId: arguments?["eventId"] as? String,
          message: arguments?["message"] as? String
        )
        result(nil)
      case "stopTriggeredSafetyAlarm":
        let arguments = call.arguments as? [String: Any]
        result(self.iosHikeSafetyMonitor.stopTriggeredAlarm(
          eventId: arguments?["eventId"] as? String
        ))
      case "wasSafetyAlarmStopped":
        let arguments = call.arguments as? [String: Any]
        result(self.iosHikeSafetyMonitor.wasSafetyAlarmStopped(
          eventId: arguments?["eventId"] as? String
        ))
      case "getNativeSafetyStatus":
        self.iosNativeSafetyStatus(result)
      case "requestIosSafetyPermissions":
        self.requestIosSafetyPermissions(result)
      case "openBackgroundLocationSettings",
           "openFullScreenIntentSettings",
           "openOverlaySettings",
           "openIosSafetySettings":
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
          result(nil)
          return
        }
        UIApplication.shared.open(settingsUrl) { _ in result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func configureHikerBleBridge() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    hikerBleBridge = HikerBleBridge(messenger: controller.binaryMessenger)
  }

  private func iosNativeSafetyStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      guard let self else {
        result(["platform": "ios", "supported": false])
        return
      }
      let locationStatus = CLLocationManager.authorizationStatus()
      let notificationStatus: String
      switch settings.authorizationStatus {
      case .authorized: notificationStatus = "authorized"
      case .provisional: notificationStatus = "provisional"
      case .ephemeral: notificationStatus = "ephemeral"
      case .denied: notificationStatus = "denied"
      case .notDetermined: notificationStatus = "not_determined"
      @unknown default: notificationStatus = "unknown"
      }
      let timeSensitiveGranted: Bool
      if #available(iOS 15.0, *) {
        timeSensitiveGranted = settings.timeSensitiveSetting == .enabled
      } else {
        timeSensitiveGranted = false
      }
      let liveActivitiesGranted: Bool
      #if canImport(ActivityKit)
      if #available(iOS 16.1, *) {
        liveActivitiesGranted = ActivityAuthorizationInfo().areActivitiesEnabled
      } else {
        // Live Activities are not available, so they are not a blocking
        // prerequisite for the otherwise supported iOS 15 safety monitor.
        liveActivitiesGranted = true
      }
      #else
      liveActivitiesGranted = true
      #endif
      let motionStatus: String
      switch CMMotionActivityManager.authorizationStatus() {
      case .authorized: motionStatus = "authorized"
      case .denied: motionStatus = "denied"
      case .restricted: motionStatus = "restricted"
      case .notDetermined: motionStatus = "not_determined"
      @unknown default: motionStatus = "unknown"
      }
      DispatchQueue.main.async {
        result([
          "platform": "ios",
          "supported": true,
          "configured": self.iosHikeSafetyMonitor.isActive,
          "fineLocationGranted": locationStatus == .authorizedAlways
            || locationStatus == .authorizedWhenInUse,
          "backgroundLocationGranted": locationStatus == .authorizedAlways,
          "fullScreenIntentGranted": true,
          "overlayGranted": true,
          "notificationAuthorizationStatus": notificationStatus,
          "notificationsAuthorized": settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral,
          "timeSensitiveGranted": timeSensitiveGranted,
          "liveActivitiesGranted": liveActivitiesGranted,
          "motionAuthorizationStatus": motionStatus,
          "motionGranted": motionStatus == "authorized",
        ])
      }
    }
  }

  private func requestIosSafetyPermissions(_ result: @escaping FlutterResult) {
    let manager = locationManager ?? CLLocationManager()
    locationManager = manager
    manager.delegate = self
    manager.requestAlwaysAuthorization()

    if CMMotionActivityManager.isActivityAvailable() {
      let motionManager = CMMotionActivityManager()
      motionAuthorizationManager = motionManager
      motionManager.startActivityUpdates(to: .main) { [weak self] _ in
        motionManager.stopActivityUpdates()
        self?.motionAuthorizationManager = nil
      }
    }

    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "ios_safety_permission_failed",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(granted)
        }
      }
    }
  }

  private func updateLiveActivitySafetyState() {
    guard let status = latestManualHikeStatus else { return }
    #if canImport(ActivityKit)
    if #available(iOS 16.1, *) {
      Task { @MainActor in
        guard let activity = Activity<ManualHikeAttributes>.activities.first(
          where: { $0.attributes.sessionId == status.sessionId }
        ) else { return }
        await activity.update(using: status.toContentState(
          safetyPhase: self.iosHikeSafetyMonitor.safetyPhase,
          warningDeadline: self.iosHikeSafetyMonitor.warningDeadline
        ))
      }
    }
    #endif
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

    let contentState = status.toContentState(
      safetyPhase: iosHikeSafetyMonitor.safetyPhase,
      warningDeadline: iosHikeSafetyMonitor.warningDeadline
    )
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
      pendingRequirePreciseLocation = arguments["requirePrecise"] as? Bool ?? false
    } else {
      pendingAllowLastKnownLocation = false
      pendingRequirePreciseLocation = false
    }
    pendingBestLocation = nil

    switch CLLocationManager.authorizationStatus() {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedWhenInUse:
      // Active hikes and paired-button handoffs need a fresh fix while the
      // app is backgrounded. iOS may present this upgrade separately from the
      // initial When In Use grant, so request it again on a later snapshot.
      manager.requestAlwaysAuthorization()
      requestOneShotLocation()
    case .authorizedAlways:
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

    manager.desiredAccuracy = pendingRequirePreciseLocation
      ? kCLLocationAccuracyBestForNavigation
      : (isPreciseLocationEnabled ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters)
    manager.allowsBackgroundLocationUpdates =
      CLLocationManager.authorizationStatus() == .authorizedAlways
    manager.pausesLocationUpdatesAutomatically = false
    locationTimeoutTimer?.invalidate()
    locationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) {
      [weak self] _ in
      self?.completePendingLocation(
        self?.pendingBestLocation ?? self?.lastKnownLocationFallback()
      )
    }
    if pendingRequirePreciseLocation {
      manager.startUpdatingLocation()
    } else {
      manager.requestLocation()
    }
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

    presentShareItems([text], result: result)
  }

  private func shareHike(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let text = arguments["text"] as? String,
          let image = arguments["image"] as? FlutterStandardTypedData,
          !text.isEmpty, !image.data.isEmpty, image.data.count <= 5 * 1024 * 1024 else {
      result(FlutterError(code: "share_hike_missing", message: "The hike card is unavailable.", details: nil)); return
    }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hike_shares", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           modified < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
      }
      let shareDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
      let file = shareDirectory.appendingPathComponent("HikerCircle hike.png")
      try image.data.write(to: file, options: .atomic)
      presentShareItems([file, text], result: result)
    } catch {
      result(FlutterError(code: "share_hike_failed", message: "Unable to prepare the hike card.", details: nil))
    }
  }

  private func presentShareItems(_ items: [Any], result: @escaping FlutterResult) {
    let activityController = UIActivityViewController(
      activityItems: items,
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
    guard let location = locations
      .filter({ $0.horizontalAccuracy >= 0 })
      .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
      return
    }
    if pendingBestLocation == nil ||
        location.horizontalAccuracy < pendingBestLocation!.horizontalAccuracy {
      pendingBestLocation = location
    }
    if !pendingRequirePreciseLocation || location.horizontalAccuracy <= 25 {
      completePendingLocation(location)
    }
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
    locationManager?.stopUpdatingLocation()
    pendingLocationResult = nil
    pendingAllowLastKnownLocation = false
    pendingRequirePreciseLocation = false
    pendingBestLocation = nil
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
    // Urgent safety speech may interrupt a routine warning, never the reverse.
    completeHikeSpeech(false)
    speechSynthesizer.stopSpeaking(at: .immediate)

    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utterance.volume = 1.0
    safetySpeechUtterance = utterance
    speechSynthesizer.speak(utterance)
  }

  private func stopSpokenPrompt() {
    completeHikeSpeech(false)
    safetySpeechUtterance = nil
    speechSynthesizer.stopSpeaking(at: .immediate)
  }

  private func speakHikePrecaution(_ requestId: String, message: String, result: @escaping FlutterResult) {
    guard !speechSynthesizer.isSpeaking, hikeSpeechResult == nil,
          safetySpeechUtterance == nil else {
      result(false)
      return
    }
    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    utterance.volume = 1.0
    hikeSpeechRequestId = requestId
    hikeSpeechUtterance = utterance
    hikeSpeechResult = result
    speechSynthesizer.speak(utterance)
  }

  private func completeHikeSpeech(_ finished: Bool) {
    let result = hikeSpeechResult
    hikeSpeechResult = nil
    hikeSpeechRequestId = nil
    hikeSpeechUtterance = nil
    result?(finished)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    if utterance === safetySpeechUtterance { safetySpeechUtterance = nil }
    if utterance === hikeSpeechUtterance {
      completeHikeSpeech(true)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    if utterance === safetySpeechUtterance { safetySpeechUtterance = nil }
    if utterance === hikeSpeechUtterance {
      completeHikeSpeech(false)
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

private final class IOSHikeSafetyMonitor: NSObject, CLLocationManagerDelegate {
  static let warningCategoryIdentifier = "HIKER_SAFETY_WARNING"
  static let monitoringStoppedCategoryIdentifier = "HIKER_MONITORING_STOPPED"
  static let safeActionIdentifier = "HIKER_IM_SAFE"
  static let openActionIdentifier = "HIKER_OPEN_APP"

  private static let warningNotificationIdentifier = "hiker_safety_warning"
  private static let escalationNotificationIdentifier = "hiker_safety_escalated"
  private static let watchdogNotificationIdentifier = "hiker_monitoring_watchdog"
  private static let defaultsPrefix = "ios_hike_safety_"
  private static let warningDuration: TimeInterval = 15
  private static let watchdogDuration: TimeInterval = 120
  private static let locationMaximumAge: TimeInterval = 30

  private enum Phase: String {
    case monitoring
    case warning = "awaiting_response"
    case readyForFlutterDispatch = "ready_for_flutter_dispatch"
    case dispatched
  }

  private let motionManager = CMMotionManager()
  private let locationManager = CLLocationManager()
  private let motionQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.leongziqi.hikercircle.ios-hike-motion"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private let warningStarted: () -> Void
  private let escalationStarted: () -> Void
  private let monitoringReset: () -> Void
  private var timer: DispatchSourceTimer?
  private var phase: Phase = .monitoring
  private var sessionId = ""
  private var trailName = "Active hike"
  private var longestRestDuration: TimeInterval = 180
  private var batterySafetyAdjusted = false
  private var batterySafetyRevision = 0
  private var batteryOriginalSensitivity: Double?
  private var batteryOriginalInterval: TimeInterval?
  private var sensitivity = 5.0
  private var fallDetectionEnabled = true
  private var shareLiveLocation = false
  private var ownerUid = ""
  private var locationUploadInterval: TimeInterval = 60
  private var lastLocationSampleAt: Date?
  private var lastLocationUploadAt = Date()
  private var uploadingLocations = false
  // FlutterFire configures Firestore settings after the native application
  // delegate returns. A persisted monitor may resume before that happens, so
  // native telemetry must stay dormant until Flutter has restored the active
  // hike and explicitly calls startOrUpdate.
  private var firebaseTelemetryReady = false
  private var lastMotionAt = Date()
  private var referenceLocation: CLLocation?
  private var latestLocation: CLLocation?
  private var latestAccelerationMagnitude = 0.0
  private var latestRotationMagnitude = 0.0
  private var latestMotionCapturedAt = Date()
  private var lastWatchdogRefreshAt: Date?
  private var eventId: String?
  private var eventKind = "prolonged_stillness"
  private var detectedAt: Date?
  private(set) var warningDeadline: Date?
  private var triggeredAt: Date?
  private var dispatchMessage: String?
  private(set) var localAlarmStopped = false
  private var fallImpactAt: Date?
  private var fallQuietSince: Date?

  private var defaults: UserDefaults { .standard }
  private func key(_ suffix: String) -> String { Self.defaultsPrefix + suffix }

  var isActive: Bool { defaults.bool(forKey: key("active")) && !sessionId.isEmpty }
  var currentEventIdentifier: String? { eventId }
  var safetyPhase: String {
    if localAlarmStopped { return "monitoring" }
    switch phase {
    case .monitoring: return "monitoring"
    case .warning: return "warning"
    case .readyForFlutterDispatch, .dispatched: return "escalated"
    }
  }

  init(
    warningStarted: @escaping () -> Void,
    escalationStarted: @escaping () -> Void,
    monitoringReset: @escaping () -> Void
  ) {
    self.warningStarted = warningStarted
    self.escalationStarted = escalationStarted
    self.monitoringReset = monitoringReset
    super.init()
    locationManager.delegate = self
  }

  func powerSettings(owner: String) -> [String: Any]? {
    guard isActive, !owner.isEmpty, owner == ownerUid else { return nil }
    var value: [String: Any] = ["sessionId": sessionId, "batterySafetyAdjusted": batterySafetyAdjusted,
      "batterySafetyRevision": batterySafetyRevision, "sensorSensitivity": sensitivity, "intervalSeconds": Int(locationUploadInterval)]
    value["batteryOriginalSensorSensitivity"] = batteryOriginalSensitivity
    value["batteryOriginalFootprintIntervalSeconds"] = batteryOriginalInterval.map { Int($0) }
    return value
  }

  private func clearBatterySafetyState() {
    batterySafetyAdjusted = false
    batterySafetyRevision = 0
    batteryOriginalSensitivity = nil
    batteryOriginalInterval = nil
    defaults.removeObject(forKey: key("battery_safety_state"))
    defaults.removeObject(forKey: key("battery_safety_adjusted"))
  }

  // Keep the original values and effective values in one durable, hike-scoped record.
  private func persistBatterySafetyState() {
    var value: [String: Any] = ["sessionId": sessionId, "ownerUid": ownerUid,
      "active": batterySafetyAdjusted, "revision": batterySafetyRevision,
      "sensitivity": sensitivity, "interval": locationUploadInterval]
    value["originalSensitivity"] = batteryOriginalSensitivity
    value["originalInterval"] = batteryOriginalInterval
    defaults.set(value, forKey: key("battery_safety_state"))
    // Legacy keys remain readable during an upgrade from the old monitor.
    defaults.set(batterySafetyAdjusted, forKey: key("battery_safety_adjusted"))
    defaults.set(sensitivity, forKey: key("sensitivity"))
    defaults.set(locationUploadInterval, forKey: key("location_upload_interval"))
  }

  private func storedBatterySafetyState() -> [String: Any]? {
    guard let value = defaults.dictionary(forKey: key("battery_safety_state")),
          value["sessionId"] as? String == sessionId,
          value["ownerUid"] as? String == ownerUid else { return nil }
    return value
  }

  private func restoreBatterySafetyState() {
    guard let value = storedBatterySafetyState() else {
      batterySafetyAdjusted = defaults.bool(forKey: key("battery_safety_adjusted"))
      batterySafetyRevision = 0
      batteryOriginalSensitivity = nil
      batteryOriginalInterval = nil
      return
    }
    batterySafetyAdjusted = value["active"] as? Bool ?? false
    batterySafetyRevision = max(0, (value["revision"] as? NSNumber)?.intValue ?? 0)
    sensitivity = min(10, max(1, Self.doubleValue(value["sensitivity"], fallback: sensitivity)))
    locationUploadInterval = max(5, Self.doubleValue(value["interval"], fallback: locationUploadInterval))
    batteryOriginalSensitivity = (value["originalSensitivity"] as? NSNumber)?.doubleValue
    batteryOriginalInterval = (value["originalInterval"] as? NSNumber)?.doubleValue
  }

  private func mergeBatterySafetyConfiguration(_ data: [String: Any], replacingSession: Bool) {
    let stored = replacingSession ? nil : storedBatterySafetyState()
    let storedRevision = max(0, (stored?["revision"] as? NSNumber)?.intValue ?? 0)
    let storedActive = !replacingSession && (stored?["active"] as? Bool ?? defaults.bool(forKey: key("battery_safety_adjusted")))
    let incomingRevision = max(0, (data["batterySafetyRevision"] as? NSNumber)?.intValue ?? 0)
    let incomingActive = data["batterySafetyAdjusted"] as? Bool ?? false
    let legacyPending = storedActive && storedRevision == 0 && incomingRevision == 0 && !incomingActive
    if !replacingSession && (storedRevision > incomingRevision || legacyPending) {
      restoreBatterySafetyState()
      if stored == nil {
        sensitivity = min(10, max(1, defaults.double(forKey: key("sensitivity"))))
        locationUploadInterval = max(5, defaults.double(forKey: key("location_upload_interval")))
      }
      if batterySafetyAdjusted {
        batteryOriginalSensitivity = batteryOriginalSensitivity ?? (data["batteryOriginalSensorSensitivity"] as? NSNumber)?.doubleValue
        batteryOriginalInterval = batteryOriginalInterval ?? (data["batteryOriginalFootprintIntervalSeconds"] as? NSNumber)?.doubleValue
      }
    } else {
      batterySafetyRevision = incomingRevision
      batterySafetyAdjusted = incomingActive
      batteryOriginalSensitivity = incomingActive ? (data["batteryOriginalSensorSensitivity"] as? NSNumber)?.doubleValue : nil
      batteryOriginalInterval = incomingActive ? (data["batteryOriginalFootprintIntervalSeconds"] as? NSNumber)?.doubleValue : nil
    }
    persistBatterySafetyState()
  }

  private func applyBatterySafetyIfNeeded() {
    guard isActive else { return }
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    guard level >= 0, level <= 1 else { return }
    if !batterySafetyAdjusted && level < 0.30 {
      batteryOriginalSensitivity = sensitivity
      batteryOriginalInterval = locationUploadInterval
      batterySafetyAdjusted = true
      sensitivity = 5
      locationUploadInterval = 60
    } else if batterySafetyAdjusted && level > 0.30 {
      guard let originalSensitivity = batteryOriginalSensitivity,
            let originalInterval = batteryOriginalInterval else { return }
      sensitivity = min(10, max(1, originalSensitivity))
      locationUploadInterval = max(5, originalInterval)
      batterySafetyAdjusted = false
      batteryOriginalSensitivity = nil
      batteryOriginalInterval = nil
    } else { return }
    batterySafetyRevision += 1
    persistBatterySafetyState()
  }

  func startOrUpdate(arguments: Any?) {
    guard let data = arguments as? [String: Any],
          let incomingSessionId = data["sessionId"] as? String,
          !incomingSessionId.isEmpty else {
      stop()
      return
    }
    let incomingFallDetectionEnabled =
      (data["fallDetectionEnabled"] as? Bool) == true
    let incomingShareLiveLocation =
      (data["shareLiveLocation"] as? Bool) == true
    let previousSessionId = defaults.string(forKey: key("session_id"))
    let incomingOwnerUid = data["ownerUid"] as? String ?? ""
    let previousOwnerUid = defaults.string(forKey: key("owner_uid")) ?? ""
    let replacingSession = previousSessionId != incomingSessionId
      || previousOwnerUid != incomingOwnerUid
    if replacingSession {
      // A new hike must not overwrite a stopped SOS that Flutter has not yet
      // durably accepted. Keep its original owner/session in a separate receipt.
      archivePendingDispatchIfNeeded()
      if eventId != nil { monitoringReset() }
      clearEventState()
    }
    sessionId = incomingSessionId
    trailName = (data["trailName"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).nonEmpty ?? "Active hike"
    longestRestDuration = max(
      30,
      Self.doubleValue(data["longestRestMillis"]) / 1000
    )
    sensitivity = min(10, max(1, Self.doubleValue(data["sensorSensitivity"], fallback: 5)))
    fallDetectionEnabled = incomingFallDetectionEnabled
    shareLiveLocation = incomingShareLiveLocation
    ownerUid = incomingOwnerUid
    locationUploadInterval = min(86400, max(5,
      Self.doubleValue(data["locationUploadIntervalMillis"], fallback: 60000) / 1000))
    mergeBatterySafetyConfiguration(data, replacingSession: replacingSession)
    firebaseTelemetryReady = true

    if replacingSession {
      phase = .monitoring
      lastMotionAt = Date()
      clearEventState()
      latestLocation = nil
      referenceLocation = nil
      lastLocationSampleAt = nil
      lastLocationUploadAt = Date()
    } else {
      restoreState()
    }
    defaults.set(true, forKey: key("active"))
    defaults.set(sessionId, forKey: key("session_id"))
    defaults.set(trailName, forKey: key("trail_name"))
    defaults.set(longestRestDuration, forKey: key("rest_seconds"))
    defaults.set(sensitivity, forKey: key("sensitivity"))
    defaults.set(fallDetectionEnabled, forKey: key("fall_detection_enabled"))
    defaults.set(shareLiveLocation, forKey: key("share_live_location"))
    defaults.set(ownerUid, forKey: key("owner_uid"))
    defaults.set(locationUploadInterval, forKey: key("location_upload_interval"))
    persistMotionClock()
    startLocationUpdates()
    startTimer()
    if fallDetectionEnabled {
      startMotionUpdates()
      refreshTerminationWatchdog(force: true)
    } else {
      motionManager.stopDeviceMotionUpdates()
      if phase == .readyForFlutterDispatch, let eventId {
        _ = stopTriggeredAlarm(eventId: eventId)
      } else {
        clearEventState()
        phase = .monitoring
      }
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.watchdogNotificationIdentifier])
    }
    publishTelemetry(force: true)
    if fallDetectionEnabled && phase == .warning {
      warningStarted()
    } else if fallDetectionEnabled
      && !localAlarmStopped && (phase == .readyForFlutterDispatch || phase == .dispatched) {
      escalationStarted()
    }
  }

  func restorePersistedSessionIfNeeded() {
    guard let savedSessionId = defaults.string(forKey: key("session_id")),
          !savedSessionId.isEmpty else { return }
    sessionId = savedSessionId
    trailName = defaults.string(forKey: key("trail_name")) ?? "Active hike"
    longestRestDuration = max(30, defaults.double(forKey: key("rest_seconds")))
    sensitivity = min(10, max(1, defaults.double(forKey: key("sensitivity"))))
    fallDetectionEnabled = defaults.object(
      forKey: key("fall_detection_enabled")
    ) == nil || defaults.bool(forKey: key("fall_detection_enabled"))
    shareLiveLocation = defaults.bool(forKey: key("share_live_location"))
    ownerUid = defaults.string(forKey: key("owner_uid")) ?? ""
    locationUploadInterval = max(5, defaults.double(forKey: key("location_upload_interval")))
    restoreBatterySafetyState()
    restoreState()
    // Ending a hike stops tracking, but an escalated receipt may still need
    // Flutter dispatch after the process restarts.
    guard defaults.bool(forKey: key("active")) else { return }
    startLocationUpdates()
    startTimer()
    if fallDetectionEnabled {
      startMotionUpdates()
      refreshTerminationWatchdog(force: true)
    }
    publishTelemetry(force: true)
    if fallDetectionEnabled && phase == .warning {
      warningStarted()
    } else if fallDetectionEnabled
      && !localAlarmStopped && (phase == .readyForFlutterDispatch || phase == .dispatched) {
      escalationStarted()
    }
  }

  func stop() {
    motionManager.stopDeviceMotionUpdates()
    locationManager.stopUpdatingLocation()
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.stopMonitoringSignificantLocationChanges()
    }
    timer?.cancel()
    timer = nil
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [
        Self.warningNotificationIdentifier,
        Self.escalationNotificationIdentifier,
        Self.watchdogNotificationIdentifier,
      ]
    )
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [
        Self.warningNotificationIdentifier,
        Self.escalationNotificationIdentifier,
        Self.watchdogNotificationIdentifier,
      ]
    )
    defaults.set(false, forKey: key("active"))
    if phase == .readyForFlutterDispatch, eventId != nil {
      localAlarmStopped = true
      persistEventState()
    } else {
      clearEventState()
      phase = .monitoring
      sessionId = ""
    }
    fallDetectionEnabled = false
    shareLiveLocation = false
    latestLocation = nil
    referenceLocation = nil
    lastLocationSampleAt = nil
    firebaseTelemetryReady = false
    monitoringReset()
    clearBatterySafetyState()
  }

  func remapSession(oldSession: String, newSession: String, owner: String) {
    guard sessionId == oldSession, ownerUid == owner, !newSession.isEmpty else { return }
    sessionId = newSession
    persistBatterySafetyState()
    defaults.set(newSession, forKey: key("session_id"))
  }

  func handleAppWillTerminate() {
    guard isActive else { return }
    scheduleMonitoringStoppedNotification(after: 1)
  }

  func pendingEvent(preferCurrent: Bool = false) -> [String: Any]? {
    let current = currentEventPayload()
    let currentOwner = FirebaseApp.app() == nil
      ? ownerUid : (Auth.auth().currentUser?.uid ?? "")
    let archived = archivedDispatchReceipts().first { receipt in
      let receiptOwner = receipt["ownerUid"] as? String ?? ""
      if !receiptOwner.isEmpty {
        return !currentOwner.isEmpty && receiptOwner == currentOwner
      }
      // Legacy receipts lack an independent owner, so only the same active
      // session can safely recover them. Never use a later account's contacts.
      return isActive && receipt["sessionId"] as? String == sessionId
    }
    // Explicit alarm cleanup must inspect the live monitor rather than a
    // stopped receipt that is being drained in the background.
    if preferCurrent { return current ?? archived }
    // Once the live event is durable, older silent receipts can drain without
    // waiting for the hiker to stop the live alarm.
    if phase == .dispatched, let archived { return archived }
    return current ?? archived
  }

  private func currentEventPayload() -> [String: Any]? {
    guard let eventId else { return nil }
    var value: [String: Any] = [
      "eventId": eventId,
      "sessionId": sessionId,
      "ownerUid": ownerUid,
      "kind": eventKind,
      "phase": phase.rawValue,
      "detectedAtMillis": Self.millis(detectedAt),
      "deadlineAtMillis": Self.millis(warningDeadline),
      "triggeredAtMillis": Self.millis(triggeredAt),
      "localAlarmStopped": localAlarmStopped,
    ]
    if let dispatchMessage { value["dispatchMessage"] = dispatchMessage }
    return value
  }

  func cancelAlert(reason: String) {
    if phase == .readyForFlutterDispatch, let eventId {
      // A stale countdown or acknowledgement may arrive after escalation.
      // It silences local output without withdrawing the pending emergency.
      _ = stopTriggeredAlarm(eventId: eventId)
      return
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
    clearEventState()
    phase = .monitoring
    lastMotionAt = Date()
    persistMotionClock()
    if isActive { refreshTerminationWatchdog(force: true) }
    monitoringReset()
  }

  func acknowledgeEvent(eventId requestedEventId: String?) {
    guard let requestedEventId, !requestedEventId.isEmpty,
          requestedEventId == eventId else { return }
    cancelAlert(reason: "Matching safety event acknowledged")
  }

  func markDispatched(eventId requestedEventId: String?, message: String?) {
    guard let requestedEventId, !requestedEventId.isEmpty else { return }
    if requestedEventId != eventId {
      removeArchivedDispatchReceipt(eventId: requestedEventId)
      return
    }
    removeArchivedDispatchReceipt(eventId: requestedEventId)
    phase = .dispatched
    dispatchMessage = message
    persistEventState()
    if localAlarmStopped {
      // Flutter has now durably saved/sent the alert. Only now may the stopped
      // event be cleared; a quick slide must not discard pending dispatch.
      cancelAlert(reason: "Stopped alert dispatch was saved")
    }
  }

  @discardableResult
  func stopTriggeredAlarm(eventId requestedEventId: String?) -> Bool {
    guard let requestedEventId, !requestedEventId.isEmpty else { return false }
    if requestedEventId != eventId {
      // Archived receipts are already silent and remain pending until the
      // matching durable dispatch acknowledgement arrives.
      return archivedDispatchReceipts().contains {
        $0["eventId"] as? String == requestedEventId
      }
    }
    if phase == .warning {
      recordStoppedSafetyAlarm(eventId: requestedEventId)
      cancelAlert(reason: "Countdown safe response received")
      return true
    }
    guard phase == .readyForFlutterDispatch || phase == .dispatched else { return false }
    recordStoppedSafetyAlarm(eventId: requestedEventId)
    localAlarmStopped = true
    persistEventState()
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
    monitoringReset()
    if phase == .dispatched {
      cancelAlert(reason: "Dispatched alarm stopped")
    }
    return true
  }

  func wasSafetyAlarmStopped(eventId requestedEventId: String?) -> Bool {
    guard let requestedEventId, !requestedEventId.isEmpty else { return false }
    let receipts = defaults.array(forKey: key("stopped_alarm_receipts")) as? [[String: Any]] ?? []
    let currentOwner = FirebaseApp.app() == nil ? nil : Auth.auth().currentUser?.uid
    return receipts.contains {
      guard $0["eventId"] as? String == requestedEventId else { return false }
      let receiptOwner = $0["ownerUid"] as? String ?? ""
      // Legacy ownerless events remain scoped by Flutter's active session.
      return receiptOwner.isEmpty || receiptOwner == currentOwner
    }
  }

  private func recordStoppedSafetyAlarm(eventId: String) {
    var receipts = defaults.array(forKey: key("stopped_alarm_receipts")) as? [[String: Any]] ?? []
    receipts.removeAll { $0["eventId"] as? String == eventId }
    receipts.append([
      "eventId": eventId,
      "ownerUid": ownerUid,
      "stoppedAtMillis": Int64(Date().timeIntervalSince1970 * 1000),
    ])
    // Proof survives removal of the dispatch receipt, without growing forever.
    defaults.set(Array(receipts.suffix(32)), forKey: key("stopped_alarm_receipts"))
  }

  private func archivedDispatchReceipts() -> [[String: Any]] {
    defaults.array(forKey: key("pending_dispatch_receipts")) as? [[String: Any]] ?? []
  }

  private func archivePendingDispatchIfNeeded() {
    guard phase == .readyForFlutterDispatch,
          var receipt = currentEventPayload(), let eventId else { return }
    receipt["localAlarmStopped"] = true
    var receipts = archivedDispatchReceipts()
    if !receipts.contains(where: { $0["eventId"] as? String == eventId }) {
      receipts.append(receipt)
      defaults.set(receipts, forKey: key("pending_dispatch_receipts"))
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [Self.warningNotificationIdentifier, Self.escalationNotificationIdentifier]
    )
  }

  private func removeArchivedDispatchReceipt(eventId: String) {
    let receipts = archivedDispatchReceipts()
    let remaining = receipts.filter { $0["eventId"] as? String != eventId }
    guard remaining.count != receipts.count else { return }
    if remaining.isEmpty {
      defaults.removeObject(forKey: key("pending_dispatch_receipts"))
    } else {
      defaults.set(remaining, forKey: key("pending_dispatch_receipts"))
    }
  }

  private func startLocationUpdates() {
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    locationManager.distanceFilter = kCLDistanceFilterNone
    locationManager.activityType = .fitness
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.showsBackgroundLocationIndicator = true
    locationManager.allowsBackgroundLocationUpdates =
      CLLocationManager.authorizationStatus() == .authorizedAlways
    locationManager.startUpdatingLocation()
    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      locationManager.startMonitoringSignificantLocationChanges()
    }
  }

  private func startMotionUpdates() {
    guard motionManager.isDeviceMotionAvailable else { return }
    motionManager.deviceMotionUpdateInterval = 0.1
    if motionManager.isDeviceMotionActive { return }
    motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
      guard let self, let motion else { return }
      self.handleMotion(motion)
    }
  }

  private func startTimer() {
    timer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in self?.evaluateState() }
    self.timer = timer
    timer.resume()
  }

  private func handleMotion(_ motion: CMDeviceMotion) {
    guard fallDetectionEnabled else { return }
    let accelerationMagnitude = sqrt(
      pow(motion.userAcceleration.x, 2)
        + pow(motion.userAcceleration.y, 2)
        + pow(motion.userAcceleration.z, 2)
    ) * 9.80665
    let rotationMagnitude = sqrt(
      pow(motion.rotationRate.x, 2)
        + pow(motion.rotationRate.y, 2)
        + pow(motion.rotationRate.z, 2)
    )
    let totalAcceleration = sqrt(
      pow(motion.gravity.x + motion.userAcceleration.x, 2)
        + pow(motion.gravity.y + motion.userAcceleration.y, 2)
        + pow(motion.gravity.z + motion.userAcceleration.z, 2)
    ) * 9.80665
    latestAccelerationMagnitude = accelerationMagnitude
    latestRotationMagnitude = rotationMagnitude
    latestMotionCapturedAt = Date()

    let normalizedSensitivity = (sensitivity - 1) / 9
    let movementThreshold = 0.55 + (1.25 - 0.55) * normalizedSensitivity
    let impactThreshold = (5.0 + (4.0 - 5.0) * normalizedSensitivity) * 9.80665
    let meaningfulMovement = rotationMagnitude > 0.08
      || accelerationMagnitude > movementThreshold

    if totalAcceleration >= impactThreshold && phase == .monitoring {
      fallImpactAt = Date()
      fallQuietSince = nil
    }
    if let fallImpactAt {
      let age = Date().timeIntervalSince(fallImpactAt)
      if age > 60 {
        self.fallImpactAt = nil
        fallQuietSince = nil
      } else if age >= 2 {
        if rotationMagnitude <= 0.08 && accelerationMagnitude <= 0.22 {
          fallQuietSince = fallQuietSince ?? Date()
          if let quietSince = fallQuietSince,
             Date().timeIntervalSince(quietSince) >= 10 {
            self.fallImpactAt = nil
            fallQuietSince = nil
            DispatchQueue.main.async { [weak self] in
              self?.beginWarning(kind: "fall_stillness")
            }
          }
        } else {
          fallQuietSince = nil
        }
      }
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if meaningfulMovement && self.phase == .monitoring {
        self.noteMeaningfulMotion()
      }
      self.publishTelemetry()
    }
  }

  private func noteMeaningfulMotion() {
    lastMotionAt = Date()
    persistMotionClock()
    refreshTerminationWatchdog()
  }

  private func evaluateState() {
    guard isActive else { return }
    applyBatterySafetyIfNeeded()
    publishTelemetry()
    guard fallDetectionEnabled else { return }
    refreshTerminationWatchdog()
    switch phase {
    case .monitoring:
      if Date().timeIntervalSince(lastMotionAt) >= longestRestDuration {
        beginWarning(kind: "prolonged_stillness")
      }
    case .warning:
      if let warningDeadline, Date() >= warningDeadline {
        escalate()
      }
    case .readyForFlutterDispatch, .dispatched:
      break
    }
  }

  private func beginWarning(kind: String) {
    guard phase == .monitoring, isActive else { return }
    let now = Date()
    eventKind = kind
    eventId = "\(sessionId):\(kind):\(Int(now.timeIntervalSince1970 * 1000))"
    detectedAt = now
    warningDeadline = now.addingTimeInterval(Self.warningDuration)
    triggeredAt = nil
    dispatchMessage = nil
    localAlarmStopped = false
    phase = .warning
    persistEventState()
    scheduleWarningNotification()
    warningStarted()
  }

  private func escalate() {
    guard phase == .warning else { return }
    phase = .readyForFlutterDispatch
    triggeredAt = Date()
    persistEventState()
    scheduleEscalationNotification()
    escalationStarted()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard isActive else {
      manager.stopUpdatingLocation()
      manager.allowsBackgroundLocationUpdates = false
      return
    }
    let status = CLLocationManager.authorizationStatus()
    manager.allowsBackgroundLocationUpdates = status == .authorizedAlways
    if status == .authorizedAlways || status == .authorizedWhenInUse {
      manager.startUpdatingLocation()
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard isActive, let location = locations.last, isFreshLocation(location) else { return }
    if let latestLocation, location.timestamp < latestLocation.timestamp { return }
    latestLocation = location
    if let referenceLocation {
      let threshold = max(
        5,
        min(100, max(referenceLocation.horizontalAccuracy, location.horizontalAccuracy) * 1.5)
      )
      if location.distance(from: referenceLocation) > threshold {
        self.referenceLocation = location
        if fallDetectionEnabled && phase == .monitoring { noteMeaningfulMotion() }
      } else if location.horizontalAccuracy < referenceLocation.horizontalAccuracy {
        self.referenceLocation = location
      }
    } else {
      referenceLocation = location
    }
    if fallDetectionEnabled { refreshTerminationWatchdog() }
    publishTelemetry()
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    publishTelemetry()
  }

  private func isFreshLocation(_ location: CLLocation) -> Bool {
    let age = Date().timeIntervalSince(location.timestamp)
    return CLLocationCoordinate2DIsValid(location.coordinate)
      && location.coordinate.latitude.isFinite && location.coordinate.longitude.isFinite
      && location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0
      && location.horizontalAccuracy <= 500 && age >= -5 && age <= Self.locationMaximumAge
  }

  private func publishTelemetry(force: Bool = false) {
    guard isActive else { return }
    let now = Date()
    if FirebaseApp.app() != nil, Auth.auth().currentUser?.uid == ownerUid,
       UIApplication.shared.applicationState != .active,
       let location = latestLocation, isFreshLocation(location), !ownerUid.isEmpty,
       lastLocationSampleAt == nil || now.timeIntervalSince(lastLocationSampleAt!) >= locationUploadInterval {
      do {
        try NativeLocationSampleBuffer.shared.append(sessionId: sessionId, ownerUid: ownerUid,
          sampledAt: Int64(now.timeIntervalSince1970 * 1000), location: location)
        HikeArrivalSafety.shared.recordFootprint(sessionId: sessionId, owner: ownerUid, location: location)
        lastLocationSampleAt = now
      } catch {
        NSLog("HikerCircle could not persist a GPS sample: %@", error.localizedDescription)
      }
    }
    guard firebaseTelemetryReady, FirebaseApp.app() != nil,
          UIApplication.shared.applicationState != .active, !uploadingLocations,
          Auth.auth().currentUser?.uid == ownerUid,
          now.timeIntervalSince(lastLocationUploadAt) >= locationUploadInterval else { return }
    lastLocationUploadAt = now
    do {
      let sessions = try NativeLocationSampleBuffer.shared.pendingSessions(ownerUid: ownerUid, forCloud: true)
        .sorted { ($0 == sessionId ? 0 : 1) < ($1 == sessionId ? 0 : 1) }
      uploadNextLocationBatch(sessions: sessions, owner: ownerUid)
    } catch {
      NSLog("HikerCircle could not read buffered GPS sessions: %@", error.localizedDescription)
    }
  }

  private func uploadNextLocationBatch(sessions: [String], owner: String) {
    guard let session = sessions.first, !uploadingLocations, isActive,
          UIApplication.shared.applicationState != .active,
          Auth.auth().currentUser?.uid == owner else { return }
    let samples: [[String: Any]]
    do {
      samples = try NativeLocationSampleBuffer.shared.pending(sessionId: session, ownerUid: owner,
        limit: 200, forCloud: true)
    } catch {
      NSLog("HikerCircle could not read the GPS retry queue: %@", error.localizedDescription)
      return
    }
    guard !samples.isEmpty else {
      uploadNextLocationBatch(sessions: Array(sessions.dropFirst()), owner: owner)
      return
    }
    let points: [[String: Any]] = samples.map { sample in
      var point: [String: Any] = [
        "recordedAtMillis": sample["sampledAtMillis"]!,
        "fixCapturedAtMillis": sample["capturedAtMillis"]!,
        "latitude": sample["latitude"]!, "longitude": sample["longitude"]!,
        "accuracyMeters": sample["accuracyMeters"]!, "pointType": "gps",
      ]
      if let altitude = sample["altitudeMeters"] { point["altitudeMeters"] = altitude }
      return point
    }
    uploadingLocations = true
    Functions.functions(region: "us-central1").httpsCallable("appendHikeFootprints")
      .call(["sessionId": session, "footprints": points]) { [weak self] result, error in
        DispatchQueue.main.async {
          guard let self else { return }
          self.uploadingLocations = false
          guard error == nil, let payload = result?.data as? [String: Any],
                let timestamps = payload["committedRecordedAtMillis"] as? [NSNumber] else {
            NSLog("HikerCircle GPS batch retained for retry: %@", error?.localizedDescription ?? "Missing server acknowledgement")
            self.uploadNextLocationBatch(sessions: Array(sessions.dropFirst()), owner: owner)
            return
          }
          let acknowledged = Set(timestamps.map(\.int64Value))
          let ids = samples.compactMap { sample -> String? in
            guard let sampledAt = sample["sampledAtMillis"] as? Int64,
                  acknowledged.contains(sampledAt) else { return nil }
            return sample["sampleId"] as? String
          }
          do {
            try NativeLocationSampleBuffer.shared.acknowledge(sessionId: session, ownerUid: owner,
              sampleIds: ids, cloud: true)
            let remaining = ids.count == samples.count && samples.count == 200
              ? sessions : Array(sessions.dropFirst())
            self.uploadNextLocationBatch(sessions: remaining, owner: owner)
          } catch {
            NSLog("HikerCircle could not retain GPS acknowledgements: %@", error.localizedDescription)
          }
        }
      }
  }

  private func refreshTerminationWatchdog(force: Bool = false) {
    let now = Date()
    if !force, let lastWatchdogRefreshAt,
       now.timeIntervalSince(lastWatchdogRefreshAt) < 45 {
      return
    }
    lastWatchdogRefreshAt = now
    scheduleMonitoringStoppedNotification(after: Self.watchdogDuration)
  }

  private func scheduleMonitoringStoppedNotification(after delay: TimeInterval) {
    guard !sessionId.isEmpty else { return }
    let content = UNMutableNotificationContent()
    content.title = "Hike monitoring stopped"
    content.body = "HikerCircle may have been terminated during your active hike. Reopen it now to restore wellbeing monitoring."
    content.sound = .default
    content.categoryIdentifier = Self.monitoringStoppedCategoryIdentifier
    content.userInfo = [
      "type": "active_hike_monitoring_stopped",
      "sessionId": sessionId,
      "deepLink": "hikercircle://hike/active?sessionId=\(sessionId)",
    ]
    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
    let request = UNNotificationRequest(
      identifier: Self.watchdogNotificationIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
    )
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [Self.watchdogNotificationIdentifier])
    center.add(request)
  }

  private func scheduleWarningNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Are you okay?"
    content.body = "Tap I'm Safe within 15 seconds. No SOS has been sent yet."
    content.sound = .default
    content.categoryIdentifier = Self.warningCategoryIdentifier
    content.userInfo = ["eventId": eventId ?? "", "sessionId": sessionId]
    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
    let request = UNNotificationRequest(
      identifier: Self.warningNotificationIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func scheduleEscalationNotification() {
    let content = UNMutableNotificationContent()
    content.title = "SOS escalation started"
    content.body = "HikerCircle is sending your emergency alert. Open the app or tap I'm Safe to stop the physical alarm."
    content.sound = .default
    content.categoryIdentifier = Self.warningCategoryIdentifier
    content.userInfo = ["eventId": eventId ?? "", "sessionId": sessionId]
    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
    let request = UNNotificationRequest(
      identifier: Self.escalationNotificationIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func restoreState() {
    if let savedMotionAt = defaults.object(forKey: key("last_motion_at")) as? Date {
      lastMotionAt = savedMotionAt
    } else {
      lastMotionAt = Date()
    }
    phase = Phase(rawValue: defaults.string(forKey: key("phase")) ?? "") ?? .monitoring
    eventId = defaults.string(forKey: key("event_id"))
    eventKind = defaults.string(forKey: key("event_kind")) ?? "prolonged_stillness"
    detectedAt = defaults.object(forKey: key("detected_at")) as? Date
    warningDeadline = defaults.object(forKey: key("warning_deadline")) as? Date
    triggeredAt = defaults.object(forKey: key("triggered_at")) as? Date
    dispatchMessage = defaults.string(forKey: key("dispatch_message"))
    localAlarmStopped = defaults.bool(forKey: key("local_alarm_stopped"))
  }

  private func persistMotionClock() {
    defaults.set(lastMotionAt, forKey: key("last_motion_at"))
  }

  private func persistEventState() {
    defaults.set(phase.rawValue, forKey: key("phase"))
    defaults.set(eventId, forKey: key("event_id"))
    defaults.set(eventKind, forKey: key("event_kind"))
    defaults.set(detectedAt, forKey: key("detected_at"))
    defaults.set(warningDeadline, forKey: key("warning_deadline"))
    defaults.set(triggeredAt, forKey: key("triggered_at"))
    defaults.set(dispatchMessage, forKey: key("dispatch_message"))
    defaults.set(localAlarmStopped, forKey: key("local_alarm_stopped"))
  }

  private func clearEventState() {
    eventId = nil
    eventKind = "prolonged_stillness"
    detectedAt = nil
    warningDeadline = nil
    triggeredAt = nil
    dispatchMessage = nil
    localAlarmStopped = false
    for suffix in [
      "phase", "event_id", "event_kind", "detected_at",
      "warning_deadline", "triggered_at", "dispatch_message", "local_alarm_stopped",
    ] {
      defaults.removeObject(forKey: key(suffix))
    }
  }

  private static func doubleValue(_ value: Any?, fallback: Double = 0) -> Double {
    if let number = value as? NSNumber { return number.doubleValue }
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    return fallback
  }

  private static func millis(_ date: Date?) -> Int64 {
    guard let date else { return 0 }
    return Int64(date.timeIntervalSince1970 * 1000)
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
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
  func toContentState(
    safetyPhase: String = "monitoring",
    warningDeadline: Date? = nil
  ) -> ManualHikeAttributes.ContentState {
    let expectedReturnAt = expectedReturnAtMillis > 0
      ? Date(timeIntervalSince1970: expectedReturnAtMillis / 1000)
      : nil

    return ManualHikeAttributes.ContentState(
      trailName: trailName,
      startedAt: Date(timeIntervalSince1970: startedAtMillis / 1000),
      expectedReturnAt: expectedReturnAt,
      checkIns: checkIns,
      queuedUpdates: queuedUpdates,
      batteryLevel: batteryLevel,
      distanceKm: distanceKm,
      routePointCount: routePointCount,
      safetyPhase: safetyPhase,
      warningDeadline: warningDeadline
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
    var queuedUpdates: Int
    var batteryLevel: Int
    var distanceKm: Double
    var routePointCount: Int
    var safetyPhase: String
    var warningDeadline: Date?
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
