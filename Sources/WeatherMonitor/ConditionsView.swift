import SwiftUI

/// Current conditions presented as a readable panel instead of disabled native
/// menu rows, whose system styling is intentionally dim.
struct ConditionsView: View {
    let state: DisplayState

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = state.error, state.temperature == nil {
                Text("⚠ \(error)")
            }

            if let temperature = state.temperature {
                Text(String(format: "%.1f °C", temperature))
                    .font(.title3.weight(.semibold))

                if let apparent = state.apparentTemperature {
                    Text(String(format: "Feels like %.1f °C · %@", apparent, comfortLabel(apparent: apparent)))
                }
                if let details = humidityAndDewPoint {
                    Text(details)
                }
                if let wind = state.windSpeed {
                    Text(String(format: "Wind %.1f m/s", wind))
                }
                Text(placeLine)
                if let observed = state.observationTime {
                    Text("Updated \(timeFormatter.string(from: observed))")
                }
                if let source = state.source {
                    Text("Source: \(source)")
                }
            }

            if let location = locationLine {
                Text(location)
            } else if let locationSource = state.locationSource {
                Text(locationSource)
            }
        }
        .font(.caption)
        .foregroundStyle(.primary.opacity(0.82))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 340, alignment: .leading)
        .background(Color.orange.opacity(0.09))
    }

    private var humidityAndDewPoint: String? {
        var parts: [String] = []
        if let humidity = state.humidity { parts.append(String(format: "Humidity %.0f%%", humidity)) }
        if let dewPoint = state.dewPoint { parts.append(String(format: "Dew point %.1f °C", dewPoint)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var placeLine: String {
        guard let name = state.stationName else { return "Forecast point" }
        guard let distance = state.distanceMeters else { return name.capitalized }
        return name.capitalized + String(format: " · %.1f km", distance / 1_000)
    }

    private var locationLine: String? {
        guard let latitude = state.latitude, let longitude = state.longitude else { return nil }
        let suffix = state.locationSource.map { " (\($0))" } ?? ""
        return String(format: "Location: %.3f, %.3f%@", latitude, longitude, suffix)
    }
}
