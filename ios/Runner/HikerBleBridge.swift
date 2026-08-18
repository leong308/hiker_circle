import CoreBluetooth
import CryptoKit
import Flutter
import Security
import UIKit
import UserNotifications

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
    let ownerScope: String?
    let pairingSecret: Data
    let peripheralIdentifier: UUID
  }

  private static let pairedButtonsKeychainService = "hiker_circle.paired_sos_buttons"
  private static let pairedButtonsKeychainAccount = "registry.v1"
  private static let activeOwnerScopeKey = "hiker_circle.active_sos_owner_scope"
  private static let legacyUnpairedEnabledKey = "hiker_circle.legacy_unpaired_sos_enabled"
  private static let legacyUnpairedEnabledKeyPrefix = "hiker_circle.legacy_unpaired_sos_enabled."
  private static let sosMonitorRequestedKey = "hiker_circle.sos_monitor_requested"
  private static let pendingEventsKey = "hiker_circle.pending_ble_sos_events"
  private static let maxHelpPacketAgeMillis: Int64 = 5 * 60 * 1000
  private static let maxHelpPacketFutureSkewMillis: Int64 = 2 * 60 * 1000
  private static let maxPendingSosAgeMillis: Int64 = 5 * 60 * 1000
  private static let maxPendingSosFutureSkewMillis: Int64 = 2 * 60 * 1000

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
  private var legacyEventHandledAtUptime: [String: TimeInterval] = [:]
  private var handledTeamPackets = Set<String>()
  private var handledTeamPacketOrder: [String] = []
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var pendingReadKinds: [UUID: PendingReadKind] = [:]
  private var pendingRssi: [UUID: Int] = [:]
  private var pendingReadTimeouts: [UUID: Timer] = [:]
  private var pairedButtons: [PairedButtonRecord] = []
  private var pairedButtonsLoadFailure: String?
  private var registryErrorNotified = false
  private var activeOwnerScope: String?
  private var pairedButtonTestDeviceId: String?
  private var pairedButtonTestExpiresAt: Date?
  private var isApplicationActive = UIApplication.shared.applicationState == .active
  private var pairingSetupRequested = false
  private var pairingPeripheral: CBPeripheral?
  private var pairingDeviceId: Data?
  private var pairingSecret: Data?
  private var pairingDisplayName: String?
  private var pairingOwnerScope: String?
  private var pairingResult: FlutterResult?
  private var pairingTimeout: Timer?
  private var pairingRequestCharacteristic: CBCharacteristic?
  private var pairingStatusCharacteristic: CBCharacteristic?
  private var pairingRequestWriteStarted = false
  private var locationPeripheral: CBPeripheral?
  private var locationPayload: Data?
  private var locationResult: FlutterResult?
  private var locationTimeout: Timer?
  private var logPeripheral: CBPeripheral?
  private var logOwner: PairedButtonRecord?
  private var logResult: FlutterResult?
  private var logTimeout: Timer?
  private var logAuthCharacteristic: CBCharacteristic?
  private var logPageCharacteristic: CBCharacteristic?
  private var logDataCharacteristic: CBCharacteristic?
  private var downloadedLogRecords: [HikerBleProtocol.LogRecord] = []
  private var nextLogPage = 0
  private var expectedLogPages = 1

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
    isSosMonitorRequested = UserDefaults.standard.bool(
      forKey: Self.sosMonitorRequestedKey
    )
    activeOwnerScope = UserDefaults.standard.string(
      forKey: Self.activeOwnerScopeKey
    )
    pairedButtons = loadPairedButtons() ?? []
    methodChannel.setMethodCallHandler(handleMethodCall)
    eventChannel.setStreamHandler(self)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    if isSosMonitorRequested {
      _ = centralManager
      requestSosNotificationAuthorization()
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    pendingReadTimeouts.values.forEach { $0.invalidate() }
    connectedPeripherals.values.forEach { centralManager.cancelPeripheralConnection($0) }
    stopScanIfIdle()
    stopAdvertising()
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    drainPendingEvents()
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
      UserDefaults.standard.set(true, forKey: Self.sosMonitorRequestedKey)
      requestSosNotificationAuthorization()
      _ = centralManager
      startScanIfReady()
      result(nil)
    case "stopSosButtonMonitor":
      isSosMonitorRequested = false
      UserDefaults.standard.set(false, forKey: Self.sosMonitorRequestedKey)
      stopScanIfIdle()
      result(nil)
    case "setActiveSosAccount":
      let accountId = (call.arguments as? [String: Any])?["accountId"] as? String
      setActiveOwnerAccount(accountId)
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
      if let loadFailure = pairedButtonsLoadFailure {
        result(FlutterError(
          code: "paired_button_registry_read_failed",
          message: loadFailure,
          details: nil
        ))
        return
      }
      result(buttonsForActiveOwner.map { button in
        [
          "deviceId": button.deviceIdHex,
          "displayName": button.displayName,
          "pairedAtMillis": button.pairedAtMillis,
          "lastSeenAtMillis": button.lastSeenAtMillis,
          "lastAcceptedEventId": button.lastAcceptedEventId,
        ]
      })
    case "armPairedSosButtonTest":
      let arguments = call.arguments as? [String: Any]
      let deviceId = (arguments?["deviceId"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased() ?? ""
      let durationMillis = min(
        max((arguments?["durationMillis"] as? NSNumber)?.intValue ?? 30_000, 5_000),
        30_000
      )
      guard deviceId.range(of: "^[0-9A-F]{12}$", options: .regularExpression) != nil,
            buttonsForActiveOwner.contains(where: { $0.deviceIdHex == deviceId }) else {
        result(FlutterError(
          code: "paired_button_test_not_paired",
          message: "This SOS button is not paired to the active account.",
          details: nil
        ))
        return
      }
      pairedButtonTestDeviceId = deviceId
      pairedButtonTestExpiresAt = Date().addingTimeInterval(Double(durationMillis) / 1000.0)
      isSosMonitorRequested = true
      UserDefaults.standard.set(true, forKey: Self.sosMonitorRequestedKey)
      _ = centralManager
      startScanIfReady()
      result(nil)
    case "cancelPairedSosButtonTest":
      clearPairedButtonTest()
      result(nil)
    case "unpairSosButton":
      if let loadFailure = pairedButtonsLoadFailure {
        result(FlutterError(
          code: "paired_button_registry_read_failed",
          message: loadFailure,
          details: nil
        ))
        return
      }
      let deviceId = (call.arguments as? [String: Any])?["deviceId"] as? String ?? ""
      let normalizedId = deviceId.uppercased()
      let updated = pairedButtons.filter {
        !($0.deviceIdHex == normalizedId && belongsToActiveOwner($0))
      }
      guard updated.count != pairedButtons.count else {
        result(false)
        return
      }
      if let status = savePairedButtons(updated) {
        result(FlutterError(
          code: "paired_button_registry_write_failed",
          message: "Unable to securely remove this SOS button (Keychain status \(status)).",
          details: nil
        ))
      } else {
        pairedButtons = updated
        result(true)
      }
    case "resetPairedSosButtonRegistry":
      resetPairedSosButtonRegistry(result: result)
    case "sendPairedSosLocation":
      sendPairedSosLocation(call: call, result: result)
    case "readPairedSosButtonLog":
      let deviceId = (call.arguments as? [String: Any])?["deviceId"] as? String ?? ""
      beginLogDownload(deviceId: deviceId, result: result)
    case "setLegacyUnpairedSosButtonEnabled":
      guard let key = legacyUnpairedSettingKey else {
        result(FlutterError(
          code: "paired_button_account_missing",
          message: "Sign in before changing the legacy SOS button setting.",
          details: nil
        ))
        return
      }
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      UserDefaults.standard.set(enabled, forKey: key)
      UserDefaults.standard.removeObject(forKey: Self.legacyUnpairedEnabledKey)
      result(nil)
    case "isLegacyUnpairedSosButtonEnabled":
      guard let key = legacyUnpairedSettingKey else {
        result(false)
        return
      }
      result(UserDefaults.standard.bool(forKey: key))
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
      handledTeamPackets.removeAll()
      handledTeamPacketOrder.removeAll()
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
    isApplicationActive = true
    // A state-restored BLE central can be created before the device's first
    // unlock, when AfterFirstUnlock Keychain records are temporarily
    // unavailable. Reload now so paired buttons recover without a relaunch.
    if pairingResult == nil, locationResult == nil, logResult == nil {
      if let reloaded = loadPairedButtons() {
        pairedButtons = reloaded
      }
    }
    drainPendingEvents()
    startScanIfReady()
  }

  @objc private func applicationDidEnterBackground() {
    isApplicationActive = false
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
    // iOS requires service filters for reliable background/locked-screen
    // discovery. Foreground scanning remains unfiltered so cross-platform
    // manufacturer-only phone test/team packets still work. Production SOS
    // button firmware must advertise sosServiceUUID alongside type 1/4/5.
    var backgroundServices: [CBUUID]? = nil
    if !isApplicationActive {
      var services: [CBUUID] = []
      if isSosMonitorRequested {
        services.append(HikerBleProtocol.sosServiceUUID)
        services.append(HikerBleProtocol.sosHelpServiceUUID)
      }
      if isTeamExchangeRequested {
        services.append(HikerBleProtocol.teamLocationServiceUUID)
      }
      if pairingSetupRequested {
        services.append(HikerBleProtocol.pairedButtonSetupServiceUUID)
      }
      let uniqueServices = services.reduce(into: [CBUUID]()) { result, uuid in
        if !result.contains(uuid) { result.append(uuid) }
      }
      backgroundServices = uniqueServices.isEmpty ? nil : uniqueServices
    }
    centralManager.scanForPeripherals(
      withServices: backgroundServices,
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
    var setupModeStatus: (state: Int, remainingSeconds: Int)?
    if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
       let payload = HikerBleProtocol.manufacturerPayload(from: manufacturerData) {
      setupModeStatus = HikerBleProtocol.decodePairedButtonSetupStatus(payload)
      if let help = HikerBleProtocol.decodeSosHelpBeacon(payload, rssi: rssiValue) {
        emitSosHelp(help)
        return
      }
      if let team = HikerBleProtocol.decodeTeamLocation(payload, rssi: rssiValue) {
        emitTeamLocation(team)
        return
      }
      if let paired = HikerBleProtocol.decodePairedSosRemote(payload, rssi: rssiValue) {
        if pairedButtonsLoadFailure != nil, let reloaded = loadPairedButtons() {
          pairedButtons = reloaded
        }
        if pairedButtonsLoadFailure != nil {
          NSLog("HikerCircle ignored paired SOS packet because its Keychain registry is unavailable")
          if !registryErrorNotified {
            registryErrorNotified = true
            emitStatus(
              "paired_button_registry_read_failed",
              message: pairedButtonsLoadFailure
            )
            if !isApplicationActive {
              postSosNotification(
                title: "SOS button needs attention",
                body: "Secure pairing data could not be read. Unlock this iPhone, open HikerCircle, and check the paired button."
              )
            }
          }
          return
        }
        if let owner = buttonsForActiveOwner.first(where: {
          $0.deviceIdHex == paired.deviceIdHex
        }),
           verifyPairedTag(owner: owner, packet: paired),
           !isReplay(owner: owner, eventId: paired.eventId) {
          if isPairedButtonTestArmed(for: paired) {
            markAccepted(ownerDeviceId: paired.deviceIdHex, eventId: paired.eventId)
            clearPairedButtonTest()
            emitPairedSosButtonTest(paired, displayName: owner.displayName)
            return
          }
          // Queue/deliver the verified emergency before advancing replay
          // state. A suspension or crash between the opposite ordering would
          // permanently consume an SOS that Flutter never received.
          if emitPairedSosButton(paired, displayName: owner.displayName) {
            markAccepted(ownerDeviceId: paired.deviceIdHex, eventId: paired.eventId)
          }
        } else if buttonsForActiveOwner.contains(where: {
          $0.deviceIdHex == paired.deviceIdHex
        }) {
          NSLog("HikerCircle rejected invalid paired SOS tag")
        } else {
          emitNearbySosButton(paired)
        }
        return
      }
      if let location = HikerBleProtocol.decodePairedSosLocationRelay(payload, rssi: rssiValue) {
        if !buttonsForActiveOwner.contains(where: {
          $0.deviceIdHex == location.deviceIdHex
        }) {
          emitNearbySosLocation(location)
        }
        return
      }
      if HikerBleProtocol.isSosPacket(payload), isLegacyUnpairedEnabled {
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
      var event: [String: Any] = [
        "type": "pairedButtonSetupDevice",
        "address": peripheral.identifier.uuidString,
        "displayName": (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
          ?? "HikerCircle Setup",
        "rssi": rssiValue,
        "receivedAtMillis": Self.currentTimeMillis(),
      ]
      if let setupModeStatus {
        event["setupModeState"] = setupModeStatus.state
        event["setupModeRemainingSeconds"] = setupModeStatus.remainingSeconds
      }
      eventSink?(event)
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
    if serviceUuids.contains(HikerBleProtocol.sosServiceUUID),
       isLegacyUnpairedEnabled {
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
    pendingReadTimeouts[peripheral.identifier]?.invalidate()
    pendingReadTimeouts[peripheral.identifier] = Timer.scheduledTimer(
      withTimeInterval: 10,
      repeats: false
    ) { [weak self, weak peripheral] _ in
      guard let self, let peripheral,
            self.connectedPeripherals[peripheral.identifier] === peripheral else { return }
      self.finishPendingRead(peripheral)
    }
  }

  private func finishPendingRead(_ peripheral: CBPeripheral) {
    let identifier = peripheral.identifier
    pendingReadTimeouts.removeValue(forKey: identifier)?.invalidate()
    connectedPeripherals.removeValue(forKey: identifier)
    pendingReadKinds.removeValue(forKey: identifier)
    pendingRssi.removeValue(forKey: identifier)
    centralManager.cancelPeripheralConnection(peripheral)
  }

  private func emitSosButton(counter: Int?, legacyDeviceId: String, rssi: Int) {
    let fingerprint = counter.map { "sos_button:event:\(legacyDeviceId):\($0)" } ??
      "sos_button_legacy_device:\(legacyDeviceId)"
    let now = Self.currentTimeMillis()
    if counter == nil {
      let uptime = ProcessInfo.processInfo.systemUptime
      if let previous = legacyEventHandledAtUptime[fingerprint], uptime - previous < 10 {
        return
      }
      legacyEventHandledAtUptime[fingerprint] = uptime
      if legacyEventHandledAtUptime.count > 128,
         let oldest = legacyEventHandledAtUptime.min(by: { $0.value < $1.value })?.key {
        legacyEventHandledAtUptime.removeValue(forKey: oldest)
      }
    } else {
      guard !hasHandledEvent(fingerprint) else {
        return
      }
      rememberHandledEvent(fingerprint)
    }
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
    emitEvent(
      event,
      durable: true,
      notificationTitle: "Your SOS button was pressed"
    )
  }

  private func emitNearbySosButton(_ packet: HikerBleProtocol.PairedSosRemotePacket) {
    let fingerprint = "paired_sos:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    let delivered = emitEvent([
      "type": "nearbySosButton",
      "source": "paired_ble_button",
      "deviceId": packet.deviceIdHex,
      "counter": Int(packet.eventId),
      "rssi": packet.rssi,
      "receivedAtMillis": Self.currentTimeMillis()
    ], durable: true, notificationTitle: "Nearby SOS button pressed")
    if delivered {
      rememberHandledEvent(fingerprint)
    }
  }

  @discardableResult
  private func emitPairedSosButton(
    _ packet: HikerBleProtocol.PairedSosRemotePacket,
    displayName: String
  ) -> Bool {
    let fingerprint = "paired_sos_owner:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else { return false }
    let delivered = emitEvent([
      "type": "pairedSosButton",
      "source": "paired_ble_button",
      "deviceId": packet.deviceIdHex,
      "displayName": displayName,
      "counter": Int(packet.eventId),
      "mode": packet.mode,
      "rssi": packet.rssi,
      "receivedAtMillis": Self.currentTimeMillis(),
    ], durable: true, notificationTitle: "Your SOS button was pressed")
    if delivered {
      rememberHandledEvent(fingerprint)
    }
    return delivered
  }

  private func emitPairedSosButtonTest(
    _ packet: HikerBleProtocol.PairedSosRemotePacket,
    displayName: String
  ) {
    let fingerprint = "paired_sos_test:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else { return }
    rememberHandledEvent(fingerprint)
    emitEvent([
      "type": "pairedSosButtonTest",
      "source": "paired_ble_button_test",
      "deviceId": packet.deviceIdHex,
      "displayName": displayName,
      "counter": Int(packet.eventId),
      "rssi": packet.rssi,
      "receivedAtMillis": Self.currentTimeMillis(),
    ])
  }

  private func isPairedButtonTestArmed(
    for packet: HikerBleProtocol.PairedSosRemotePacket
  ) -> Bool {
    guard packet.mode == 1,
          pairedButtonTestDeviceId == packet.deviceIdHex,
          let expiresAt = pairedButtonTestExpiresAt else { return false }
    if expiresAt <= Date() {
      clearPairedButtonTest()
      return false
    }
    return true
  }

  private func clearPairedButtonTest() {
    pairedButtonTestDeviceId = nil
    pairedButtonTestExpiresAt = nil
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
    // Serial arithmetic accepts the legitimate UInt32 wrap but deliberately
    // rejects a firmware reset to a small counter. Reset firmware must be
    // physically re-paired so captured old packets never become valid again.
    let forwardDistance = eventId &- last
    return forwardDistance == 0 || forwardDistance >= 0x8000_0000
  }

  private func markAccepted(ownerDeviceId: String, eventId: UInt32) {
    guard let index = pairedButtons.firstIndex(where: {
      $0.deviceIdHex == ownerDeviceId && belongsToActiveOwner($0)
    }) else {
      return
    }
    pairedButtons[index].lastSeenAtMillis = Self.currentTimeMillis()
    pairedButtons[index].lastAcceptedEventId = eventId
    if let status = savePairedButtons(pairedButtons) {
      NSLog("HikerCircle could not persist paired SOS replay state: %d", status)
    }
  }

  private func emitNearbySosLocation(_ packet: HikerBleProtocol.PairedSosLocationRelayPacket) {
    let fingerprint = "paired_sos_location:\(packet.deviceIdHex):\(packet.eventId)"
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    let delivered = emitEvent([
      "type": "nearbySosLocation",
      "source": "paired_ble_button_location",
      "deviceId": packet.deviceIdHex,
      "counter": Int(packet.eventId),
      "latitude": packet.latitude,
      "longitude": packet.longitude,
      "accuracyMeters": packet.accuracyMeters,
      "receivedAtMillis": Self.currentTimeMillis(),
      "rssi": packet.rssi
    ], durable: true, notificationTitle: "Nearby SOS location received")
    if delivered {
      rememberHandledEvent(fingerprint)
    }
  }

  private func emitSosHelp(_ packet: HikerBleProtocol.SosHelpBeaconPacket) {
    let now = Self.currentTimeMillis()
    guard packet.capturedAtMillis <= now + Self.maxHelpPacketFutureSkewMillis,
          now - packet.capturedAtMillis <= Self.maxHelpPacketAgeMillis else {
      return
    }
    let fingerprint = sosHelpFingerprint(packet)
    guard !hasHandledEvent(fingerprint) else {
      return
    }
    let delivered = emitEvent([
      "type": "sosHelp",
      "source": "ble_sos_test",
      "phoneNumberHash": Int(packet.phoneNumberHash),
      "latitude": packet.latitude,
      "longitude": packet.longitude,
      "accuracyMeters": packet.accuracyMeters,
      "capturedAtMillis": Int64(packet.capturedAtMillis),
      "receivedAtMillis": now,
      "rssi": packet.rssi
    ], durable: true, notificationTitle: "Nearby SOS needs help")
    if delivered {
      rememberHandledEvent(fingerprint)
    }
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
    guard let ownTeamHash = Self.int64Value(latestTeamPayload?["teamSessionHash"]),
          let ownPhoneHash = Self.int64Value(latestTeamPayload?["phoneNumberHash"]),
          UInt32(truncatingIfNeeded: ownTeamHash) == packet.teamSessionHash,
          UInt32(truncatingIfNeeded: ownPhoneHash) != packet.phoneNumberHash else {
      return
    }
    let fingerprint = [
      String(packet.teamSessionHash),
      String(packet.phoneNumberHash),
      String(packet.latitude),
      String(packet.longitude),
      String(packet.accuracyMeters),
      String(packet.capturedAtMillis),
    ].joined(separator: ":")
    guard handledTeamPackets.insert(fingerprint).inserted else { return }
    handledTeamPacketOrder.append(fingerprint)
    while handledTeamPacketOrder.count > 128 {
      handledTeamPackets.remove(handledTeamPacketOrder.removeFirst())
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
    let accuracyMeters = Self.doubleValue(arguments["accuracyMeters"])
    guard Self.isValidBleLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters
    ) else { return nil }
    let phoneHash = UInt32(truncatingIfNeeded:
      Self.int64Value(arguments["phoneNumberHash"]) ?? Int64(HikerBleProtocol.phoneHash(phoneNumber))
    )
    return HikerBleProtocol.SosHelpPayload(
      phoneNumberHash: phoneHash,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
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
    let accuracyMeters = Self.doubleValue(arguments["accuracyMeters"])
    guard Self.isValidBleLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters
    ) else { return nil }
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
      accuracyMeters: accuracyMeters,
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

  private static func isValidBleLocation(
    latitude: Double,
    longitude: Double,
    accuracyMeters: Double?
  ) -> Bool {
    latitude.isFinite && longitude.isFinite &&
      (-90.0...90.0).contains(latitude) &&
      (-180.0...180.0).contains(longitude) &&
      (accuracyMeters == nil || (accuracyMeters!.isFinite && accuracyMeters! >= 0))
  }

  private var buttonsForActiveOwner: [PairedButtonRecord] {
    pairedButtons.filter(belongsToActiveOwner)
  }

  private var isLegacyUnpairedEnabled: Bool {
    guard let key = legacyUnpairedSettingKey else { return false }
    return UserDefaults.standard.bool(forKey: key)
  }

  private var legacyUnpairedSettingKey: String? {
    activeOwnerScope.map { Self.legacyUnpairedEnabledKeyPrefix + $0 }
  }

  private func belongsToActiveOwner(_ button: PairedButtonRecord) -> Bool {
    guard let activeOwnerScope else { return false }
    return button.ownerScope == activeOwnerScope
  }

  private func setActiveOwnerAccount(_ accountId: String?) {
    clearPairedButtonTest()
    let normalized = accountId?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard let normalized, !normalized.isEmpty else {
      activeOwnerScope = nil
      UserDefaults.standard.removeObject(forKey: Self.activeOwnerScopeKey)
      return
    }
    let digest = SHA256.hash(data: Data(normalized.utf8))
    let scope = digest.map { String(format: "%02X", $0) }.joined()
    activeOwnerScope = scope
    UserDefaults.standard.set(scope, forKey: Self.activeOwnerScopeKey)
    drainPendingEvents()
  }

  private func loadPairedButtons() -> [PairedButtonRecord]? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.pairedButtonsKeychainService,
      kSecAttrAccount as String: Self.pairedButtonsKeychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      pairedButtonsLoadFailure = nil
      registryErrorNotified = false
      return []
    }
    guard status == errSecSuccess, let data = item as? Data else {
      NSLog("HikerCircle could not load paired SOS buttons from Keychain: %d", status)
      pairedButtonsLoadFailure =
        "Unable to securely read paired SOS buttons (Keychain status \(status)). Unlock this iPhone and try again."
      return nil
    }
    do {
      let records = try JSONDecoder().decode([PairedButtonRecord].self, from: data)
      pairedButtonsLoadFailure = nil
      registryErrorNotified = false
      return records
    } catch {
      NSLog("HikerCircle could not decode the paired SOS button registry: %@", error.localizedDescription)
      pairedButtonsLoadFailure =
        "The secure paired SOS button registry is unreadable. Reinstall or contact support before pairing again."
      return nil
    }
  }

  /// Returns nil on success, otherwise the Security.framework status.
  private func savePairedButtons(_ records: [PairedButtonRecord]) -> OSStatus? {
    guard let data = try? JSONEncoder().encode(records) else { return errSecParam }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.pairedButtonsKeychainService,
      kSecAttrAccount as String: Self.pairedButtonsKeychainAccount,
    ]
    var status = SecItemUpdate(
      base as CFDictionary,
      [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ] as CFDictionary
    )
    if status == errSecItemNotFound {
      var add = base
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess ? nil : status
  }

  private func resetPairedSosButtonRegistry(result: @escaping FlutterResult) {
    guard pairingResult == nil, locationResult == nil, logResult == nil else {
      result(FlutterError(
        code: "paired_button_busy",
        message: "Finish the current SOS button operation before resetting its secure registry.",
        details: nil
      ))
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.pairedButtonsKeychainService,
      kSecAttrAccount as String: Self.pairedButtonsKeychainAccount,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      result(FlutterError(
        code: "paired_button_registry_reset_failed",
        message: "Unable to reset the secure SOS button registry (Keychain status \(status)). Unlock this iPhone and try again.",
        details: nil
      ))
      return
    }

    pairedButtons.removeAll()
    pairedButtonsLoadFailure = nil
    registryErrorNotified = false
    handledEventIds.removeAll()
    handledEventIdOrder.removeAll()
    legacyEventHandledAtUptime.removeAll()

    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: Self.pendingEventsKey)
    defaults.removeObject(forKey: Self.legacyUnpairedEnabledKey)
    if let key = legacyUnpairedSettingKey {
      defaults.removeObject(forKey: key)
    }
    // Deliberately preserve activeOwnerScope and its persisted account key. A
    // registry recovery must not detach the signed-in account from SOS scope.
    result(nil)
  }

  private func randomBytes(_ count: Int) -> Data? {
    var data = Data(repeating: 0, count: count)
    let status = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
    }
    return status == errSecSuccess ? data : nil
  }

  private func beginPairing(address: String, displayName: String, result: @escaping FlutterResult) {
    if let loadFailure = pairedButtonsLoadFailure {
      result(FlutterError(code: "paired_button_registry_read_failed", message: loadFailure, details: nil))
      return
    }
    if pairingResult != nil {
      result(FlutterError(code: "paired_button_pairing_active", message: "Another SOS button pairing operation is already active.", details: nil))
      return
    }
    if locationResult != nil || logResult != nil {
      result(FlutterError(code: "paired_button_busy", message: "The SOS button is busy with another maintenance operation.", details: nil))
      return
    }
    guard let ownerScope = activeOwnerScope else {
      result(FlutterError(code: "paired_button_account_missing", message: "Sign in before pairing an SOS button.", details: nil))
      return
    }
    guard let uuid = UUID(uuidString: address),
          let deviceId = randomBytes(6),
          let secret = randomBytes(32) else {
      result(FlutterError(code: "paired_button_invalid_request", message: "The iOS peripheral identifier or random pairing material is invalid.", details: nil))
      return
    }
    pairingDeviceId = deviceId
    pairingSecret = secret
    pairingDisplayName = displayName
    pairingOwnerScope = ownerScope
    pairingRequestWriteStarted = false
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

  @discardableResult
  private func emitEvent(
    _ event: [String: Any],
    durable: Bool = false,
    notificationTitle: String? = nil
  ) -> Bool {
    let canDeliverDirectly = isApplicationActive &&
      UIApplication.shared.applicationState == .active
    var delivered = false
    if durable, !canDeliverDirectly {
      delivered = persistPendingEvent(event)
    } else if let eventSink {
      eventSink(event)
      delivered = true
    } else if durable {
      delivered = persistPendingEvent(event)
    }
    if durable, !canDeliverDirectly, let notificationTitle {
      postSosNotification(title: notificationTitle)
    }
    return delivered
  }

  @discardableResult
  private func persistPendingEvent(_ event: [String: Any]) -> Bool {
    guard let ownerScope = activeOwnerScope,
          JSONSerialization.isValidJSONObject(event) else { return false }
    let defaults = UserDefaults.standard
    var pending: [[String: Any]] = []
    if let data = defaults.data(forKey: Self.pendingEventsKey),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
      pending = decoded
    }
    pending.append([
      "ownerScope": ownerScope,
      "event": event,
    ])
    if pending.count > 16 {
      pending.removeFirst(pending.count - 16)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: pending) else {
      return false
    }
    defaults.set(data, forKey: Self.pendingEventsKey)
    return defaults.data(forKey: Self.pendingEventsKey) == data
  }

  private func drainPendingEvents() {
    guard isApplicationActive,
          UIApplication.shared.applicationState == .active,
          let eventSink,
          let ownerScope = activeOwnerScope else { return }
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: Self.pendingEventsKey),
          let pending = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return
    }
    var remaining: [[String: Any]] = []
    var matchingEvents: [[String: Any]] = []
    let now = Self.currentTimeMillis()
    for item in pending {
      guard let itemOwnerScope = item["ownerScope"] as? String,
             let event = item["event"] as? [String: Any],
             let validatedEvent = validatedPendingEvent(event, now: now) else {
        continue
      }
      if itemOwnerScope == ownerScope {
        matchingEvents.append(validatedEvent)
      } else {
        remaining.append([
          "ownerScope": itemOwnerScope,
          "event": validatedEvent,
        ])
      }
    }
    matchingEvents.forEach { eventSink($0) }
    if remaining.isEmpty {
      defaults.removeObject(forKey: Self.pendingEventsKey)
    } else if let data = try? JSONSerialization.data(withJSONObject: remaining) {
      defaults.set(data, forKey: Self.pendingEventsKey)
    }
  }

  private func validatedPendingEvent(
    _ event: [String: Any],
    now: Int64
  ) -> [String: Any]? {
    guard JSONSerialization.isValidJSONObject(event),
          let receivedAtMillis = Self.int64Value(event["receivedAtMillis"]),
          receivedAtMillis > 0,
          receivedAtMillis <= now + Self.maxPendingSosFutureSkewMillis,
          now - receivedAtMillis <= Self.maxPendingSosAgeMillis,
          let type = event["type"] as? String,
          let source = event["source"] as? String else {
      return nil
    }
    var validated = event
    switch type {
    case "pairedSosButton":
      guard source == "paired_ble_button",
            let deviceId = event["deviceId"] as? String,
            let decodedId = Data(hexString: deviceId), decodedId.count == 6,
            let counter = Self.int64Value(event["counter"]),
            (0...Int64(UInt32.max)).contains(counter),
            Self.int64Value(event["mode"]) == 1 else {
        return nil
      }
      validated["deviceId"] = deviceId.uppercased()
      if let displayName = event["displayName"] as? String {
        validated["displayName"] = String(displayName.prefix(64))
      }
    case "sosButton":
      guard source == "ble_button" else { return nil }
      if let rawCounter = event["counter"] {
        guard let counter = Self.int64Value(rawCounter),
              (0...Int64(UInt32.max)).contains(counter) else {
          return nil
        }
      }
    case "nearbySosButton", "nearbySosLocation":
      guard source == (type == "nearbySosLocation"
              ? "paired_ble_button_location"
              : "paired_ble_button"),
            let deviceId = event["deviceId"] as? String,
            let decodedId = Data(hexString: deviceId), decodedId.count == 6,
            let counter = Self.int64Value(event["counter"]),
            (0...Int64(UInt32.max)).contains(counter) else {
        return nil
      }
      validated["deviceId"] = deviceId.uppercased()
      if type == "nearbySosLocation" {
        guard let latitude = Self.doubleValue(event["latitude"]),
              let longitude = Self.doubleValue(event["longitude"]),
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              !(latitude == 0 && longitude == 0) else {
          return nil
        }
      }
    case "sosHelp":
      guard source == "ble_sos_test",
            let latitude = Self.doubleValue(event["latitude"]),
            let longitude = Self.doubleValue(event["longitude"]),
            let capturedAtMillis = Self.int64Value(event["capturedAtMillis"]),
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude),
            !(latitude == 0 && longitude == 0),
            capturedAtMillis <= now + Self.maxPendingSosFutureSkewMillis,
            now - capturedAtMillis <= Self.maxPendingSosAgeMillis else {
        return nil
      }
    default:
      return nil
    }
    return validated
  }

  private func requestSosNotificationAuthorization() {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound]
    ) { _, _ in }
  }

  private func postSosNotification(
    title: String,
    body: String = "Open HikerCircle to continue the emergency workflow."
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "hiker_circle_ble_sos_\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
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
    pairingRequestWriteStarted = false
    pairingDeviceId = nil
    pairingSecret = nil
    pairingDisplayName = nil
    pairingOwnerScope = nil
    let result = pairingResult
    pairingResult = nil
    if success {
      result?(nil)
    } else if let errorCode {
      result?(FlutterError(code: errorCode, message: errorMessage, details: nil))
    }
  }

  private func handlePairingStatus(_ data: Data) {
    guard data.count == 10,
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
            let deviceId = pairingDeviceId,
            let ownerScope = pairingOwnerScope else { return }
      guard activeOwnerScope == ownerScope else {
        finishPairing(
          success: false,
          errorCode: "paired_button_account_changed",
          errorMessage: "The signed-in account changed during pairing. Pair the SOS button again."
        )
        return
      }
      let deviceIdHex = deviceId.map { String(format: "%02X", $0) }.joined()
      var updated = pairedButtons.filter {
        $0.deviceIdHex != deviceIdHex &&
          $0.peripheralIdentifier != peripheral.identifier
      }
      updated.append(
        PairedButtonRecord(
          deviceIdHex: deviceIdHex,
          displayName: displayName,
          pairedAtMillis: Self.currentTimeMillis(),
          lastSeenAtMillis: nil,
          lastAcceptedEventId: nil,
          ownerScope: ownerScope,
          pairingSecret: secret,
          peripheralIdentifier: peripheral.identifier
        )
      )
      if let keychainStatus = savePairedButtons(updated) {
        finishPairing(
          success: false,
          errorCode: "paired_button_registry_write_failed",
          errorMessage: "The button confirmed pairing, but this iPhone could not save it securely (Keychain status \(keychainStatus)). Pair it again."
        )
        return
      }
      pairedButtons = updated
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
    if let loadFailure = pairedButtonsLoadFailure {
      result(FlutterError(code: "paired_button_registry_read_failed", message: loadFailure, details: nil))
      return
    }
    if locationResult != nil {
      result(FlutterError(code: "paired_button_location_active", message: "Another SOS button location handoff is already active.", details: nil))
      return
    }
    if pairingResult != nil || logResult != nil {
      result(FlutterError(code: "paired_button_busy", message: "The SOS button is busy with another maintenance operation.", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let deviceId = (arguments["deviceId"] as? String)?.uppercased(),
          let eventId = Self.int64Value(arguments["eventId"]),
          let latitude = (arguments["latitude"] as? NSNumber)?.doubleValue,
          let longitude = (arguments["longitude"] as? NSNumber)?.doubleValue else {
      result(FlutterError(code: "paired_button_location_invalid", message: "A button ID, event ID, latitude, and longitude are required.", details: nil))
      return
    }
    let accuracy = (arguments["accuracyMeters"] as? NSNumber)?.doubleValue
    guard Self.isValidBleLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy
    ) else {
      result(FlutterError(code: "paired_button_location_invalid", message: "The SOS button location coordinates or accuracy are invalid.", details: nil))
      return
    }
    guard let owner = buttonsForActiveOwner.first(where: {
      $0.deviceIdHex == deviceId
    }) else {
      result(FlutterError(code: "paired_button_not_found", message: "The button is not paired on this iPhone.", details: nil))
      return
    }
    guard let peripheral = centralManager.retrievePeripherals(withIdentifiers: [owner.peripheralIdentifier]).first else {
      result(FlutterError(code: "paired_button_not_found", message: "The paired button is not reachable.", details: nil))
      return
    }
    let normalizedAccuracy = accuracy ?? 0
    let capturedAt = Self.int64Value(arguments["capturedAtMillis"]) ?? Self.currentTimeMillis()
    locationPayload = HikerBleProtocol.encodeSosLocationHandoff(
      eventId: UInt32(truncatingIfNeeded: eventId),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: normalizedAccuracy,
      capturedAtMillis: capturedAt,
      pairingSecret: owner.pairingSecret
    )
    locationPeripheral = peripheral
    locationResult = result
    peripheral.delegate = self
    centralManager.connect(peripheral, options: nil)
    locationTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) {
      [weak self] _ in
      self?.finishLocation(
        success: false,
        errorCode: "paired_button_location_timeout",
        errorMessage: "The SOS button location handoff timed out."
      )
    }
  }

  private func finishLocation(success: Bool, errorCode: String? = nil, errorMessage: String? = nil) {
    locationTimeout?.invalidate()
    locationTimeout = nil
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

  private func beginLogDownload(deviceId: String, result: @escaping FlutterResult) {
    if let loadFailure = pairedButtonsLoadFailure {
      result(FlutterError(code: "paired_button_registry_read_failed", message: loadFailure, details: nil))
      return
    }
    if logResult != nil {
      result(FlutterError(code: "paired_button_log_active", message: "Another SOS button log download is already active.", details: nil))
      return
    }
    if pairingResult != nil || locationResult != nil {
      result(FlutterError(code: "paired_button_busy", message: "The SOS button is busy with another maintenance operation.", details: nil))
      return
    }
    guard let owner = buttonsForActiveOwner.first(where: {
      $0.deviceIdHex == deviceId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }) else {
      result(FlutterError(code: "paired_button_log_not_available", message: "This button is not paired on this iPhone.", details: nil))
      return
    }
    guard let peripheral = centralManager.retrievePeripherals(
      withIdentifiers: [owner.peripheralIdentifier]
    ).first else {
      result(FlutterError(code: "paired_button_log_not_found", message: "Tap Start, then press the external button five times within 3 seconds.", details: nil))
      return
    }
    logOwner = owner
    logPeripheral = peripheral
    logResult = result
    downloadedLogRecords = []
    nextLogPage = 0
    expectedLogPages = 1
    peripheral.delegate = self
    centralManager.connect(peripheral, options: nil)
    logTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
      self?.finishLogDownload(
        success: false,
        errorCode: "paired_button_log_timeout",
        errorMessage: "The SOS button log download timed out."
      )
    }
  }

  private func writeLogPage(_ page: Int, peripheral: CBPeripheral) {
    guard let characteristic = logPageCharacteristic else {
      finishLogDownload(
        success: false,
        errorCode: "paired_button_log_page_missing",
        errorMessage: "The SOS button log paging characteristic is unavailable."
      )
      return
    }
    peripheral.writeValue(Data([UInt8(page)]), for: characteristic, type: .withResponse)
  }

  private func finishLogDownload(
    success: Bool,
    errorCode: String? = nil,
    errorMessage: String? = nil
  ) {
    logTimeout?.invalidate()
    logTimeout = nil
    if let peripheral = logPeripheral {
      centralManager.cancelPeripheralConnection(peripheral)
    }
    logPeripheral = nil
    logOwner = nil
    logAuthCharacteristic = nil
    logPageCharacteristic = nil
    logDataCharacteristic = nil
    let result = logResult
    logResult = nil
    if success {
      result?(downloadedLogRecords.map(\.platformMap))
    } else if let errorCode {
      result?(FlutterError(code: errorCode, message: errorMessage, details: nil))
    }
    downloadedLogRecords = []
    nextLogPage = 0
    expectedLogPages = 1
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
    if logPeripheral?.identifier == peripheral.identifier {
      peripheral.discoverServices([
        HikerBleProtocol.pairedButtonMaintenanceServiceUUID,
        HikerBleProtocol.pairedButtonSetupServiceUUID,
      ])
      return
    }
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
    if logPeripheral?.identifier == peripheral.identifier {
      finishLogDownload(success: false, errorCode: "paired_button_log_connect_failed", errorMessage: "Unable to connect. Tap Start, then press the external button five times within 3 seconds.")
      return
    }
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
    pendingReadTimeouts.removeValue(forKey: peripheral.identifier)?.invalidate()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    if logPeripheral?.identifier == peripheral.identifier {
      finishLogDownload(success: false, errorCode: "paired_button_log_disconnected", errorMessage: "The SOS button disconnected before its log was downloaded.")
      return
    }
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
    pendingReadTimeouts.removeValue(forKey: peripheral.identifier)?.invalidate()
  }
}

extension HikerBleBridge: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let services = peripheral.services else {
      centralManager.cancelPeripheralConnection(peripheral)
      return
    }
    for service in services {
      if logPeripheral?.identifier == peripheral.identifier,
         (service.uuid == HikerBleProtocol.pairedButtonMaintenanceServiceUUID ||
          service.uuid == HikerBleProtocol.pairedButtonSetupServiceUUID) {
        peripheral.discoverCharacteristics([
          HikerBleProtocol.pairedButtonLogChallengeCharacteristicUUID,
          HikerBleProtocol.pairedButtonLogAuthCharacteristicUUID,
          HikerBleProtocol.pairedButtonLogDataCharacteristicUUID,
          HikerBleProtocol.pairedButtonLogPageCharacteristicUUID,
        ], for: service)
      } else if pairingPeripheral?.identifier == peripheral.identifier,
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
    var logChallengeCharacteristic: CBCharacteristic?
    for characteristic in characteristics {
      if logPeripheral?.identifier == peripheral.identifier {
        if characteristic.uuid == HikerBleProtocol.pairedButtonLogAuthCharacteristicUUID {
          logAuthCharacteristic = characteristic
        } else if characteristic.uuid == HikerBleProtocol.pairedButtonLogDataCharacteristicUUID {
          logDataCharacteristic = characteristic
        } else if characteristic.uuid == HikerBleProtocol.pairedButtonLogPageCharacteristicUUID {
          logPageCharacteristic = characteristic
        } else if characteristic.uuid == HikerBleProtocol.pairedButtonLogChallengeCharacteristicUUID {
          logChallengeCharacteristic = characteristic
        }
      } else if pairingPeripheral?.identifier == peripheral.identifier {
        if characteristic.uuid == HikerBleProtocol.pairedButtonPairRequestCharacteristicUUID {
          pairingRequestCharacteristic = characteristic
        } else if characteristic.uuid == HikerBleProtocol.pairedButtonStatusCharacteristicUUID {
          pairingStatusCharacteristic = characteristic
        }
      } else if locationPeripheral?.identifier == peripheral.identifier,
                characteristic.uuid == HikerBleProtocol.sosLocationCharacteristicUUID,
                let payload = locationPayload {
        guard payload.count == 30,
              payload.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
          finishLocation(
            success: false,
            errorCode: "paired_button_location_payload_too_long",
            errorMessage: "This BLE connection cannot carry the required 30-byte location payload."
          )
          return
        }
        peripheral.writeValue(payload, for: characteristic, type: .withResponse)
      } else if characteristic.uuid == HikerBleProtocol.sosHelpCharacteristicUUID ||
          characteristic.uuid == HikerBleProtocol.teamLocationCharacteristicUUID {
        peripheral.readValue(for: characteristic)
      }
    }
    if logPeripheral?.identifier == peripheral.identifier {
      guard let challenge = logChallengeCharacteristic,
            logAuthCharacteristic != nil,
            logDataCharacteristic != nil,
            logPageCharacteristic != nil else {
        finishLogDownload(
          success: false,
          errorCode: "paired_button_log_service_missing",
          errorMessage: "This firmware does not expose authenticated BLE logs."
        )
        return
      }
      peripheral.readValue(for: challenge)
    } else if pairingPeripheral?.identifier == peripheral.identifier {
      guard pairingRequestCharacteristic != nil,
            let statusCharacteristic = pairingStatusCharacteristic else {
        finishPairing(
          success: false,
          errorCode: "paired_button_setup_service_invalid",
          errorMessage: "The SOS button setup characteristics are incomplete."
        )
        return
      }
      peripheral.setNotifyValue(true, for: statusCharacteristic)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateNotificationStateFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard pairingPeripheral?.identifier == peripheral.identifier,
          characteristic.uuid == HikerBleProtocol.pairedButtonStatusCharacteristicUUID else {
      return
    }
    if pairingRequestWriteStarted {
      return
    }
    guard error == nil, characteristic.isNotifying,
          let requestCharacteristic = pairingRequestCharacteristic,
          let deviceId = pairingDeviceId,
          let secret = pairingSecret else {
      finishPairing(
        success: false,
        errorCode: "paired_button_notifications_failed",
        errorMessage: "Unable to subscribe to button pairing status."
      )
      return
    }
    let value = HikerBleProtocol.encodePairRequest(
      deviceId: deviceId,
      pairingSecret: secret
    )
    guard value.count == 42,
          value.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
      finishPairing(
        success: false,
        errorCode: "paired_button_pair_payload_too_long",
        errorMessage: "This iPhone BLE connection cannot carry the required 42-byte pairing payload."
      )
      return
    }
    pairingRequestWriteStarted = true
    // This request contains the long-lived pairing secret and has no
    // app-layer confidentiality. The SOS-button firmware MUST configure this
    // characteristic to require an encrypted, MITM-authenticated BLE link
    // before accepting the write. iOS exposes no public bond-state API that
    // can independently prove that requirement here.
    peripheral.writeValue(value, for: requestCharacteristic, type: .withResponse)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if logPeripheral?.identifier == peripheral.identifier {
      guard error == nil, let data = characteristic.value else {
        finishLogDownload(success: false, errorCode: "paired_button_log_read_failed", errorMessage: "The SOS button log read failed.")
        return
      }
      if characteristic.uuid == HikerBleProtocol.pairedButtonLogChallengeCharacteristicUUID {
        guard let owner = logOwner,
              let deviceId = Data(hexString: owner.deviceIdHex),
              let auth = HikerBleProtocol.encodeLogAuthentication(
                challenge: data,
                deviceId: deviceId,
                pairingSecret: owner.pairingSecret
              ),
              let authCharacteristic = logAuthCharacteristic else {
          finishLogDownload(success: false, errorCode: "paired_button_log_challenge_invalid", errorMessage: "The SOS button returned an invalid log challenge.")
          return
        }
        guard auth.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
          finishLogDownload(success: false, errorCode: "paired_button_log_payload_too_long", errorMessage: "This BLE connection cannot carry the authenticated log request.")
          return
        }
        peripheral.writeValue(auth, for: authCharacteristic, type: .withResponse)
        return
      }
      if characteristic.uuid == HikerBleProtocol.pairedButtonLogDataCharacteristicUUID {
        guard let page = HikerBleProtocol.decodeLogPage(data),
              page.pageIndex == nextLogPage else {
          finishLogDownload(success: false, errorCode: "paired_button_log_auth_failed", errorMessage: "The button rejected authentication or returned invalid log data.")
          return
        }
        downloadedLogRecords.append(contentsOf: page.records)
        expectedLogPages = max(1, (page.totalCount + 7) / 8)
        nextLogPage += 1
        if nextLogPage < expectedLogPages {
          writeLogPage(nextLogPage, peripheral: peripheral)
        } else {
          finishLogDownload(success: true)
        }
        return
      }
    }
    if pairingPeripheral?.identifier == peripheral.identifier,
       characteristic.uuid == HikerBleProtocol.pairedButtonStatusCharacteristicUUID {
      guard error == nil, let data = characteristic.value else { return }
      handlePairingStatus(data)
      return
    }
    defer {
      finishPendingRead(peripheral)
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
    if logPeripheral?.identifier == peripheral.identifier {
      guard error == nil else {
        finishLogDownload(success: false, errorCode: "paired_button_log_write_failed", errorMessage: "The authenticated log request was rejected.")
        return
      }
      if characteristic.uuid == HikerBleProtocol.pairedButtonLogAuthCharacteristicUUID {
        writeLogPage(0, peripheral: peripheral)
      } else if characteristic.uuid == HikerBleProtocol.pairedButtonLogPageCharacteristicUUID,
                let dataCharacteristic = logDataCharacteristic {
        peripheral.readValue(for: dataCharacteristic)
      }
      return
    }
    if pairingPeripheral?.identifier == peripheral.identifier,
       characteristic.uuid == HikerBleProtocol.pairedButtonPairRequestCharacteristicUUID {
      if let error {
        finishPairing(
          success: false,
          errorCode: "paired_button_pair_write_failed",
          errorMessage: "The SOS button rejected the pairing data: \(error.localizedDescription)"
        )
      } else {
        emitStatus("paired_button_pairing_written")
        pairingTimeout?.invalidate()
        pairingTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) {
          [weak self] _ in
          self?.finishPairing(
            success: false,
            errorCode: "paired_button_confirmation_timeout",
            errorMessage: "The button was not physically confirmed within 15 seconds."
          )
        }
      }
      return
    }
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
  static let pairedButtonLogChallengeCharacteristicUUID = CBUUID(string: "7e2a1d3c-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonLogAuthCharacteristicUUID = CBUUID(string: "7e2a1d3d-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonLogDataCharacteristicUUID = CBUUID(string: "7e2a1d3e-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonLogPageCharacteristicUUID = CBUUID(string: "7e2a1d3f-8b10-4f4d-9f78-0c6f1d65cba1")
  static let pairedButtonMaintenanceServiceUUID = CBUUID(string: "7e2a1d40-8b10-4f4d-9f78-0c6f1d65cba1")
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
  private static let typePairedButtonSetupStatus: UInt8 = 0x06
  private static let logChallengeType: UInt8 = 0x10
  private static let logDataType: UInt8 = 0x12

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

  struct LogRecord {
    let sequence: UInt32
    let uptimeMillis: UInt32
    let epochSeconds: UInt32
    let eventId: UInt32
    let type: UInt8
    let resetReason: UInt8
    let detail: UInt16

    var platformMap: [String: Any] {
      [
        "sequence": Int64(sequence),
        "uptimeMillis": Int64(uptimeMillis),
        "epochSeconds": Int64(epochSeconds),
        "eventId": Int64(eventId),
        "type": Int(type),
        "resetReason": Int(resetReason),
        "detail": Int(detail),
      ]
    }
  }

  struct LogPage {
    let totalCount: Int
    let pageIndex: Int
    let records: [LogRecord]
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
    data.count == 9 &&
      data[0] == magicH &&
      data[1] == magicC &&
      data[2] == version &&
      data[3] == typeSos &&
      data[4] == 0x01
  }

  static func decodePairedButtonSetupStatus(
    _ data: Data
  ) -> (state: Int, remainingSeconds: Int)? {
    guard data.count == 6,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == typePairedButtonSetupStatus else {
      return nil
    }
    return (state: Int(data[4]), remainingSeconds: Int(data[5]))
  }

  static func decodePairedSosRemote(
    _ data: Data,
    rssi: Int
  ) -> PairedSosRemotePacket? {
    guard data.count == 23,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == pairedVersion,
          data[3] == typePairedSosRemote,
          data[4] == 0x01 else {
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
    guard data.count == 24,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == pairedVersion,
          data[3] == typePairedSosLocationRelay else {
      return nil
    }
    let latitude = Double(readInt32(data, at: 14)) / 10_000_000.0
    let longitude = Double(readInt32(data, at: 18)) / 10_000_000.0
    guard isValidCoordinate(latitude: latitude, longitude: longitude) else {
      return nil
    }
    return PairedSosLocationRelayPacket(
      deviceId: Data(data[4..<10]),
      eventId: readUInt32(data, at: 10),
      latitude: latitude,
      longitude: longitude,
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

  static func encodeLogAuthentication(
    challenge: Data,
    deviceId: Data,
    pairingSecret: Data
  ) -> Data? {
    guard challenge.count == 26,
          deviceId.count == 6,
          pairingSecret.count == 32,
          challenge[0] == magicH,
          challenge[1] == magicC,
          challenge[2] == version,
          challenge[3] == logChallengeType,
          Data(challenge[4..<10]) == deviceId else {
      return nil
    }
    let tag = HMAC<SHA256>.authenticationCode(
      for: challenge,
      using: SymmetricKey(data: pairingSecret)
    )
    var result = challenge
    result.append(contentsOf: tag.prefix(8))
    return result
  }

  static func decodeLogPage(_ data: Data) -> LogPage? {
    guard data.count >= 8,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == logDataType,
          data[4] == 20 else {
      return nil
    }
    let totalCount = Int(data[5])
    let pageIndex = Int(data[6])
    let recordCount = Int(data[7])
    guard totalCount <= 32,
          recordCount <= 8,
          data.count == 8 + recordCount * 20 else {
      return nil
    }
    var records: [LogRecord] = []
    for index in 0..<recordCount {
      let offset = 8 + index * 20
      records.append(
        LogRecord(
          sequence: readUInt32(data, at: offset),
          uptimeMillis: readUInt32(data, at: offset + 4),
          epochSeconds: readUInt32(data, at: offset + 8),
          eventId: readUInt32(data, at: offset + 12),
          type: data[offset + 16],
          resetReason: data[offset + 17],
          detail: readUInt16(data, at: offset + 18)
        )
      )
    }
    return LogPage(
      totalCount: totalCount,
      pageIndex: pageIndex,
      records: records
    )
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
    appendInt32(coordinateE7(latitude, limit: 90), to: &signed)
    appendInt32(coordinateE7(longitude, limit: 180), to: &signed)
    appendUInt16(accuracyDecimeters(accuracyMeters), to: &signed)
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
    appendInt32(coordinateE7(payload.latitude, limit: 90), to: &data)
    appendInt32(coordinateE7(payload.longitude, limit: 180), to: &data)
    appendUInt16(accuracyDecimeters(payload.accuracyMeters), to: &data)
    appendUInt32(UInt32(truncatingIfNeeded: payload.capturedAtMillis / 1000), to: &data)
    return data
  }

  static func decodeSosHelpBeacon(_ data: Data, rssi: Int) -> SosHelpBeaconPacket? {
    guard data.count == 22,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == typeSosHelp else {
      return nil
    }
    let latitude = Double(readInt32(data, at: 8)) / 10_000_000.0
    let longitude = Double(readInt32(data, at: 12)) / 10_000_000.0
    guard isValidCoordinate(latitude: latitude, longitude: longitude) else {
      return nil
    }
    return SosHelpBeaconPacket(
      phoneNumberHash: readUInt32(data, at: 4),
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: Double(readUInt16(data, at: 16)) / 10.0,
      capturedAtMillis: Int64(readUInt32(data, at: 18)) * 1000,
      rssi: rssi
    )
  }

  static func encodeTeamLocation(_ payload: TeamLocationPayload) -> Data {
    var data = Data([magicH, magicC, version, typeTeamLocation])
    appendUInt32(payload.teamSessionHash, to: &data)
    appendUInt32(payload.phoneNumberHash, to: &data)
    appendInt32(coordinateE7(payload.latitude, limit: 90), to: &data)
    appendInt32(coordinateE7(payload.longitude, limit: 180), to: &data)
    appendUInt16(accuracyDecimeters(payload.accuracyMeters), to: &data)
    appendUInt32(UInt32(truncatingIfNeeded: payload.capturedAtMillis / 1000), to: &data)
    return data
  }

  static func decodeTeamLocation(_ data: Data, rssi: Int) -> TeamLocationPacket? {
    guard data.count == 26,
          data[0] == magicH,
          data[1] == magicC,
          data[2] == version,
          data[3] == typeTeamLocation else {
      return nil
    }
    let latitude = Double(readInt32(data, at: 12)) / 10_000_000.0
    let longitude = Double(readInt32(data, at: 16)) / 10_000_000.0
    guard isValidCoordinate(latitude: latitude, longitude: longitude) else {
      return nil
    }
    return TeamLocationPacket(
      teamSessionHash: readUInt32(data, at: 4),
      phoneNumberHash: readUInt32(data, at: 8),
      latitude: latitude,
      longitude: longitude,
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
    guard let meters, meters.isFinite else { return 0 }
    let clamped = max(0, min(6553.5, meters))
    return UInt16((clamped * 10).rounded())
  }

  private static func coordinateE7(_ value: Double, limit: Double) -> Int32 {
    guard value.isFinite else { return 0 }
    let clamped = max(-limit, min(limit, value))
    return Int32((clamped * 10_000_000).rounded())
  }

  private static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
    latitude.isFinite && longitude.isFinite &&
      (-90.0...90.0).contains(latitude) &&
      (-180.0...180.0).contains(longitude)
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

private extension Data {
  init?(hexString: String) {
    let normalized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count.isMultiple(of: 2) else {
      return nil
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(normalized.count / 2)
    var index = normalized.startIndex
    while index < normalized.endIndex {
      let next = normalized.index(index, offsetBy: 2)
      guard let byte = UInt8(String(normalized[index..<next]), radix: 16) else {
        return nil
      }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
