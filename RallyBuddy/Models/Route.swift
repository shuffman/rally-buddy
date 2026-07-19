import CoreLocation
import Foundation
import SwiftData

/// One line of a generated co-driver script, anchored to the point on the
/// route where it should be spoken.
struct PaceNote: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var text: String
}

@Model
final class Route {
    var name: String
    var createdAt: Date
    /// Interleaved lat/lon pairs for the waypoints the user tapped.
    var waypointCoords: [Double]
    /// Interleaved lat/lon pairs for the road-snapped path between them.
    var pathCoords: [Double]
    var distanceMeters: Double
    /// Interleaved lat/lon pairs for turn locations (step boundaries) —
    /// used to avoid flagging intersection turns as tight corners.
    var maneuverCoords: [Double] = []
    /// Turn-by-turn guidance: interleaved lat/lon per instruction, aligned
    /// with `guidanceInstructions`. Empty for routes saved before v0.6.0.
    var guidanceCoords: [Double] = []
    var guidanceInstructions: [String] = []
    /// AI co-driver script: interleaved lat/lon trigger points, aligned with
    /// `scriptLines`. Generated at planning time so drives work offline.
    var scriptCoords: [Double] = []
    var scriptLines: [String] = []

    init(
        name: String,
        waypoints: [CLLocationCoordinate2D],
        path: [CLLocationCoordinate2D],
        distanceMeters: Double,
        maneuvers: [CLLocationCoordinate2D] = [],
        guidanceSteps: [RouteBuilder.GuidanceStep] = []
    ) {
        self.name = name
        self.createdAt = .now
        self.waypointCoords = Self.pack(waypoints)
        self.pathCoords = Self.pack(path)
        self.distanceMeters = distanceMeters
        self.maneuverCoords = Self.pack(maneuvers)
        self.guidanceCoords = Self.pack(guidanceSteps.map(\.coordinate))
        self.guidanceInstructions = guidanceSteps.map(\.instruction)
    }

    var waypoints: [CLLocationCoordinate2D] { Self.unpack(waypointCoords) }
    var path: [CLLocationCoordinate2D] { Self.unpack(pathCoords) }
    var maneuvers: [CLLocationCoordinate2D] { Self.unpack(maneuverCoords) }

    var guidanceSteps: [RouteBuilder.GuidanceStep] {
        let coords = Self.unpack(guidanceCoords)
        guard coords.count == guidanceInstructions.count else { return [] }
        return zip(coords, guidanceInstructions).map {
            RouteBuilder.GuidanceStep(coordinate: $0, instruction: $1)
        }
    }

    var paceNotes: [PaceNote] {
        let coords = Self.unpack(scriptCoords)
        guard coords.count == scriptLines.count else { return [] }
        return zip(coords, scriptLines).map { PaceNote(coordinate: $0, text: $1) }
    }

    func setPaceNotes(_ notes: [PaceNote]) {
        scriptCoords = Self.pack(notes.map(\.coordinate))
        scriptLines = notes.map(\.text)
    }

    var formattedDistance: String {
        String(format: "%.1f km", distanceMeters / 1000)
    }

    static func pack(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
        coordinates.flatMap { [$0.latitude, $0.longitude] }
    }

    static func unpack(_ values: [Double]) -> [CLLocationCoordinate2D] {
        stride(from: 0, to: values.count - 1, by: 2).map {
            CLLocationCoordinate2D(latitude: values[$0], longitude: values[$0 + 1])
        }
    }
}
