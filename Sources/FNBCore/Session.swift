import Foundation

public struct Sample: Sendable {
    public let t: TimeInterval
    public let volts: Double
    public let amps: Double
    public let dPlus: Double
    public let dMinus: Double
    public let celsius: Double
    public var watts: Double { volts * amps }
}

public struct HandshakeEvent: Sendable, Identifiable {
    public let id: Int
    public let t: TimeInterval
    public let dPlus: Double
    public let dMinus: Double
    public let volts: Double
    public let amps: Double
    public let marker: [UInt8]
}

public struct RestartEvent: Sendable, Identifiable {
    public let id: Int
    public let t: TimeInterval
    public let fromBoot: UInt32
    public let toBoot: UInt32
}

/// VBUS moved to a new level and held it.
public struct VoltageStep: Sendable, Identifiable {
    public let id: Int
    public let t: TimeInterval
    public let from: Double
    public let to: Double
    public let amps: Double
    public let dPlus: Double
    public let dMinus: Double
}

public struct TypeStats: Sendable {
    public var count = 0
    public var firstT: TimeInterval = 0
    public var lastT: TimeInterval = 0
    public var lastRaw: [UInt8] = []
    public var lastFrame: Frame?
    public var rate: Double? {
        guard count > 2, lastT > firstT else { return nil }
        return Double(count - 1) / (lastT - firstT)
    }
}

public struct LogEntry: Sendable {
    public let t: TimeInterval
    public let outgoing: Bool
    public let bytes: [UInt8]
}

public struct Range1: Sendable {
    public var low: Double
    public var high: Double
    mutating func include(_ v: Double) {
        low = min(low, v)
        high = max(high, v)
    }
}

/// Everything known about the current measurement session. All access is on the main thread.
public final class Session {
    public static let maxSamples = 432_000 // 12 hours at 10 per second
    public static let maxLog = 200_000

    // Live values, nil while disconnected.
    public private(set) var volts: Double?
    public private(set) var amps: Double?
    public private(set) var preciseVolts: Double?
    public private(set) var preciseAmps: Double?
    public private(set) var preciseWatts: Double?
    public private(set) var dPlus: Double?
    public private(set) var dMinus: Double?
    public private(set) var celsius: Double?
    public private(set) var hasStatus = false
    public private(set) var ohms: Double?
    public private(set) var marker: [UInt8]?
    public private(set) var triggerStatus: UInt8?
    /// What the tester currently detects on the line, from packet 0x06.
    public var detectedProtocols: String? {
        guard let marker, marker.count == 2 else { return nil }
        return FNBProtocol.describeDetected(marker[0], marker[1])
    }
    public var watts: Double? {
        guard let volts, let amps else { return nil }
        return volts * amps
    }

    // Survive reconnects.
    public private(set) var info: DeviceInfo?
    public private(set) var group: StoredGroup?
    /// Latest totals for every group seen, and each group's totals when first seen this session.
    public private(set) var groups: [UInt8: StoredGroup] = [:]
    /// Totals for every group, from the tester's group list.
    public private(set) var groupList: [UInt8: GroupEntry] = [:]
    public private(set) var lastAcknowledgement: (type: UInt8, opcode: UInt8)?
    private var groupBases: [UInt8: StoredGroup] = [:]
    public private(set) var restarts: [RestartEvent] = []
    public private(set) var steps: [VoltageStep] = []
    public private(set) var samples: [Sample] = []
    public private(set) var events: [HandshakeEvent] = []
    public private(set) var log: [LogEntry] = []
    public private(set) var typeStats: [UInt8: TypeStats] = [:]
    public private(set) var seenMarkers: [[UInt8]] = []

    // Session totals, cleared by `resetSession`.
    public private(set) var energyWh = 0.0
    public private(set) var chargeAh = 0.0
    public private(set) var activeSeconds = 0.0
    public private(set) var voltRange: Range1?
    public private(set) var ampRange: Range1?
    public private(set) var wattRange: Range1?

    public private(set) var frameCount = 0
    public private(set) var unknownCount = 0
    private var parser = FrameParser()
    private var priorBad = 0
    private var priorSkipped = 0
    private var eventID = 0
    private var settledVolts: Double?
    private var candidateVolts = 0.0
    private var candidateCount = 0
    private var lastSample: Sample?
    private var firstVoltageAt: TimeInterval?

    /// Called for each 10-per-second sample, e.g. to write it to a recording.
    public var onSample: ((Sample) -> Void)?

    public init() {}

    public var badChecksums: Int { priorBad + parser.checksumFailures }
    public var skippedBytes: Int { priorSkipped + parser.skippedBytes }

    /// What the tester added this session, across every group selected along the way.
    public var groupDelta: (energyWh: Double, capacityAh: Double)? {
        guard !groups.isEmpty else { return nil }
        var energy = 0.0, capacity = 0.0
        for (id, latest) in groups {
            guard let base = groupBases[id] else { continue }
            energy += latest.energyWh - base.energyWh
            capacity += latest.capacityAh - base.capacityAh
        }
        return (energy, capacity)
    }

    public func feed<S: Sequence>(_ bytes: S, at t: TimeInterval) where S.Element == UInt8 {
        for frame in parser.feed(bytes) {
            ingest(frame, at: t)
        }
    }

    public func noteOutgoing(_ bytes: [UInt8], at t: TimeInterval) {
        appendLog(LogEntry(t: t, outgoing: true, bytes: bytes))
    }

    private func ingest(_ frame: Frame, at t: TimeInterval) {
        frameCount += 1
        appendLog(LogEntry(t: t, outgoing: false, bytes: frame.raw))
        var stats = typeStats[frame.type] ?? TypeStats(firstT: t)
        stats.count += 1
        stats.lastT = t
        stats.lastRaw = frame.raw
        stats.lastFrame = frame
        typeStats[frame.type] = stats

        switch Packet.decode(frame) {
        case let .info(value):
            if let old = info, old.bootCount != value.bootCount {
                eventID += 1
                restarts.append(RestartEvent(id: eventID, t: t, fromBoot: old.bootCount, toBoot: value.bootCount))
                if restarts.count > 500 { restarts.removeFirst(100) }
            }
            info = value
        case let .precise(v, a, w):
            preciseVolts = v
            preciseAmps = a
            preciseWatts = w
        case let .status(o, c):
            hasStatus = true
            ohms = o
            celsius = c
        case let .triggerStatus(code):
            triggerStatus = code
        case let .groupEntry(entry):
            groupList[entry.group] = entry
        case let .acknowledgement(type, opcode):
            lastAcknowledgement = (type, opcode)
        case let .dataLines(p, n, _, _):
            dPlus = p
            dMinus = n
            noteMarker(Array(frame.payload[4...5]), at: t, dPlus: p, dMinus: n)
        case let .basic(v, a):
            volts = v
            amps = a
            noteVoltage(v, amps: a, at: t)
            addSample(volts: v, amps: a, at: t)
        case let .group(value):
            if groupBases[value.group] == nil { groupBases[value.group] = value }
            groups[value.group] = value
            group = value
        case .unknown:
            unknownCount += 1
        }
    }

    private func noteMarker(_ value: [UInt8], at t: TimeInterval, dPlus p: Double, dMinus n: Double) {
        if !seenMarkers.contains(value) { seenMarkers.append(value) }
        // Data-line packets arrive just before the first voltage packet; wait so the row is complete.
        guard value != marker, volts != nil else { return }
        marker = value
        eventID += 1
        events.append(HandshakeEvent(id: eventID, t: t, dPlus: p, dMinus: n,
                                     volts: volts ?? 0, amps: amps ?? 0, marker: value))
        if events.count > 500 { events.removeFirst(100) }
    }

    /// Records a step when VBUS settles at least 0.5 V from its last level. A reading must repeat to
    /// count as settled, so a fast 5, 7, 9, 12 V ramp is one step and a one-sample blip is none.
    private func noteVoltage(_ v: Double, amps a: Double, at t: TimeInterval) {
        if abs(v - candidateVolts) <= 0.25 {
            candidateCount += 1
        } else {
            candidateVolts = v
            candidateCount = 1
        }
        guard candidateCount >= 2 else { return }
        guard let level = settledVolts else {
            settledVolts = v
            return
        }
        guard abs(v - level) > 0.5 else { return }
        eventID += 1
        steps.append(VoltageStep(id: eventID, t: t, from: level, to: v, amps: a,
                                 dPlus: dPlus ?? 0, dMinus: dMinus ?? 0))
        if steps.count > 1000 { steps.removeFirst(200) }
        settledVolts = v
    }

    private func addSample(volts v: Double, amps a: Double, at t: TimeInterval) {
        // Other fields arrive up to a quarter second after the first voltage. Recording before then
        // would chart and save placeholder zeros. The time limit keeps a missing field from blocking data.
        let firstSeen = firstVoltageAt ?? t
        firstVoltageAt = firstSeen
        if dPlus == nil || dMinus == nil || celsius == nil, t - firstSeen < 2 { return }
        let sample = Sample(t: t, volts: v, amps: a, dPlus: dPlus ?? 0, dMinus: dMinus ?? 0, celsius: celsius ?? 0)
        if let last = lastSample {
            // A gap means the link dropped. Don't count what wasn't measured.
            let dt = t - last.t
            if dt > 0, dt <= 1 {
                energyWh += last.watts * dt / 3600
                chargeAh += last.amps * dt / 3600
                activeSeconds += dt
            }
        }
        lastSample = sample
        samples.append(sample)
        if samples.count > Self.maxSamples { samples.removeFirst(Self.maxSamples / 10) }
        Self.widen(&voltRange, v)
        Self.widen(&ampRange, a)
        Self.widen(&wattRange, sample.watts)
        onSample?(sample)
    }

    private static func widen(_ range: inout Range1?, _ v: Double) {
        if range == nil { range = Range1(low: v, high: v) } else { range?.include(v) }
    }

    private func appendLog(_ entry: LogEntry) {
        log.append(entry)
        if log.count > Self.maxLog { log.removeFirst(Self.maxLog / 10) }
    }

    /// The link went away: live values stop being true. History and totals stay.
    public func linkLost() {
        priorBad = badChecksums
        priorSkipped = skippedBytes
        parser = FrameParser()
        volts = nil; amps = nil
        preciseVolts = nil; preciseAmps = nil; preciseWatts = nil
        dPlus = nil; dMinus = nil
        celsius = nil; ohms = nil; hasStatus = false
        marker = nil
        triggerStatus = nil
        lastSample = nil
        firstVoltageAt = nil
        settledVolts = nil
        candidateCount = 0
    }

    /// Clears session totals and history, leaving device details in place.
    public func resetSession() {
        energyWh = 0; chargeAh = 0; activeSeconds = 0
        voltRange = nil; ampRange = nil; wattRange = nil
        samples.removeAll()
        events.removeAll()
        steps.removeAll()
        restarts.removeAll()
        lastSample = nil
        groupBases = groups
    }

    public func rawLogText() -> String {
        var out = "time_s\tdirection\tbytes\n"
        for e in log {
            out += String(format: "%.3f\t%@\t%@\n", e.t, e.outgoing ? "tx" : "rx", Hex.string(e.bytes))
        }
        return out
    }
}

/// Streams samples to a CSV file.
public final class CSVRecorder {
    public static let header = "time_utc,elapsed_s,voltage_v,current_a,power_w,d_plus_v,d_minus_v,temperature_c,precise_voltage_v,precise_current_a,precise_power_w,load_ohm\n"

    private let handle: FileHandle
    private let formatter = ISO8601DateFormatter()
    private var startT: TimeInterval?
    public private(set) var rows = 0
    public let url: URL

    public init(url: URL) throws {
        self.url = url
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard FileManager.default.createFile(atPath: url.path, contents: Data(Self.header.utf8)) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    public func write(_ s: Sample, session: Session, now: Date) throws {
        let start = startT ?? s.t
        startT = start
        func opt(_ v: Double?, _ places: Int) -> String {
            v.map { String(format: "%.\(places)f", $0) } ?? ""
        }
        let fields: [String] = [
            formatter.string(from: now),
            String(format: "%.3f", s.t - start),
            String(format: "%.3f", s.volts),
            String(format: "%.3f", s.amps),
            String(format: "%.4f", s.watts),
            String(format: "%.3f", s.dPlus),
            String(format: "%.3f", s.dMinus),
            String(format: "%.1f", s.celsius),
            opt(session.preciseVolts, 4),
            opt(session.preciseAmps, 4),
            opt(session.preciseWatts, 4),
            opt(session.ohms, 4),
        ]
        try handle.write(contentsOf: Data((fields.joined(separator: ",") + "\n").utf8))
        rows += 1
    }

    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }
}
