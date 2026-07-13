import CoreLocation
import Foundation
import MapLibre
import Observation

/// Manages downloaded offline map regions via MapLibre's offline storage.
/// Each pack is a tile pyramid (zoom 0–14) for a bounding box, named by
/// the user-facing area it covers.
@MainActor
@Observable
final class OfflineMapManager {
    nonisolated static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    private(set) var packs: [MLNOfflinePack] = []
    /// Bumped on every progress notification so SwiftUI re-reads pack state.
    private(set) var progressTick = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name: Notification.Name in [
            .MLNOfflinePackProgressChanged,
            .MLNOfflinePackError,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.progressTick += 1 }
                }
            )
        }
        reload()
    }


    func reload() {
        packs = MLNOfflineStorage.shared.packs ?? []
    }

    func name(of pack: MLNOfflinePack) -> String {
        (try? JSONDecoder().decode([String: String].self, from: pack.context))?["name"]
            ?? "Map area"
    }

    func download(name: String, bounds: MLNCoordinateBounds) {
        let region = MLNTilePyramidOfflineRegion(
            styleURL: Self.styleURL,
            bounds: bounds,
            fromZoomLevel: 0,
            toZoomLevel: 14
        )
        let context = (try? JSONEncoder().encode(["name": name])) ?? Data()
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, _ in
            pack?.resume()
            Task { @MainActor in self?.reload() }
        }
    }

    func delete(_ pack: MLNOfflinePack) {
        MLNOfflineStorage.shared.removePack(pack) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: - Region helpers

    /// A square bounding box around a point, `radiusKm` in each direction.
    nonisolated static func bounds(
        around center: CLLocationCoordinate2D,
        radiusKm: Double
    ) -> MLNCoordinateBounds {
        let dLat = radiusKm / 111.0
        let dLon = radiusKm / (111.0 * max(cos(center.latitude * .pi / 180), 0.1))
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(
                latitude: center.latitude - dLat,
                longitude: center.longitude - dLon
            ),
            ne: CLLocationCoordinate2D(
                latitude: center.latitude + dLat,
                longitude: center.longitude + dLon
            )
        )
    }

    /// A bounding box covering a route path plus a padding corridor.
    nonisolated static func bounds(
        of path: [CLLocationCoordinate2D],
        paddingKm: Double
    ) -> MLNCoordinateBounds? {
        guard let first = path.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in path {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let dLat = paddingKm / 111.0
        let midLat = (minLat + maxLat) / 2
        let dLon = paddingKm / (111.0 * max(cos(midLat * .pi / 180), 0.1))
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: minLat - dLat, longitude: minLon - dLon),
            ne: CLLocationCoordinate2D(latitude: maxLat + dLat, longitude: maxLon + dLon)
        )
    }
}
