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
                .foregroundStyle(
                    .linearGradient(
                        colors: [.orange.opacity(0.35), .orange.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("°C", sample.temperature)
                )
                .foregroundStyle(.orange)
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
                .foregroundStyle(.orange)
                .symbolSize(50)
            }
        }
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
