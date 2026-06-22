// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WeatherMonitor",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "WeatherMonitor",
            path: "Sources/WeatherMonitor"
        )
    ]
)
