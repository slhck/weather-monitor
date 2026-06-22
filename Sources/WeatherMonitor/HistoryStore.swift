import Foundation
import Combine

/// One recorded temperature reading.
struct Sample: Codable, Identifiable, Hashable {
    let date: Date
    let temperature: Double
    var id: Date { date }
}

/// Persists temperature samples to a JSON file and prunes old ones.
/// File: ~/Library/Application Support/WeatherMonitor/history.json
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var samples: [Sample] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("WeatherMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
        samples = loadFromDisk()
    }

    /// Stores a reading, ignoring duplicate observation timestamps, then prunes
    /// anything older than the retention window.
    func record(temperature: Double, at date: Date, maxAgeDays: Int) {
        guard !samples.contains(where: { $0.date == date }) else { return }
        var updated = samples
        updated.append(Sample(date: date, temperature: temperature))
        updated.sort { $0.date < $1.date }
        samples = prune(updated, maxAgeDays: maxAgeDays, now: date)
        saveToDisk()
    }

    /// Re-applies the retention window immediately (e.g. after the user lowers it).
    func reprune(maxAgeDays: Int) {
        samples = prune(samples, maxAgeDays: maxAgeDays, now: Date())
        saveToDisk()
    }

    private func prune(_ list: [Sample], maxAgeDays: Int, now: Date) -> [Sample] {
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        return list.filter { $0.date >= cutoff }
    }

    private func loadFromDisk() -> [Sample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Sample].self, from: data)) ?? []
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
