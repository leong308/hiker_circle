// MobileSecurityBridge supplies Keychain keys, device identity, and capture-state covering.
import Flutter
import UIKit
import Security
import FirebaseCore
import FirebaseAppCheck
import DeviceCheck

final class HikerCircleAppCheckFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    #if DEBUG
      return AppCheckDebugProvider(app: app)
    #else
      if DCAppAttestService.shared.isSupported { return AppAttestProvider(app: app) }
      return DeviceCheckProvider(app: app)
    #endif
  }
}

enum LocalDatabaseKeyStore {
  private static let lock = NSRecursiveLock()
  static func key(_ name: String) throws -> String {
    lock.lock(); defer { lock.unlock() }
    guard ["flutter-main", "native-location"].contains(name) else { throw KeyError.unavailable }
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.leongziqi.hikercircle.database.v1",
      kSecAttrAccount as String: name, kSecAttrSynchronizable as String: false]
    var item: CFTypeRef?
    var read = query
    read[kSecReturnData as String] = true
    let status = SecItemCopyMatching(read as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) { return key }
    guard status == errSecItemNotFound else { throw KeyError.unavailable }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw KeyError.unavailable }
    let key = bytes.map { String(format: "%02x", $0) }.joined()
    var add = query
    add[kSecValueData as String] = Data(key.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(add as CFDictionary, nil)
    if added == errSecDuplicateItem { return try self.key(name) }
    guard added == errSecSuccess else { throw KeyError.unavailable }
    return key
  }
  enum KeyError: Error { case unavailable }
}

final class MobileSecurityBridge {
  private weak var window: UIWindow?
  private var protectedRoutes = Set<String>()
  private var observers: [NSObjectProtocol] = []
  private let cover = UIView()
  private var inactive = false
  private let channel: FlutterMethodChannel

  init(window: UIWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    cover.backgroundColor = .black
    cover.isUserInteractionEnabled = true
    cover.accessibilityLabel = "Password page hidden during capture"
    channel = FlutterMethodChannel(name: "hiker_circle/security", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let data = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "deviceInfo": result(["name": UIDevice.current.model, "platform": "ios"])
      case "databaseKey":
        do { result(try LocalDatabaseKeyStore.key(data["name"] as? String ?? "")) }
        catch { result(FlutterError(code: "database-key-unavailable", message: "The protected local database key is unavailable.", details: nil)) }
      case "protectPasswordPage":
        let route = data["route"] as? String ?? ""
        if data["enabled"] as? Bool == true { self.protectedRoutes.insert(route) }
        else { self.protectedRoutes.remove(route) }
        self.updateCover()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateCover() })
    observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.inactive = true; self?.updateCover() })
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.inactive = false; self?.updateCover() })
  }
  private func updateCover() {
    guard let window else { return }
    // Supported capture-state response; this does not claim to block still screenshots.
    if !protectedRoutes.isEmpty && (inactive || window.screen.isCaptured) {
      cover.frame = window.bounds
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(cover)
      window.bringSubviewToFront(cover)
    } else { cover.removeFromSuperview() }
  }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
