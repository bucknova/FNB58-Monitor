import AppKit
import FNBCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var monitor: Monitor?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { monitor?.stopRecording() }
}

enum Section: String, CaseIterable, Identifiable {
    case live = "Live", device = "Device", packets = "Packets", control = "Control"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .live: "waveform.path.ecg"
        case .device: "info.circle"
        case .packets: "list.bullet.rectangle"
        case .control: "slider.horizontal.3"
        }
    }
}

@main
struct FNB58MonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let monitor = Monitor()

    var body: some Scene {
        Window("FNB58 Monitor", id: "main") {
            RootView()
                .environment(monitor)
                .onAppear { delegate.monitor = monitor }
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 900)
        .commands {
            CommandGroup(after: .sidebar) {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.rawValue) { monitor.ui.section = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}

/// Uses the native split view and toolbar, which draw Liquid Glass themselves on macOS 26 and later.
/// Content stays on plain surfaces, because glass is meant for navigation and controls.
struct RootView: View {
    @Environment(Monitor.self) private var monitor
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue

    var body: some View {
        @Bindable var ui = monitor.ui
        NavigationSplitView {
            List(Section.allCases, selection: Binding<Section?>(
                get: { ui.section },
                set: { if let value = $0 { ui.section = value } })
            ) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
            }
        } detail: {
            ScrollView {
                VStack(spacing: 14) {
                    LinkBanner()
                    switch ui.section {
                    case .live: LiveView()
                    case .device: DeviceView()
                    case .packets: PacketsView()
                    case .control: ControlView()
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
            }
            .background(P.bg)
            .foregroundStyle(P.ink)
            .font(.system(size: 14))
            .navigationTitle(ui.section.rawValue)
            .navigationSubtitle(monitor.connected?.name ?? "")
            .toolbar { MonitorToolbar() }
        }
        .onAppear { (Appearance(rawValue: appearance) ?? .auto).apply() }
        .onChange(of: appearance) { _, value in (Appearance(rawValue: value) ?? .auto).apply() }
        .alert("Something went wrong", isPresented: Binding(
            get: { monitor.errorMessage != nil },
            set: { if !$0 { monitor.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(monitor.errorMessage ?? "")
        }
    }
}

struct MonitorToolbar: ToolbarContent {
    @Environment(Monitor.self) private var monitor

    private var dot: Color {
        switch monitor.link {
        case .streaming: .green
        case .noData, .scanning, .connecting, .handshaking, .starting: .yellow
        default: .red
        }
    }

    private var statusText: String {
        var parts = [monitor.link.label]
        if monitor.isConnected, let group = monitor.session.group?.group { parts.append("Group \(group)") }
        if let rssi = monitor.rssi { parts.append("\(rssi) dBm") }
        return parts.joined(separator: " · ")
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            let _ = monitor.tick
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(statusText).monospacedDigit().fixedSize()
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                monitor.toggleRecording()
            } label: {
                Label(monitor.recorder == nil ? "Record CSV" : "Stop recording",
                      systemImage: monitor.recorder == nil ? "record.circle" : "stop.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .tint(monitor.recorder == nil ? nil : .red)
        }
    }
}

struct LinkBanner: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        switch monitor.link {
        case .starting where monitor.waitingForPermission:
            banner("Waiting for Bluetooth access. If macOS is showing a permission prompt, choose Allow.") {
                Button("Open settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                }
                .buttonStyle(.bordered)
            }
        case .unauthorized:
            banner("FNB58 Monitor needs Bluetooth access to reach your tester. Turn it on in Privacy and Security, then reopen the app.") {
                Button("Open settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                }
                .buttonStyle(.bordered)
            }
        case .bluetoothOff:
            banner("Bluetooth is off. Turn it on to connect to your tester.") { EmptyView() }
        case .unsupported:
            banner("This Mac doesn't support Bluetooth LE, which the tester needs.") { EmptyView() }
        case .scanning:
            banner("Looking for your tester. Check that it's powered on and its Bluetooth is enabled.") { EmptyView() }
        case .noData:
            banner("Your tester is connected but has stopped sending data. Trying to restart the stream.") { EmptyView() }
        default:
            EmptyView()
        }
    }

    private func banner<Action: View>(_ text: String, @ViewBuilder action: () -> Action) -> some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                Text(text).foregroundStyle(P.ink2)
                Spacer(minLength: 8)
                action()
            }
        }
    }
}
