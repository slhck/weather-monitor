import Foundation
import Combine

/// Holds the station list once loaded, so the preferences picker can update
/// itself when the data arrives.
@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [StationInfo] = []
}
