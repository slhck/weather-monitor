import Foundation
import Combine

/// One temperature reading — a single point on the chart.
struct Sample: Identifiable, Hashable {
    let date: Date
    let temperature: Double
    var id: Date { date }
}

/// Fetches the temperature history for the currently shown station or location
/// on demand and keeps each (source, range) result in memory, so switching
/// ranges — or returning to a station you've already viewed — is instant.
/// Nothing is stored on disk; the authoritative history lives on the APIs.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var isLoading = false
    @Published var range: HistoryRange = .h24 {
        didSet { if range != oldValue { reload() } }
    }

    private let geosphere: GeosphereClient
    private let openMeteo: OpenMeteoClient

    private var source: HistorySource?
    private var cache: [CacheKey: [Sample]] = [:]
    private var loadingKey: CacheKey?

    private struct CacheKey: Hashable {
        let source: HistorySource
        let range: HistoryRange
    }

    init(geosphere: GeosphereClient, openMeteo: OpenMeteoClient) {
        self.geosphere = geosphere
        self.openMeteo = openMeteo
    }

    /// Point the chart at the current data source, reusing cached data when it's
    /// available (called when the chart view appears).
    func activate(source: HistorySource?) {
        if source != self.source {
            self.source = source
            samples = [] // don't keep showing the previous station's curve
        }
        reload()
    }

    /// Point the chart at `source` and pull a fresh window ending now, ignoring
    /// any cached copy. Called when the menu opens so the chart is never stale.
    func forceReload(source: HistorySource?) {
        if source != self.source {
            self.source = source
            samples = []
        }
        if let source {
            cache[CacheKey(source: source, range: range)] = nil
        }
        reload()
    }

    /// Forget all cached lookups so the next view fetches fresh data. Called
    /// after a live refresh so the chart's most recent point stays current.
    func invalidate() {
        cache.removeAll()
    }

    private func reload() {
        guard let source else {
            samples = []
            isLoading = false
            loadingKey = nil
            return
        }

        let range = self.range
        let key = CacheKey(source: source, range: range)
        if let cached = cache[key] {
            samples = cached
            isLoading = false
            return
        }
        // A fetch for this exact view is already running; let it finish rather
        // than firing a second identical request.
        if loadingKey == key { return }

        loadingKey = key
        isLoading = true
        Task {
            let result = await fetch(source: source, range: range)
            cache[key] = result
            loadingKey = nil
            // Only display it if the user hasn't switched away in the meantime.
            if self.source == source && self.range == range {
                samples = result
                isLoading = false
            }
        }
    }

    private func fetch(source: HistorySource, range: HistoryRange) async -> [Sample] {
        let end = Date()
        let start = end.addingTimeInterval(-range.duration)
        let raw: [Sample]
        switch source {
        case let .geosphere(stationID, _):
            raw = (try? await geosphere.history(stationID: stationID, start: start, end: end)) ?? []
        case let .openMeteo(latitude, longitude):
            raw = (try? await openMeteo.history(latitude: latitude, longitude: longitude, start: start, end: end)) ?? []
        }
        return downsample(raw, max: 400)
    }

    /// Thins a dense series so the small menu chart stays light, always keeping
    /// the most recent point.
    private func downsample(_ samples: [Sample], max: Int) -> [Sample] {
        guard samples.count > max, max > 1 else { return samples }
        let step = Int((Double(samples.count) / Double(max)).rounded(.up))
        var result = samples.enumerated()
            .filter { $0.offset % step == 0 }
            .map(\.element)
        if let last = samples.last, result.last?.id != last.id {
            result.append(last)
        }
        return result
    }

    /// One-line "N points · min … · max …" summary, or nil when empty.
    var summary: String? {
        let temperatures = samples.map(\.temperature)
        guard let minimum = temperatures.min(), let maximum = temperatures.max() else { return nil }
        return String(
            format: "%d points · min %.1f °C · max %.1f °C",
            samples.count, minimum, maximum
        )
    }
}
