import SwiftUI

/// Dock-accessible weather UI for Macs where the status item is hidden by the
/// notch or by other menu bar items.
struct WeatherWindowView: View {
    let state: DisplayState
    @ObservedObject var history: HistoryStore
    @ObservedObject var forecast: ForecastStore
    @ObservedObject var settings: AppSettings
    let refresh: () -> Void
    let openPreferences: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Weather Monitor")
                    .font(.headline)
                Spacer()
                Text("Forecast")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForecastRangePicker(settings: settings)
                    .frame(width: 150)
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Refresh now")
                Button(action: openPreferences) {
                    Label("Preferences", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("Preferences")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        ConditionsView(state: state)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        MenuHistoryView(store: history, settings: settings, source: state.historySource)
                            .background(warmPanelBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .gridCellAnchor(.top)

                    GridRow {
                        TemperatureForecastView(
                            store: forecast, settings: settings,
                            latitude: state.latitude, longitude: state.longitude
                        )
                        .background(warmPanelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        PrecipitationForecastView(
                            store: forecast,
                            latitude: state.latitude, longitude: state.longitude
                        )
                        .background(precipitationPanelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .gridCellAnchor(.top)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private var warmPanelBackground: some View {
        Color.orange.opacity(0.07)
    }

    private var precipitationPanelBackground: some View {
        Color.blue.opacity(0.08)
    }
}
