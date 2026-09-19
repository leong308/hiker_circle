// Standalone host contract test (does not request GPS, Firebase, or simulator access):
// swiftc ios/Runner/NativeLocationSampleBuffer.swift ios/RunnerTests/NativeLocationSampleBufferContract.swift -o /tmp/native-location-contract
import Foundation
import CoreLocation

@main
enum NativeLocationSampleBufferContract {
  static func main() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let database = folder.appendingPathComponent("samples.sqlite")
    let fixTime = Date(timeIntervalSince1970: 1_800_000_000)
    let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 5.42, longitude: 100.27),
      altitude: 100, horizontalAccuracy: 8, verticalAccuracy: 5, timestamp: fixTime)
    let first: Int64 = 1_800_000_005_000
    let second = first + 5000
    do {
      let buffer = NativeLocationSampleBuffer(databaseURL: database)
      try buffer.append(sessionId: "hike", ownerUid: "owner", sampledAt: first, location: fix)
      try buffer.append(sessionId: "hike", ownerUid: "owner", sampledAt: second, location: fix)
      try buffer.append(sessionId: "hike", ownerUid: "owner", sampledAt: first,
        location: CLLocation(latitude: 1, longitude: 2))
      let rows = try buffer.pending(sessionId: "hike", ownerUid: "owner")
      precondition(rows.count == 2, "Stationary samples need separate time identities; retries must deduplicate.")
      precondition(rows[0]["latitude"] as? Double == 5.42, "Duplicate sample must preserve the first payload.")
      precondition(rows[0]["capturedAtMillis"] as? Int64 == 1_800_000_000_000, "OS fix time must survive independently of sample time.")
      let wrongOwner = try buffer.pending(sessionId: "hike", ownerUid: "other")
      precondition(wrongOwner.isEmpty, "Account isolation failed.")
      try buffer.acknowledge(sessionId: "hike", ownerUid: "other", sampleIds: ["hike:\(first)"], cloud: true)
      let stillPending = try buffer.pending(sessionId: "hike", ownerUid: "owner", forCloud: true)
      precondition(stillPending.count == 2, "An unrelated account must not acknowledge samples.")
      try buffer.acknowledge(sessionId: "hike", ownerUid: "owner", sampleIds: ["hike:\(first)"], cloud: true)
      let cloudFirst = try buffer.pending(sessionId: "hike", ownerUid: "owner")
      precondition(cloudFirst.count == 2 && cloudFirst[0]["cloudAcknowledged"] as? Bool == true,
        "Cloud completion must preserve samples until Flutter imports them.")
      try buffer.acknowledge(sessionId: "hike", ownerUid: "owner", sampleIds: ["hike:\(second)"])
    }
    let reopened = NativeLocationSampleBuffer(databaseURL: database)
    let localRows = try reopened.pending(sessionId: "hike", ownerUid: "owner")
    let cloudRows = try reopened.pending(sessionId: "hike", ownerUid: "owner", forCloud: true)
    precondition(localRows.count == 1 && cloudRows.count == 1, "Both acknowledgements must survive restart independently.")
    precondition(cloudRows[0]["sampledAtMillis"] as? Int64 == second, "Local transfer must retain the cloud retry.")
    let sessions = try reopened.pendingSessions(ownerUid: "owner")
    precondition(sessions == ["hike"], "Ended-session buffers must remain discoverable.")
    try reopened.acknowledge(sessionId: "hike", ownerUid: "owner", sampleIds: ["hike:\(first)"])
    try reopened.acknowledge(sessionId: "hike", ownerUid: "owner", sampleIds: ["hike:\(second)"], cloud: true)
    let remainingLocal = try reopened.pending(sessionId: "hike", ownerUid: "owner")
    let remainingCloud = try reopened.pending(sessionId: "hike", ownerUid: "owner", forCloud: true)
    precondition(remainingLocal.isEmpty && remainingCloud.isEmpty, "Fully acknowledged samples should be released.")
    try reopened.append(sessionId: "offline", ownerUid: "owner", sampledAt: first, location: fix)
    try reopened.append(sessionId: "offline", ownerUid: "owner", sampledAt: second, location: fix)
    try reopened.acknowledge(sessionId: "offline", ownerUid: "owner", sampleIds: ["offline:\(first)"])
    try reopened.acknowledge(sessionId: "offline", ownerUid: "owner", sampleIds: ["offline:\(second)"], cloud: true)
    try reopened.append(sessionId: "canonical", ownerUid: "owner", sampledAt: first, location: fix)
    try reopened.acknowledge(sessionId: "canonical", ownerUid: "owner", sampleIds: ["canonical:\(first)"], cloud: true)
    let moved = try reopened.remapSession(oldSessionId: "offline", newSessionId: "canonical", ownerUid: "owner")
    precondition(moved == 2, "Canonical remapping must transfer every timestamp.")
    let remapped = try reopened.pending(sessionId: "canonical", ownerUid: "owner")
    let remappedCloud = try reopened.pending(sessionId: "canonical", ownerUid: "owner", forCloud: true)
    precondition(remapped.count == 1 && remapped[0]["sampleId"] as? String == "canonical:\(second)", "Local transfer must survive remapping and duplicate merges.")
    precondition(remappedCloud.count == 1 && remappedCloud[0]["sampledAtMillis"] as? Int64 == second, "Only acknowledgements for the canonical session may be preserved.")
    let repeated = try reopened.remapSession(oldSessionId: "offline", newSessionId: "canonical", ownerUid: "owner")
    precondition(repeated == 0, "Canonical remapping must be idempotent.")
    try reopened.append(sessionId: "conflict-source", ownerUid: "owner", sampledAt: first, location: fix)
    try reopened.append(sessionId: "conflict-target", ownerUid: "other", sampledAt: first, location: fix)
    do {
      _ = try reopened.remapSession(oldSessionId: "conflict-source", newSessionId: "conflict-target", ownerUid: "owner")
      preconditionFailure("Cross-account target collision must fail without losing the original sample.")
    } catch { }
    let retained = try reopened.pending(sessionId: "conflict-source", ownerUid: "owner")
    precondition(retained.count == 1, "Failed remapping must roll back atomically.")
    print("Native location buffer contract passed: stationary identity, fix timestamps, deduplication, restart, account isolation, independent acknowledgements, canonical remapping and rollback.")
  }
}
