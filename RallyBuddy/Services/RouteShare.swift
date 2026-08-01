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
        /// Corner chevrons (v3 of the format); nil in older files.
        var severity: Int? = nil
    }

    /// Bumped whenever a field is added. v2 added maneuvers, v3 feature
    /// severity, v4 turn-by-turn guidance. Files written before 2026-07-31
    /// all claim v1 regardless of content — `payload()` never set this — so
    /// treat a v1 file as "inspect the optional fields", not "has none".
    static let currentVersion = 4

    var version: Int = currentVersion
    var name: String
    var waypoints: [Double]
    var path: [Double]
    var distanceMeters: Double
    var features: [Feature]
    /// Added in v2 of the format; optional for backward compatibility.
    var maneuvers: [Double]? = nil
    /// Turn-by-turn guidance (v4); optional for backward compatibility.
    var guidanceCoords: [Double]? = nil
    var guidanceInstructions: [String]? = nil
}

/// Snapshot of a route + all candidate features, filtered down to the ones
/// near the path only when the share actually happens.
struct RouteExport: Transferable {
    var name: String
    var waypoints: [Double]
    var path: [Double]
    var distanceMeters: Double
    var maneuvers: [Double]
    var guidanceCoords: [Double]
    var guidanceInstructions: [String]
    var candidateFeatures: [SharedRoute.Feature]

    /// Features within this many meters of the path are included.
    static let corridorWidth: CLLocationDistance = 200

    init(route: Route, features: [RoadFeature]) {
        self.name = route.name
        self.waypoints = route.waypointCoords
        self.path = route.pathCoords
        self.distanceMeters = route.distanceMeters
        self.maneuvers = route.maneuverCoords
        self.guidanceCoords = route.guidanceCoords
        self.guidanceInstructions = route.guidanceInstructions
        self.candidateFeatures = features.map {
            SharedRoute.Feature(
                type: $0.type.rawValue,
                latitude: $0.latitude,
                longitude: $0.longitude,
                bearing: $0.bearing,
                note: $0.note,
                severity: $0.severity
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
        let pathCoordinates = Route.unpack(path)
        // Bounding-box reject first: the per-point distance scan below is
        // O(features × path points), and a feature far from the route used to
        // walk the entire polyline before being discarded. The box is padded
        // by the corridor width so it can never exclude a real match.
        let degreeLatPad = Self.corridorWidth / 110_540
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        for coordinate in pathCoordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let midLat = (minLat + maxLat) / 2
        let degreeLonPad =
            Self.corridorWidth / (111_320 * max(cos(midLat * .pi / 180), 0.05))

        let pathLocations = pathCoordinates.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let nearby = pathCoordinates.isEmpty ? [] : candidateFeatures.filter { feature in
            guard feature.latitude >= minLat - degreeLatPad,
                feature.latitude <= maxLat + degreeLatPad,
                feature.longitude >= minLon - degreeLonPad,
                feature.longitude <= maxLon + degreeLonPad
            else { return false }
            let location = CLLocation(
                latitude: feature.latitude,
                longitude: feature.longitude
            )
            return pathLocations.contains {
                $0.distance(from: location) < Self.corridorWidth
            }
        }
        return SharedRoute(
            version: SharedRoute.currentVersion,
            name: name,
            waypoints: waypoints,
            path: path,
            distanceMeters: distanceMeters,
            features: nearby,
            maneuvers: maneuvers,
            guidanceCoords: guidanceCoords,
            guidanceInstructions: guidanceInstructions
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

        let guidanceCoords = Route.unpack(shared.guidanceCoords ?? [])
        let guidanceInstructions = shared.guidanceInstructions ?? []
        let guidanceSteps: [RouteBuilder.GuidanceStep] =
            guidanceCoords.count == guidanceInstructions.count
            ? zip(guidanceCoords, guidanceInstructions).map {
                RouteBuilder.GuidanceStep(coordinate: $0, instruction: $1)
            }
            : []
        let route = Route(
            name: shared.name,
            waypoints: Route.unpack(shared.waypoints),
            path: Route.unpack(shared.path),
            distanceMeters: shared.distanceMeters,
            maneuvers: Route.unpack(shared.maneuvers ?? []),
            guidanceSteps: guidanceSteps
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
                    note: feature.note,
                    severity: feature.severity ?? 2
                )
            )
        }

        return route
    }
}
