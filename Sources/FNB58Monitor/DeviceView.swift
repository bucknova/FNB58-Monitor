import FNBCore
import SwiftUI

struct DeviceView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let _ = monitor.tick
        let s = monitor.session
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your tester").fontWeight(.semibold).padding(.bottom, 6)
                        InfoRow(label: "Model", value: s.info.map { "FNB\($0.model)" } ?? Fmt.dash, divider: false)
                        InfoRow(label: "Serial number", value: s.info.map { "\($0.serial)" } ?? Fmt.dash)
                        InfoRow(label: "Firmware", value: s.info.map { "v\($0.firmwareVersion)" } ?? Fmt.dash)
                        InfoRow(label: "Boot count", value: s.info.map { "\($0.bootCount)" } ?? Fmt.dash)
                        InfoRow(label: "Bluetooth address", value: monitor.connected?.address ?? Fmt.dash, mono: true)
                        InfoRow(label: "Time since power-on", value: s.group.map { Fmt.clock(Double($0.uptimeSeconds)) } ?? Fmt.dash)
                    }
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.group.map { "Stored on the tester, group \($0.group)" } ?? "Stored on the tester")
                            .fontWeight(.semibold).padding(.bottom, 6)
                        InfoRow(label: "Energy", value: Fmt.num(s.group?.energyWh, 3, "Wh"), divider: false)
                        InfoRow(label: "Capacity", value: Fmt.num(s.group?.capacityAh, 3, "Ah"))
                        InfoRow(label: "Active time", value: s.group.map { Fmt.clock(Double($0.activeSeconds)) } ?? Fmt.dash)
                        Text("During this session").font(.system(size: 13, weight: .semibold)).foregroundStyle(P.ink2)
                            .padding(.top, 12).padding(.bottom, 2)
                        InfoRow(label: "Tester added", value: s.groupDelta.map {
                            String(format: "%.4f Wh, %.1f mAh", $0.energyWh, $0.capacityAh * 1000)
                        } ?? Fmt.dash, divider: false)
                        InfoRow(label: "App calculated", value: String(format: "%.4f Wh, %.1f mAh", s.energyWh, s.chargeAh * 1000))
                    }
                }
            }
            AllGroupsCard()
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Charger activity").fontWeight(.semibold)
                    Text("Moments the tester's detected protocols changed, newest first. Detected now: \(s.detectedProtocols ?? Fmt.dash).")
                        .font(.system(size: 13)).foregroundStyle(P.ink3)
                    if s.events.isEmpty {
                        Text("Nothing yet. Connect a load to see the handshake.")
                            .foregroundStyle(P.ink3).padding(.vertical, 12)
                    } else {
                        EventsTable(events: s.events)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voltage steps").fontWeight(.semibold)
                        Text("Each time VBUS settled at a new level, newest first. Peak this session: \(Fmt.num(s.voltRange?.high, 2, "V")).")
                            .font(.system(size: 13)).foregroundStyle(P.ink3)
                        if s.steps.isEmpty {
                            Text("None yet. Fast-charge and PD tools show up here.")
                                .foregroundStyle(P.ink3).padding(.vertical, 12)
                        } else {
                            StepsTable(steps: s.steps)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tester restarts").fontWeight(.semibold)
                        Text("Noticed when the boot count changes after reconnecting, newest first.")
                            .font(.system(size: 13)).foregroundStyle(P.ink3)
                        if s.restarts.isEmpty {
                            Text("None this session. PD tools restart the tester.")
                                .foregroundStyle(P.ink3).padding(.vertical, 12)
                        } else {
                            ForEach(s.restarts.suffix(20).reversed()) { r in
                                InfoRow(label: monitor.clock(r.t),
                                        value: r.toBoot == r.fromBoot + 1 ? "Boot \(r.toBoot)" : "Boot \(r.fromBoot) to \(r.toBoot)")
                            }
                        }
                    }
                }
                .frame(maxWidth: 340)
            }
        }
    }
}

struct AllGroupsCard: View {
    @Environment(Monitor.self) private var monitor

    private struct Row: Identifiable {
        let id: UInt8
        let energy: Double
        let capacity: Double
        let seconds: UInt32?
    }

    var body: some View {
        let s = monitor.session
        let selected = s.group?.group ?? s.info?.currentGroup
        let ids = Set(s.groupList.keys).union(s.groups.keys).sorted()
        let rows: [Row] = ids.compactMap { id in
            let live = s.groups[id]
            let listed = s.groupList[id]
            // The selected group's live packet is newer than the list, and only it has active time.
            let energy = id == selected ? (live?.energyWh ?? listed?.energyWh) : (listed?.energyWh ?? live?.energyWh)
            let capacity = id == selected ? (live?.capacityAh ?? listed?.capacityAh) : (listed?.capacityAh ?? live?.capacityAh)
            guard let energy, let capacity else { return nil }
            return Row(id: id, energy: energy, capacity: capacity, seconds: live?.activeSeconds)
        }
        let shown = rows.filter { $0.energy > 0 || $0.capacity > 0 || $0.id == selected }
        let empty = rows.count - shown.count
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("All groups").fontWeight(.semibold)
                    Spacer()
                    Button("Refresh") { monitor.refreshDeviceState() }
                        .buttonStyle(.bordered)
                        .disabled(!monitor.isConnected)
                }
                if rows.isEmpty {
                    Text("Group totals appear once your tester is connected.").foregroundStyle(P.ink3)
                } else {
                    HStack(spacing: 10) {
                        Text("Selected group").foregroundStyle(P.ink3)
                        Picker("Selected group", selection: Binding<UInt8>(
                            get: { monitor.pendingGroup ?? selected ?? 1 },
                            set: { monitor.selectGroup($0) })
                        ) {
                            ForEach(1...max(UInt8(1), s.info?.groupCount ?? UInt8(rows.count)), id: \.self) { id in
                                Text("\(id)").tag(id)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!monitor.isConnected)
                        if let notice = monitor.groupNotice {
                            Text(notice).font(.system(size: 13)).foregroundStyle(P.riskFg)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 7) {
                        GridRow {
                            ForEach(["Group", "Energy", "Capacity", "Active time"], id: \.self) {
                                Text($0).font(.system(size: 13)).foregroundStyle(P.ink3)
                            }
                        }
                        ForEach(shown) { row in
                            Divider().overlay(P.line)
                            GridRow {
                                Text(row.id == selected ? "\(row.id), selected" : "\(row.id)")
                                Text(Fmt.num(row.energy, 3, "Wh"))
                                Text(Fmt.num(row.capacity, 3, "Ah"))
                                Text(row.seconds.map { Fmt.clock(Double($0)) } ?? Fmt.dash)
                            }
                            .monospacedDigit()
                        }
                    }
                    if empty > 0 {
                        Text(empty == 1 ? "1 other group is empty." : "\(empty) other groups are empty.")
                            .font(.system(size: 13)).foregroundStyle(P.ink3)
                    }
                }
            }
        }
    }
}

struct EventsTable: View {
    @Environment(Monitor.self) private var monitor
    let events: [HandshakeEvent]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
            GridRow {
                ForEach(["Time", "D+", "D−", "Voltage", "Current", "Detected"], id: \.self) { title in
                    Text(title).font(.system(size: 13)).foregroundStyle(P.ink3)
                }
            }
            ForEach(events.suffix(40).reversed()) { e in
                Divider().overlay(P.line)
                GridRow {
                    Text(monitor.clock(e.t, tenths: true))
                    Text(Fmt.num(e.dPlus, 3, "V"))
                    Text(Fmt.num(e.dMinus, 3, "V"))
                    Text(Fmt.num(e.volts, 3, "V"))
                    Text(Fmt.num(e.amps, 3, "A"))
                    Text(e.marker.count == 2 ? FNBProtocol.describeDetected(e.marker[0], e.marker[1]) : Hex.string(e.marker))
                }
                .monospacedDigit()
            }
        }
    }
}

struct StepsTable: View {
    @Environment(Monitor.self) private var monitor
    let steps: [VoltageStep]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
            GridRow {
                ForEach(["Time", "From", "To", "Current", "D+", "D−"], id: \.self) { title in
                    Text(title).font(.system(size: 13)).foregroundStyle(P.ink3)
                }
            }
            ForEach(steps.suffix(40).reversed()) { step in
                Divider().overlay(P.line)
                GridRow {
                    Text(monitor.clock(step.t, tenths: true))
                    Text(Fmt.num(step.from, 2, "V"))
                    Text(Fmt.num(step.to, 2, "V"))
                    Text(Fmt.num(step.amps, 3, "A"))
                    Text(Fmt.num(step.dPlus, 2, "V"))
                    Text(Fmt.num(step.dMinus, 2, "V"))
                }
                .monospacedDigit()
            }
        }
    }
}
