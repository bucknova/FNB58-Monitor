import FNBCore
import SwiftUI

struct LiveView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        let _ = monitor.tick
        let s = monitor.session
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HeroTile(title: "Voltage", value: Fmt.num(s.volts, 3), unit: "V", detail: "Precise " + Fmt.num(s.preciseVolts, 4, "V"))
                HeroTile(title: "Current", value: Fmt.num(s.amps, 3), unit: "A", detail: "Precise " + Fmt.num(s.preciseAmps, 4, "A"))
                HeroTile(title: "Power", value: Fmt.num(s.watts, 2), unit: "W", detail: "Precise " + Fmt.num(s.preciseWatts, 4, "W"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                SmallTile(title: "D+", value: Fmt.num(s.dPlus, 3, "V"))
                SmallTile(title: "D−", value: Fmt.num(s.dMinus, 3, "V"))
                SmallTile(title: "Temperature", value: Fmt.num(s.celsius, 1, "°C"))
                SmallTile(title: "Load", value: Fmt.ohms(s))
                SmallTile(title: "Session energy", value: Fmt.num(s.energyWh, 3, "Wh"))
                SmallTile(title: "Session charge", value: Fmt.num(s.chargeAh * 1000, 1, "mAh"))
            }
            Card(padding: 12) {
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Text("Detected").foregroundStyle(P.ink3)
                        Text(s.detectedProtocols ?? Fmt.dash)
                    }
                    HStack(spacing: 8) {
                        Text("Trigger").foregroundStyle(P.ink3)
                        Text(s.triggerStatus.map { FNBProtocol.describeTrigger($0) } ?? Fmt.dash)
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
            HistoryCard()
        }
    }
}

struct HeroTile: View {
    let title: String, value: String, unit: String, detail: String
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).foregroundStyle(P.ink3)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.system(size: 44, weight: .medium)).monospacedDigit()
                    Text(unit).font(.system(size: 18)).foregroundStyle(P.ink3)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.system(size: 13)).monospacedDigit().foregroundStyle(P.ink4)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SmallTile: View {
    let title: String, value: String
    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(P.ink3)
                Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum TimeWindow: Double, CaseIterable, Identifiable {
    case s30 = 30, m1 = 60, m5 = 300, h1 = 3600, all = 0
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .s30: "30 s"
        case .m1: "1 min"
        case .m5: "5 min"
        case .h1: "1 h"
        case .all: "All"
        }
    }
}

struct ChartSeries {
    let name: String
    let color: Color
    let get: (Sample) -> Double
}

struct HistoryCard: View {
    @Environment(Monitor.self) private var monitor
    private var ui: UIState { monitor.ui }

    private func visible(_ all: [Sample]) -> ArraySlice<Sample> {
        guard ui.window != .all, let end = all.last?.t else { return all[...] }
        let cutoff = end - ui.window.rawValue
        var lo = 0, hi = all.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if all[mid].t < cutoff { lo = mid + 1 } else { hi = mid }
        }
        return all[lo...]
    }

    var body: some View {
        @Bindable var ui = monitor.ui
        let _ = monitor.tick
        let data = visible(monitor.session.samples)
        Card(padding: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("History").fontWeight(.semibold)
                    Spacer()
                    Picker("Time range", selection: $ui.window) {
                        ForEach(TimeWindow.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: ui.window) { _, _ in ui.hover = nil }
                    Button("Reset session") { ui.confirmReset = true }.buttonStyle(.bordered)
                }
                if data.count < 2 {
                    Text("Charts appear once your tester starts sending data.")
                        .foregroundStyle(P.ink3)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    let single = { (name: String, get: @escaping (Sample) -> Double) in
                        [ChartSeries(name: name, color: P.series1, get: get)]
                    }
                    MetricChart(title: "Voltage", unit: "V", places: 3, minSpan: 0.5, series: single("Voltage") { $0.volts }, data: data, hover: $ui.hover)
                    MetricChart(title: "Current", unit: "A", places: 3, minSpan: 0.5, series: single("Current") { $0.amps }, data: data, hover: $ui.hover)
                    MetricChart(title: "Power", unit: "W", places: 2, minSpan: 2, series: single("Power") { $0.watts }, data: data, hover: $ui.hover)
                    MetricChart(title: "Data lines", unit: "V", places: 3, minSpan: 0.5,
                                series: [ChartSeries(name: "D+", color: P.series1) { $0.dPlus },
                                         ChartSeries(name: "D−", color: P.series2) { $0.dMinus }],
                                data: data, hover: $ui.hover)
                    MetricChart(title: "Temperature", unit: "°C", places: 1, minSpan: 2, series: single("Temperature") { $0.celsius }, data: data, hover: $ui.hover)
                    HStack {
                        Text(Fmt.clock(data.first!.t - monitor.session.samples.first!.t))
                        Spacer()
                        Text(Fmt.clock(data.last!.t - monitor.session.samples.first!.t))
                    }
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(P.ink4)
                    .padding(.leading, 72)
                }
            }
        }
        .confirmationDialog("Reset this session?", isPresented: $ui.confirmReset) {
            Button("Reset session", role: .destructive) { monitor.session.resetSession() }
        } message: {
            Text("This clears the charts, session totals, and activity logs. Totals stored on your tester aren't affected.")
        }
    }
}

struct MetricChart: View {
    let title: String
    let unit: String
    let places: Int
    let minSpan: Double
    let series: [ChartSeries]
    let data: ArraySlice<Sample>
    @Binding var hover: CGFloat?

    private struct Plot {
        var low: Double, high: Double
        // Per series: min and max per bucket, so short spikes survive when zoomed out.
        var lines: [[(x: CGFloat, low: Double, high: Double)]]
    }

    private func makePlot() -> Plot {
        let buckets = 500
        let n = data.count
        var low = Double.infinity, high = -Double.infinity
        var lines: [[(x: CGFloat, low: Double, high: Double)]] = []
        let start = data.startIndex
        for s in series {
            var line: [(x: CGFloat, low: Double, high: Double)] = []
            if n <= buckets {
                line.reserveCapacity(n)
                for i in 0..<n {
                    let v = s.get(data[start + i])
                    line.append((CGFloat(i) / CGFloat(n - 1), v, v))
                    low = min(low, v); high = max(high, v)
                }
            } else {
                line.reserveCapacity(buckets)
                for b in 0..<buckets {
                    let from = start + b * n / buckets, to = start + (b + 1) * n / buckets
                    var l = Double.infinity, h = -Double.infinity
                    for i in from..<to {
                        let v = s.get(data[i])
                        l = min(l, v); h = max(h, v)
                    }
                    line.append((CGFloat(b) / CGFloat(buckets - 1), l, h))
                    low = min(low, l); high = max(high, h)
                }
            }
            lines.append(line)
        }
        if high - low < minSpan {
            let mid = (high + low) / 2
            low = mid - minSpan / 2
            high = mid + minSpan / 2
        }
        return Plot(low: low, high: high, lines: lines)
    }

    private var readIndex: Int {
        guard let hover else { return data.endIndex - 1 }
        return data.startIndex + min(data.count - 1, max(0, Int((hover * CGFloat(data.count - 1)).rounded())))
    }

    private var reading: String {
        let sample = data[readIndex]
        let values = series.map { (series.count > 1 ? "\($0.name) " : "") + String(format: "%.\(places)f", $0.get(sample)) + " " + unit }
        return values.joined(separator: "   ")
    }

    var body: some View {
        let plot = makePlot()
        let colors = series.map(\.color)
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Text(title).foregroundStyle(P.ink3)
                if series.count > 1 {
                    ForEach(series.indices, id: \.self) { i in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(series[i].color).frame(width: 10, height: 10)
                            Text(series[i].name).foregroundStyle(P.ink3)
                        }
                    }
                }
                Spacer()
                Text(reading).monospacedDigit()
            }
            .font(.system(size: 13))
            .padding(.leading, 72)
            HStack(spacing: 10) {
                VStack(alignment: .trailing) {
                    Text(String(format: "%.\(max(1, places - 1))f", plot.high))
                    Spacer()
                    Text(String(format: "%.\(max(1, places - 1))f", plot.low))
                }
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(P.ink4)
                .frame(width: 62, alignment: .trailing)
                GeometryReader { geo in
                    Canvas { ctx, size in
                        let pad = (plot.high - plot.low) * 0.1
                        let lo = plot.low - pad, hi = plot.high + pad
                        func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - lo) / (hi - lo)) * size.height }
                        var mid = Path()
                        mid.move(to: CGPoint(x: 0, y: size.height / 2))
                        mid.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        ctx.stroke(mid, with: .color(P.grid), lineWidth: 1)
                        for (index, line) in plot.lines.enumerated() {
                            var path = Path()
                            for (i, p) in line.enumerated() {
                                let x = p.x * size.width
                                if i == 0 {
                                    path.move(to: CGPoint(x: x, y: y(p.low)))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y(p.low)))
                                }
                                if p.high != p.low { path.addLine(to: CGPoint(x: x, y: y(p.high))) }
                            }
                            ctx.stroke(path, with: .color(colors[index]),
                                       style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        }
                        if let hover {
                            var cross = Path()
                            cross.move(to: CGPoint(x: hover * size.width, y: 0))
                            cross.addLine(to: CGPoint(x: hover * size.width, y: size.height))
                            ctx.stroke(cross, with: .color(P.ink2), lineWidth: 1)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(point): hover = max(0, min(1, point.x / max(1, geo.size.width)))
                        case .ended: hover = nil
                        }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(title) history")
                .accessibilityValue(reading)
            }
            .frame(height: 92)
        }
    }
}
