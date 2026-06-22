import Foundation

/// Free, key-less fallback used when Geosphere has no nearby station
/// (e.g. outside Austria) or is unreachable. https://open-meteo.com/
struct OpenMeteoClient {
    func temperature(latitude: Double, longitude: Double) async throws -> PointReading {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return PointReading(
            temperature: response.current.temperature_2m,
            observationTime: parseTimestamp(response.current.time)
        )
    }

    private struct Response: Decodable {
        let current: Current

        struct Current: Decodable {
            let temperature_2m: Double
            let time: String
        }
    }
}
