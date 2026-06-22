import Foundation

/// Everything the menu bar UI needs to render itself after a refresh.
struct DisplayState {
    var temperature: Double? = nil
    var stationName: String? = nil
    var distanceMeters: Double? = nil
    var observationTime: Date? = nil
    var source: String? = nil
    var locationSource: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var error: String? = nil
    /// How the history chart should fetch its timeseries for this reading.
    var historySource: HistorySource? = nil
}

/// Identifies where the history chart pulls its timeseries from, so it can
/// follow whichever station or location is currently shown.
enum HistorySource: Hashable {
    case geosphere(stationID: String, stationName: String)
    case openMeteo(latitude: Double, longitude: Double)
}

/// A selectable time window for the history chart.
enum HistoryRange: String, CaseIterable, Identifiable {
    case h12, h24, d3, d7, d14

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h12: return "12h"
        case .h24: return "24h"
        case .d3: return "3d"
        case .d7: return "7d"
        case .d14: return "14d"
        }
    }

    /// Length of the window in seconds.
    var duration: TimeInterval {
        switch self {
        case .h12: return 12 * 3_600
        case .h24: return 24 * 3_600
        case .d3: return 3 * 86_400
        case .d7: return 7 * 86_400
        case .d14: return 14 * 86_400
        }
    }
}

/// A weather station from the Geosphere metadata, used for the picker and lookups.
struct StationInfo: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let state: String
    let latitude: Double
    let longitude: Double
    let active: Bool
}

/// A temperature reading tied to a named weather station.
struct StationReading: Sendable {
    let temperature: Double
    let stationID: String
    let stationName: String
    let stationDistance: Double // meters from the user
    let observationTime: Date?
}

/// A temperature reading for a coordinate (no station, e.g. a forecast point).
struct PointReading: Sendable {
    let temperature: Double
    let observationTime: Date?
}

enum WeatherError: Error {
    case noData
}

enum LocationError: Error {
    case denied
    case timeout
    case unavailable
}
