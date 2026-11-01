import Foundation

/// Fixed local presence timing, independent of page visits and old warning preferences.
enum SosButtonPresencePolicy {
  static let absenceMillis: Int64 = 3_600_000
  /// Ignore future clock values while retaining the most recent real observation.
  static func reference(lastSeen: Int64?, pairedAt: Int64, now: Int64) -> Int64 {
    min(lastSeen ?? pairedAt, now)
  }
  /// Restore the remaining interval instead of starting a fresh hour on restart.
  static func remaining(lastSeen: Int64?, pairedAt: Int64, now: Int64) -> Int64 {
    max(0, reference(lastSeen: lastSeen, pairedAt: pairedAt, now: now) + absenceMillis - now)
  }
  /// Suppress routine heartbeats after the first successful detection.
  static func announceSeen(previous: Int64?, announced: Bool, now: Int64) -> Bool {
    !announced || previous == nil || now - previous! >= absenceMillis
  }
}

/// Durable owner-scoped local notices survive a suspended Flutter engine.
final class SosButtonNoticeStore {
  private let defaults: UserDefaults
  private let historyKey = "hiker_circle.button_presence_history.v1"
  /// Allows isolated persistence tests without accessing production preferences.
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  /// Separate notification cycles by account, button and physical pairing.
  func key(owner: String, device: String, pairedAt: Int64) -> String { "\(owner).\(device).\(pairedAt)" }
  /// Keep first-detection acknowledgement across process restarts.
  func hasAnnounced(_ key: String) -> Bool { defaults.bool(forKey: "button_seen.\(key)") }
  /// Record first detection before presenting the local alert.
  func markAnnounced(_ key: String) { defaults.set(true, forKey: "button_seen.\(key)") }
  /// Identify the absence deadline already submitted to the operating system.
  func scheduledReference(_ key: String) -> Int64? { (defaults.object(forKey: "button_schedule.\(key)") as? NSNumber)?.int64Value }
  /// Persist only an accepted operating-system schedule.
  func markScheduled(_ key: String, reference: Int64) { defaults.set(reference, forKey: "button_schedule.\(key)") }
  private var records: [[String: Any]] { defaults.array(forKey: historyKey) as? [[String: Any]] ?? [] }
  @discardableResult
  /// Deduplicate native notice records before handing them to Flutter.
  func append(owner: String, id: String, title: String, body: String, type: String, at: Int64) -> [String: Any]? {
    var all = records
    if all.contains(where: { $0["messageId"] as? String == id }) { return nil }
    let note: [String: Any] = ["ownerScope": owner, "messageId": id, "title": title,
      "body": body, "type": type, "receivedAtMillis": at,
      "deepLink": "hikercircle://sos/device-settings?source=button_presence"]
    all.append(note)
    defaults.set(Array(all.suffix(128)), forKey: historyKey)
    return note
  }
  /// Keep the warning watermark after history acknowledgement to prevent duplicate alerts.
  func recordLost(owner: String, key: String, name: String, reference: Int64, now: Int64) -> [String: Any]? {
    guard now - reference >= SosButtonPresencePolicy.absenceMillis else { return nil }
    let marker = "button_lost_recorded.\(key)"
    if (defaults.object(forKey: marker) as? NSNumber)?.int64Value == reference { return nil }
    let result = append(owner: owner, id: "button_unseen:\(key):\(reference)", title: "SOS button not seen",
      body: "HikerCircle has not detected \(name) for 1 hour. Check its power and keep it nearby.",
      type: "sos_button_unseen", at: reference + SosButtonPresencePolicy.absenceMillis)
    defaults.set(reference, forKey: marker)
    return result
  }
  /// Return records belonging only to the requesting account.
  func notices(owner: String) -> [[String: Any]] { records.filter { $0["ownerScope"] as? String == owner } }
  /// Drop records only after their SQLite history copy is confirmed.
  func acknowledge(owner: String, ids: Set<String>) {
    defaults.set(records.filter { !($0["ownerScope"] as? String == owner && ids.contains($0["messageId"] as? String ?? "")) }, forKey: historyKey)
  }
}
