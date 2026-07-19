#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WeatherMonitor"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "==> Building (release)…"
swift build -c release

echo "==> Assembling ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
cp "Assets/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> Code signing (ad-hoc)…"
# Ad-hoc signing is enough for CoreLocation to prompt for permission locally.
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"

if [[ "${1:-}" == "run" ]]; then
	echo "==> Launching…"
	open "${APP_BUNDLE}"
fi
