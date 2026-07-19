import Foundation
import Combine

/// User preferences, persisted in UserDefaults. Views bind to these directly.
@MainActor
final class AppSettings: ObservableObject {
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    /// Empty string means "automatic (use my location)"; otherwise a station id.
    @Published var stationOverrideID: String {
        didSet { UserDefaults.standard.set(stationOverrideID, forKey: Keys.stationOverrideID) }
    }

    /// Use the cold-to-warm chart gradient instead of the system accent colour.
    @Published var colorfulCharts: Bool {
        didSet { UserDefaults.standard.set(colorfulCharts, forKey: Keys.colorfulCharts) }
    }

    /// Shared visible window for both forecast charts.
    @Published var forecastRange: ForecastRange {
        didSet { UserDefaults.standard.set(forecastRange.rawValue, forKey: Keys.forecastRange) }
    }

    private enum Keys {
        static let refreshMinutes = "refreshMinutes"
        static let stationOverrideID = "stationOverrideID"
        static let colorfulCharts = "colorfulCharts"
        static let forecastRange = "forecastRange"
    }

    init() {
        let defaults = UserDefaults.standard
        refreshMinutes = defaults.object(forKey: Keys.refreshMinutes) as? Int ?? 10
        stationOverrideID = defaults.string(forKey: Keys.stationOverrideID) ?? ""
        colorfulCharts = defaults.object(forKey: Keys.colorfulCharts) as? Bool ?? false
        forecastRange = defaults.string(forKey: Keys.forecastRange)
            .flatMap(ForecastRange.init(rawValue:)) ?? .h24
    }
}
