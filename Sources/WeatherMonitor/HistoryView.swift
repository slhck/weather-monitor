import SwiftUI
import Charts

struct HistoryView: View {
    @ObservedObject var history: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temperature History")
                .font(.title3.bold())

            if history.samples.isEmpty {
                Spacer()
                Text("No readings yet.\nData appears here as it is collected.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Chart(history.samples) { sample in
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
                .chartYAxisLabel("°C")
                .frame(minHeight: 280)

                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 380)
    }

    private var summary: String? {
        let temperatures = history.samples.map(\.temperature)
        guard let minimum = temperatures.min(), let maximum = temperatures.max() else { return nil }
        return String(
            format: "%d readings · min %.1f °C · max %.1f °C",
            history.samples.count, minimum, maximum
        )
    }
}
