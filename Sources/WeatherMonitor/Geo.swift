import Foundation

/// Great-circle distance between two coordinates, in meters.
func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let earthRadius = 6_371_000.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a1 = lat1 * .pi / 180
    let a2 = lat2 * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(a1) * cos(a2) * sin(dLon / 2) * sin(dLon / 2)
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
}

/// Parses the various timestamp shapes the weather APIs return.
/// Geosphere uses "2026-06-22T06:40+00:00"; Open-Meteo uses "2026-06-22T08:45".
func parseTimestamp(_ value: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value) { return date }

    for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm"] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        if let date = formatter.date(from: value) { return date }
    }
    return nil
}
