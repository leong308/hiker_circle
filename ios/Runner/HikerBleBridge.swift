import CoreBluetooth
import Flutter
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
    guard isSosMonitorRequested || isTeamExchangeRequested else {
      return
    }
    if centralManager.isScanning {
      centralManager.stopScan()
    }
    let serviceFilter: [CBUUID]?
    if UIApplication.shared.applicationState == .background {
      serviceFilter = [
        HikerBleProtocol.sosServiceUUID,
        HikerBleProtocol.sosHelpServiceUUID,
        HikerBleProtocol.teamLocationServiceUUID
      ]
    } else {
      serviceFilter = nil
    }
    centralManager.scanForPeripherals(
      withServices: serviceFilter,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    )
    emitStatus("ios_ble_scan_started")
  }

  private func stopScanIfIdle() {
    guard !isSosMonitorRequested && !isTeamExchangeRequested else {
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
    connectedPeripherals.removeValue(forKey: peripheral.identifier)
    pendingReadKinds.removeValue(forKey: peripheral.identifier)
    pendingRssi.removeValue(forKey: peripheral.identifier)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
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
      if service.uuid == HikerBleProtocol.sosHelpServiceUUID {
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
      if characteristic.uuid == HikerBleProtocol.sosHelpCharacteristicUUID ||
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
  static let manufacturerId: UInt16 = 0x02E5

  private static let magicH: UInt8 = 0x48
  private static let magicC: UInt8 = 0x43
  private static let version: UInt8 = 0x01
  private static let typeSos: UInt8 = 0x01
  private static let typeTeamLocation: UInt8 = 0x02
  private static let typeSosHelp: UInt8 = 0x03

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
