import AppKit

@main
struct WeatherMonitorApp {
    @MainActor
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        // .accessory => no Dock icon, no main menu; the app lives only in the menu bar.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
