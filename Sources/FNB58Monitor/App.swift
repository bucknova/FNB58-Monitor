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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 900)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { monitor.ui.sidebarVisible.toggle() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.rawValue) { monitor.ui.section = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
    }
}

/// macOS 27's native split view draws its sidebar flush with the window, so the floating sidebar is
/// built here: an inset panel using the system's Liquid Glass material, beside plain content.
struct RootView: View {
    @Environment(Monitor.self) private var monitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = Appearance.auto.rawValue

    private static let sidebarWidth: CGFloat = 212
    private static let margin: CGFloat = 8

    var body: some View {
        @Bindable var ui = monitor.ui
        ZStack(alignment: .topLeading) {
            DetailColumn(leadingInset: ui.sidebarVisible ? Self.sidebarWidth + Self.margin : 0)
            if ui.sidebarVisible {
                FloatingSidebar(appearance: $appearance)
                    .frame(width: Self.sidebarWidth)
                    .padding(Self.margin)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: ui.sidebarVisible)
        .background(P.window)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar { MonitorToolbar() }
        .chromelessToolbar()
        .onAppear {
            (Appearance(rawValue: appearance) ?? .auto).apply()
            // With no title bar to grab, let empty background areas move the window.
            NSApp.windows.forEach { $0.isMovableByWindowBackground = true }
        }
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

struct SidebarToggle: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        Button {
            monitor.ui.sidebarVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(monitor.ui.sidebarVisible ? "Hide sidebar" : "Show sidebar")
    }
}

struct FloatingSidebar: View {
    @Environment(Monitor.self) private var monitor
    @Binding var appearance: String

    var body: some View {
        @Bindable var ui = monitor.ui
        VStack(spacing: 0) {
            // The window's close, minimize, and zoom buttons sit over this row.
            HStack {
                Spacer()
                SidebarToggle().buttonStyle(.borderless)
            }
            .frame(height: 30)
            .padding(.top, 6)
            .padding(.horizontal, 12)
            List(Section.allCases, selection: Binding<Section?>(
                get: { ui.section },
                set: { if let value = $0 { ui.section = value } })
            ) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .floatingGlass(cornerRadius: 18)
    }
}

struct DetailColumn: View {
    @Environment(Monitor.self) private var monitor
    let leadingInset: CGFloat

    var body: some View {
        let ui = monitor.ui
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
            .padding(EdgeInsets(top: 8, leading: leadingInset + 12, bottom: 24, trailing: 20))
        }
        .foregroundStyle(P.ink)
        .font(.system(size: 14))
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailHeader(leadingInset: leadingInset)
        }
    }
}

struct DetailHeader: View {
    @Environment(Monitor.self) private var monitor
    let leadingInset: CGFloat

    var body: some View {
        let _ = monitor.tick
        HStack(spacing: 12) {
            if !monitor.ui.sidebarVisible {
                // Clears the window's close, minimize, and zoom buttons.
                SidebarToggle().glassControl().padding(.leading, 76)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(monitor.ui.section.rawValue).font(.system(size: 15, weight: .semibold))
                if let name = monitor.connected?.name {
                    Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        .frame(height: 36)
        .padding(.leading, leadingInset + 12)
        .padding(.trailing, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(P.window.opacity(0.92))
    }
}

/// Status and recording stay in the native toolbar, which draws true Liquid Glass controls.
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

    private var status: some View {
        let _ = monitor.tick
        return HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(statusText).monospacedDigit().foregroundStyle(.secondary).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    var body: some ToolbarContent {
        // Status isn't a control, so it sits on the bar without a glass capsule of its own.
        // The bar has no title, so a flexible spacer keeps these at the trailing edge.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) { status }
                .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
        } else {
            ToolbarItem(placement: .primaryAction) { status }
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

private extension View {
    /// The system's Liquid Glass where available, otherwise its closest translucent material.
    @ViewBuilder
    func floatingGlass(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 2)
        }
    }

    @ViewBuilder
    func glassControl() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Removes the window title and hard line from the toolbar, leaving only its controls.
    @ViewBuilder
    func chromelessToolbar() -> some View {
        if #available(macOS 26.0, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
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
            banner("Looking for your tester. Check that it's powered on, its Bluetooth is enabled, and no other app or phone is connected to it. It only accepts one connection at a time.") { EmptyView() }
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
