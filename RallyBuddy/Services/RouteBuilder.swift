import CoreLocation
import Foundation
import MapKit

/// Turns a sequence of tapped waypoints into a road-snapped path using
/// MKDirections, one leg per waypoint pair.
enum RouteBuilder {
    struct PlannedPath {
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: Double
        /// Turn locations (route step boundaries + intermediate waypoints).
        let maneuvers: [CLLocationCoordinate2D]
    }

    static func plan(through waypoints: [CLLocationCoordinate2D]) async throws -> PlannedPath {
        guard waypoints.count >= 2 else {
            return PlannedPath(coordinates: [], distanceMeters: 0, maneuvers: [])
        }

        var coordinates: [CLLocationCoordinate2D] = []
        var distance: CLLocationDistance = 0
        var maneuvers: [CLLocationCoordinate2D] = Array(waypoints.dropFirst().dropLast())

        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
            request.transportType = .automobile

            let response = try await MKDirections(request: request).calculate()
            guard let leg = response.routes.first else { continue }
            coordinates.append(contentsOf: leg.polyline.coordinateArray)
            distance += leg.distance
            for step in leg.steps.dropFirst() {
                if let turn = step.polyline.coordinateArray.first {
                    maneuvers.append(turn)
                }
            }
            try Task.checkCancellation()
        }

        return PlannedPath(coordinates: coordinates, distanceMeters: distance, maneuvers: maneuvers)
    }
}

extension MKPolyline {
    var coordinateArray: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: pointCount
        )
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}
