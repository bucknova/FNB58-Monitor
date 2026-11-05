import Foundation
import FNBCore

// Replays real captures from an FNB58, with its serial replaced by 123456, through the parser and session logic.
var failures = 0
func expect(_ ok: Bool, _ what: String) {
    print((ok ? "ok    " : "FAIL  ") + what)
    if !ok { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

func load(_ path: String) throws -> [(t: Double, bytes: [UInt8])] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ")
        guard parts.count == 2, let t = Double(parts[0]), let b = Hex.bytes(String(parts[1])) else { return nil }
        return (t, b)
    }
}

let dir = CommandLine.arguments.dropFirst().first ?? "Tests"

expect(Array(FNBProtocol.startMeasuring) == [0xAA, 0x81, 0x00, 0xF4], "command 0x81 matches known bytes")
expect(Array(FNBProtocol.startStreaming) == [0xAA, 0x82, 0x00, 0xA7], "command 0x82 matches known bytes")
expect(Array(FNBProtocol.frame(opcode: 0x84)) == [0xAA, 0x84, 0x00, 0x01], "frame builder matches AA 84 00 01")

// Idle capture: parser behaviour.
let idle = try load("\(dir)/capture-idle.txt")
expect(idle.count == 300, "idle capture loaded (\(idle.count) notifications)")
var parser = FrameParser()
var frames: [Frame] = []
for n in idle { frames += parser.feed(n.bytes) }
expect(parser.checksumFailures == 0 && parser.skippedBytes == 0, "idle: no checksum failures or skipped bytes")
expect(frames.count == 898, "idle: all 898 frames found (\(frames.count))")
expect(!frames.contains { Packet.decode($0) == .unknown }, "idle: every frame decodes")

let joined = idle.flatMap { $0.bytes }
for size in [1, 7, 19] {
    var p = FrameParser()
    var out: [Frame] = []
    var i = 0
    while i < joined.count {
        out += p.feed(joined[i..<min(i + size, joined.count)])
        i += size
    }
    expect(out.map(\.raw) == frames.map(\.raw), "reassembly across \(size)-byte chunks")
}

var corrupted = joined
corrupted[40] ^= 0x10
var p2 = FrameParser()
let recovered = p2.feed(corrupted)
expect(recovered.count >= frames.count - 2, "recovers after corruption (\(recovered.count) frames)")
expect(p2.checksumFailures >= 1, "corruption detected")

let packets = frames.map(Packet.decode)
if case let .info(info)? = packets.first {
    expect(info.model == 58 && info.serial == 123456, "info: model 58, placeholder serial 123456")
    expect(info.firmwareRaw == 115 && info.bootCount == 513, "info: firmware 115, boot count 513")
} else {
    expect(false, "first frame is device info")
}
expect(packets.contains { if case let .status(o, c) = $0 { return o == nil && near(c, 27.9) }; return false }, "idle: open-circuit load, 27.9 C")
expect(Packet.decode(Frame(type: 0x99, payload: [1], raw: [])) == .unknown, "unknown types stay unknown")
expect(Hex.bytes("aa 81 00") == [0xAA, 0x81, 0x00] && Hex.bytes("zz") == nil && Hex.bytes("a") == nil, "hex parsing")

// Loaded capture: session totals and verified scales.
let loaded = try load("\(dir)/capture-load.txt")
let session = Session()
let csvURL = FileManager.default.temporaryDirectory.appendingPathComponent("fnbcheck-\(UUID().uuidString).csv")
let recorder = try CSVRecorder(url: csvURL)
var csvError: Error?
session.onSample = { s in
    do { try recorder.write(s, session: session, now: Date(timeIntervalSince1970: s.t)) } catch { csvError = error }
}
for n in loaded { session.feed(n.bytes, at: n.t) }
try recorder.close()

expect(session.frameCount == 4383, "load: 4383 frames (\(session.frameCount))")
expect(session.badChecksums == 0 && session.unknownCount == 0, "load: no bad checksums or unknown frames")
expect(near(session.volts ?? 0, 5.934), "load: final 5.934 V")
expect(near(session.amps ?? 0, 1.881), "load: final 1.881 A")
expect(near(session.preciseWatts ?? 0, 11.1418), "load: final precise 11.1418 W")
expect(near(session.ohms ?? 0, 3.1636), "load: final 3.1636 ohm")
expect(near(session.celsius ?? 0, 29.8), "load: final 29.8 C")
expect(near(session.dPlus ?? 0, 0.804) && near(session.dMinus ?? 0, 2.802), "load: final D+ 0.804, D- 2.802")
if let p = session.preciseWatts, let v = session.preciseVolts, let a = session.preciseAmps {
    expect(near(p, v * a, 0.01), "load: precise power equals volts x amps")
}
if let d = session.groupDelta {
    expect(near(session.energyWh, d.energyWh, d.energyWh * 0.02), "load: session energy \(session.energyWh) within 2% of tester's \(d.energyWh)")
    expect(near(session.chargeAh, d.capacityAh, d.capacityAh * 0.02), "load: session charge \(session.chargeAh) within 2% of tester's \(d.capacityAh)")
} else {
    expect(false, "load: stored totals tracked")
}
expect(session.events.count == 8 && session.events[0].marker == [0x01, 0x08] && session.events[0].volts > 4, "load: handshake timeline has 8 changes with real voltages (\(session.events.count))")
expect(session.samples.allSatisfy { $0.celsius > 20 && $0.dPlus > 0 && $0.dMinus > 0 }, "load: no placeholder zeros in any sample (\(session.samples.count))")
expect(near(session.ampRange?.high ?? 0, 2.423), "load: peak current 2.423 A")
expect(near(session.voltRange?.low ?? 0, 4.903), "load: lowest voltage 4.903 V")
expect(session.typeStats[0x07].flatMap(\.rate).map { near($0, 10, 0.5) } == true, "load: 0x07 rate about 10 per second")
expect(session.rawLogText().split(separator: "\n").count == 4384, "load: raw log has every frame")

expect(csvError == nil, "csv: no write errors")
let csv = try String(contentsOf: csvURL, encoding: .utf8).split(separator: "\n")
expect(csv.first.map { String($0) + "\n" } == CSVRecorder.header, "csv: header")
expect(csv.count == session.samples.count + 1, "csv: one row per sample (\(csv.count - 1))")
expect(csv.last?.split(separator: ",", omittingEmptySubsequences: false).count == 12, "csv: 12 columns")
try? FileManager.default.removeItem(at: csvURL)

// A dropped link: no invented energy, live values cleared, totals kept.
let before = session.energyWh
let lastT = loaded.last!.t
session.linkLost()
expect(session.volts == nil && session.celsius == nil, "link lost: live values cleared")
let countBefore = session.samples.count
session.feed(FNBProtocol.frame(opcode: 0x07, payload: [0x2E, 0x17, 0x59, 0x07]), at: lastT + 60)
expect(session.samples.count == countBefore, "link lost: voltage alone isn't recorded until other fields return")
session.feed(FNBProtocol.frame(opcode: 0x06, payload: [0x24, 0x03, 0xF2, 0x0A, 0, 0]), at: lastT + 60.05)
session.feed(FNBProtocol.frame(opcode: 0x05, payload: [0x94, 0x7B, 0, 0, 1, 0x2A, 1]), at: lastT + 60.06)
session.feed(FNBProtocol.frame(opcode: 0x07, payload: [0x2E, 0x17, 0x59, 0x07]), at: lastT + 60.1)
session.feed(FNBProtocol.frame(opcode: 0x07, payload: [0x2E, 0x17, 0x59, 0x07]), at: lastT + 60.2)
expect(session.samples.count == countBefore + 2, "link restored: recording resumes")
let silent = Session()
for i in 0..<30 { silent.feed(FNBProtocol.frame(opcode: 0x07, payload: [0x2E, 0x17, 0x59, 0x07]), at: Double(i) * 0.1) }
expect(!silent.samples.isEmpty, "a field that never arrives doesn't block recording forever")
let added = session.energyWh - before
expect(added < 0.001, "link lost: 60 s gap adds no meaningful energy (\(added) Wh)")
session.resetSession()
expect(session.energyWh == 0 && session.samples.isEmpty && session.info != nil, "reset clears totals, keeps device details")

// Command capture: real replies to 0x85 and 0x8A.
expect(Array(FNBProtocol.requestTriggerStatus) == [0xAA, 0x85, 0x00, 0x30], "status command bytes")
expect(Array(FNBProtocol.requestGroupList) == [0xAA, 0x8A, 0x00, 0x0E], "group list command bytes")
let commands = try load("\(dir)/capture-commands.txt")
let commandSession = Session()
for n in commands { commandSession.feed(n.bytes, at: n.t) }
expect(commandSession.badChecksums == 0 && commandSession.unknownCount == 0, "commands: all replies decode")
expect(commandSession.triggerStatus == 0, "commands: trigger status is idle")
expect(FNBProtocol.describeTrigger(commandSession.triggerStatus ?? 99) == "Idle", "commands: idle has its name")
expect(commandSession.groupList.count == 10 && Set(commandSession.groupList.keys) == Set(1...10), "commands: all 10 groups listed")
expect(near(commandSession.groupList[1]?.energyWh ?? 0, 372.05508), "commands: group 1 energy matches live packet")
expect(near(commandSession.groupList[1]?.capacityAh ?? 0, 48.83147), "commands: group 1 capacity matches live packet")
expect(commandSession.groupList[2]?.energyWh == 0, "commands: group 2 empty")
expect(commandSession.info?.groupCount == 10 && commandSession.info?.currentGroup == 1, "commands: 10 groups, group 1 current")
expect(commandSession.info?.firmwareVersion == "1.15", "commands: firmware 1.15")

expect(Array(FNBProtocol.selectGroup(2)) == [0xAA, 0x88, 0x01, 0x02, 0x55], "select group 2 matches bytes tested on hardware")
expect(Array(FNBProtocol.selectGroup(1)) == [0xAA, 0x88, 0x01, 0x01, 0x36], "select group 1 matches bytes tested on hardware")

// Names for detected protocols, using pairs seen on real chargers.
expect(FNBProtocol.describeDetected(1, 8) == "DCP 1.5A + Apple 2.4A", "detected: 01 08")
expect(FNBProtocol.describeDetected(9, 1) == "Samsung 2.0A + DCP 1.5A", "detected: 09 01")
expect(FNBProtocol.describeDetected(6, 0) == "QC3.0", "detected: unknown second value is left out")
expect(FNBProtocol.describeDetected(0, 0) == "None detected", "detected: none")
expect(FNBProtocol.describeDetected(200, 0) == "Protocol 200", "detected: out-of-range value doesn't crash")
expect(FNBProtocol.describeTrigger(99) == "State 99", "trigger: out-of-range value doesn't crash")

// Temperature sign and acknowledgements.
func frameFor(_ type: UInt8, _ payload: [UInt8]) -> Frame { Frame(type: type, payload: payload, raw: []) }
if case let .status(_, c) = Packet.decode(frameFor(0x05, [0x99, 0x99, 0x99, 0x19, 0x00, 0x32, 0x00])) {
    expect(near(c, -5.0), "temperature: sign byte 0 is negative")
} else { expect(false, "temperature: decodes") }
if case let .status(_, c) = Packet.decode(frameFor(0x05, [0x99, 0x99, 0x99, 0x19, 0xFF, 0x32, 0x00])) {
    expect(near(c, -5.0), "temperature: sign byte FF is negative")
} else { expect(false, "temperature: decodes") }
expect(Packet.decode(frameFor(0x01, [0x86])) == .acknowledgement(type: 1, opcode: 0x86), "acknowledgement decodes")
expect(Packet.decode(frameFor(0x09, [1, 2])) == .unknown, "wrong-length status stays unknown")

// Menu capture: group switches, tester restarts, and PD voltage sweeps.
let menus = try load("\(dir)/capture-menus.txt")
let menuSession = Session()
for n in menus { menuSession.feed(n.bytes, at: n.t) }
expect(menuSession.badChecksums == 0, "menus: split notifications reassemble with no bad checksums")
expect(menuSession.unknownCount == 0, "menus: no unknown packet types")
expect(Set(menuSession.groups.keys) == [1, 2], "menus: groups 1 and 2 both tracked")
expect(menuSession.groups[2]?.energyWh == 0 && (menuSession.groups[1]?.energyWh ?? 0) > 372, "menus: each group keeps its own totals")
expect(menuSession.group?.group == 1, "menus: selected group is back to 1")
expect(menuSession.restarts.map(\.toBoot) == [516, 517, 518], "menus: three restarts, boots 516 to 518 (\(menuSession.restarts.map(\.toBoot)))")
let levels = menuSession.steps.map(\.to)
print("      voltage steps: " + levels.map { String(format: "%.1f", $0) }.joined(separator: " "))
expect(levels.contains { near($0, 27.8, 0.3) }, "menus: 27.8 V step found")
expect(levels.contains { near($0, 19.8, 0.3) }, "menus: 19.8 V step found")
expect(levels.contains { near($0, 12.0, 0.3) }, "menus: 12 V step found")
expect(!levels.contains { $0 > 7 && $0 < 8.5 }, "menus: a fast ramp through 7.8 V isn't a step")
expect(menuSession.steps.allSatisfy { abs($0.to - $0.from) > 0.5 }, "menus: every step is over 0.5 V")

let idleSession = Session()
for n in idle { idleSession.feed(n.bytes, at: n.t) }
expect(idleSession.steps.isEmpty, "idle: voltage noise makes no steps")
expect(idleSession.restarts.isEmpty, "idle: no restarts")
let loadSteps = Session()
for n in loaded { loadSteps.feed(n.bytes, at: n.t) }
print("      load steps: " + loadSteps.steps.map { String(format: "%.2f>%.2f", $0.from, $0.to) }.joined(separator: " "))
expect(loadSteps.steps.last.map { near($0.to, 5.94, 0.1) } == true, "load: the rise to 5.94 V is a step")
expect(near(loadSteps.groupDelta?.energyWh ?? 0, 0.43356, 0.0001), "load: tester-added energy still correct")

menuSession.resetSession()
expect(menuSession.steps.isEmpty && menuSession.restarts.isEmpty && menuSession.groupDelta?.energyWh == 0, "reset clears logs and restarts the group comparison")

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
