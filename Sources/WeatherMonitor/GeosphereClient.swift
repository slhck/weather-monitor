import Foundation

/// Talks to the Geosphere Austria Data Hub (TAWES 10-minute station network).
/// Docs: https://dataset.api.hub.geosphere.at/v1/docs/
actor GeosphereClient {
    private let base = "https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min"
    private let historicalBase = "https://dataset.api.hub.geosphere.at/v1/station/historical/tawes-v1-10min"
    private var stationsCache: [StationInfo]?

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// The full list of stations (cached for the session), for the picker.
    func stationList() async throws -> [StationInfo] {
        try await loadStations()
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
        let values = try await temperatures(forStationIDs: ids)

        for candidate in candidates {
            if let value = values.byStation[candidate.station.id] {
                return StationReading(
                    temperature: value,
                    stationID: candidate.station.id,
                    stationName: candidate.station.name,
                    stationDistance: candidate.distance,
                    observationTime: values.observationTime
                )
            }
        }

        throw WeatherError.noData
    }

    /// Reads the current air temperature for one specific station (override mode).
    func temperature(forStationID id: String) async throws -> StationReading {
        let stations = try await loadStations()
        let name = stations.first(where: { $0.id == id })?.name ?? id
        let values = try await temperatures(forStationIDs: id)
        guard let value = values.byStation[id] else { throw WeatherError.noData }
        return StationReading(
            temperature: value,
            stationID: id,
            stationName: name,
            stationDistance: 0,
            observationTime: values.observationTime
        )
    }

    /// Reads the 10-minute air-temperature (`TL`) timeseries for one station
    /// over a time window, for the history chart.
    func history(stationID: String, start: Date, end: Date) async throws -> [Sample] {
        var components = URLComponents(string: historicalBase)!
        components.queryItems = [
            URLQueryItem(name: "parameters", value: "TL"),
            URLQueryItem(name: "station_ids", value: stationID),
            URLQueryItem(name: "start", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "end", value: isoFormatter.string(from: end))
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(CurrentResponse.self, from: data)

        guard let parameter = response.features.first?.properties.parameters["TL"] else { return [] }

        var samples: [Sample] = []
        for (index, timestamp) in response.timestamps.enumerated() {
            guard index < parameter.data.count,
                  let value = parameter.data[index],
                  let date = parseTimestamp(timestamp) else { continue }
            samples.append(Sample(date: date, temperature: value))
        }
        return samples
    }

    // MARK: - Helpers

    private func temperatures(forStationIDs ids: String) async throws -> (byStation: [String: Double], observationTime: Date?) {
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "parameters", value: "TL"),
            URLQueryItem(name: "station_ids", value: ids)
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(CurrentResponse.self, from: data)

        var byStation: [String: Double] = [:]
        for feature in response.features {
            if let parameter = feature.properties.parameters["TL"],
               let latest = parameter.data.compactMap({ $0 }).last {
                byStation[feature.properties.station] = latest
            }
        }
        return (byStation, response.timestamps.last.flatMap(parseTimestamp))
    }

    /// Loads (and caches for the session) the full station list with coordinates.
    private func loadStations() async throws -> [StationInfo] {
        if let cached = stationsCache { return cached }

        let url = URL(string: base + "/metadata")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(MetadataResponse.self, from: data)

        let stations = metadata.stations.map {
            StationInfo(
                id: $0.id,
                name: $0.name,
                state: $0.state ?? "",
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
        let state: String?
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
