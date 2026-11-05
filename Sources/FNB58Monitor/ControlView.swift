import FNBCore
import SwiftUI

struct ControlView: View {
    @Environment(Monitor.self) private var monitor
    private var ui: UIState { monitor.ui }

    private var frame: Data? {
        let op = ui.opcode.trimmingCharacters(in: .whitespaces)
        guard op.count == 2, let code = Hex.bytes(op)?.first,
              let body = Hex.bytes(ui.payload), body.count <= 255 else { return nil }
        return FNBProtocol.frame(opcode: code, payload: body)
    }

    var body: some View {
        @Bindable var monitor = monitor
        @Bindable var ui = monitor.ui
        VStack(spacing: 14) {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connection").fontWeight(.semibold)
                    HStack(spacing: 10) {
                        if monitor.isConnected || monitor.link == .connecting {
                            Button("Disconnect") { monitor.disconnect() }.buttonStyle(.bordered)
                        } else {
                            Button("Connect") { monitor.connectOrScan() }.buttonStyle(.bordered)
                        }
                        Button("Restart stream") { monitor.restartStream() }
                            .buttonStyle(.bordered)
                            .disabled(!monitor.isConnected)
                        Toggle("Reconnect automatically", isOn: $monitor.autoReconnect)
                            .toggleStyle(.checkbox)
                            .padding(.leading, 6)
                        Spacer()
                        Text("USB: planned after Bluetooth").foregroundStyle(P.ink3)
                    }
                    if !monitor.isConnected, !monitor.devices.isEmpty {
                        ForEach(monitor.devices) { device in
                            HStack {
                                Text(device.name).font(.system(size: 13, design: .monospaced))
                                Text("\(device.rssi) dBm").monospacedDigit().foregroundStyle(P.ink4)
                                Spacer()
                                Button("Connect") { monitor.connect(device) }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Device commands").fontWeight(.semibold).padding(.bottom, 6)
                    CommandRow(name: "Start measuring and streaming", op: "81, 82", status: "Works on your tester", bg: P.okBg, fg: P.okFg)
                    CommandRow(name: "Get trigger status", op: "85", status: "Works on your tester", bg: P.okBg, fg: P.okFg)
                    CommandRow(name: "List all groups", op: "8A", status: "Works on your tester", bg: P.okBg, fg: P.okFg)
                    CommandRow(name: "Stop streaming", op: "84", status: "Untested", bg: P.warnBg, fg: P.warnFg)
                    CommandRow(name: "Select group", op: "88", status: "Works on your tester", bg: P.okBg, fg: P.okFg)
                    CommandRow(name: "Stop trigger", op: "87", status: "Untested", bg: P.warnBg, fg: P.warnFg)
                    CommandRow(name: "Trigger fast charge", op: "86", status: "Untested, can raise voltage", bg: P.riskBg, fg: P.riskFg)
                    CommandRow(name: "Clear group", op: "89", status: "Untested, erases totals", bg: P.riskBg, fg: P.riskFg)
                    CommandRow(name: "Change settings", op: "", status: "No known command", bg: P.fill, fg: P.ink2)
                }
            }
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Command console").fontWeight(.semibold)
                    HStack(alignment: .bottom, spacing: 10) {
                        field("Opcode", text: $ui.opcode, prompt: "84").frame(width: 80)
                        field("Payload (hex)", text: $ui.payload, prompt: "None")
                        Button("Send") {
                            guard let frame else {
                                ui.message = "Enter a two-digit opcode and a payload in hex."
                                return
                            }
                            guard monitor.isConnected else {
                                ui.message = "Connect to your tester first."
                                return
                            }
                            ui.pending = frame
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 10) {
                        Text("Frame").foregroundStyle(P.ink3)
                        Text(frame.map { Hex.string($0) } ?? "Enter valid hex")
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Text(ui.message).font(.system(size: 13)).foregroundStyle(P.ink2)
                }
            }
        }
        .confirmationDialog("Send this command to your tester?", isPresented: Binding(
            get: { ui.pending != nil },
            set: { if !$0 { ui.pending = nil } })
        ) {
            Button("Send", role: .destructive) {
                guard let data = ui.pending else { return }
                if monitor.send(data) {
                    ui.message = "Sent \(Hex.string(data)). Check the Packets screen for what changed."
                } else {
                    ui.message = "It wasn't sent because the connection dropped."
                }
                ui.pending = nil
            }
        } message: {
            Text(warning)
        }
    }

    private var warning: String {
        let hex = ui.pending.map { Hex.string($0) } ?? ""
        switch ui.pending?.dropFirst().first {
        case 0x86:
            return "\(hex)\n\nThis can raise the voltage on anything connected, up to 20 V. Disconnect anything you wouldn't want exposed to that."
        case 0x89:
            return "\(hex)\n\nThis can permanently erase a stored group's totals."
        default:
            return "\(hex)\n\nYour tester's response to this command may be unknown."
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(P.ink3)
            TextField(title, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
        }
    }
}

struct CommandRow: View {
    let name: String, op: String, status: String
    let bg: Color, fg: Color
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(P.line).frame(height: 1)
            HStack(spacing: 8) {
                Text(name)
                Text(op).font(.system(size: 13, design: .monospaced)).foregroundStyle(P.ink3)
                Spacer()
                Text(status).font(.system(size: 13)).foregroundStyle(fg)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(bg, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.vertical, 9)
        }
    }
}
