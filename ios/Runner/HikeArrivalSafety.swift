import Foundation
import CoreLocation
import UserNotifications
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions

/// Persists a hike-scoped arrival warning independently of fall detection and Flutter's lifecycle.
final class HikeArrivalSafety {
  static let shared = HikeArrivalSafety()
  static let notificationPrefix = "hiker_arrival_"
  private let storageKey = "hiker_circle_arrival_safety_v1"
  private var timer: Timer?
  private var acknowledgementInFlight = false
  private var lastAcknowledgementAttempt: Double = 0
  var onChanged: (() -> Void)?
  private var value: [String: Any] {
    get { UserDefaults.standard.dictionary(forKey: storageKey) ?? [:] }
    set {
      if !NSDictionary(dictionary: newValue).isEqual(to: value) { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
  }

  /// Keeps the same physical hike's response when a provisional tracking ID is remapped.
  func configure(_ data: [String: Any]) -> [String: Any]? {
    guard let owner = data["owner"] as? String, !owner.isEmpty,
          let tracking = data["trackingKey"] as? String, tracking.count == 64,
          let plan = data["plan"] as? [String: Any], let targets = plan["targets"] as? [[String: Any]], !targets.isEmpty else { return nil }
    var state = value
    let changed = state["owner"] as? String != owner || state["trackingKey"] as? String != tracking
    if changed {
      cancelNotification(state)
      let warning = max(number(plan["latestArrivalAtMillis"]), nowMillis())
      state = ["owner": owner, "trackingKey": tracking, "warningAtMillis": warning,
               "responseDeadlineMillis": warning + number(data["responseWindowMillis"], fallback: 300000)]
    }
    state["sessionId"] = data["sessionId"]
    state["eventId"] = data["eventId"]
    state["trailName"] = data["trailName"]
    state["plan"] = plan
    var proof = state["proof"] as? [String: Any] ?? [:]
    if let supplied = data["proof"] as? [String: Any] {
      var gates = proof["passedGates"] as? [String: Any] ?? [:]
      for (key, at) in supplied["passedGates"] as? [String: Any] ?? [:] where gates[key] == nil { gates[key] = at }
      proof["passedGates"] = gates
      if supplied["arrivedAtMillis"] != nil { proof = supplied }
    }
    state["proof"] = proof
    if let cloud = data["cloud"] as? [String: Any] {
      if let warning = cloud["warningAtMillis"] { state["warningAtMillis"] = warning }
      if let deadline = cloud["responseDeadlineMillis"] { state["responseDeadlineMillis"] = deadline }
      if let status = cloud["status"] as? String, ["safe", "arrived", "completed"].contains(status) {
        state["safe"] = true
        state["cloudAcknowledged"] = true
      }
    }
    value = state
    if timer == nil {
      timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    if state["safe"] as? Bool == true || proof["arrivedAtMillis"] != nil {
      cancelNotification(state)
      if proof["arrivedAtMillis"] != nil { acknowledgeCloudIfNeeded(state) }
    }
    else { scheduleNotificationIfNeeded() }
    tick()
    return snapshot()
  }

  /// Uses only durable recorded fixes, with the same accuracy and loop-gate rules as the cloud.
  func recordFootprint(sessionId: String, owner: String, location: CLLocation) {
    var state = value
    guard state["sessionId"] as? String == sessionId, state["owner"] as? String == owner,
          let plan = state["plan"] as? [String: Any], let targets = plan["targets"] as? [[String: Any]],
          CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy >= 0,
          location.horizontalAccuracy <= number(plan["maximumAccuracyMeters"], fallback: 100) else { return }
    let time = location.timestamp.timeIntervalSince1970 * 1000
    guard time >= number(plan["startedAtMillis"]), time <= nowMillis() + 10000 else { return }
    var proof = state["proof"] as? [String: Any] ?? [:]
    if proof["arrivedAtMillis"] != nil { acknowledgeCloudIfNeeded(state); return }
    var passed = proof["passedGates"] as? [String: Any] ?? [:]
    let radius = number(plan["radiusMeters"], fallback: 100)
    for target in targets {
      let id = target["id"] as? String ?? ""
      let gated = target["requiresGate"] as? Bool ?? false
      if gated, passed[id] == nil,
         (target["gates"] as? [[String: Any]] ?? []).contains(where: { distance(location, $0) <= radius }) { passed[id] = time }
      let gate = number(passed[id], fallback: -1)
      if (!gated || gate >= number(plan["startedAtMillis"]) && gate < time), distance(location, target) <= radius {
        proof["arrivedAtMillis"] = time
        proof["targetId"] = id
        proof["targetName"] = target["name"]
        break
      }
    }
    proof["passedGates"] = passed
    state["proof"] = proof
    value = state
    if proof["arrivedAtMillis"] != nil { cancelNotification(state); acknowledgeCloudIfNeeded(state); onChanged?() }
  }

  /// Restores only the signed-in owner's pending local confirmation.
  func read(owner: String) -> [String: Any]? { value["owner"] as? String == owner ? snapshot() : nil }

  /// Saves an explicit safe response before the app attempts authenticated cloud cancellation.
  func confirmSafe(owner: String, trackingKey: String) -> [String: Any]? {
    var state = value
    guard state["owner"] as? String == owner, state["trackingKey"] as? String == trackingKey else { return nil }
    state["safe"] = true
    state["cloudAcknowledged"] = false
    state["safeAtMillis"] = nowMillis()
    value = state
    cancelNotification(state)
    onChanged?()
    return snapshot()
  }

  /// Stops only the matching account's arrival work when its active hike ends.
  func stop(owner: String) {
    let state = value
    guard state["owner"] as? String == owner else { return }
    cancelNotification(state)
    UserDefaults.standard.removeObject(forKey: storageKey)
    timer?.invalidate(); timer = nil
  }

  /// Returns a fresh overdue decision, even after manual app launch or process termination.
  private func snapshot() -> [String: Any] {
    var state = value
    let arrived = (state["proof"] as? [String: Any])?["arrivedAtMillis"] != nil
    state["arrived"] = arrived
    state["overdue"] = !arrived && (state["safe"] as? Bool) != true && nowMillis() >= number(state["warningAtMillis"], fallback: .greatestFiniteMagnitude)
    return state
  }

  /// Wakes the foreground confirmation; the system notification remains responsible for background sound.
  private func tick() {
    var state = value
    guard snapshot()["overdue"] as? Bool == true, state["notifiedAtMillis"] == nil else { return }
    state["notifiedAtMillis"] = state["warningAtMillis"]
    value = state
    onChanged?()
  }

  /// Schedules a bundled spoken notification sound, which does not require a running Flutter isolate.
  private func scheduleNotificationIfNeeded() {
    var state = value
    guard let tracking = state["trackingKey"] as? String, let session = state["sessionId"] as? String,
          state["notifiedAtMillis"] == nil else { return }
    let warning = number(state["warningAtMillis"])
    if number(state["scheduledWarningAtMillis"], fallback: -1) == warning { return }
    let content = UNMutableNotificationContent()
    content.title = "Is everything okay?"
    content.body = "Arrival at the peak or trail end has not been confirmed. Open HikerCircle and confirm you are okay before your emergency contacts are alerted."
    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "arrival_overdue.caf"))
    var link = URLComponents()
    link.scheme = "hikercircle"; link.host = "hike"; link.path = "/arrival"
    link.queryItems = [URLQueryItem(name: "sessionId", value: session)]
    content.userInfo = ["deepLink": link.string ?? "", "type": "local_arrival_overdue"]
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, (warning - nowMillis()) / 1000), repeats: false)
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationPrefix + tracking, content: content, trigger: trigger))
    state["scheduledWarningAtMillis"] = warning
    value = state
  }

  /// Cancels both pending and delivered copies after actual arrival or an explicit confirmation.
  private func cancelNotification(_ state: [String: Any]) {
    guard let tracking = state["trackingKey"] as? String else { return }
    let ids = [Self.notificationPrefix + tracking]
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
  }

  /// A recorded arrival cancels cloud work even while Flutter is suspended.
  private func acknowledgeCloudIfNeeded(_ state: [String: Any]) {
    guard state["cloudAcknowledged"] as? Bool != true, !acknowledgementInFlight,
          nowMillis() - lastAcknowledgementAttempt >= 15000,
          FirebaseApp.app() != nil, let owner = state["owner"] as? String, Auth.auth().currentUser?.uid == owner,
          let session = state["sessionId"] as? String, let event = state["eventId"] as? String else { return }
    acknowledgementInFlight = true; lastAcknowledgementAttempt = nowMillis()
    let reason = (state["proof"] as? [String: Any])?["arrivedAtMillis"] != nil ? "recorded_arrival" : "hiker_confirmation"
    // Update cloud: confirm safe hike arrival
    Functions.functions().httpsCallable("confirmHikeArrivalSafety").call(["sessionId": session, "eventId": event, "reason": reason]) { [weak self] _, error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.acknowledgementInFlight = false
        var current = self.value
        guard error == nil, current["trackingKey"] as? String == state["trackingKey"] as? String,
              current["eventId"] as? String == event else { return }
        current["cloudAcknowledged"] = true
        self.value = current
        self.onChanged?()
      }
    }
  }

  /// Converts the validated destination into a native distance check.
  private func distance(_ location: CLLocation, _ point: [String: Any]) -> Double {
    guard let lat = point["latitude"] as? NSNumber, let lng = point["longitude"] as? NSNumber,
          abs(lat.doubleValue) <= 90, abs(lng.doubleValue) <= 180 else { return .greatestFiniteMagnitude }
    return location.distance(from: CLLocation(latitude: lat.doubleValue, longitude: lng.doubleValue))
  }

  /// Reads numeric channel values without depending on a specific integer representation.
  private func number(_ value: Any?, fallback: Double = 0) -> Double { (value as? NSNumber)?.doubleValue ?? fallback }

  /// Keeps native and cloud wall clocks in the same millisecond format.
  private func nowMillis() -> Double { Date().timeIntervalSince1970 * 1000 }
}
