// HikerCircleSecurityBridgePlugin shares Keychain keys and database migration leases across engines.
import Flutter
import Foundation
import Security

public final class HikerCircleSecurityBridgePlugin: NSObject, FlutterPlugin {
  private static let lock = NSRecursiveLock()
  private static let condition = NSCondition()
  private static var leases = [String: String]()
  private let owner = UUID().uuidString + ":"
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "hiker_circle/database_security", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HikerCircleSecurityBridgePlugin(), channel: channel)
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let data = call.arguments as? [String: Any] ?? [:]
    if call.method == "acquireDatabase" {
      guard let path = data["path"] as? String, !path.isEmpty else { result(FlutterError(code: "database-lock-unavailable", message: "Database lock unavailable.", details: nil)); return }
      let canonical = URL(fileURLWithPath: path).standardizedFileURL.path
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let owner = self?.owner else { return }
        let token = UUID().uuidString
        Self.condition.lock()
        while Self.leases[canonical] != nil && self != nil { Self.condition.wait() }
        guard self != nil else { Self.condition.unlock(); return }
        Self.leases[canonical] = owner + token
        Self.condition.unlock()
        DispatchQueue.main.async { result(token) }
      }
      return
    }
    if call.method == "releaseDatabase" {
      if let path = data["path"] as? String, let token = data["lease"] as? String {
        let canonical = URL(fileURLWithPath: path).standardizedFileURL.path
        Self.condition.lock()
        if Self.leases[canonical] == owner + token { Self.leases.removeValue(forKey: canonical); Self.condition.broadcast() }
        Self.condition.unlock()
      }
      result(nil); return
    }
    guard call.method == "databaseKey" else { result(FlutterMethodNotImplemented); return }
    do { result(try Self.key(data["name"] as? String ?? "")) }
    catch { result(FlutterError(code: "database-key-unavailable", message: "The protected local database key is unavailable.", details: nil)) }
  }
  private static func key(_ name: String) throws -> String {
    lock.lock(); defer { lock.unlock() }
    guard ["flutter-main", "native-location"].contains(name) else { throw KeyError.unavailable }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.leongziqi.hikercircle.database.v1", kSecAttrAccount as String: name,
      kSecAttrSynchronizable as String: false]
    var item: CFTypeRef?
    var read = query; read[kSecReturnData as String] = true
    let status = SecItemCopyMatching(read as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) { return key }
    guard status == errSecItemNotFound else { throw KeyError.unavailable }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw KeyError.unavailable }
    let key = bytes.map { String(format: "%02x", $0) }.joined()
    var add = query; add[kSecValueData as String] = Data(key.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(add as CFDictionary, nil)
    if added == errSecDuplicateItem { return try self.key(name) }
    guard added == errSecSuccess else { throw KeyError.unavailable }
    return key
  }
  private enum KeyError: Error { case unavailable }
  deinit {
    Self.condition.lock()
    Self.leases = Self.leases.filter { !$0.value.hasPrefix(owner) }
    Self.condition.broadcast(); Self.condition.unlock()
  }
}
