import Foundation
import Combine

/// User preferences, persisted in UserDefaults. Views bind to these directly.
@MainActor
final class AppSettings: ObservableObject {
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: Keys.refreshMinutes) }
    }

    @Published var maxStorageDays: Int {
        didSet { UserDefaults.standard.set(maxStorageDays, forKey: Keys.maxStorageDays) }
    }

    /// Empty string means "automatic (use my location)"; otherwise a station id.
    @Published var stationOverrideID: String {
        didSet { UserDefaults.standard.set(stationOverrideID, forKey: Keys.stationOverrideID) }
    }

    private enum Keys {
        static let refreshMinutes = "refreshMinutes"
        static let maxStorageDays = "maxStorageDays"
        static let stationOverrideID = "stationOverrideID"
    }

    init() {
        let defaults = UserDefaults.standard
        refreshMinutes = defaults.object(forKey: Keys.refreshMinutes) as? Int ?? 10
        maxStorageDays = defaults.object(forKey: Keys.maxStorageDays) as? Int ?? 7
        stationOverrideID = defaults.string(forKey: Keys.stationOverrideID) ?? ""
    }
}
