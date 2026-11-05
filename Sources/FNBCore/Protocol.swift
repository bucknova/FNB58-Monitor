import Foundation

/// FNB58 Bluetooth LE protocol.
///
/// Frame: `AA <type> <len> <payload…> <check>`
/// `check` is the low byte of CRC-16/XMODEM (poly 0x1021, init 0) over every
/// preceding byte, including the AA header. Frames can share a notification
/// and integers are little-endian.
public enum FNBProtocol {
    public static let notifyService = "FFE0"
    public static let notifyCharacteristic = "FFE4"
    public static let writeService = "FFE5"
    public static let writeCharacteristic = "FFE9"

    /// Payload lengths observed on hardware. Anything else is treated as an unknown type.
    public static let knownLengths: [UInt8: Int] = [
        0x03: 14, 0x04: 12, 0x05: 7, 0x06: 6, 0x07: 4, 0x08: 17, 0x09: 1, 0x0A: 9,
    ]

    /// Index carried twice in packet 0x06.
    public static let detectedProtocols = [
        "Unknown", "DCP 1.5A", "QC2.0 5V", "QC2.0 9V", "QC2.0 12V", "QC2.0 20V", "QC3.0",
        "Apple 2.1A", "Apple 2.4A", "Samsung 2.0A", "USB2.0 Full", "USB2.0 High",
        "FCP/AFC 9V", "FCP/AFC 12V", "Huawei SCP", "PD MTK",
    ]

    /// Index carried in packet 0x09. Zero means no trigger is running.
    public static let triggerStates = [
        "Idle", "QC2", "QC3", "FCP", "SCP", "AFC", "PD", "PD1", "VOOC", "SVOOC", "SVOOC",
    ]

    /// Describes the pair of detected protocols, leaving out unknowns.
    public static func describeDetected(_ first: UInt8, _ second: UInt8) -> String {
        var names: [String] = []
        for code in [first, second] where code != 0 {
            let name = Int(code) < detectedProtocols.count ? detectedProtocols[Int(code)] : "Protocol \(code)"
            if !names.contains(name) { names.append(name) }
        }
        return names.isEmpty ? "None detected" : names.joined(separator: " + ")
    }

    public static func describeTrigger(_ code: UInt8) -> String {
        Int(code) < triggerStates.count ? triggerStates[Int(code)] : "State \(code)"
    }

    /// The value sent in the load-resistance field when no current flows.
    public static let openCircuitResistanceRaw: UInt32 = 0x1999_9999

    public static func check<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return UInt8(crc & 0xFF)
    }

    /// Builds a complete frame for `opcode` with a correct length and checksum.
    public static func frame(opcode: UInt8, payload: [UInt8] = []) -> Data {
        var bytes: [UInt8] = [0xAA, opcode, UInt8(payload.count)] + payload
        bytes.append(check(bytes))
        return Data(bytes)
    }

    public static let startMeasuring = frame(opcode: 0x81)
    public static let startStreaming = frame(opcode: 0x82)
    public static let requestTriggerStatus = frame(opcode: 0x85)
    public static let requestGroupList = frame(opcode: 0x8A)

    public static func selectGroup(_ group: UInt8) -> Data {
        frame(opcode: 0x88, payload: [group])
    }
}

public struct Frame: Sendable {
    public let type: UInt8
    public let payload: [UInt8]
    public let raw: [UInt8]

    public init(type: UInt8, payload: [UInt8], raw: [UInt8]) {
        self.type = type
        self.payload = payload
        self.raw = raw
    }
}

public struct DeviceInfo: Equatable, Sendable {
    public let model: UInt16
    public let firmwareRaw: UInt16
    public let serial: UInt32
    public let bootCount: UInt32
    public let groupCount: UInt8
    public let currentGroup: UInt8
    public var firmwareVersion: String { String(format: "%.2f", Double(firmwareRaw) / 100) }
}

public struct GroupEntry: Equatable, Sendable {
    public let group: UInt8
    public let energyWh: Double
    public let capacityAh: Double
}

public struct StoredGroup: Equatable, Sendable {
    public let group: UInt8
    public let energyWh: Double
    public let capacityAh: Double
    public let activeSeconds: UInt32
    public let uptimeSeconds: UInt32
}

public enum Packet: Equatable, Sendable {
    case info(DeviceInfo)
    /// Type 0x04, 4 Hz: 0.1 mV / 0.1 mA / 0.1 mW resolution.
    case precise(volts: Double, amps: Double, watts: Double)
    /// Type 0x05, 4 Hz. `ohms` is nil when the device reports open circuit.
    case status(ohms: Double?, celsius: Double)
    /// Type 0x06, 10 Hz.
    case dataLines(dPlus: Double, dMinus: Double, first: UInt8, second: UInt8)
    /// Type 0x07, 10 Hz: 1 mV / 1 mA resolution.
    case basic(volts: Double, amps: Double)
    /// Type 0x08, 2 Hz.
    case group(StoredGroup)
    /// Type 0x09, in reply to command 0x85.
    case triggerStatus(UInt8)
    /// Type 0x0A, one per group in reply to command 0x8A.
    case groupEntry(GroupEntry)
    /// Types 0x01 and 0x02: the tester acknowledging a command.
    case acknowledgement(type: UInt8, opcode: UInt8)
    case unknown

    public static func decode(_ frame: Frame) -> Packet {
        let p = frame.payload
        func u16(_ i: Int) -> UInt16 { UInt16(p[i]) | UInt16(p[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 {
            UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
        }
        if frame.type == 0x01 || frame.type == 0x02, let opcode = p.first {
            return .acknowledgement(type: frame.type, opcode: opcode)
        }
        guard FNBProtocol.knownLengths[frame.type] == p.count else { return .unknown }
        switch frame.type {
        case 0x03:
            return .info(DeviceInfo(model: u16(0), firmwareRaw: u16(2), serial: u32(4),
                                    bootCount: u32(8), groupCount: p[12], currentGroup: p[13]))
        case 0x04:
            return .precise(volts: Double(u32(0)) / 10_000, amps: Double(u32(4)) / 10_000,
                            watts: Double(u32(8)) / 10_000)
        case 0x05:
            let raw = u32(0)
            // Byte 4 is the temperature's sign, read as signed: above zero is positive.
            let sign = Int8(bitPattern: p[4]) > 0 ? 1.0 : -1.0
            return .status(ohms: raw == FNBProtocol.openCircuitResistanceRaw ? nil : Double(raw) / 10_000,
                           celsius: sign * Double(u16(5)) / 10)
        case 0x06:
            return .dataLines(dPlus: Double(u16(0)) / 1000, dMinus: Double(u16(2)) / 1000, first: p[4], second: p[5])
        case 0x07:
            return .basic(volts: Double(u16(0)) / 1000, amps: Double(u16(2)) / 1000)
        case 0x08:
            return .group(StoredGroup(group: p[0], energyWh: Double(u32(1)) / 100_000,
                                      capacityAh: Double(u32(5)) / 100_000,
                                      activeSeconds: u32(9), uptimeSeconds: u32(13)))
        case 0x09:
            return .triggerStatus(p[0])
        case 0x0A:
            return .groupEntry(GroupEntry(group: p[0], energyWh: Double(u32(1)) / 100_000,
                                          capacityAh: Double(u32(5)) / 100_000))
        default:
            return .unknown
        }
    }
}

/// Reassembles frames from notifications, tolerating splits and garbage.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []
    public private(set) var checksumFailures = 0
    public private(set) var skippedBytes = 0

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [Frame] where S.Element == UInt8 {
        buffer.append(contentsOf: bytes)
        var frames: [Frame] = []
        var i = 0
        scan: while i < buffer.count {
            guard buffer[i] == 0xAA else {
                i += 1
                skippedBytes += 1
                continue
            }
            guard i + 3 <= buffer.count else { break }
            let type = buffer[i + 1]
            let length = Int(buffer[i + 2])
            if let expected = FNBProtocol.knownLengths[type], expected != length {
                i += 1
                skippedBytes += 1
                continue
            }
            let total = length + 4
            guard i + total <= buffer.count else { break scan }
            let raw = Array(buffer[i..<(i + total)])
            guard FNBProtocol.check(raw.dropLast()) == raw[total - 1] else {
                checksumFailures += 1
                i += 1
                skippedBytes += 1
                continue
            }
            frames.append(Frame(type: type, payload: Array(raw[3..<(total - 1)]), raw: raw))
            i += total
        }
        buffer.removeFirst(i)
        // A corrupt length could otherwise stall the parser waiting for bytes that never come.
        if buffer.count > 512 {
            skippedBytes += buffer.count
            buffer.removeAll()
        }
        return frames
    }
}

public enum Hex {
    public static func string<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Parses hex with optional spaces. Returns nil on invalid input.
    public static func bytes(_ text: String) -> [UInt8]? {
        let clean = text.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}
