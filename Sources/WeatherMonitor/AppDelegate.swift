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
    private lazy var forecast = ForecastStore(
        geosphere: geosphere, openMeteo: openMeteo, range: settings.forecastRange
    )
    private let stationStore = StationStore()
    private var cancellables = Set<AnyCancellable>()

    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var menuIsOpen = false
    private var state = DisplayState()

    private var prefsWindow: NSWindow?
    private var weatherWindow: NSWindow?
    private var weatherHostingController: NSHostingController<WeatherWindowView>?

    /// If the nearest Austrian station is farther than this, the user is most
    /// likely outside Austria, so we use the Open-Meteo fallback instead.
    private let maxStationDistance = 150_000.0 // meters

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
        openWeatherWindow()

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

        settings.$forecastRange
            .dropFirst()
            .sink { [weak self] range in self?.forecast.range = range }
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

    @objc private func openWeatherWindow() {
        if weatherWindow == nil {
            let hosting = NSHostingController(rootView: weatherWindowView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Weather Monitor"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 740, height: 520))
            window.minSize = NSSize(width: 720, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            weatherHostingController = hosting
            weatherWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        weatherWindow?.makeKeyAndOrderFront(nil)
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
                newState.humidity = reading.humidity
                newState.windSpeed = reading.windSpeed
                newState.dewPoint = reading.dewPoint
                newState.stationName = reading.stationName
                newState.latitude = reading.latitude
                newState.longitude = reading.longitude
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
            newState.humidity = reading.humidity
            newState.windSpeed = reading.windSpeed
            newState.dewPoint = reading.dewPoint
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
            newState.humidity = reading.humidity
            newState.windSpeed = reading.windSpeed
            newState.dewPoint = reading.dewPoint
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
        forecast.invalidate()
        // The window first appears before the asynchronous location/weather
        // refresh finishes. Updating an NSHostingController's root view does not
        // call onAppear again, so activate the stores explicitly for the new state.
        history.activate(source: newState.historySource)
        forecast.activate(latitude: newState.latitude, longitude: newState.longitude)
        weatherHostingController?.rootView = weatherWindowView()
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
        // Don't swap the menu out from under an open one — the displayed menu's
        // chart updates live from the store, and we rebuild on close instead.
        if !menuIsOpen {
            statusItem.menu = buildMenu()
        }
    }

    private func toolTipText() -> String {
        if let temperature = state.temperature {
            var text = String(format: "%.1f °C", temperature)
            if let apparent = state.apparentTemperature {
                text += String(format: " · feels like %.1f °C", apparent)
            }
            if let name = state.stationName {
                text += " — \(name.capitalized)"
            }
            return text
        }
        return state.error ?? "Weather Monitor"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(chartItem())
        menu.addItem(.separator())
        menu.addItem(conditionsItem())
        menu.addItem(.separator())
        menu.addItem(forecastRangeItem())
        menu.addItem(temperatureForecastItem())
        menu.addItem(precipitationForecastItem())
        menu.addItem(.separator())

        menu.addItem(actionItem("Open Weather Window", #selector(openWeatherWindow), key: "o"))
        menu.addItem(actionItem("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(actionItem("Refresh Now", #selector(refreshClicked), key: "r"))

        menu.addItem(.separator())

        menu.addItem(actionItem("Quit Weather Monitor", #selector(quitClicked), key: "q"))

        return menu
    }

    /// A menu item whose content is the compact SwiftUI temperature chart,
    /// pointed at whatever station or location the current reading came from.
    private func chartItem() -> NSMenuItem {
        let view = MenuHistoryView(store: history, settings: settings, source: state.historySource)
        return viewItem(view)
    }

    private func conditionsItem() -> NSMenuItem {
        viewItem(ConditionsView(state: state))
    }

    private func temperatureForecastItem() -> NSMenuItem {
        let view = TemperatureForecastView(
            store: forecast, settings: settings,
            latitude: state.latitude, longitude: state.longitude
        )
        return viewItem(view)
    }

    private func forecastRangeItem() -> NSMenuItem {
        let view = HStack(spacing: 8) {
            Text("Forecast")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForecastRangePicker(settings: settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .frame(width: 340)
        return viewItem(view)
    }

    private func precipitationForecastItem() -> NSMenuItem {
        let view = PrecipitationForecastView(
            store: forecast, latitude: state.latitude, longitude: state.longitude
        )
        return viewItem(view)
    }

    private func viewItem<ViewType: View>(_ view: ViewType) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    private func weatherWindowView() -> WeatherWindowView {
        WeatherWindowView(
            state: state,
            history: history,
            forecast: forecast,
            settings: settings,
            refresh: { [weak self] in Task { await self?.refresh() } },
            openPreferences: { [weak self] in self?.openPreferences() }
        )
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

extension AppDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        openWeatherWindow()
        return false
    }
}

// MARK: - Menu lifecycle

extension AppDelegate: NSMenuDelegate {
    /// Opening the menu pulls fresh data: a current window for the chart (which
    /// updates live in place) and a new temperature reading. Without this the
    /// menu would keep showing whatever was last fetched on the timer.
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        history.forceReload(source: state.historySource)
        forecast.forceReload(latitude: state.latitude, longitude: state.longitude)
        Task { await refresh() }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        // Rebuild so the text rows reflect anything that refreshed while open.
        render()
    }
}
