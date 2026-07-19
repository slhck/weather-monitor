import Foundation

/// Free, key-less fallback used when Geosphere has no nearby station
/// (e.g. outside Austria) or is unreachable. https://open-meteo.com/
struct OpenMeteoClient {
    func temperature(latitude: Double, longitude: Double) async throws -> PointReading {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,dew_point_2m,wind_speed_10m"),
            // Match Geosphere's units so the apparent-temperature math is consistent.
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return PointReading(
            temperature: response.current.temperature_2m,
            humidity: response.current.relative_humidity_2m,
            windSpeed: response.current.wind_speed_10m,
            dewPoint: response.current.dew_point_2m,
            observationTime: parseTimestamp(response.current.time)
        )
    }

    /// Reads the hourly temperature timeseries for a coordinate over a window,
    /// for the history chart (used outside Austria / as a fallback).
    func history(latitude: Double, longitude: Double, start: Date, end: Date) async throws -> [Sample] {
        // Request whole past days covering the window, then trim to [start, end].
        let pastDays = min(92, max(1, Int((end.timeIntervalSince(start) / 86_400).rounded(.up)) + 1))
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(HistoryResponse.self, from: data)

        var samples: [Sample] = []
        for (index, time) in response.hourly.time.enumerated() {
            guard index < response.hourly.temperature_2m.count,
                  let date = utcHourFormatter.date(from: time),
                  date >= start, date <= end else { continue }
            samples.append(Sample(date: date, temperature: response.hourly.temperature_2m[index]))
        }
        return samples
    }

    /// Forecast fallback for coordinates outside GeoSphere's NWP grid.
    func forecast(latitude: Double, longitude: Double, end: Date) async throws -> [ForecastPoint] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let now = Date()
        var points: [ForecastPoint] = []
        for (index, timestamp) in response.hourly.time.enumerated() {
            guard index < response.hourly.temperature_2m.count,
                  index < response.hourly.precipitation.count,
                  let date = utcHourFormatter.date(from: timestamp),
                  date >= now, date <= end else { continue }
            points.append(ForecastPoint(
                date: date,
                temperature: response.hourly.temperature_2m[index],
                precipitation: response.hourly.precipitation[index]
            ))
        }
        return points
    }

    /// Open-Meteo returns naive timestamps (e.g. "2026-06-15T00:00"); with
    /// `timezone=UTC` they are UTC, so parse them as such.
    private let utcHourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    private struct Response: Decodable {
        let current: Current

        struct Current: Decodable {
            let temperature_2m: Double
            let relative_humidity_2m: Double?
            let dew_point_2m: Double?
            let wind_speed_10m: Double?
            let time: String
        }
    }

    private struct HistoryResponse: Decodable {
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
        }
    }

    private struct ForecastResponse: Decodable {
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let precipitation: [Double]
        }
    }
}
