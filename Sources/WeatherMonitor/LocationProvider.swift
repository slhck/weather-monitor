import CoreLocation

/// Wraps CoreLocation in a single async call that resolves to one location fix.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var requested = false
    private var generation = 0

    override init() {
        super.init()
        manager.delegate = self
        // City-level accuracy is plenty for picking the nearest station, and it
        // resolves faster than a precise fix.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Returns a single location fix, requesting permission the first time.
    func currentLocation(timeout: TimeInterval = 10) async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.requested = false
            self.generation += 1
            let myGeneration = self.generation

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                beginRequest()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            @unknown default:
                manager.requestWhenInUseAuthorization()
            }

            // Don't let a silent CoreLocation stall hang the refresh forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.finish(.failure(LocationError.timeout))
            }
        }
    }

    private func beginRequest() {
        guard !requested else { return }
        requested = true
        manager.requestLocation()
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.beginRequest()
            case .denied, .restricted:
                self.finish(.failure(LocationError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            if let location {
                self.finish(.success(location))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }
}

/// Approximate location from the public IP address, used when CoreLocation is
/// unavailable or the user declined the permission prompt.
enum IPLocation {
    struct Response: Decodable {
        let latitude: Double
        let longitude: Double
    }

    static func fetch() async throws -> (latitude: Double, longitude: Double) {
        let url = URL(string: "https://ipapi.co/json/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.latitude, response.longitude)
    }
}
