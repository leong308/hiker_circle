// NativeLocationSampleBuffer stores encrypted GPS samples with separate local and cloud ACKs.
import Foundation
import CoreLocation
import SQLCipher

/// Two independent acknowledgements preserve both the local route and cloud retry queue.
final class NativeLocationSampleBuffer {
  static let shared = NativeLocationSampleBuffer()
  private var database: OpaquePointer?
  private let lock = NSRecursiveLock()
  private let databaseURL: URL?
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  // An injected URL lets the persistence contract run against a temporary real SQLite file.
  init(databaseURL: URL? = nil) { self.databaseURL = databaseURL }
  deinit { if let database { sqlite3_close(database) } }

  private struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  // connection: Open the encrypted GPS buffer under the shared migration lease.
  private func connection() throws -> OpaquePointer {
    if let database { return database }
    let url: URL
    if let databaseURL { url = databaseURL }
    else {
      let directory = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
      url = directory.appendingPathComponent("native_hike_locations_encrypted.sqlite")
      try migratePlaintextIfNeeded(from: directory.appendingPathComponent("native_hike_locations.sqlite"), to: url)
    }
    let key = try LocalDatabaseKeyStore.key("native-location")
    var opened: OpaquePointer?
    guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
          let opened else {
      if let opened { sqlite3_close(opened) }
      throw DatabaseError(message: "Unable to open the native GPS buffer.")
    }
    database = opened
    let keyed = key.utf8CString.withUnsafeBufferPointer { bytes in
      sqlite3_key(opened, bytes.baseAddress, Int32(bytes.count - 1))
    }
    guard keyed == SQLITE_OK else {
      sqlite3_close(opened); database = nil
      throw DatabaseError(message: "The native GPS encryption key is unavailable.")
    }
    sqlite3_busy_timeout(opened, 5000)
    do {
      try execute("PRAGMA journal_mode=WAL")
      try execute("""
        CREATE TABLE IF NOT EXISTS samples (
          sample_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, owner_uid TEXT NOT NULL,
          sampled_at INTEGER NOT NULL, captured_at INTEGER NOT NULL,
          latitude REAL NOT NULL, longitude REAL NOT NULL, accuracy REAL NOT NULL,
          altitude REAL, speed REAL, local_transferred INTEGER NOT NULL DEFAULT 0,
          cloud_acknowledged INTEGER NOT NULL DEFAULT 0)
        """)
      try execute("CREATE INDEX IF NOT EXISTS samples_session_time ON samples(session_id, owner_uid, sampled_at)")
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
      var protectedURL = url
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try protectedURL.setResourceValues(values)
    } catch {
      sqlite3_close(opened)
      database = nil
      throw error
    }
    return opened
  }

  // migratePlaintextIfNeeded: Verify the SQLCipher export before removing the original plaintext buffer.
  private func migratePlaintextIfNeeded(from original: URL, to target: URL) throws {
    let files = FileManager.default
    let key = try LocalDatabaseKeyStore.key("native-location")
    func open(_ url: URL, password: String?) throws -> OpaquePointer {
      var db: OpaquePointer?
      guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
        if let db { sqlite3_close(db) }
        throw DatabaseError(message: "Unable to open the native GPS migration source.")
      }
      if let password {
        let status = password.utf8CString.withUnsafeBufferPointer { sqlite3_key(db, $0.baseAddress, Int32($0.count - 1)) }
        guard status == SQLITE_OK else { sqlite3_close(db); throw DatabaseError(message: "GPS migration key failed.") }
      }
      return db
    }
    func run(_ db: OpaquePointer, _ sql: String) throws {
      guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError(message: "The native GPS encryption migration failed.") }
    }
    func removeOriginal() throws {
      for suffix in ["", "-wal", "-shm", "-journal"] {
        let path = original.path + suffix
        if files.fileExists(atPath: path) { try files.removeItem(atPath: path) }
      }
    }
    if files.fileExists(atPath: target.path) {
      let db = try open(target, password: key); defer { sqlite3_close(db) }
      try run(db, "SELECT count(*) FROM sqlite_master")
      try removeOriginal()
      return
    }
    guard files.fileExists(atPath: original.path) else { return }
    let pending = URL(fileURLWithPath: target.path + ".pending")
    if files.fileExists(atPath: pending.path) { try files.removeItem(at: pending) }
    let source = try open(original, password: nil)
    do {
      try run(source, "PRAGMA wal_checkpoint(TRUNCATE)")
      let path = pending.path.replacingOccurrences(of: "'", with: "''")
      try run(source, "ATTACH DATABASE '\(path)' AS encrypted KEY '\(key)'")
      try run(source, "SELECT sqlcipher_export('encrypted')")
      try run(source, "DETACH DATABASE encrypted")
      sqlite3_close(source)
    } catch { sqlite3_close(source); throw error }
    let encrypted = try open(pending, password: key)
    do { try run(encrypted, "SELECT count(*) FROM samples"); sqlite3_close(encrypted) }
    catch { sqlite3_close(encrypted); throw error }
    try files.moveItem(at: pending, to: target)
    try removeOriginal()
  }

  private func execute(_ sql: String, values: [Any?] = []) throws {
    let db = try connection()
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else { throw DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    let status = sqlite3_step(statement)
    guard status == SQLITE_DONE || status == SQLITE_ROW else {
      throw DatabaseError(message: String(cString: sqlite3_errmsg(db)))
    }
  }

  private func bind(_ values: [Any?], to statement: OpaquePointer) throws {
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      switch value {
      case let value as String: status = sqlite3_bind_text(statement, index, value, -1, transient)
      case let value as Int64: status = sqlite3_bind_int64(statement, index, value)
      case let value as Int: status = sqlite3_bind_int64(statement, index, Int64(value))
      case let value as Double: status = sqlite3_bind_double(statement, index, value)
      default: status = sqlite3_bind_null(statement, index)
      }
      if status != SQLITE_OK { throw DatabaseError(message: "Unable to bind a GPS buffer value.") }
    }
  }

  func append(sessionId: String, ownerUid: String, sampledAt: Int64, location: CLLocation) throws {
    guard !sessionId.isEmpty, !ownerUid.isEmpty else { return }
    lock.lock(); defer { lock.unlock() }
    try execute("""
      INSERT OR IGNORE INTO samples (sample_id, session_id, owner_uid, sampled_at,
        captured_at, latitude, longitude, accuracy, altitude, speed) VALUES (?,?,?,?,?,?,?,?,?,?)
      """, values: ["\(sessionId):\(sampledAt)", sessionId, ownerUid, sampledAt,
        Int64(location.timestamp.timeIntervalSince1970 * 1000), location.coordinate.latitude,
        location.coordinate.longitude, location.horizontalAccuracy,
        location.verticalAccuracy >= 0 && location.altitude.isFinite && (-1000...100000).contains(location.altitude) ? location.altitude : nil,
        location.speed >= 0 && location.speed.isFinite ? location.speed : nil])
  }

  func pendingSessions(ownerUid: String, forCloud: Bool = false) throws -> [String] {
    guard !ownerUid.isEmpty else { return [] }
    lock.lock(); defer { lock.unlock() }
    let db = try connection()
    let flag = forCloud ? "cloud_acknowledged" : "local_transferred"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT session_id FROM samples WHERE owner_uid=? AND \(flag)=0 GROUP BY session_id ORDER BY MIN(sampled_at)", -1, &statement, nil) == SQLITE_OK,
          let statement else { throw DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(statement) }
    try bind([ownerUid], to: statement)
    var sessions: [String] = []
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW {
      sessions.append(String(cString: sqlite3_column_text(statement, 0)))
      status = sqlite3_step(statement)
    }
    guard status == SQLITE_DONE else { throw DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    return sessions
  }

  func remapSession(oldSessionId: String, newSessionId: String, ownerUid: String) throws -> Int {
    guard !oldSessionId.isEmpty, !newSessionId.isEmpty, !ownerUid.isEmpty else {
      throw DatabaseError(message: "A signed-in owner and both session identities are required.")
    }
    guard oldSessionId != newSessionId else { return 0 }
    lock.lock(); defer { lock.unlock() }
    let db = try connection()
    try execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      try execute("""
        INSERT OR IGNORE INTO samples (sample_id,session_id,owner_uid,sampled_at,captured_at,
          latitude,longitude,accuracy,altitude,speed,local_transferred,cloud_acknowledged)
        SELECT ? || ':' || sampled_at, ?, owner_uid,sampled_at,captured_at,latitude,longitude,
          accuracy,altitude,speed,local_transferred,0 FROM samples WHERE session_id=? AND owner_uid=?
        """, values: [newSessionId, newSessionId, oldSessionId, ownerUid])
      try execute("""
        UPDATE samples SET local_transferred=MAX(local_transferred, COALESCE(
          (SELECT original.local_transferred FROM samples original WHERE original.session_id=?
            AND original.owner_uid=? AND original.sampled_at=samples.sampled_at),0))
        WHERE session_id=? AND owner_uid=?
        """, values: [oldSessionId, ownerUid, newSessionId, ownerUid])
      var statement: OpaquePointer?
      let check = "SELECT COUNT(*) FROM samples original LEFT JOIN samples destination ON destination.session_id=? AND destination.owner_uid=original.owner_uid AND destination.sampled_at=original.sampled_at WHERE original.session_id=? AND original.owner_uid=? AND destination.sample_id IS NULL"
      guard sqlite3_prepare_v2(db, check, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw DatabaseError(message: String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      try bind([newSessionId, oldSessionId, ownerUid], to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_int(statement, 0) == 0 else {
        throw DatabaseError(message: "The target GPS session belongs to another account.")
      }
      try execute("DELETE FROM samples WHERE session_id=? AND owner_uid=?", values: [oldSessionId, ownerUid])
      let moved = Int(sqlite3_changes(db))
      try execute("COMMIT")
      return moved
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  // pending: Read this account's ordered batch for local import or cloud upload.
  func pending(sessionId: String, ownerUid: String, limit: Int = 500, forCloud: Bool = false) throws -> [[String: Any]] {
    guard !sessionId.isEmpty, !ownerUid.isEmpty else { return [] }
    lock.lock(); defer { lock.unlock() }
    let db = try connection()
    let flag = forCloud ? "cloud_acknowledged" : "local_transferred"
    let sql = "SELECT sample_id,session_id,sampled_at,captured_at,latitude,longitude,accuracy,altitude,speed,cloud_acknowledged FROM samples WHERE session_id=? AND owner_uid=? AND \(flag)=0 ORDER BY sampled_at LIMIT ?"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
          let statement else { throw DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    defer { sqlite3_finalize(statement) }
    try bind([sessionId, ownerUid, min(500, max(1, limit))], to: statement)
    var rows: [[String: Any]] = []
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW {
      var row: [String: Any] = [
        "sampleId": String(cString: sqlite3_column_text(statement, 0)),
        "sessionId": String(cString: sqlite3_column_text(statement, 1)),
        "sampledAtMillis": sqlite3_column_int64(statement, 2),
        "capturedAtMillis": sqlite3_column_int64(statement, 3),
        "latitude": sqlite3_column_double(statement, 4),
        "longitude": sqlite3_column_double(statement, 5),
        "accuracyMeters": sqlite3_column_double(statement, 6),
        "cloudAcknowledged": sqlite3_column_int(statement, 9) == 1,
      ]
      if sqlite3_column_type(statement, 7) != SQLITE_NULL { row["altitudeMeters"] = sqlite3_column_double(statement, 7) }
      if sqlite3_column_type(statement, 8) != SQLITE_NULL { row["speedMetersPerSecond"] = sqlite3_column_double(statement, 8) }
      rows.append(row)
      status = sqlite3_step(statement)
    }
    guard status == SQLITE_DONE else { throw DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    return rows
  }

  @discardableResult
  // acknowledge: Keep each sample until both independent consumers have acknowledged it.
  func acknowledge(sessionId: String, ownerUid: String, sampleIds: [String], cloud: Bool = false) throws -> Int {
    guard !sessionId.isEmpty, !ownerUid.isEmpty, !sampleIds.isEmpty else { return 0 }
    lock.lock(); defer { lock.unlock() }
    let db = try connection()
    let flag = cloud ? "cloud_acknowledged" : "local_transferred"
    try execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      var changed = 0
      for sampleId in Set(sampleIds) {
        try execute("UPDATE samples SET \(flag)=1 WHERE session_id=? AND owner_uid=? AND sample_id=?",
          values: [sessionId, ownerUid, sampleId])
        changed += Int(sqlite3_changes(db))
      }
      try execute("DELETE FROM samples WHERE local_transferred=1 AND cloud_acknowledged=1")
      try execute("COMMIT")
      return changed
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
}
