import SwiftUI
import Charts

/// The temperature line-and-area chart shown inside the menu, with a labelled
/// time axis and a hover/drag scrubber that reads out the value at a point.
struct TemperatureChart: View {
    let samples: [Sample]
    let range: HistoryRange

    @State private var selected: Sample?

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("°C", sample.temperature)
                )
                .foregroundStyle(areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("°C", sample.temperature)
                )
                .foregroundStyle(lineGradient)
                .interpolationMethod(.catmullRom)
            }

            if let selected {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("Time", selected.date),
                    y: .value("°C", selected.temperature)
                )
                .foregroundStyle(TemperatureColor.color(for: selected.temperature))
                .symbolSize(50)
            }
        }
        .chartYScale(domain: domain)
        // Catmull-Rom can overshoot the data at sharp peaks/valleys; clip so the
        // smoothed curve and its fill never spill past the plot onto the buttons.
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: axisFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): select(at: location, proxy: proxy, geo: geo)
                            case .ended: selected = nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { select(at: $0.location, proxy: proxy, geo: geo) }
                                .onEnded { _ in selected = nil }
                        )

                    if let selected, let x = proxy.position(forX: selected.date) {
                        tooltip(selected)
                            .position(
                                x: clampedTooltipX(geo[proxy.plotAreaFrame].minX + x, width: geo.size.width),
                                y: 12
                            )
                    }
                }
            }
        }
    }

    private func tooltip(_ sample: Sample) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1f °C", sample.temperature))
                .font(.caption2.bold())
                .foregroundStyle(TemperatureColor.color(for: sample.temperature))
            Text(sample.date, format: pointFormat)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.gray.opacity(0.25)))
        .fixedSize()
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        let plot = geo[proxy.plotAreaFrame]
        let xInPlot = location.x - plot.minX
        guard xInPlot >= 0, xInPlot <= plot.width,
              let date = proxy.value(atX: xInPlot, as: Date.self) else { return }
        selected = samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func clampedTooltipX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let margin: CGFloat = 36
        return min(max(x, margin), max(margin, width - margin))
    }

    /// The visible temperature range, padded slightly so the line doesn't touch
    /// the top and bottom edges. Pinning the y-scale to this lets the colour
    /// gradient map a vertical position back to its actual temperature.
    private var domain: ClosedRange<Double> {
        let temps = samples.map(\.temperature)
        guard let lo = temps.min(), let hi = temps.max() else { return -20...40 }
        guard hi > lo else { return (lo - 1)...(hi + 1) }
        let pad = Swift.max((hi - lo) * 0.12, 0.5)
        return (lo - pad)...(hi + pad)
    }

    /// Colours the line by its value: each point is drawn in the colour that
    /// matches its temperature, since the gradient runs top-to-bottom over the
    /// same range the y-axis uses.
    private var lineGradient: LinearGradient {
        TemperatureColor.gradient(min: domain.lowerBound, max: domain.upperBound)
    }

    /// The same colour scale as the line, faded back for the fill underneath.
    private var areaGradient: LinearGradient {
        TemperatureColor.gradient(min: domain.lowerBound, max: domain.upperBound, opacity: 0.25)
    }

    /// Axis tick labels: clock time for intraday ranges, dates for longer ones.
    private var axisFormat: Date.FormatStyle {
        switch range {
        case .h12, .h24: return .dateTime.hour().minute()
        case .d3: return .dateTime.weekday(.abbreviated)
        case .d7, .d14: return .dateTime.month(.abbreviated).day()
        }
    }

    /// The scrubber readout's timestamp format.
    private var pointFormat: Date.FormatStyle {
        switch range {
        case .h12, .h24: return .dateTime.hour().minute()
        default: return .dateTime.month(.abbreviated).day().hour().minute()
        }
    }
}

/// Maps a temperature (°C) to a colour on a cold-to-warm scale: blue below
/// freezing, shifting to green around 20°C, then orange and red, and on to
/// violet toward 40°C. Used to colour the history chart by its value.
enum TemperatureColor {
    private struct Stop { let t, r, g, b: Double }

    /// Anchor colours, ascending by temperature. RGB is interpolated linearly
    /// between neighbours — the same blending SwiftUI applies to gradient stops.
    private static let stops: [Stop] = [
        Stop(t: -20, r: 0.20, g: 0.45, b: 0.95), // blue
        Stop(t:   0, r: 0.10, g: 0.70, b: 0.90), // cyan
        Stop(t:  20, r: 0.30, g: 0.78, b: 0.38), // green
        Stop(t:  25, r: 0.96, g: 0.62, b: 0.15), // orange
        Stop(t:  30, r: 0.90, g: 0.25, b: 0.20), // red
        Stop(t:  40, r: 0.62, g: 0.20, b: 0.82), // violet
    ]

    private static func rgb(for t: Double) -> (r: Double, g: Double, b: Double) {
        let first = stops.first!, last = stops.last!
        if t <= first.t { return (first.r, first.g, first.b) }
        if t >= last.t { return (last.r, last.g, last.b) }
        for i in 1..<stops.count where t <= stops[i].t {
            let lo = stops[i - 1], hi = stops[i]
            let f = (t - lo.t) / (hi.t - lo.t)
            return (lo.r + (hi.r - lo.r) * f,
                    lo.g + (hi.g - lo.g) * f,
                    lo.b + (hi.b - lo.b) * f)
        }
        return (last.r, last.g, last.b)
    }

    /// The colour for a single temperature.
    static func color(for t: Double) -> Color {
        let c = rgb(for: t)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// A top-to-bottom gradient spanning `min...max`, so that a point's vertical
    /// position in a chart with a matching y-scale lands on its own colour.
    static func gradient(min: Double, max: Double, opacity: Double = 1) -> LinearGradient {
        let span = Swift.max(max - min, 0.0001)
        // Top of the plot is the warmest value, so emit temperatures descending.
        let temps = ([max, min] + stops.map(\.t).filter { $0 > min && $0 < max })
            .sorted(by: >)
        let out = temps.map { t in
            Gradient.Stop(color: color(for: t).opacity(opacity), location: (max - t) / span)
        }
        return LinearGradient(stops: out, startPoint: .top, endPoint: .bottom)
    }
}

/// The compact history chart shown directly inside the menu bar dropdown,
/// with buttons to switch the time window.
struct MenuHistoryView: View {
    @ObservedObject var store: HistoryStore
    let source: HistorySource?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Temperature History")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }

            chart
                .frame(height: 110)

            HStack(spacing: 4) {
                ForEach(HistoryRange.allCases) { range in
                    rangeButton(range)
                }
            }

            Text(store.summary ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 340)
        .onAppear { store.activate(source: source) }
    }

    @ViewBuilder private var chart: some View {
        if store.samples.isEmpty {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    Text(source == nil ? "No data available" : "No readings for this range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
        } else {
            TemperatureChart(samples: store.samples, range: store.range)
        }
    }

    private func rangeButton(_ range: HistoryRange) -> some View {
        let selected = store.range == range
        return Button {
            store.range = range
        } label: {
            Text(range.label)
                .font(.caption2.weight(selected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
