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
