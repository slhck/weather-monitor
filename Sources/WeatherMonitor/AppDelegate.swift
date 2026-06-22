import AppKit
import SwiftUI
import Combine
import CoreLocation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let location = LocationProvider()
    private let geosphere = GeosphereClient()
    private let openMeteo = OpenMeteoClient()

    private let settings = AppSettings()
    private lazy var history = HistoryStore(geosphere: geosphere, openMeteo: openMeteo)
    private let stationStore = StationStore()
    private var cancellables = Set<AnyCancellable>()

    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var state = DisplayState()

    private var prefsWindow: NSWindow?

    /// If the nearest Austrian station is farther than this, the user is most
    /// likely outside Austria, so we use the Open-Meteo fallback instead.
    private let maxStationDistance = 150_000.0 // meters

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "…"
            if let image = NSImage(systemSymbolName: "thermometer", accessibilityDescription: "Temperature") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
        }
        render()

        // Load the station list in the background for the preferences picker.
        Task {
            if let stations = try? await geosphere.stationList() {
                stationStore.stations = stations
            }
        }

        // React to settings changes (dropFirst skips the value emitted on subscribe).
        settings.$refreshMinutes
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &cancellables)

        settings.$stationOverrideID
            .dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)

        scheduleTimer()
        Task { await refresh() }
    }

    // MARK: Timer

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(max(1, settings.refreshMinutes) * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: Actions

    @objc private func refreshClicked() {
        Task { await refresh() }
    }

    @objc private func openPreferences() {
        if prefsWindow == nil {
            let view = PreferencesView(settings: settings, stationStore: stationStore)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Preferences"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            prefsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: Refresh pipeline

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Manual override: query the chosen station directly, no location needed.
        let overrideID = settings.stationOverrideID
        if !overrideID.isEmpty {
            var newState = DisplayState()
            newState.locationSource = "Chosen station"
            if let reading = try? await geosphere.temperature(forStationID: overrideID) {
                newState.temperature = reading.temperature
                newState.stationName = reading.stationName
                newState.observationTime = reading.observationTime
                newState.source = "Geosphere Austria"
                newState.historySource = .geosphere(stationID: reading.stationID, stationName: reading.stationName)
            } else {
                newState.error = "Station unavailable"
            }
            apply(newState)
            return
        }

        // Automatic mode: location -> nearest Geosphere station -> Open-Meteo.
        var latitude = 0.0
        var longitude = 0.0
        var locationSource = ""
        do {
            let fix = try await location.currentLocation()
            latitude = fix.coordinate.latitude
            longitude = fix.coordinate.longitude
            locationSource = "GPS"
        } catch {
            if let approx = try? await IPLocation.fetch() {
                latitude = approx.latitude
                longitude = approx.longitude
                locationSource = "Approx. (IP)"
            } else {
                apply(DisplayState(error: "Location unavailable"))
                return
            }
        }

        var newState = DisplayState()
        newState.latitude = latitude
        newState.longitude = longitude
        newState.locationSource = locationSource

        if let reading = try? await geosphere.nearestTemperature(latitude: latitude, longitude: longitude),
           reading.stationDistance <= maxStationDistance {
            newState.temperature = reading.temperature
            newState.stationName = reading.stationName
            newState.distanceMeters = reading.stationDistance
            newState.observationTime = reading.observationTime
            newState.source = "Geosphere Austria"
            newState.historySource = .geosphere(stationID: reading.stationID, stationName: reading.stationName)
            apply(newState)
            return
        }

        if let reading = try? await openMeteo.temperature(latitude: latitude, longitude: longitude) {
            newState.temperature = reading.temperature
            newState.observationTime = reading.observationTime
            newState.source = "Open-Meteo"
            newState.historySource = .openMeteo(latitude: latitude, longitude: longitude)
            apply(newState)
            return
        }

        newState.error = "Weather unavailable"
        apply(newState)
    }

    private func apply(_ newState: DisplayState) {
        state = newState
        // Drop cached history so the chart refetches a current window next time.
        history.invalidate()
        render()
    }

    // MARK: Rendering

    private func render() {
        if let temperature = state.temperature {
            statusItem.button?.title = String(format: "%.0f°", temperature)
        } else {
            statusItem.button?.title = "—"
        }
        statusItem.button?.toolTip = toolTipText()
        statusItem.menu = buildMenu()
    }

    private func toolTipText() -> String {
        if let temperature = state.temperature {
            var text = String(format: "%.1f °C", temperature)
            if let name = state.stationName {
                text += " — \(name.capitalized)"
            }
            return text
        }
        return state.error ?? "Weather Monitor"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(chartItem())
        menu.addItem(.separator())

        if let error = state.error, state.temperature == nil {
            menu.addItem(infoItem("⚠ \(error)"))
        }

        if let temperature = state.temperature {
            menu.addItem(infoItem(String(format: "%.1f °C", temperature)))

            if let name = state.stationName {
                var line = name.capitalized
                if let distance = state.distanceMeters {
                    line += String(format: " · %.1f km", distance / 1000)
                }
                menu.addItem(infoItem(line))
            } else {
                menu.addItem(infoItem("Forecast point"))
            }

            if let observed = state.observationTime {
                menu.addItem(infoItem("Updated \(timeFormatter.string(from: observed))"))
            }
            if let source = state.source {
                menu.addItem(infoItem("Source: \(source)"))
            }
        }

        if let latitude = state.latitude, let longitude = state.longitude {
            let suffix = state.locationSource.map { " (\($0))" } ?? ""
            menu.addItem(infoItem(String(format: "Location: %.3f, %.3f%@", latitude, longitude, suffix)))
        } else if let locationSource = state.locationSource {
            menu.addItem(infoItem(locationSource))
        }

        menu.addItem(.separator())

        menu.addItem(actionItem("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(actionItem("Refresh Now", #selector(refreshClicked), key: "r"))

        menu.addItem(.separator())

        menu.addItem(actionItem("Quit Weather Monitor", #selector(quitClicked), key: "q"))

        return menu
    }

    /// A menu item whose content is the compact SwiftUI temperature chart,
    /// pointed at whatever station or location the current reading came from.
    private func chartItem() -> NSMenuItem {
        let view = MenuHistoryView(store: history, source: state.historySource)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
