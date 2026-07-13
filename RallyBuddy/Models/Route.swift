import CoreLocation
import Foundation
import SwiftData

@Model
final class Route {
    var name: String
    var createdAt: Date
    /// Interleaved lat/lon pairs for the waypoints the user tapped.
    var waypointCoords: [Double]
    /// Interleaved lat/lon pairs for the road-snapped path between them.
    var pathCoords: [Double]
    var distanceMeters: Double

    init(
        name: String,
        waypoints: [CLLocationCoordinate2D],
        path: [CLLocationCoordinate2D],
        distanceMeters: Double
    ) {
        self.name = name
        self.createdAt = .now
        self.waypointCoords = Self.pack(waypoints)
        self.pathCoords = Self.pack(path)
        self.distanceMeters = distanceMeters
    }

    var waypoints: [CLLocationCoordinate2D] { Self.unpack(waypointCoords) }
    var path: [CLLocationCoordinate2D] { Self.unpack(pathCoords) }

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
