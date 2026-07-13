import CoreLocation
import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let rallyBuddyRoute = UTType(exportedAs: "com.shuffman.rallybuddy.route")
}

/// The on-disk `.rallybuddy` document: a route plus the marked features
/// along it. Versioned so the format can evolve.
struct SharedRoute: Codable {
    struct Feature: Codable {
        var type: String
        var latitude: Double
        var longitude: Double
        var bearing: Double?
        var note: String
    }

    var version: Int = 1
    var name: String
    var waypoints: [Double]
    var path: [Double]
    var distanceMeters: Double
    var features: [Feature]
}

/// Snapshot of a route + all candidate features, filtered down to the ones
/// near the path only when the share actually happens.
struct RouteExport: Transferable {
    var name: String
    var waypoints: [Double]
    var path: [Double]
    var distanceMeters: Double
    var candidateFeatures: [SharedRoute.Feature]

    /// Features within this many meters of the path are included.
    static let corridorWidth: CLLocationDistance = 200

    init(route: Route, features: [RoadFeature]) {
        self.name = route.name
        self.waypoints = route.waypointCoords
        self.path = route.pathCoords
        self.distanceMeters = route.distanceMeters
        self.candidateFeatures = features.map {
            SharedRoute.Feature(
                type: $0.type.rawValue,
                latitude: $0.latitude,
                longitude: $0.longitude,
                bearing: $0.bearing,
                note: $0.note
            )
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .rallyBuddyRoute) { export in
            let data = try JSONEncoder().encode(export.payload())
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory
                .appendingPathComponent(export.safeFilename)
                .appendingPathExtension("rallybuddy")
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }

    private var safeFilename: String {
        let cleaned = name.components(
            separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")
        ).joined()
        return cleaned.isEmpty ? "Route" : cleaned
    }

    func payload() -> SharedRoute {
        let pathLocations = Route.unpack(path).map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let nearby = candidateFeatures.filter { feature in
            let location = CLLocation(
                latitude: feature.latitude,
                longitude: feature.longitude
            )
            return pathLocations.contains {
                $0.distance(from: location) < Self.corridorWidth
            }
        }
        return SharedRoute(
            name: name,
            waypoints: waypoints,
            path: path,
            distanceMeters: distanceMeters,
            features: nearby
        )
    }
}

enum RouteShareImporter {
    /// Imported features closer than this to an existing feature of the
    /// same type are treated as duplicates and skipped.
    static let duplicateRadius: CLLocationDistance = 25

    @discardableResult
    static func importRoute(
        from url: URL,
        into context: ModelContext,
        existingFeatures: [RoadFeature]
    ) throws -> Route {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let shared = try JSONDecoder().decode(SharedRoute.self, from: data)

        let route = Route(
            name: shared.name,
            waypoints: Route.unpack(shared.waypoints),
            path: Route.unpack(shared.path),
            distanceMeters: shared.distanceMeters
        )
        context.insert(route)

        for feature in shared.features {
            guard let type = RoadFeatureType(rawValue: feature.type) else { continue }
            let location = CLLocation(
                latitude: feature.latitude,
                longitude: feature.longitude
            )
            let isDuplicate = existingFeatures.contains { existing in
                existing.type == type
                    && CLLocation(
                        latitude: existing.latitude,
                        longitude: existing.longitude
                    ).distance(from: location) < duplicateRadius
            }
            guard !isDuplicate else { continue }
            context.insert(
                RoadFeature(
                    type: type,
                    coordinate: location.coordinate,
                    bearing: feature.bearing,
                    note: feature.note
                )
            )
        }

        return route
    }
}
