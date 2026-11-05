import AppKit
import FNBCore
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
    func make(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? make(dark) : make(light)
    })
}

enum P {
    static let bg = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let plot = dyn(0x191B1E, 0xF7F7F5)
    static let line = dyn(0x303338, 0xDADAD6)
    static let grid = dyn(0x2C2F34, 0xE6E6E2)
    static let ctl = dyn(0x484C53, 0xB4B6BA)
    static let ctlOn = dyn(0x8A8E95, 0x6B6E74)
    static let fill = dyn(0x2C3036, 0xE7E8EA)
    static let ink = dyn(0xF2F2F0, 0x1A1B1D)
    static let strong = dyn(0xFFFFFF, 0x000000)
    static let ink2 = dyn(0xD7D9DC, 0x3A3C40)
    static let ink3 = dyn(0xBDBFC4, 0x55575C)
    static let ink4 = dyn(0xA8ABB0, 0x62646A)
    static let series1 = dyn(0x5AA9FF, 0x1F6FD1)
    static let series2 = dyn(0xE8793F, 0xC4501C)
    static let ok = dyn(0x4CC38A, 0x1A8F5A)
    static let warnDot = dyn(0xF5CF72, 0xB98900)
    static let badDot = dyn(0xFF8A8A, 0xC43030)
    static let okBg = dyn(0x163A2A, 0xDDF3E7)
    static let okFg = dyn(0x8FE3BB, 0x0F5C3A)
    static let warnBg = dyn(0x40320F, 0xFBEFC9)
    static let warnFg = dyn(0xF5CF72, 0x6B4E00)
    static let riskBg = dyn(0x4A1D1D, 0xFBDFDF)
    static let riskFg = dyn(0xFFB4B4, 0x8F1D1D)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(P.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false
    var divider = true
    var body: some View {
        VStack(spacing: 0) {
            if divider { Rectangle().fill(P.line).frame(height: 1) }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).foregroundStyle(P.ink3)
                Spacer(minLength: 8)
                Text(value)
                    .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 14))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 8)
        }
    }
}

enum Fmt {
    static let dash = "—"
    static func num(_ v: Double?, _ places: Int, _ unit: String = "") -> String {
        guard let v else { return dash }
        let s = String(format: "%.\(places)f", v)
        return unit.isEmpty ? s : "\(s) \(unit)"
    }
    static func clock(_ seconds: Double) -> String {
        let t = Int(seconds.rounded(.down))
        let h = t / 3600, m = t / 60 % 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    static func ohms(_ session: Session) -> String {
        guard session.hasStatus else { return dash }
        guard let o = session.ohms else { return "Open" }
        return o >= 1000 ? String(format: "%.1f kΩ", o / 1000) : String(format: "%.2f Ω", o)
    }
}
