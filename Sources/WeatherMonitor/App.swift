import AppKit

@main
struct WeatherMonitorApp {
    @MainActor
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        // A regular app remains reachable from the Dock when the menu bar icon
        // is hidden by a MacBook notch or crowded status items.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
