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

`AppDelegate` is the single coordinator. It owns every client and store, runs the refresh pipeline, holds the current `DisplayState`, and rebuilds the `NSMenu` on each render. The history chart is embedded directly in the menu as a custom-view `NSMenuItem` (a SwiftUI `MenuHistoryView` wrapped in an `NSHostingView`). Preferences is the only separate screen, hosted in a plain `NSWindow` via `NSHostingController` and opened from a menu item.

The refresh pipeline (`AppDelegate.refresh()`) is the core logic and has two modes:

- Override mode: if the user pinned a specific station in Preferences (`stationOverrideID` non-empty), query that station directly — no location lookup.
- Automatic mode: get a location fix, then try the nearest Geosphere station; if the closest station is farther than `maxStationDistance` (150 km, i.e. probably outside Austria) or Geosphere fails, fall back to Open-Meteo for the coordinate.

Each successful branch also records a `DisplayState.historySource` — `.geosphere(stationID:…)` or `.openMeteo(latitude:longitude:)` — so the chart knows where to pull its timeseries from and follows whichever station or location is currently shown.

Location resolution (`LocationProvider`) wraps CoreLocation in a single async call with a 10s timeout, and `IPLocation` provides an IP-based approximate fallback when the user denies permission or CoreLocation stalls.

Data clients:

- `GeosphereClient` is an `actor`. It caches the full station list for the session, and `nearestTemperature` asks the 6 closest active stations in one request (the nearest may have a momentary data gap) and returns the first one reporting air temperature (`TL`), together with relative humidity (`RF`), wind speed (`FF`, m/s) and dew point (`TP`) when the station reports them. `history(stationID:start:end:)` reads the 10-minute `TL` timeseries for one station over a window from the `station/historical/tawes-v1-10min` endpoint, for the chart. Private `Decodable` structs at the bottom of the file mirror the API's JSON shapes.
- `OpenMeteoClient` is a stateless `struct`. `temperature(...)` returns the current temperature plus humidity, wind (requested in m/s to match Geosphere) and dew point; `history(...)` returns an hourly timeseries over a window (via the forecast endpoint's `past_days`, trimmed to the requested range), used outside Austria / as the fallback.

Settings and history:

- `AppSettings` is an `ObservableObject` backed by `UserDefaults`; SwiftUI views bind to it directly. `AppDelegate` subscribes to its `@Published` properties with Combine (using `.dropFirst()` to skip the initial value) so changing the refresh interval reschedules the timer and changing the station triggers a refresh.
- `HistoryStore` does not persist anything. It fetches the temperature timeseries on demand for the active `HistorySource` and selected `HistoryRange`, and caches each `(source, range)` result in memory so switching ranges — or returning to a station you've already viewed — is instant. `AppDelegate.apply()` calls `invalidate()` after each refresh so the chart's most recent point stays current. `MenuHistoryView`/`TemperatureChart` (Swift Charts) render it with a labelled, range-aware time axis and a hover/drag scrubber that reads out the value at a point.
- `StationStore` just holds the loaded station list so the Preferences picker can update when the data arrives.

`Models.swift` holds the shared value types (`DisplayState`, `StationInfo`, readings, errors) plus `HistorySource` and `HistoryRange`; `DisplayState.apparentTemperature` derives the "feels like" misery index on demand. `Sample` (one chart point) lives in `HistoryStore.swift`. `Geo.swift` has two free functions: `haversineMeters` for distances and `parseTimestamp` for the differing timestamp formats the two APIs return. `Comfort.swift` computes the Steadman apparent temperature from temperature, humidity and wind, plus a short comfort label for it.

## Concurrency

UI-touching types (`AppDelegate`, `LocationProvider`, `AppSettings`, `HistoryStore`, `StationStore`) are `@MainActor`. Network access lives off the main actor: `GeosphereClient` is an `actor`, `OpenMeteoClient` is a value type. Value types crossing actor boundaries (`StationInfo`, the readings) are `Sendable`. Keep this split when adding code — do blocking or network work off `@MainActor`, mutate UI state on it.
