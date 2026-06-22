import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var stationStore: StationStore

    private let refreshOptions = [5, 10, 15, 30, 60]

    private var sortedStations: [StationInfo] {
        stationStore.stations.filter { $0.active }.sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Picker("Refresh every", selection: $settings.refreshMinutes) {
                ForEach(refreshOptions, id: \.self) { minutes in
                    Text(label(forMinutes: minutes)).tag(minutes)
                }
            }

            Picker("Location", selection: $settings.stationOverrideID) {
                Text("Automatic (my location)").tag("")
                ForEach(sortedStations) { station in
                    Text(label(for: station)).tag(station.id)
                }
            }
            if sortedStations.isEmpty {
                Text("Loading stations…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 220)
    }

    private func label(forMinutes minutes: Int) -> String {
        minutes == 60 ? "1 hour" : "\(minutes) minutes"
    }

    private func label(for station: StationInfo) -> String {
        let name = station.name.capitalized
        return station.state.isEmpty ? name : "\(name) — \(station.state)"
    }
}
