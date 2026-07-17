import CoreLocation
import Foundation
import Observation

/// Turn-by-turn guidance along a planned route: tracks progress, announces
/// maneuvers, detects off-route and reroutes, and detects arrival.
/// Feature callouts remain AlertEngine's job; both run during a drive.
@MainActor
@Observable
final class NavigationEngine {
    private struct ActiveStep {
        let coordinate: CLLocationCoordinate2D
        let instruction: String
        var pathIndex: Int = 0
        var announcedFar = false
        var announcedNear = false
    }

    // Published state for the phone UI (and later, CarPlay).
    private(set) var isNavigating = false
    private(set) var nextInstruction: String?
    private(set) var nextManeuverDistance: CLLocationDistance?
    private(set) var remainingDistance: CLLocationDistance?
    private(set) var isOffRoute = false
    private(set) var isRerouting = false
    private(set) var hasArrived = false

    /// Speech output, injected by AppServices (and a test hook).
    @ObservationIgnored var announce: (String) -> Void = { _ in }

    private var path: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []
    private var steps: [ActiveStep] = []
    private var stepCursor = 0
    private var progressIndex = 0
    private var offRouteCount = 0
    private var finalDestination: CLLocationCoordinate2D?
    private var rerouteTask: Task<Void, Never>?

    // Tuning (meters).
    static let farAnnounceDistance: Double = 500
    static let nearAnnounceDistance: Double = 120
    static let offRouteTolerance: Double = 60
    static let offRouteConfirmCount = 3
    static let arrivalRadius: Double = 45

    // MARK: - Lifecycle

    func start(route: Route) {
        stop()
        configure(
            path: route.path,
            steps: route.guidanceSteps,
            destination: route.waypoints.last ?? route.path.last
        )
        guard path.count >= 2 else { return }
        isNavigating = true
        hasArrived = false
        if steps.isEmpty {
            announce("Following route. This route has no turn instructions; replan it to add them")
        } else {
            announce("Navigation started")
        }
    }

    func stop() {
        rerouteTask?.cancel()
        rerouteTask = nil
        isNavigating = false
        isOffRoute = false
        isRerouting = false
        nextInstruction = nil
        nextManeuverDistance = nil
        remainingDistance = nil
        path = []
        steps = []
    }

    private func configure(
        path newPath: [CLLocationCoordinate2D],
        steps newSteps: [RouteBuilder.GuidanceStep],
        destination: CLLocationCoordinate2D?
    ) {
        path = newPath
        cumulative = Self.cumulativeDistances(path)
        steps = newSteps.map {
            ActiveStep(coordinate: $0.coordinate, instruction: $0.instruction)
        }
        for i in steps.indices {
            steps[i].pathIndex = Self.nearestIndex(on: path, to: steps[i].coordinate)
        }
        steps.sort { $0.pathIndex < $1.pathIndex }
        stepCursor = 0
        progressIndex = 0
        offRouteCount = 0
        finalDestination = destination
    }

    // MARK: - Per-fix update

    func update(location: CLLocation) {
        guard isNavigating, !isRerouting, path.count >= 2 else { return }

        progressIndex = Self.advance(on: path, from: progressIndex, toward: location.coordinate)
        let nearest = path[progressIndex]
        let crossTrack = location.distance(
            from: CLLocation(latitude: nearest.latitude, longitude: nearest.longitude)
        )
        remainingDistance = max(0, (cumulative.last ?? 0) - cumulative[progressIndex])

        // Arrival
        if let destination = finalDestination {
            let toDestination = location.distance(
                from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            )
            if toDestination < Self.arrivalRadius
                || (progressIndex >= path.count - 2 && crossTrack < Self.offRouteTolerance)
            {
                announce("You have arrived")
                hasArrived = true
                stop()
                return
            }
        }

        // Off-route detection (needs several consecutive bad fixes)
        if crossTrack > Self.offRouteTolerance {
            offRouteCount += 1
            if offRouteCount >= Self.offRouteConfirmCount {
                isOffRoute = true
                reroute(from: location)
                return
            }
        } else {
            offRouteCount = 0
            isOffRoute = false
        }

        // Maneuver bookkeeping
        while stepCursor < steps.count, steps[stepCursor].pathIndex <= progressIndex {
            stepCursor += 1
        }
        guard stepCursor < steps.count else {
            nextInstruction = finalDestination != nil ? "Continue to destination" : nil
            nextManeuverDistance = remainingDistance
            return
        }

        let distance = max(
            0, cumulative[steps[stepCursor].pathIndex] - cumulative[progressIndex]
        )
        nextInstruction = steps[stepCursor].instruction
        nextManeuverDistance = distance

        if distance < Self.nearAnnounceDistance, !steps[stepCursor].announcedNear {
            steps[stepCursor].announcedNear = true
            steps[stepCursor].announcedFar = true
            announce(steps[stepCursor].instruction)
        } else if distance < Self.farAnnounceDistance, !steps[stepCursor].announcedFar {
            steps[stepCursor].announcedFar = true
            let rounded = Int(max(100, (distance / 100).rounded() * 100))
            announce("In \(rounded) meters, \(lowercasedFirst(steps[stepCursor].instruction))")
        }
    }

    // MARK: - Rerouting

    private func reroute(from location: CLLocation) {
        guard let destination = finalDestination, !isRerouting else { return }
        isRerouting = true
        announce("Rerouting")
        rerouteTask = Task {
            do {
                let planned = try await RouteBuilder.plan(
                    through: [location.coordinate, destination]
                )
                guard !Task.isCancelled else { return }
                configure(
                    path: planned.coordinates,
                    steps: planned.guidanceSteps,
                    destination: destination
                )
                isOffRoute = false
            } catch {
                // No network (or no route): stay on the old path so the trail
                // is still drawn; the next off-route streak retries.
                offRouteCount = 0
            }
            isRerouting = false
        }
    }

    // MARK: - Geometry

    private func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    static func cumulativeDistances(_ path: [CLLocationCoordinate2D]) -> [Double] {
        var result: [Double] = [0]
        result.reserveCapacity(path.count)
        for i in 1..<max(path.count, 1) {
            let d = CLLocation(latitude: path[i - 1].latitude, longitude: path[i - 1].longitude)
                .distance(
                    from: CLLocation(latitude: path[i].latitude, longitude: path[i].longitude)
                )
            result.append(result[i - 1] + d)
        }
        return result
    }

    static func nearestIndex(
        on path: [CLLocationCoordinate2D],
        to coordinate: CLLocationCoordinate2D
    ) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for (i, point) in path.enumerated() {
            let d = target.distance(
                from: CLLocation(latitude: point.latitude, longitude: point.longitude)
            )
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return best
    }

    /// Nearest path index in a forward-biased window around the last known
    /// progress, so progress never jumps backward on switchbacks.
    static func advance(
        on path: [CLLocationCoordinate2D],
        from lastIndex: Int,
        toward coordinate: CLLocationCoordinate2D
    ) -> Int {
        let start = max(0, lastIndex - 5)
        let end = min(path.count - 1, lastIndex + 80)
        var best = lastIndex
        var bestDistance = Double.greatestFiniteMagnitude
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for i in start...end {
            let d = target.distance(
                from: CLLocation(latitude: path[i].latitude, longitude: path[i].longitude)
            )
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        return max(best, lastIndex)
    }
}
