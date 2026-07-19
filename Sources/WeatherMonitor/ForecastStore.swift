import Foundation
import Combine

/// One hourly forecast point used by both forecast panels.
struct ForecastPoint: Identifiable, Hashable, Sendable {
    let date: Date
    let temperature: Double
    let precipitation: Double
    var id: Date { date }
}

/// Loads and caches the forecast shared by the temperature and precipitation
/// panels. GeoSphere's NWP forecast is primary; Open-Meteo covers locations
/// outside that model grid or temporary GeoSphere failures.
@MainActor
final class ForecastStore: ObservableObject {
    @Published private(set) var points: [ForecastPoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var sourceName: String?
    @Published var range: ForecastRange {
        didSet { if range != oldValue { reload() } }
    }

    private let geosphere: GeosphereClient
    private let openMeteo: OpenMeteoClient
    private var coordinate: Coordinate?
    private var cache: [CacheKey: Result] = [:]
    private var loadingKey: CacheKey?

    private struct Coordinate: Hashable {
        let latitude: Double
        let longitude: Double
    }

    private struct CacheKey: Hashable {
        let coordinate: Coordinate
        let range: ForecastRange
    }

    private struct Result {
        let points: [ForecastPoint]
        let sourceName: String
    }

    init(geosphere: GeosphereClient, openMeteo: OpenMeteoClient, range: ForecastRange) {
        self.geosphere = geosphere
        self.openMeteo = openMeteo
        self.range = range
    }

    func activate(latitude: Double?, longitude: Double?) {
        let next = latitude.flatMap { latitude in
            longitude.map { Coordinate(latitude: latitude, longitude: $0) }
        }
        if next != coordinate {
            coordinate = next
            points = []
            sourceName = nil
        }
        reload()
    }

    func forceReload(latitude: Double?, longitude: Double?) {
        activate(latitude: latitude, longitude: longitude)
        if let coordinate {
            cache[CacheKey(coordinate: coordinate, range: range)] = nil
        }
        reload()
    }

    func invalidate() {
        cache.removeAll()
    }

    private func reload() {
        guard let coordinate else {
            points = []
            isLoading = false
            sourceName = nil
            loadingKey = nil
            return
        }

        let range = self.range
        let key = CacheKey(coordinate: coordinate, range: range)
        if let cached = cache[key] {
            apply(cached, for: key)
            return
        }
        if loadingKey == key { return }

        loadingKey = key
        isLoading = true
        Task {
            let result = await fetch(coordinate: coordinate, range: range)
            cache[key] = result
            if loadingKey == key { loadingKey = nil }
            apply(result, for: key)
        }
    }

    private func fetch(coordinate: Coordinate, range: ForecastRange) async -> Result {
        let end = Date().addingTimeInterval(range.duration)
        if let points = try? await geosphere.forecast(
            latitude: coordinate.latitude, longitude: coordinate.longitude, end: end
        ), !points.isEmpty {
            return Result(points: trim(points, through: end), sourceName: "GeoSphere NWP")
        }

        let points = (try? await openMeteo.forecast(
            latitude: coordinate.latitude, longitude: coordinate.longitude, end: end
        )) ?? []
        return Result(points: trim(points, through: end), sourceName: "Open-Meteo")
    }

    private func trim(_ points: [ForecastPoint], through end: Date) -> [ForecastPoint] {
        let now = Date().addingTimeInterval(-3_600)
        return points.filter { $0.date >= now && $0.date <= end }
    }

    private func apply(_ result: Result, for key: CacheKey) {
        guard coordinate == key.coordinate, range == key.range else { return }
        points = result.points
        sourceName = result.sourceName
        isLoading = false
    }
}
