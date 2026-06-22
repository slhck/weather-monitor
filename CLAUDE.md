# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu bar app (Swift, AppKit + SwiftUI) that shows the current outdoor temperature. It reads from the Geosphere Austria Data Hub when a station is nearby and falls back to Open-Meteo otherwise. No API keys; both APIs are open.

## Build and run

- `./build.sh run` — compile (release), assemble `WeatherMonitor.app`, ad-hoc sign, and launch.
- `./build.sh` — same, without launching.
- `swift build -c release` — compile only, no app bundle.

The ad-hoc code signing step is required: CoreLocation will not prompt for permission unless the app is signed, even locally. `WeatherMonitor.app` is rebuilt from scratch on every run and is git-ignored.

There are no tests and no linter configured. `Package.swift` is a plain SwiftPM executable target (Swift 5.9, macOS 13).

## Architecture

The app has no storyboard and no main window. `App.swift` manually creates the `NSApplication`, sets `.accessory` activation policy (no Dock icon, menu-bar only), and hands off to `AppDelegate`.

`AppDelegate` is the single coordinator. It owns every client and store, runs the refresh pipeline, holds the current `DisplayState`, and rebuilds the `NSMenu` on each render. The two SwiftUI screens (Preferences, History) are hosted in plain `NSWindow`s via `NSHostingController` and opened from menu items.

The refresh pipeline (`AppDelegate.refresh()`) is the core logic and has two modes:

- Override mode: if the user pinned a specific station in Preferences (`stationOverrideID` non-empty), query that station directly — no location lookup.
- Automatic mode: get a location fix, then try the nearest Geosphere station; if the closest station is farther than `maxStationDistance` (150 km, i.e. probably outside Austria) or Geosphere fails, fall back to Open-Meteo for the coordinate.

Location resolution (`LocationProvider`) wraps CoreLocation in a single async call with a 10s timeout, and `IPLocation` provides an IP-based approximate fallback when the user denies permission or CoreLocation stalls.

Data clients:

- `GeosphereClient` is an `actor`. It caches the full station list for the session, and `nearestTemperature` asks the 6 closest active stations in one request (the nearest may have a momentary data gap) and returns the first one reporting air temperature (`TL`). Private `Decodable` structs at the bottom of the file mirror the API's JSON shapes.
- `OpenMeteoClient` is a stateless `struct` returning a single current temperature.

Settings and persistence:

- `AppSettings` is an `ObservableObject` backed by `UserDefaults`; SwiftUI views bind to it directly. `AppDelegate` subscribes to its `@Published` properties with Combine (using `.dropFirst()` to skip the initial value) so changing the refresh interval reschedules the timer, changing the station triggers a refresh, and changing retention re-prunes history.
- `HistoryStore` appends each reading to `~/Library/Application Support/WeatherMonitor/history.json`, dedupes by observation timestamp, and prunes beyond the retention window. `HistoryView` draws it with Swift Charts.
- `StationStore` just holds the loaded station list so the Preferences picker can update when the data arrives.

`Models.swift` holds the shared value types (`DisplayState`, `StationInfo`, readings, errors). `Geo.swift` has two free functions: `haversineMeters` for distances and `parseTimestamp` for the differing timestamp formats the two APIs return.

## Concurrency

UI-touching types (`AppDelegate`, `LocationProvider`, `AppSettings`, `HistoryStore`, `StationStore`) are `@MainActor`. Network access lives off the main actor: `GeosphereClient` is an `actor`, `OpenMeteoClient` is a value type. Value types crossing actor boundaries (`StationInfo`, the readings) are `Sendable`. Keep this split when adding code — do blocking or network work off `@MainActor`, mutate UI state on it.
