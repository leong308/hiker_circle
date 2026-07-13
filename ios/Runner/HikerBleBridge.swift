import CoreBluetooth
import CryptoKit
import Flutter
import Security
import UIKit

final class HikerBleBridge: NSObject, FlutterStreamHandler {
  private enum AdvertisementMode {
    case none
    case sosHelp
    case teamLocation
  }

  private enum PendingReadKind {
    case sosHelp
    case teamLocation
  }

  private struct PairedButtonRecord: Codable {
    let deviceIdHex: String
    let displayName: String
    let pairedAtMillis: Int64
    var lastSeenAtMillis: Int64?
    var lastAcceptedEventId: UInt32?
    let pairingSecret: Data
    let peripheralIdentifier: UUID
  }

  private static let pairedButtonsKeychainService = "hiker_circle.paired_sos_buttons"
  private static let pairedButtonsKeychainAccount = "registry.v1"

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private lazy var centralManager = CBCentralManager(
    delegate: self,
    queue: .main,
    options: [
      CBCentralManagerOptionShowPowerAlertKey: true,
      CBCentralManagerOptionRestoreIdentifierKey: "hiker_circle_ble_central"
    ]
  )
  private lazy var peripheralManager = CBPeripheralManager(
    delegate: self,
    queue: .main,
    options: [
      CBPeripheralManagerOptionShowPowerAlertKey: true,
      CBPeripheralManagerOptionRestoreIdentifierKey: "hiker_circle_ble_peripheral"
    ]
  )
  private var sosHelpCharacteristic: CBMutableCharacteristic?
  private var teamLocationCharacteristic: CBMutableCharacteristic?
  private var didInstallGattServices = false
  private var isSosMonitorRequested = false
  private var isTeamExchangeRequested = false
  private var latestTeamPayload: [String: Any]?
  private var latestTeamPacket: Data?
  private var latestSosHelpPacket: Data?
  private var advertisedMode = AdvertisementMode.none
  private var sosHelpStopTimer: Timer?
  private var handledEventIds = Set<String>()
  private var handledEventIdOrder: [String] = []
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var pendingReadKinds: [UUID: PendingReadKind] = [:]
  private var pendingRssi: [UUID: Int] = [:]
  private var pairedButtons: [PairedButtonRecord] = []
  private var pairingSetupRequested = false
  private var pairingPeripheral: CBPeripheral?
  private var pairingDeviceId: Data?
  private var pairingSecret: Data?
  private var pairingDisplayName: String?
  private var pairingResult: FlutterResult?
  private var pairingTimeout: Timer?
  private var pairingRequestCharacteristic: CBCharacteristic?
  private var pairingStatusCharacteristic: CBCharacteristic?
  private var locationPeripheral: CBPeripheral?
  private var locationPayload: Data?
  private var locationResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "hiker_circle/ble_bridge",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "hiker_circle/ble_events",
      binaryMessenger: messenger
    )
    super.init()
    pairedButtons = loadPairedButtons()
    methodChannel.setMethodCallHandler(handleMethodCall)
    eventChannel.setStreamHandler(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    stopScanIfIdle()
    stopAdvertising()
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      _ = centralManager
      result(true)
    case "startSosButtonMonitor":
      isSosMonitorRequested = true
      _ = centralManager
      startScanIfReady()
      result(nil)
    case "stopSosButtonMonitor":
      isSosMonitorRequested = false
      stopScanIfIdle()
      result(nil)
    case "startPairedButtonSetupScan":
      pairingSetupRequested = true
      _ = centralManager
      startScanIfReady()
      result(nil)
    case "stopPairedButtonSetupScan":
      pairingSetupRequested = false
      stopScanIfIdle()
      result(nil)
    case "pairSosButton":
      guard let arguments = call.arguments as? [String: Any],
            let address = arguments["address"] as? String,
            let displayName = arguments["displayName"] as? String else {
        result(FlutterError(code: "paired_button_invalid_request", message: "A button address and display name are required.", details: nil))
        return
      }
      beginPairing(address: address, displayName: displayName, result: result)
    case "listPairedSosButtons":
      result(pairedButtons.map { button in
        [
          "deviceId": button.deviceIdHex,
          "displayName": button.displayName,
          "pairedAtMillis": button.pairedAtMillis,
          "lastSeenAtMillis": button.lastSeenAtMillis,
          "lastAcceptedEventId": button.lastAcceptedEventId,
        ]
      })
    case "unpairSosButton":
      let deviceId = (call.arguments as? [String: Any])?["deviceId"] as? String ?? ""
      let before = pairedButtons.count
      pairedButtons.removeAll { $0.deviceIdHex == deviceId.uppercased() }
      savePairedButtons()
      result(before != pairedButtons.count)
    case "sendPairedSosLocation":
      sendPairedSosLocation(call: call, result: result)
    case "broadcastPhysicalSosTest":
      guard let payload = sosHelpPayload(from: call) else {
        result(FlutterError(
          code: "ble_sos_test_invalid",
          message: "Physical SOS test payload is invalid.",
          details: nil
        ))
        return
      }
      let packet = HikerBleProtocol.encodeSosHelpBeacon(payload)
      latestSosHelpPacket = packet
      _ = peripheralManager
      advertiseSosHelp(durationMillis: payload.durationMillis)
      result(nil)
    case "startTeamLocationExchange", "updateTeamLocation":
      guard let payload = teamPayload(from: call) else {
        result(FlutterError(
          code: "ble_team_location_invalid",
          message: "Team BLE location payload is invalid.",
          details: nil
        ))
        return
      }
      latestTeamPayload = payload.raw
      latestTeamPacket = HikerBleProtocol.encodeTeamLocation(payload)
      isTeamExchangeRequested = true
      _ = centralManager
      _ = peripheralManager
      startScanIfReady()
      advertiseTeamLocationIfReady()
      result(nil)
    case "stopTeamLocationExchange":
      isTeamExchangeRequested = false
      latestTeamPayload = nil
      latestTeamPacket = nil
      stopScanIfIdle()
      if advertisedMode == .teamLocation {
        stopAdvertising()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func applicationDidBecomeActive() {
    startScanIfReady()
  }

  @objc private func applicationDidEnterBackground() {
    startScanIfReady()
  }

  private func startScanIfReady() {
    guard centralManager.state == .poweredOn else {
      emitStatus("ios_ble_scan_waiting", message: centralStateMessage)
      return
    }
    guard isSosMonitorRequested || isTeamExchangeRequested || pairingSetupRequested else {
      return
    }
    if centralManager.isScanning {
      centralManager.stopScan()
    }
    // The physical ESP32 button uses the compact manufacturer packet rather
    // than a 128-bit service UUID, so filtering by service UUID here makes
    // the button invisible whenever iOS applies the background scan path.
    // Core Bluetooth throttles background scans itself; leave discovery
    // unfiltered so handleAdvertisement can validate the manufacturer ID and
    // packet signature safely.
    centralManager.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    )
    emitStatus("ios_ble_scan_started")
  }

  private func stopScanIfIdle() {
    guard !isSosMonitorRequested && !isTeamExchangeRequested && !pairingSetupRequested else {
      return
    }
    if centralManager.isScanning {
      centralManager.stopScan()
      emitStatus("ios_ble_scan_stopped")
    }
  }

  private func advertiseSosHelp(durationMillis: Int64) {
    sosHelpStopTimer?.invalidate()
    let duration = max(3000, min(8000, durationMillis))
    guard peripheralManager.state == .poweredOn else {
      emitStatus("ios_ble_sos_test_waiting", message: peripheralStateMessage)
      return
    }
    installGattServicesIfNeeded()
    startAdvertising(.sosHelp)
    sosHelpStopTimer = Timer.scheduledTimer(withTimeInterval: Double(duration) / 1000.0, repeats: false) {
      [weak self] _ in
      self?.stopSosHelpAdvertising()
    }
  }

  private func stopSosHelpAdvertising() {
    sosHelpStopTimer?.invalidate()
    sosHelpStopTimer = nil
    latestSosHelpPacket = nil
    if advertisedMode == .sosHelp {
      stopAdvertising()
    }
    advertiseTeamLocationIfReady()
  }

  private func advertiseTeamLocationIfReady() {
    guard isTeamExchangeRequested, latestTeamPacket != nil else {
      return
    }
    guard latestSosHelpPacket == nil else {
      return
    }
    guard peripheralManager.state == .poweredOn else {
      emitStatus("ios_team_ble_waiting", message: peripheralStateMessage)
      return
    }
    installGattServicesIfNeeded()
    startAdvertising(.teamLocation)
  }

  private func startAdvertising(_ mode: AdvertisementMode) {
    if peripheralManager.isAdvertising {
      peripheralManager.stopAdvertising()
    }
    let serviceUuid: CBUUID
    let status: String
    switch mode {
    case .sosHelp:
      serviceUuid = HikerBleProtocol.sosHelpServiceUUID
      status = "ios_ble_sos_test_advertising_started"
    case .teamLocation:
      serviceUuid = HikerBleProtocol.teamLocationServiceUUID
      status = "ios_team_ble_advertising_started"
    case .none:
      return
    }
    advertisedMode = mode
    peripheralManager.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [serviceUuid]
    ])
    emitStatus(status)
  }

  private func stopAdvertising() {
    if peripheralManager.isAdvertising {
      peripheralManager.stopAdvertising()
    }
    advertisedMode = .none
  }

  private func installGattServicesIfNeeded() {
    guard !didInstallGattServices else {
      return
    }
    let helpCharacteristic = CBMutableCharacteristic(
      type: HikerBleProtocol.sosHelpCharacteristicUUID,
      properties: [.read],
      value: nil,
      permissions: [.readable]
    )
    let helpService = CBMutableService(
      type: HikerBleProtocol.sosHelpServiceUUID,
      primary: true
    )
    helpService.characteristics = [helpCharacteristic]

    let teamCharacteristic = CBMutableCharacteristic(
      type: HikerBleProtocol.teamLocationCharacteristicUUID,
      properties: [.read],
      value: nil,
      permissions: [.readable]
    )
    let teamService = CBMutableService(
      type: HikerBleProtocol.teamLocationServiceUUID,
      primary: true
    )
    teamService.characteristics = [teamCharacteristic]

    sosHelpCharacteristic = helpCharacteristic
    teamLocationCharacteristic = teamCharacteristic
    peripheralManager.add(helpService)
    peripheralManager.add(teamService)
    didInstallGattServices = true
  }

  private func handleAdvertisement(
    peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    let rssiValue = rssi.intValue
    if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
       let payload = HikerBleProtocol.manufacturerPayload(from: manufacturerData) {
      if let help = HikerBleProtocol.decodeSosHelpBeacon(payload, rssi: rssiValue) {
        emitSosHelp(help)
        return
      }
      if let team = HikerBleProtocol.decodeTeamLocation(payload, rssi: rssiValue) {
        emitTeamLocation(team)
        return
      }
      if let paired = HikerBleProtocol.decodePairedSosRemote(payload, rssi: rssiValue) {
        if let owner = pairedButtons.first(where: { $0.deviceIdHex == paired.deviceIdHex }),
           verifyPairedTag(owner: owner, packet: paired),
           !isReplay(owner: owner, eventId: paired.eventId) {
          markAccepted(ownerDeviceId: paired.deviceIdHex, eventId: paired.eventId)
          emitPairedSosButton(paired, displayName: owner.displayName)
        } else if pairedButtons.contains(where: { $0.deviceIdHex == paired.deviceIdHex }) {
          NSLog("HikerCircle rejected invalid paired SOS tag")
        } else {
          emitNearbySosButton(paired)
        }
        return
      }
      if let location = HikerBleProtocol.decodePairedSosLocationRelay(payload, rssi: rssiValue) {
        emitNearbySosLocation(location)
        return
      }
      if HikerBleProtocol.isSosPacket(payload) {
        logPhysicalSosPackage(
          peripheral: peripheral,
          rssi: rssiValue,
          manufacturerData: manufacturerData,
          payload: payload,
          counter: HikerBleProtocol.sosCounter(from: payload),
          serviceUuids: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        )
        emitSosButton(
          counter: HikerBleProtocol.sosCounter(from: payload),
          legacyDeviceId: peripheral.identifier.uuidString,
          rssi: rssiValue
        )
        return
      }
    }

    let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    if pairingSetupRequested,
       serviceUuids.contains(HikerBleProtocol.pairedButtonSetupServiceUUID) {
      eventSink?([
        "type": "pairedButtonSetupDevice",
        "address": peripheral.identifier.uuidString,
        "displayName": (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
          ?? "HikerCircle Setup",
        "rssi": rssiValue,
        "receivedAtMillis": Self.currentTimeMillis(),
      ])
      return
    }
    if serviceUuids.contains(HikerBleProtocol.sosHelpServiceUUID) {
      connectForRead(peripheral: peripheral, kind: .sosHelp, rssi: rssiValue)
      return
    }
    if serviceUuids.contains(HikerBleProtocol.teamLocationServiceUUID) {
      connectForRead(peripheral: peripheral, kind: .teamLocation, rssi: rssiValue)
      return
    }
    if serviceUuids.contains(HikerBleProtocol.sosServiceUUID) {
      logPhysicalSosPackage(
        peripheral: peripheral,
        rssi: rssiValue,
        manufacturerData: nil,
        payload: nil,
        counter: nil,
        serviceUuids: serviceUuids
      )
      emitSosButton(counter: nil, legacyDeviceId: peripheral.identifier.uuidString, rssi: rssiValue)
    }
  }

  private func logPhysicalSosPackage(
    peripheral: CBPeripheral,
    rssi: Int,
    manufacturerData: Data?,
    payload: Data?,
    counter: Int?,
    serviceUuids: [CBUUID]
  ) {
    NSLog(
      "HikerCircle physical SOS BLE package: peripheral=%@ rssi=%d eventId=%@ manufacturerId=0x%04X manufacturerData=%@ payload=%@ serviceUuids=[%@]",
      peripheral.identifier.uuidString,
      rssi,
      counter.map { String($0) } ?? "none",
      Int(HikerBleProtocol.manufacturerId),
      hexString(manufacturerData),
      hexString(payload),
      serviceUuids.map { $0.uuidString }.joined(separator: ",")
    )
  }

  private func connectForRead(peripheral: CBPeripheral, kind: PendingReadKind, rssi: Int) {
    guard connectedPeripherals[peripheral.identifier] == nil else {
      return
    }
    connectedPeripherals[peripheral.identifier] = peripheral
    pendingReadKinds[peripheral.identifier] = kind
    pendingRssi[peripheral.identifier] = rssi
    peripheral.delegate = self
    centralManager.connect(peripheral, options: nil)
  }

  private func emitSosButton(counter: Int?, legacyDeviceId: String, rssi: Int) {
    let fingerprint = counter.map { "sos_button:event:\($0)" } ??
      "sos_button_legacy_device:\(legacyDeviceId)"
    let now = Self.currentTimeMillis()
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    rememberHandledEvent(fingerprint)
    var event: [String: Any] = [
      "type": "sosButton",
      "source": "ble_button",
      "rssi": rssi,
      "receivedAtMillis": now
    ]
    if let counter {
      event["counter"] = counter
      event["broadcastId"] = counter
    }
    eventSink?(event)
  }

  private func emitNearbySosButton(_ packet: HikerBleProtocol.PairedSosRemotePacket) {
    let fingerprint = "paired_sos:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    rememberHandledEvent(fingerprint)
    eventSink?([
      "type": "nearbySosButton",
      "source": "paired_ble_button",
      "deviceId": packet.deviceIdHex,
      "counter": Int(packet.eventId),
      "rssi": packet.rssi,
      "receivedAtMillis": Self.currentTimeMillis()
    ])
  }

  private func emitPairedSosButton(
    _ packet: HikerBleProtocol.PairedSosRemotePacket,
    displayName: String
  ) {
    let fingerprint = "paired_sos_owner:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else { return }
    rememberHandledEvent(fingerprint)
    eventSink?([
      "type": "pairedSosButton",
      "source": "paired_ble_button",
      "deviceId": packet.deviceIdHex,
      "displayName": displayName,
      "counter": Int(packet.eventId),
      "mode": packet.mode,
      "rssi": packet.rssi,
      "receivedAtMillis": Self.currentTimeMillis(),
    ])
  }

  private func verifyPairedTag(
    owner: PairedButtonRecord,
    packet: HikerBleProtocol.PairedSosRemotePacket
  ) -> Bool {
    let key = SymmetricKey(data: owner.pairingSecret)
    let digest = HMAC<SHA256>.authenticationCode(for: packet.signedPayload, using: key)
    return Data(digest.prefix(8)) == packet.messageTag
  }

  private func isReplay(owner: PairedButtonRecord, eventId: UInt32) -> Bool {
    guard let last = owner.lastAcceptedEventId else { return false }
    return eventId <= last
  }

  private func markAccepted(ownerDeviceId: String, eventId: UInt32) {
    guard let index = pairedButtons.firstIndex(where: { $0.deviceIdHex == ownerDeviceId }) else {
      return
    }
    pairedButtons[index].lastSeenAtMillis = Self.currentTimeMillis()
    pairedButtons[index].lastAcceptedEventId = eventId
    savePairedButtons()
  }

  private func emitNearbySosLocation(_ packet: HikerBleProtocol.PairedSosLocationRelayPacket) {
    let fingerprint = "paired_sos_location:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    rememberHandledEvent(fingerprint)
    eventSink?([
      "type": "nearbySosLocation",
      "source": "paired_ble_button_location",
      "deviceId": packet.deviceIdHex,
      "counter": Int(packet.eventId),
      "latitude": packet.latitude,
      "longitude": packet.longitude,
      "accuracyMeters": packet.accuracyMeters,
      "receivedAtMillis": Self.currentTimeMillis(),
      "rssi": packet.rssi
    ])
  }

  private func emitSosHelp(_ packet: HikerBleProtocol.SosHelpBeaconPacket) {
    let fingerprint = sosHelpFingerprint(packet)
    let now = Self.currentTimeMillis()
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    rememberHandledEvent(fingerprint)
    eventSink?([
      "type": "sosHelp",
      "source": "ble_sos_test",
      "phoneNumberHash": Int(packet.phoneNumberHash),
      "latitude": packet.latitude,
      "longitude": packet.longitude,
      "accuracyMeters": packet.accuracyMeters,
      "capturedAtMillis": Int64(packet.capturedAtMillis),
      "receivedAtMillis": now,
      "rssi": packet.rssi
    ])
  }

  private func sosHelpFingerprint(_ packet: HikerBleProtocol.SosHelpBeaconPacket) -> String {
    return [
      "sos_help",
      String(packet.phoneNumberHash),
      String(packet.latitude),
      String(packet.longitude),
      String(packet.accuracyMeters),
      String(packet.capturedAtMillis)
    ].joined(separator: ":")
  }

  private func hasHandledEvent(_ fingerprint: String) -> Bool {
    return handledEventIds.contains(fingerprint)
  }

  private func rememberHandledEvent(_ fingerprint: String) {
    guard handledEventIds.insert(fingerprint).inserted else {
      return
    }
    handledEventIdOrder.append(fingerprint)
    while handledEventIdOrder.count > 128 {
      handledEventIds.remove(handledEventIdOrder.removeFirst())
    }
  }

  private func hexString(_ data: Data?) -> String {
    guard let data else {
      return "none"
    }
    return data.map { String(format: "%02X", $0) }.joined(separator: " ")
  }

  private func emitTeamLocation(_ packet: HikerBleProtocol.TeamLocationPacket) {
    if let ownHash = Self.int64Value(latestTeamPayload?["phoneNumberHash"]),
       UInt32(truncatingIfNeeded: ownHash) == packet.phoneNumberHash {
      return
    }
    eventSink?([
      "type": "teamLocation",
      "teamSessionHash": Int(packet.teamSessionHash),
      "phoneNumberHash": Int(packet.phoneNumberHash),
      "latitude": packet.latitude,
      "longitude": packet.longitude,
      "accuracyMeters": packet.accuracyMeters,
      "capturedAtMillis": Int64(packet.capturedAtMillis),
      "receivedAtMillis": Self.currentTimeMillis(),
      "rssi": packet.rssi
    ])
  }

  private func emitStatus(_ status: String, message: String? = nil) {
    var event: [String: Any] = [
      "type": "status",
      "status": status,
      "receivedAtMillis": Self.currentTimeMillis()
    ]
    if let message {
      event["message"] = message
    }
    eventSink?(event)
  }

  private var centralStateMessage: String {
    stateMessage(for: centralManager.state)
  }

  private var peripheralStateMessage: String {
    stateMessage(for: peripheralManager.state)
  }

  private func stateMessage(for state: CBManagerState) -> String {
    switch state {
    case .poweredOn:
      return "Bluetooth is ready."
    case .poweredOff:
      return "Bluetooth is turned off."
    case .unauthorized:
      return "Bluetooth permission is not granted for HikerCircle."
    case .unsupported:
      return "This device does not support BLE."
    case .resetting:
      return "Bluetooth is resetting."
    case .unknown:
      return "Bluetooth is not ready yet."
    @unknown default:
      return "Bluetooth is not ready yet."
    }
  }

  private func sosHelpPayload(from call: FlutterMethodCall) -> HikerBleProtocol.SosHelpPayload? {
    guard let arguments = call.arguments as? [String: Any],
          let phoneNumber = arguments["phoneNumber"] as? String,
          let latitude = Self.doubleValue(arguments["latitude"]),
          let longitude = Self.doubleValue(arguments["longitude"]) else {
      return nil
    }
    let phoneHash = UInt32(truncatingIfNeeded:
      Self.int64Value(arguments["phoneNumberHash"]) ?? Int64(HikerBleProtocol.phoneHash(phoneNumber))
    )
    return HikerBleProtocol.SosHelpPayload(
      phoneNumberHash: phoneHash,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: Self.doubleValue(arguments["accuracyMeters"]),
      capturedAtMillis: Self.int64Value(arguments["capturedAtMillis"]) ?? Self.currentTimeMillis(),
      durationMillis: Self.int64Value(arguments["durationMillis"]) ?? 5000
    )
  }

  private func teamPayload(from call: FlutterMethodCall) -> HikerBleProtocol.TeamLocationPayload? {
    guard let arguments = call.arguments as? [String: Any],
          let teamSessionId = arguments["teamSessionId"] as? String,
          let phoneNumber = arguments["phoneNumber"] as? String,
          let latitude = Self.doubleValue(arguments["latitude"]),
          let longitude = Self.doubleValue(arguments["longitude"]) else {
      return nil
    }
    let teamHash = UInt32(truncatingIfNeeded:
      Self.int64Value(arguments["teamSessionHash"]) ?? Int64(HikerBleProtocol.hash(teamSessionId))
    )
    let phoneHash = UInt32(truncatingIfNeeded:
      Self.int64Value(arguments["phoneNumberHash"]) ?? Int64(HikerBleProtocol.phoneHash(phoneNumber))
    )
    return HikerBleProtocol.TeamLocationPayload(
      raw: [
        "teamSessionHash": Int(teamHash),
        "phoneNumberHash": Int(phoneHash)
      ],
      teamSessionHash: teamHash,
      phoneNumberHash: phoneHash,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: Self.doubleValue(arguments["accuracyMeters"]),
      capturedAtMillis: Self.int64Value(arguments["capturedAtMillis"]) ?? Self.currentTimeMillis()
    )
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

  private static func int64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
      return number.int64Value
    }
    if let int = value as? Int {
      return Int64(int)
    }
    if let int64 = value as? Int64 {
      return int64
    }
    return nil
  }

  private static func currentTimeMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private func loadPairedButtons() -> [PairedButtonRecord] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.pairedButtonsKeychainService,
      kSecAttrAccount as String: Self.pairedButtonsKeychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return [] }
    return (try? JSONDecoder().decode([PairedButtonRecord].self, from: data)) ?? []
  }

  private func savePairedButtons() {
    guard let data = try? JSONEncoder().encode(pairedButtons) else { return }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.pairedButtonsKeychainService,
      kSecAttrAccount as String: Self.pairedButtonsKeychainAccount,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = data
    SecItemAdd(add as CFDictionary, nil)
  }

  private func randomBytes(_ count: Int) -> Data? {
    var data = Data(repeating: 0, count: count)
    let status = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
    }
    return status == errSecSuccess ? data : nil
  }

  private func beginPairing(address: String, displayName: String, result: @escaping FlutterResult) {
    guard let uuid = UUID(uuidString: address),
          let deviceId = randomBytes(6),
          let secret = randomBytes(32) else {
      result(FlutterError(code: "paired_button_invalid_request", message: "The iOS peripheral identifier or random pairing material is invalid.", details: nil))
      return
    }
    finishPairing(success: false)
    pairingDeviceId = deviceId
    pairingSecret = secret
    pairingDisplayName = displayName
    pairingResult = result
    pairingPeripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
    guard let peripheral = pairingPeripheral else {
      finishPairing(success: false, errorCode: "paired_button_not_found", errorMessage: "The setup button is no longer available.")
      return
    }
    peripheral.delegate = self
    centralManager.connect(peripheral, options: nil)
    pairingTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
      self?.finishPairing(success: false, errorCode: "paired_button_timeout", errorMessage: "The button pairing window expired.")
    }
  }

  private func finishPairing(success: Bool, errorCode: String? = nil, errorMessage: String? = nil) {
    pairingTimeout?.invalidate()
    pairingTimeout = nil
    if let peripheral = pairingPeripheral {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    pairingPeripheral = nil
    pairingRequestCharacteristic = nil
    pairingStatusCharacteristic = nil
    let result = pairingResult
    pairingResult = nil
    if success {
      result?(nil)
    } else if let errorCode {
      result?(FlutterError(code: errorCode, message: errorMessage, details: nil))
    }
  }

  private func handlePairingStatus(_ data: Data) {
    guard data.count >= 10,
          data[0] == 0x48,
          data[1] == 0x43,
          data[2] == 0x01,
          let deviceId = pairingDeviceId else { return }
    let status = data[3]
    if status >= 0x03 && Data(data[4..<10]) != deviceId { return }
    switch status {
    case 0x01:
      emitStatus("paired_button_ready")
    case 0x02:
      emitStatus("paired_button_awaiting_confirmation")
    case 0x03:
      guard let peripheral = pairingPeripheral,
            let secret = pairingSecret,
            let displayName = pairingDisplayName,
            let deviceId = pairingDeviceId else { return }
      pairedButtons.removeAll { $0.deviceIdHex == deviceId.map { String(format: "%02X", $0) }.joined() }
      pairedButtons.append(
        PairedButtonRecord(
          deviceIdHex: deviceId.map { String(format: "%02X", $0) }.joined(),
          displayName: displayName,
          pairedAtMillis: Self.currentTimeMillis(),
          lastSeenAtMillis: nil,
          lastAcceptedEventId: nil,
          pairingSecret: secret,
          peripheralIdentifier: peripheral.identifier
        )
      )
      savePairedButtons()
      emitStatus("paired_button_paired")
      finishPairing(success: true)
    case 0x04:
      finishPairing(success: false, errorCode: "paired_button_invalid_request", errorMessage: "The button rejected the pairing request.")
    case 0x05:
      finishPairing(success: false, errorCode: "paired_button_confirmation_expired", errorMessage: "The button confirmation window expired.")
    default:
      break
    }
  }

  private func sendPairedSosLocation(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let deviceId = (arguments["deviceId"] as? String)?.uppercased(),
          let eventId = Self.int64Value(arguments["eventId"]),
          let latitude = (arguments["latitude"] as? NSNumber)?.doubleValue,
          let longitude = (arguments["longitude"] as? NSNumber)?.doubleValue else {
      result(FlutterError(code: "paired_button_location_invalid", message: "A button ID, event ID, latitude, and longitude are required.", details: nil))
      return
    }
    guard let owner = pairedButtons.first(where: { $0.deviceIdHex == deviceId }) else {
      result(FlutterError(code: "paired_button_not_found", message: "The button is not paired on this iPhone.", details: nil))
      return
    }
    guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [owner.peripheralIdentifier]).first else {
      result(FlutterError(code: "paired_button_not_found", message: "The paired button is not reachable.", details: nil))
      return
    }
    let accuracy = (arguments["accuracyMeters"] as? NSNumber)?.doubleValue ?? 0
    let capturedAt = Self.int64Value(arguments["capturedAtMillis"]) ?? Self.currentTimeMillis()
    locationPayload = HikerBleProtocol.encodeSosLocationHandoff(
      eventId: UInt32(truncatingIfNeeded: eventId),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      capturedAtMillis: capturedAt,
      pairingSecret: owner.pairingSecret
    )
    locationPeripheral = peripheral
    locationResult = result
    peripheral.delegate = self
    centralManager.connect(peripheral, options: nil)
  }

  private func finishLocation(success: Bool, errorCode: String? = nil, errorMessage: String? = nil) {
    if let peripheral = locationPeripheral {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    locationPeripheral = nil
    locationPayload = nil
    let result = locationResult
    locationResult = nil
    if success {
      result?(nil)
    } else if let errorCode {
      result?(FlutterError(code: errorCode, message: errorMessage, details: nil))
    }
  }
}

extension HikerBleBridge: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      startScanIfReady()
    } else {
      emitStatus("ios_ble_scan_unavailable", message: centralStateMessage)
    }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    emitStatus("ios_ble_scan_restored")
    startScanIfReady()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    handleAdvertisement(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    if pairingPeripheral?.identifier == peripheral.identifier {
      peripheral.discoverServices([HikerBleProtocol.pairedButtonSetupServiceUUID])
      return
    }
    if locationPeripheral?.identifier == peripheral.identifier {
      peripheral.discoverServices([HikerBleProtocol.activeSosServiceUUID])
      return
    }
    guard let kind = pendingReadKinds[peripheral.identifier] else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    switch kind {
    case .sosHelp:
      peripheral.discoverServices([HikerBleProtocol.sosHelpServiceUUID])
    case .teamLocation:
      peripheral.discoverServices([HikerBleProtocol.teamLocationServiceUUID])
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    if pairingPeripheral?.identifier == peripheral.identifier {
      finishPairing(success: false, errorCode: "paired_button_connect_failed", errorMessage: "Unable to connect to the setup button.")
      return
    }
    if locationPeripheral?.identifier == peripheral.identifier {
      finishLocation(success: false, errorCode: "paired_button_location_connect_failed", errorMessage: "Unable to connect to the SOS button.")
      return
    }
    connectedPeripherals.removeValue(forKey: peripheral.identifier)
    pendingReadKinds.removeValue(forKey: peripheral.identifier)
    pendingRssi.removeValue(forKey: peripheral.identifier)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    if pairingPeripheral?.identifier == peripheral.identifier {
      finishPairing(success: false, errorCode: "paired_button_disconnected", errorMessage: "The setup button disconnected before pairing completed.")
      return
    }
    if locationPeripheral?.identifier == peripheral.identifier {
      finishLocation(success: false, errorCode: "paired_button_location_disconnected", errorMessage: "The SOS button disconnected before the location was sent.")
      return
    }
    connectedPeripherals.removeValue(forKey: peripheral.identifier)
    pendingReadKinds.removeValue(forKey: peripheral.identifier)
    pendingRssi.removeValue(forKey: peripheral.identifier)
  }
}

extension HikerBleBridge: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let services = peripheral.services else {
      centralManager.cancelPeripheralConnection(peripheral)
      return
    }
    for service in services {
      if pairingPeripheral?.identifier == peripheral.identifier,
         service.uuid == HikerBleProtocol.pairedButtonSetupServiceUUID {
        peripheral.discoverCharacteristics([
          HikerBleProtocol.pairedButtonPairRequestCharacteristicUUID,
          HikerBleProtocol.pairedButtonStatusCharacteristicUUID,
        ], for: service)
      } else if locationPeripheral?.identifier == peripheral.identifier,
                service.uuid == HikerBleProtocol.activeSosServiceUUID {
        peripheral.discoverCharacteristics([
          HikerBleProtocol.sosLocationCharacteristicUUID,
        ], for: service)
      } else if service.uuid == HikerBleProtocol.sosHelpServiceUUID {
        peripheral.discoverCharacteristics([HikerBleProtocol.sosHelpCharacteristicUUID], for: service)
      } else if service.uuid == HikerBleProtocol.teamLocationServiceUUID {
        peripheral.discoverCharacteristics([HikerBleProtocol.teamLocationCharacteristicUUID], for: service)
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil, let characteristics = service.characteristics else {
      centralManager.cancelPeripheralConnection(peripheral)
      return
    }
    for characteristic in characteristics {
      if pairingPeripheral?.identifier == peripheral.identifier {
        if characteristic.uuid == HikerBleProtocol.pairedButtonPairRequestCharacteristicUUID {
          pairingRequestCharacteristic = characteristic
        } else if characteristic.uuid == HikerBleProtocol.pairedButtonStatusCharacteristicUUID {
          pairingStatusCharacteristic = characteristic
          peripheral.setNotifyValue(true, for: characteristic)
        }
        if pairingRequestCharacteristic != nil && pairingStatusCharacteristic != nil {
          let deviceId = pairingDeviceId ?? Data()
          let secret = pairingSecret ?? Data()
          let value = HikerBleProtocol.encodePairRequest(deviceId: deviceId, pairingSecret: secret)
          peripheral.writeValue(value, for: pairingRequestCharacteristic!, type: .withResponse)
          emitStatus("paired_button_pairing_written")
        }
      } else if locationPeripheral?.identifier == peripheral.identifier,
                characteristic.uuid == HikerBleProtocol.sosLocationCharacteristicUUID,
                let payload = locationPayload {
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)
      } else if characteristic.uuid == HikerBleProtocol.sosHelpCharacteristicUUID ||
          characteristic.uuid == HikerBleProtocol.teamLocationCharacteristicUUID {
        peripheral.readValue(for: characteristic)
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if pairingPeripheral?.identifier == peripheral.identifier,
       characteristic.uuid == HikerBleProtocol.pairedButtonStatusCharacteristicUUID {
      guard error == nil, let data = characteristic.value else { return }
      handlePairingStatus(data)
      return
    }
    defer {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    guard error == nil, let data = characteristic.value else {
      return
    }
    let rssi = pendingRssi[peripheral.identifier] ?? 0
    if characteristic.uuid == HikerBleProtocol.sosHelpCharacteristicUUID,
       let packet = HikerBleProtocol.decodeSosHelpBeacon(data, rssi: rssi) {
      emitSosHelp(packet)
      return
    }
    if characteristic.uuid == HikerBleProtocol.teamLocationCharacteristicUUID,
       let packet = HikerBleProtocol.decodeTeamLocation(data, rssi: rssi) {
      emitTeamLocation(packet)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if locationPeripheral?.identifier == peripheral.identifier,
       characteristic.uuid == HikerBleProtocol.sosLocationCharacteristicUUID {
      if error == nil {
        finishLocation(success: true)
      } else {
        finishLocation(success: false, errorCode: "paired_button_location_write_failed", errorMessage: "The button rejected the location handoff.")
      }
    }
  }
}

extension HikerBleBridge: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      installGattServicesIfNeeded()
      if latestSosHelpPacket != nil {
        advertiseSosHelp(durationMillis: 5000)
      } else {
        advertiseTeamLocationIfReady()
      }
    } else {
      emitStatus("ios_ble_advertising_unavailable", message: peripheralStateMessage)
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
    installGattServicesIfNeeded()
    if latestSosHelpPacket != nil {
      advertiseSosHelp(durationMillis: 5000)
    } else {
      advertiseTeamLocationIfReady()
    }
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    if let error = error {
      emitStatus("ios_ble_advertising_failed", message: error.localizedDescription)
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveRead request: CBATTRequest
  ) {
    let data: Data?
    if request.characteristic.uuid == HikerBleProtocol.sosHelpCharacteristicUUID {
      data = latestSosHelpPacket
    } else if request.characteristic.uuid == HikerBleProtocol.teamLocationCharacteristicUUID {
      data = latestTeamPacket
    } else {
      data = nil
    }

    guard let data else {
      peripheral.respond(to: request, withResult: .attributeNotFound)
      return
    }
    guard request.offset <= data.count else {
      peripheral.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = data.subdata(in: request.offset..<data.count)
    peripheral.respond(to: request, withResult: .success)
  }
}

private enum HikerBleProtocol {
  static let sosServiceUUID = CBUUID(string: "7e2a1d32-8b10-4f4d-9f78-0c6f1d65cba1")
  static let teamLocationServiceUUID = CBUUID(string: "7e2a1d33-8b10-4f4d-9f78-0c6f1d65cba1")
  static let sosHelpServiceUUID = CBUUID(string: "7e2a1d34-8b10-4f4d-9f78-0c6f1d65cba1")
  static let sosHelpCharacteristicUUID = CBUUID(string: "7e2a1d35-8b10-4f4d-9f78-0c6f1d65cba1")
  static let teamLocationCharacteristicUUID = CBUUID(string: "7e2a1d36-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonSetupServiceUUID = CBUUID(string: "7e2a1d37-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonPairRequestCharacteristicUUID = CBUUID(string: "7e2a1d38-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonStatusCharacteristicUUID = CBUUID(string: "7e2a1d39-8b10-4f4d-9f78-0c6f1d65cba1")
  static let activeSosServiceUUID = CBUUID(string: "7e2a1d3a-8b10-4f4d-9f78-0c6f1d65cba1")
  static let sosLocationCharacteristicUUID = CBUUID(string: "7e2a1d3b-8b10-4f4d-9f78-0c6f1d65cba1")
  static let manufacturerId: UInt16 = 0x02E5

  private static let magicH: UInt8 = 0x48
  private static let magicC: UInt8 = 0x43
  private static let version: UInt8 = 0x01
  private static let pairedVersion: UInt8 = 0x02
  private static let typeSos: UInt8 = 0x01
  private static let typeTeamLocation: UInt8 = 0x02
  private static let typeSosHelp: UInt8 = 0x03
  private static let typePairedSosRemote: UInt8 = 0x04
  private static let typePairedSosLocationRelay: UInt8 = 0x05

  struct SosHelpPayload {
    let phoneNumberHash: UInt32
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAtMillis: Int64
    let durationMillis: Int64
  }

  struct TeamLocationPayload {
    let raw: [String: Any]
    let teamSessionHash: UInt32
    let phoneNumberHash: UInt32
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let capturedAtMillis: Int64
  }

  struct SosHelpBeaconPacket {
    let phoneNumberHash: UInt32
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let capturedAtMillis: Int64
    let rssi: Int
  }

  struct TeamLocationPacket {
    let teamSessionHash: UInt32
    let phoneNumberHash: UInt32
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let capturedAtMillis: Int64
    let rssi: Int
  }

  struct PairedSosRemotePacket {
    let deviceId: Data
    let eventId: UInt32
    let mode: Int
    let messageTag: Data
    let signedPayload: Data
    let rssi: Int

    var deviceIdHex: String {
      deviceId.map { String(format: "%02X", $0) }.joined()
    }
  }

  struct PairedSosLocationRelayPacket {
    let deviceId: Data
    let eventId: UInt32
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let rssi: Int

    var deviceIdHex: String {
      deviceId.map { String(format: "%02X", $0) }.joined()
    }
  }

  static func manufacturerPayload(from data: Data) -> Data? {
    guard data.count >= 2 else {
      return nil
    }
    let companyId = UInt16(data[0]) | (UInt16(data[1]) << 8)
    guard companyId == manufacturerId else {
      return nil
    }
    return Data(data.dropFirst(2))
  }

  static func isSosPacket(_ data: Data) -> Bool {
    data.count >= 4 &&
      data[0] == magicH &&
      data[1] == magicC &&
      data[2] == version &&
      data[3] == typeSos
  }

  static func decodePairedSosRemote(
    _ data: Data,
    rssi: Int
  ) -> PairedSosRemotePacket? {
    guard data.count >= 23,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == pairedVersion,
          data[3] == typePairedSosRemote else {
      return nil
    }
    return PairedSosRemotePacket(
      deviceId: Data(data[5..<11]),
      eventId: readUInt32(data, at: 11),
      mode: Int(data[4]),
      messageTag: Data(data[15..<23]),
      signedPayload: Data(data[0..<15]),
      rssi: rssi
    )
  }

  static func decodePairedSosLocationRelay(
    _ data: Data,
    rssi: Int
  ) -> PairedSosLocationRelayPacket? {
    guard data.count >= 24,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == pairedVersion,
          data[3] == typePairedSosLocationRelay else {
      return nil
    }
    return PairedSosLocationRelayPacket(
      deviceId: Data(data[4..<10]),
      eventId: readUInt32(data, at: 10),
      latitude: Double(readInt32(data, at: 14)) / 10_000_000.0,
      longitude: Double(readInt32(data, at: 18)) / 10_000_000.0,
      accuracyMeters: Double(readUInt16(data, at: 22)) / 10.0,
      rssi: rssi
    )
  }

  static func encodePairRequest(deviceId: Data, pairingSecret: Data) -> Data {
    var data = Data([magicH, magicC, version, 0x01])
    data.append(deviceId)
    data.append(pairingSecret)
    return data
  }

  static func encodeSosLocationHandoff(
    eventId: UInt32,
    latitude: Double,
    longitude: Double,
    accuracyMeters: Double,
    capturedAtMillis: Int64,
    pairingSecret: Data
  ) -> Data {
    var signed = Data([magicH, magicC, pairedVersion, typePairedSosLocationRelay])
    appendUInt32(eventId, to: &signed)
    appendInt32(Int32((latitude * 10_000_000).rounded()), to: &signed)
    appendInt32(Int32((longitude * 10_000_000).rounded()), to: &signed)
    let accuracyDecimeters = max(0, min(65535, Int((accuracyMeters * 10).rounded())))
    appendUInt16(UInt16(accuracyDecimeters), to: &signed)
    appendUInt32(UInt32(truncatingIfNeeded: capturedAtMillis / 1000), to: &signed)
    let tag = HMAC<SHA256>.authenticationCode(
      for: signed,
      using: SymmetricKey(data: pairingSecret)
    )
    signed.append(contentsOf: tag.prefix(8))
    return signed
  }

  static func sosCounter(from data: Data) -> Int? {
    guard isSosPacket(data), data.count >= 9 else {
      return nil
    }
    return Int(readUInt32(data, at: 5))
  }

  static func encodeSosHelpBeacon(_ payload: SosHelpPayload) -> Data {
    var data = Data([magicH, magicC, version, typeSosHelp])
    appendUInt32(payload.phoneNumberHash, to: &data)
    appendInt32(Int32((payload.latitude * 10_000_000).rounded()), to: &data)
    appendInt32(Int32((payload.longitude * 10_000_000).rounded()), to: &data)
    appendUInt16(accuracyDecimeters(payload.accuracyMeters), to: &data)
    appendUInt32(UInt32(truncatingIfNeeded: payload.capturedAtMillis / 1000), to: &data)
    return data
  }

  static func decodeSosHelpBeacon(_ data: Data, rssi: Int) -> SosHelpBeaconPacket? {
    guard data.count >= 22,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == typeSosHelp else {
      return nil
    }
    return SosHelpBeaconPacket(
      phoneNumberHash: readUInt32(data, at: 4),
      latitude: Double(readInt32(data, at: 8)) / 10_000_000.0,
      longitude: Double(readInt32(data, at: 12)) / 10_000_000.0,
      accuracyMeters: Double(readUInt16(data, at: 16)) / 10.0,
      capturedAtMillis: Int64(readUInt32(data, at: 18)) * 1000,
      rssi: rssi
    )
  }

  static func encodeTeamLocation(_ payload: TeamLocationPayload) -> Data {
    var data = Data([magicH, magicC, version, typeTeamLocation])
    appendUInt32(payload.teamSessionHash, to: &data)
    appendUInt32(payload.phoneNumberHash, to: &data)
    appendInt32(Int32((payload.latitude * 10_000_000).rounded()), to: &data)
    appendInt32(Int32((payload.longitude * 10_000_000).rounded()), to: &data)
    appendUInt16(accuracyDecimeters(payload.accuracyMeters), to: &data)
    appendUInt32(UInt32(truncatingIfNeeded: payload.capturedAtMillis / 1000), to: &data)
    return data
  }

  static func decodeTeamLocation(_ data: Data, rssi: Int) -> TeamLocationPacket? {
    guard data.count >= 26,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == typeTeamLocation else {
      return nil
    }
    return TeamLocationPacket(
      teamSessionHash: readUInt32(data, at: 4),
      phoneNumberHash: readUInt32(data, at: 8),
      latitude: Double(readInt32(data, at: 12)) / 10_000_000.0,
      longitude: Double(readInt32(data, at: 16)) / 10_000_000.0,
      accuracyMeters: Double(readUInt16(data, at: 20)) / 10.0,
      capturedAtMillis: Int64(readUInt32(data, at: 22)) * 1000,
      rssi: rssi
    )
  }

  static func hash(_ value: String) -> UInt32 {
    var hash: UInt32 = 0x811c9dc5
    for byte in value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 0x01000193
    }
    return hash
  }

  static func phoneHash(_ phoneNumber: String) -> UInt32 {
    hash(phoneNumber.filter { $0.isNumber })
  }

  private static func accuracyDecimeters(_ meters: Double?) -> UInt16 {
    let value = Int(((meters ?? 0) * 10).rounded())
    return UInt16(max(0, min(65535, value)))
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
  }

  private static func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
  }

  private static func appendInt32(_ value: Int32, to data: inout Data) {
    appendUInt32(UInt32(bitPattern: value), to: &data)
  }

  private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
  }

  private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24) |
      (UInt32(data[offset + 1]) << 16) |
      (UInt32(data[offset + 2]) << 8) |
      UInt32(data[offset + 3])
  }

  private static func readInt32(_ data: Data, at offset: Int) -> Int32 {
    Int32(bitPattern: readUInt32(data, at: offset))
  }
}
