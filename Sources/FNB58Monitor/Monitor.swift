import AppKit
import CoreBluetooth
import FNBCore
import Observation

enum LinkState: Equatable {
    case starting, bluetoothOff, unauthorized, unsupported
    case idle, scanning, connecting, handshaking, streaming, noData

    var label: String {
        switch self {
        case .starting: "Starting Bluetooth"
        case .bluetoothOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth access needed"
        case .unsupported: "Bluetooth isn't available"
        case .idle: "Disconnected"
        case .scanning: "Looking for your tester"
        case .connecting: "Connecting"
        case .handshaking: "Starting data stream"
        case .streaming: "Streaming over Bluetooth"
        case .noData: "Connected, no data"
        }
    }
}

/// View state. Kept in a model because `@State` needs a compiler plugin that only ships with full Xcode.
@Observable
final class UIState {
    var section = Section.live
    var window = TimeWindow.s30
    var hover: CGFloat?
    var confirmReset = false
    var opcode = ""
    var payload = ""
    var message = "Length and checksum are added for you. You'll confirm before anything is sent."
    var pending: Data?
}

struct FoundDevice: Identifiable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral
    var rssi: Int
    var address: String?
}

/// Owns the Bluetooth link and the session. Everything runs on the main queue.
@Observable
final class Monitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Views read this to refresh 5 times a second, however fast frames arrive.
    private(set) var tick = 0
    private(set) var link: LinkState = .starting
    private(set) var devices: [FoundDevice] = []
    private(set) var connected: FoundDevice?
    private(set) var rssi: Int?
    private(set) var recorder: CSVRecorder?
    /// The group just requested, until the tester's live data confirms it.
    private(set) var pendingGroup: UInt8?
    private(set) var groupNotice: String?
    /// macOS gives no state while its permission prompt is waiting, so a long wait suggests one.
    private(set) var waitingForPermission = false
    var errorMessage: String?
    var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: Keys.reconnect) }
    }

    @ObservationIgnored let session = Session()
    @ObservationIgnored let ui = UIState()
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var notifyChar: CBCharacteristic?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var userDisconnected = false
    @ObservationIgnored private var lastFrameCount = 0
    @ObservationIgnored private var lastDataAt = Date()
    @ObservationIgnored private var connectStartedAt = Date()
    @ObservationIgnored private var restartedForNoData = false
    @ObservationIgnored private var streamGeneration = 0
    @ObservationIgnored private var ticksSinceRSSI = 0
    @ObservationIgnored private var pendingGroupSince = Date()
    @ObservationIgnored private var lastSeenGroup: UInt8?
    @ObservationIgnored private var keepAwake: NSObjectProtocol?
    @ObservationIgnored private var recordingActivity: NSObjectProtocol?
    @ObservationIgnored private let epoch = Date()

    private enum Keys {
        static let device = "lastDeviceID"
        static let reconnect = "autoReconnect"
    }

    override init() {
        autoReconnect = UserDefaults.standard.object(forKey: Keys.reconnect) as? Bool ?? true
        super.init()
        // App Nap would slow Bluetooth delivery and timers while the window is in the background.
        keepAwake = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Measuring USB power")
        central = CBCentralManager(delegate: self, queue: .main)
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.onTimer() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        session.onSample = { [weak self] sample in self?.record(sample) }
    }

    /// Wall-clock time for a session timestamp, so log rows can be matched to what you were doing.
    func clock(_ t: TimeInterval, tenths: Bool = false) -> String {
        let f = DateFormatter()
        f.dateFormat = tenths ? "HH:mm:ss.S" : "HH:mm:ss"
        return f.string(from: epoch.addingTimeInterval(t))
    }

    var isConnected: Bool {
        [.handshaking, .streaming, .noData].contains(link)
    }

    private var now: TimeInterval { Date().timeIntervalSince(epoch) }

    // MARK: Actions

    func connect(_ device: FoundDevice) {
        userDisconnected = false
        begin(device)
    }

    func connectOrScan() {
        userDisconnected = false
        startScan()
    }

    func disconnect() {
        userDisconnected = true
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        } else {
            link = .idle
        }
    }

    func restartStream() {
        guard isConnected else { return }
        sendStartSequence()
    }

    /// Asks the tester to select a group. The selector follows once live data confirms it.
    func selectGroup(_ group: UInt8) {
        guard isConnected, group != session.group?.group else { return }
        groupNotice = nil
        pendingGroup = group
        pendingGroupSince = Date()
        send(FNBProtocol.selectGroup(group))
    }

    /// Asks for the trigger status and all group totals. Both are read-only.
    func refreshDeviceState() {
        guard isConnected else { return }
        send(FNBProtocol.requestTriggerStatus)
        send(FNBProtocol.requestGroupList)
    }

    /// Sends a frame to the tester. Returns false when there's no connection.
    @discardableResult
    func send(_ data: Data) -> Bool {
        guard let peripheral, let writeChar, isConnected else { return false }
        let type: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        session.noteOutgoing(Array(data), at: now)
        peripheral.writeValue(data, for: writeChar, type: type)
        return true
    }

    // MARK: Recording

    func toggleRecording() {
        if recorder != nil {
            stopRecording()
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "FNB58 \(Self.fileStamp()).csv"
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.startRecording(url)
            }
        }
    }

    func exportRawLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "FNB58 raw log \(Self.fileStamp()).txt"
        let text = session.rawLogText()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self?.errorMessage = "Couldn't save the raw log. \(error.localizedDescription)"
            }
        }
    }

    func stopRecording() {
        guard let active = recorder else { return }
        recorder = nil
        if let recordingActivity { ProcessInfo.processInfo.endActivity(recordingActivity) }
        recordingActivity = nil
        do {
            try active.close()
        } catch {
            errorMessage = "The recording may be incomplete. \(error.localizedDescription)"
        }
    }

    private func startRecording(_ url: URL) {
        do {
            recorder = try CSVRecorder(url: url)
            recordingActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording USB power to a file")
        } catch {
            errorMessage = "Couldn't start recording. \(error.localizedDescription)"
        }
    }

    private func record(_ sample: Sample) {
        guard let recorder else { return }
        do {
            try recorder.write(sample, session: session, now: Date())
        } catch {
            self.recorder = nil
            if let recordingActivity { ProcessInfo.processInfo.endActivity(recordingActivity) }
            recordingActivity = nil
            errorMessage = "Recording stopped because the file couldn't be written. \(error.localizedDescription)"
        }
    }

    private static func fileStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    // MARK: Link management

    private func startScan() {
        guard central.state == .poweredOn else { return }
        devices.removeAll { $0.peripheral.identifier != peripheral?.identifier }
        link = .scanning
        // The advertised service keeps the scan working however the name is delivered.
        central.scanForPeripherals(withServices: [CBUUID(string: FNBProtocol.notifyService)])
    }

    private func begin(_ device: FoundDevice) {
        central.stopScan()
        peripheral = device.peripheral
        connected = device
        link = .connecting
        connectStartedAt = Date()
        device.peripheral.delegate = self
        central.connect(device.peripheral)
    }

    private func sendStartSequence() {
        streamGeneration += 1
        let generation = streamGeneration
        if link != .streaming { link = .handshaking }
        restartedForNoData = false
        lastDataAt = Date()
        send(FNBProtocol.startMeasuring)
        // The tester needs a moment after the first command before it will stream.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, generation == self.streamGeneration, self.isConnected else { return }
            self.send(FNBProtocol.startStreaming)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, generation == self.streamGeneration else { return }
            self.refreshDeviceState()
        }
    }

    private func onTimer() {
        tick &+= 1
        ticksSinceRSSI += 1
        if session.frameCount != lastFrameCount {
            lastFrameCount = session.frameCount
            lastDataAt = Date()
            restartedForNoData = false
            if link == .handshaking || link == .noData { link = .streaming }
        }
        if isConnected, ticksSinceRSSI >= 10 {
            ticksSinceRSSI = 0
            peripheral?.readRSSI()
        }
        let waiting = link == .starting && Date().timeIntervalSince(epoch) > 5
        if waiting != waitingForPermission { waitingForPermission = waiting }
        checkGroup()
        watchdog()
    }

    private func checkGroup() {
        let current = session.group?.group
        if let current, let last = lastSeenGroup, current != last {
            // Whether from here or the tester's buttons, the totals list may now be out of date.
            refreshDeviceState()
        }
        lastSeenGroup = current ?? lastSeenGroup
        guard let pending = pendingGroup else { return }
        if current == pending {
            pendingGroup = nil
        } else if Date().timeIntervalSince(pendingGroupSince) > 3 {
            pendingGroup = nil
            groupNotice = "Your tester didn't switch to group \(pending)."
        }
    }

    private func watchdog() {
        let quiet = Date().timeIntervalSince(lastDataAt)
        switch link {
        case .streaming where quiet > 3:
            link = .noData
        case .handshaking where quiet > 8, .noData where quiet > 6 && !restartedForNoData:
            restartedForNoData = true
            sendStartSequence()
            lastDataAt = Date().addingTimeInterval(-6)
            link = .noData
        case .noData where quiet > 15:
            // Still silent after a restart. A fresh connection is the remaining option.
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
        case .connecting where Date().timeIntervalSince(connectStartedAt) > 20:
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            connected = nil
            afterLinkDown()
        default:
            break
        }
    }

    private func afterLinkDown() {
        if userDisconnected || !autoReconnect {
            link = .idle
        } else {
            startScan()
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            if !userDisconnected, !isConnected, link != .connecting { startScan() }
        case .poweredOff:
            session.linkLost()
            link = .bluetoothOff
            peripheral = nil
            connected = nil
        case .unauthorized:
            link = .unauthorized
        case .unsupported:
            link = .unsupported
        default:
            break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi value: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        // Other products share this generic Bluetooth service, so the name decides.
        guard name.hasPrefix("FNB58") else { return }
        var address: String?
        if let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count == 8 {
            address = m.dropFirst(2).map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        let device = FoundDevice(id: p.identifier, name: name, peripheral: p, rssi: value.intValue, address: address)
        if let i = devices.firstIndex(where: { $0.id == p.identifier }) {
            devices[i] = device
        } else {
            devices.append(device)
        }
        guard !userDisconnected, link == .scanning else { return }
        let remembered = UserDefaults.standard.string(forKey: Keys.device)
        if remembered == nil || remembered == p.identifier.uuidString {
            begin(device)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Keys.device)
        notifyChar = nil
        writeChar = nil
        link = .handshaking
        lastDataAt = Date()
        p.discoverServices([CBUUID(string: FNBProtocol.notifyService), CBUUID(string: FNBProtocol.writeService)])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil
        connected = nil
        afterLinkDown()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        streamGeneration += 1
        pendingGroup = nil
        session.linkLost()
        peripheral = nil
        connected = nil
        rssi = nil
        notifyChar = nil
        writeChar = nil
        afterLinkDown()
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for service in p.services ?? [] {
            p.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == CBUUID(string: FNBProtocol.notifyCharacteristic) { notifyChar = ch }
            if ch.uuid == CBUUID(string: FNBProtocol.writeCharacteristic) { writeChar = ch }
        }
        if let notifyChar, writeChar != nil, !notifyChar.isNotifying {
            p.setNotifyValue(true, for: notifyChar)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.isNotifying, error == nil { sendStartSequence() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let value = ch.value else { return }
        session.feed(value, at: now)
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI value: NSNumber, error: Error?) {
        if error == nil { rssi = value.intValue }
    }
}
