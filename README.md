# Weather Monitor

A tiny macOS menu bar app that shows the current local outdoor temperature. It
finds the weather station nearest to your location using the Geosphere Austria
Data Hub and falls back to Open-Meteo when no Austrian station is close enough.

## How it works

The app determines your location, then fetches the temperature in this order:

- Your position comes from CoreLocation. If you decline the permission prompt or
  location services are unavailable, it falls back to an approximate location
  derived from your public IP address.
- It downloads the Geosphere Austria station list (TAWES 10-minute network),
  picks the nearest active stations, and reads the current air temperature
  (`TL`) from the closest one that is reporting.
- If the nearest Austrian station is more than 150 km away (so you are probably
  outside Austria) or Geosphere is unreachable, it uses the free, key-less
  Open-Meteo API for the temperature at your coordinates.

The temperature appears in the menu bar. Click it to see the station name and
distance, when the reading was taken, the data source, your location, and a
manual refresh. It refreshes automatically every 10 minutes.

## Requirements

- macOS 12 or later
- A Swift toolchain (Xcode or the Command Line Tools: `xcode-select --install`)

## Build and run

```sh
./build.sh run
```

This compiles the app, assembles `WeatherMonitor.app`, signs it ad-hoc, and
launches it. To only build the bundle without launching, run `./build.sh`.

The first launch shows a system prompt asking to use your location. Allow it for
the nearest-station feature; if you deny it, the app still works using the
IP-based fallback.

## Run at login

To start the app automatically, move `WeatherMonitor.app` to `/Applications`
and add it under System Settings → General → Login Items.

## Notes

- The app has no Dock icon or main window — it lives entirely in the menu bar
  (`LSUIElement`).
- No API keys are required. Both Geosphere Austria and Open-Meteo are open APIs.
- Geosphere API docs: https://dataset.api.hub.geosphere.at/v1/docs/
