import FNBCore
import SwiftUI

struct PacketsView: View {
    @Environment(Monitor.self) private var monitor

    private static let names: [UInt8: String] = [
        0x07: "Measurements", 0x06: "Data lines", 0x04: "Precise",
        0x05: "Load, temperature", 0x08: "Stored totals", 0x03: "Device info",
        0x09: "Trigger status", 0x0A: "Group list", 0x01: "Acknowledgement", 0x02: "Acknowledgement",
    ]
    private static let order: [UInt8] = [0x07, 0x06, 0x04, 0x05, 0x08, 0x03, 0x09, 0x0A]

    private func decoded(_ frame: Frame?) -> String {
        guard let frame else { return Fmt.dash }
        switch Packet.decode(frame) {
        case let .basic(v, a): return String(format: "%.3f V, %.3f A", v, a)
        case let .dataLines(p, n, first, second):
            return String(format: "D+ %.3f V, D− %.3f V, ", p, n) + FNBProtocol.describeDetected(first, second)
        case let .precise(v, a, w): return String(format: "%.4f V, %.4f A, %.4f W", v, a, w)
        case let .status(o, c):
            return (o.map { String(format: "%.4f Ω", $0) } ?? "Open load") + String(format: ", %.1f °C", c)
        case let .group(g):
            return "Group \(g.group): " + String(format: "%.3f Wh, %.3f Ah, ", g.energyWh, g.capacityAh) + Fmt.clock(Double(g.activeSeconds))
        case let .info(i):
            return "FNB\(i.model), serial \(i.serial), firmware v\(i.firmwareVersion), boot \(i.bootCount), group \(i.currentGroup) of \(i.groupCount)"
        case let .triggerStatus(code):
            return FNBProtocol.describeTrigger(code)
        case let .groupEntry(e):
            return "Group \(e.group): " + String(format: "%.3f Wh, %.3f Ah", e.energyWh, e.capacityAh)
        case let .acknowledgement(type, opcode):
            return String(format: "Type %d for command %02X", type, opcode)
        case .unknown:
            return "Not recognised"
        }
    }

    private func rate(_ stats: TypeStats?, type: UInt8) -> String {
        guard let stats else { return Fmt.dash }
        if [0x01, 0x02, 0x09, 0x0A].contains(type) { return "On request" }
        guard let r = stats.rate, r >= 0.05 else { return "At connection" }
        return String(format: "%.1f per second", r)
    }

    var body: some View {
        let _ = monitor.tick
        let s = monitor.session
        let extra = s.typeStats.keys.filter { !Self.order.contains($0) }.sorted()
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                SmallTile(title: "Frames received", value: s.frameCount.formatted())
                SmallTile(title: "Bad checksums", value: s.badChecksums.formatted())
                SmallTile(title: "Unknown packet types", value: s.unknownCount.formatted())
                SmallTile(title: "Skipped bytes", value: s.skippedBytes.formatted())
            }
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Latest frame of each type").fontWeight(.semibold)
                        Spacer()
                        Button("Export raw log") { monitor.exportRawLog() }.buttonStyle(.bordered)
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            ForEach(["Type", "Rate", "Decoded", "Raw bytes"], id: \.self) {
                                Text($0).font(.system(size: 13)).foregroundStyle(P.ink3)
                            }
                        }
                        ForEach(Self.order + extra, id: \.self) { type in
                            let stats = s.typeStats[type]
                            Divider().overlay(P.line)
                            GridRow {
                                HStack(spacing: 6) {
                                    Text(String(format: "0x%02X", type)).font(.system(size: 13, design: .monospaced))
                                    Text(Self.names[type] ?? "Unknown")
                                }
                                .fixedSize()
                                Text(rate(stats, type: type)).monospacedDigit().fixedSize()
                                Text(decoded(stats?.lastFrame)).monospacedDigit().textSelection(.enabled)
                                Text(stats.map { Hex.string($0.lastRaw) } ?? Fmt.dash)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(P.ink2)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}
