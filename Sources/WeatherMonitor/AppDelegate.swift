import AppKit
import CoreLocation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let location = LocationProvider()
    private let geosphere = GeosphereClient()
    private let openMeteo = OpenMeteoClient()
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var state = DisplayState()

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

        // Geosphere updates every 10 minutes, so refreshing on that cadence is plenty.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        Task { await refresh() }
    }

    // MARK: Actions

    @objc private func refreshClicked() {
        Task { await refresh() }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: Refresh pipeline

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // 1) Where are we? Prefer CoreLocation, fall back to IP geolocation.
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
                state = DisplayState(error: "Location unavailable")
                render()
                return
            }
        }

        var newState = DisplayState()
        newState.latitude = latitude
        newState.longitude = longitude
        newState.locationSource = locationSource

        // 2) Nearest Geosphere Austria station.
        if let reading = try? await geosphere.nearestTemperature(latitude: latitude, longitude: longitude),
           reading.stationDistance <= maxStationDistance {
            newState.temperature = reading.temperature
            newState.stationName = reading.stationName
            newState.distanceMeters = reading.stationDistance
            newState.observationTime = reading.observationTime
            newState.source = "Geosphere Austria"
            state = newState
            render()
            return
        }

        // 3) Fallback: Open-Meteo forecast point.
        if let reading = try? await openMeteo.temperature(latitude: latitude, longitude: longitude) {
            newState.temperature = reading.temperature
            newState.observationTime = reading.observationTime
            newState.source = "Open-Meteo"
            state = newState
            render()
            return
        }

        newState.error = "Weather unavailable"
        state = newState
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
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Weather Monitor", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
