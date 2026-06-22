import Foundation

/// Everything the menu bar UI needs to render itself after a refresh.
struct DisplayState {
    var temperature: Double?
    var stationName: String?
    var distanceMeters: Double?
    var observationTime: Date?
    var source: String?
    var locationSource: String?
    var latitude: Double?
    var longitude: Double?
    var error: String?
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
