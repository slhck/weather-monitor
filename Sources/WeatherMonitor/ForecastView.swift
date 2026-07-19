import SwiftUI
import Charts

/// One range control shared by both forecast charts.
struct ForecastRangePicker: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ForecastRange.allCases) { range in
                let selected = settings.forecastRange == range
                Button {
                    settings.forecastRange = range
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
    }
}

/// The shared panel shell for the two forecast charts.
private struct ForecastPanel<Content: View>: View {
    let title: String
    let isLoading: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 340)
    }
}

struct TemperatureForecastView: View {
    @ObservedObject var store: ForecastStore
    @ObservedObject var settings: AppSettings
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        ForecastPanel(title: "Temperature Forecast", isLoading: store.isLoading) {
            Group {
                if store.points.isEmpty {
                    emptyChart
                } else {
                    Chart(store.points) { point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("°C", point.temperature)
                        )
                        .foregroundStyle(areaStyle)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("°C", point.temperature)
                        )
                        .foregroundStyle(lineStyle)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis { forecastXAxis }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .chartPlotStyle { $0.clipped() }
                }
            }
            .frame(height: 90)

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            store.range = settings.forecastRange
            store.activate(latitude: latitude, longitude: longitude)
        }
        .onChange(of: settings.forecastRange) { newRange in store.range = newRange }
    }

    private var temperatures: [Double] { store.points.map(\.temperature) }

    private var lineStyle: LinearGradient {
        guard settings.colorfulCharts, let minimum = temperatures.min(), let maximum = temperatures.max() else {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
        }
        return TemperatureColor.gradient(min: minimum, max: maximum)
    }

    private var areaStyle: LinearGradient {
        guard settings.colorfulCharts, let minimum = temperatures.min(), let maximum = temperatures.max() else {
            return LinearGradient(
                colors: [Color.yellow.opacity(0.24), Color.orange.opacity(0.12)],
                startPoint: .top, endPoint: .bottom
            )
        }
        return TemperatureColor.gradient(min: minimum, max: maximum, opacity: 0.25)
    }

    private var summary: String {
        guard let minimum = temperatures.min(), let maximum = temperatures.max() else {
            return store.isLoading ? "Loading forecast…" : "No forecast available"
        }
        return String(format: "min %.1f °C · max %.1f °C · %@", minimum, maximum, store.sourceName ?? "")
    }

    private var emptyChart: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.08))
            .overlay(Text(store.isLoading ? "Loading…" : "No forecast available").font(.caption).foregroundStyle(.secondary))
    }

    @AxisContentBuilder private var forecastXAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: store.range == .h48 ? .dateTime.weekday(.abbreviated).hour() : .dateTime.hour())
        }
    }
}

struct PrecipitationForecastView: View {
    @ObservedObject var store: ForecastStore
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        ForecastPanel(title: "Precipitation Forecast", isLoading: store.isLoading) {
            Group {
                if store.points.isEmpty {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.08))
                        .overlay(Text(store.isLoading ? "Loading…" : "No forecast available").font(.caption).foregroundStyle(.secondary))
                } else {
                    Chart(store.points) { point in
                        BarMark(
                            x: .value("Time", point.date),
                            y: .value("mm", point.precipitation)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: store.range == .h48 ? .dateTime.weekday(.abbreviated).hour() : .dateTime.hour())
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                }
            }
            .frame(height: 90)

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { store.activate(latitude: latitude, longitude: longitude) }
    }

    private var summary: String {
        guard !store.points.isEmpty else {
            return store.isLoading ? "Loading forecast…" : "No forecast available"
        }
        let total = store.points.reduce(0) { $0 + $1.precipitation }
        return String(format: "total %.1f mm · %@", total, store.sourceName ?? "")
    }
}
