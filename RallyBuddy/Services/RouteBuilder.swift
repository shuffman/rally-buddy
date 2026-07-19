import CoreLocation
import Foundation
import MapKit

/// Turns a sequence of tapped waypoints into a road-snapped path using
/// MKDirections, one leg per waypoint pair.
enum RouteBuilder {
    struct GuidanceStep {
        let coordinate: CLLocationCoordinate2D
        let instruction: String
    }

    struct PlannedPath {
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: Double
        /// Turn locations (route step boundaries + intermediate waypoints).
        let maneuvers: [CLLocationCoordinate2D]
        /// Spoken/visual turn-by-turn instructions, ordered along the route.
        let guidanceSteps: [GuidanceStep]
        /// Sum of MKDirections leg travel-time estimates.
        let expectedTravelTime: TimeInterval
    }

    /// One road-snapped leg between two waypoints, as returned by MKDirections.
    struct PlannedLeg {
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: Double
        let maneuvers: [CLLocationCoordinate2D]
        let guidanceSteps: [GuidanceStep]
        let expectedTravelTime: TimeInterval
    }

    /// Memoizes MKDirections legs by endpoint pair so re-plans that share
    /// legs (the generator's refinement pass, re-generation) skip the
    /// network. Keys round coordinates to 5 decimals (~1 m).
    final class LegCache {
        private var legs: [String: PlannedLeg] = [:]

        fileprivate func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
            String(
                format: "%.5f,%.5f->%.5f,%.5f",
                a.latitude, a.longitude, b.latitude, b.longitude
            )
        }

        fileprivate func leg(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> PlannedLeg? {
            legs[key(a, b)]
        }

        fileprivate func store(
            _ leg: PlannedLeg, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
        ) {
            legs[key(a, b)] = leg
        }
    }

    static func plan(
        through waypoints: [CLLocationCoordinate2D],
        interLegDelay: Duration = .zero,
        legCache: LegCache? = nil
    ) async throws -> PlannedPath {
        guard waypoints.count >= 2 else {
            return PlannedPath(
                coordinates: [], distanceMeters: 0, maneuvers: [], guidanceSteps: [],
                expectedTravelTime: 0
            )
        }

        var coordinates: [CLLocationCoordinate2D] = []
        var distance: CLLocationDistance = 0
        var maneuvers: [CLLocationCoordinate2D] = Array(waypoints.dropFirst().dropLast())
        var guidanceSteps: [GuidanceStep] = []
        var travelTime: TimeInterval = 0

        for (start, end) in zip(waypoints, waypoints.dropFirst()) {
            let leg: PlannedLeg
            if let cached = legCache?.leg(start, end) {
                leg = cached
            } else {
                guard let fetched = try await fetchLeg(from: start, to: end) else { continue }
                leg = fetched
                legCache?.store(leg, start, end)
                if interLegDelay > .zero {
                    try await Task.sleep(for: interLegDelay)
                }
            }
            coordinates.append(contentsOf: leg.coordinates)
            distance += leg.distanceMeters
            maneuvers.append(contentsOf: leg.maneuvers)
            guidanceSteps.append(contentsOf: leg.guidanceSteps)
            travelTime += leg.expectedTravelTime
            try Task.checkCancellation()
        }

        return PlannedPath(
            coordinates: coordinates,
            distanceMeters: distance,
            maneuvers: maneuvers,
            guidanceSteps: guidanceSteps,
            expectedTravelTime: travelTime
        )
    }

    /// One MKDirections request. Retries once after 5 s on throttling, then
    /// rethrows so the caller can drop just this route. Returns nil when no
    /// drivable road connects the pair (matching the old skip-the-leg
    /// behavior).
    private static func fetchLeg(
        from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D
    ) async throws -> PlannedLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch let error as MKError where error.code == .loadingThrottled {
            try await Task.sleep(for: .seconds(5))
            response = try await MKDirections(request: request).calculate()
        }
        guard let leg = response.routes.first else { return nil }

        var guidanceSteps: [GuidanceStep] = []
        for step in leg.steps {
            guard !step.instructions.isEmpty,
                let turn = step.polyline.coordinateArray.first
            else { continue }
            guidanceSteps.append(
                GuidanceStep(coordinate: turn, instruction: step.instructions)
            )
        }
        var maneuvers: [CLLocationCoordinate2D] = []
        for step in leg.steps.dropFirst() {
            if let turn = step.polyline.coordinateArray.first {
                maneuvers.append(turn)
            }
        }
        return PlannedLeg(
            coordinates: leg.polyline.coordinateArray,
            distanceMeters: leg.distance,
            maneuvers: maneuvers,
            guidanceSteps: guidanceSteps,
            expectedTravelTime: leg.expectedTravelTime
        )
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
