import Foundation

/// Talks to the Geosphere Austria Data Hub (TAWES 10-minute station network).
/// Docs: https://dataset.api.hub.geosphere.at/v1/docs/
actor GeosphereClient {
    private let base = "https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min"
    private var stationsCache: [Station]?

    struct Station {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        let active: Bool
    }

    /// Finds the nearest stations and returns the closest one that is currently
    /// reporting an air temperature (`TL`).
    func nearestTemperature(latitude: Double, longitude: Double) async throws -> StationReading {
        let stations = try await loadStations()

        let candidates = stations
            .filter { $0.active }
            .map { (station: $0, distance: haversineMeters(latitude, longitude, $0.latitude, $0.longitude)) }
            .sorted { $0.distance < $1.distance }
            .prefix(6)

        guard !candidates.isEmpty else { throw WeatherError.noData }

        // Ask for all candidate stations in one request; the nearest one might
        // briefly have a gap in its data, so we keep a few in reserve.
        let ids = candidates.map { $0.station.id }.joined(separator: ",")
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "parameters", value: "TL"),
            URLQueryItem(name: "station_ids", value: ids)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(CurrentResponse.self, from: data)

        var valueByStation: [String: Double] = [:]
        for feature in response.features {
            if let parameter = feature.properties.parameters["TL"],
               let latest = parameter.data.compactMap({ $0 }).last {
                valueByStation[feature.properties.station] = latest
            }
        }

        let observationTime = response.timestamps.last.flatMap(parseTimestamp)

        for candidate in candidates {
            if let value = valueByStation[candidate.station.id] {
                return StationReading(
                    temperature: value,
                    stationName: candidate.station.name,
                    stationDistance: candidate.distance,
                    observationTime: observationTime
                )
            }
        }

        throw WeatherError.noData
    }

    /// Loads (and caches for the session) the full station list with coordinates.
    private func loadStations() async throws -> [Station] {
        if let cached = stationsCache { return cached }

        let url = URL(string: base + "/metadata")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(MetadataResponse.self, from: data)

        let stations = metadata.stations.map {
            Station(
                id: $0.id,
                name: $0.name,
                latitude: $0.lat,
                longitude: $0.lon,
                active: $0.is_active ?? true
            )
        }
        stationsCache = stations
        return stations
    }
}

// MARK: - JSON shapes

private struct MetadataResponse: Decodable {
    let stations: [MetaStation]

    struct MetaStation: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
        let is_active: Bool?
    }
}

private struct CurrentResponse: Decodable {
    let timestamps: [String]
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Properties
    }

    struct Properties: Decodable {
        let parameters: [String: Parameter]
        let station: String
    }

    struct Parameter: Decodable {
        let data: [Double?]
    }
}
