import CoreLocation
import Foundation
import SwiftData

/// Launch-argument demo mode (`--demo-nav`): plans a real route, seeds a
/// few features along it, activates navigation, and writes the path to
/// Documents/demo_path.json so tooling can replay it as simulated GPS.
/// Used for screenshots and manual testing; inert in normal launches.
enum DemoSeeder {
    @MainActor
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-nav") else { return }
        let services = AppServices.shared
        let context = services.container.mainContext

        // Re-runnable: reuse the demo route if it already exists.
        let existing = try? context.fetch(FetchDescriptor<Route>()).first {
            $0.name == "Demo — Cornell Climb"
        }
        if let existing {
            services.activeRoute = existing
            services.startDrive()
            return
        }

        // NW Portland: Lovejoy up through Cornell Rd's curves.
        let start = CLLocationCoordinate2D(latitude: 45.52950, longitude: -122.69850)
        let end = CLLocationCoordinate2D(latitude: 45.54160, longitude: -122.74450)

        guard let planned = try? await RouteBuilder.plan(through: [start, end]),
            planned.coordinates.count >= 2
        else { return }

        let route = Route(
            name: "Demo — Cornell Climb",
            waypoints: [start, end],
            path: planned.coordinates,
            distanceMeters: planned.distanceMeters,
            maneuvers: planned.maneuvers,
            guidanceSteps: planned.guidanceSteps
        )
        context.insert(route)

        // A few features along the route so callouts fire during the demo.
        let count = planned.coordinates.count
        let picks: [(fraction: Double, type: RoadFeatureType, severity: Int)] = [
            (0.35, .tightCorner, 2),
            (0.55, .residentialZone, 2),
            (0.75, .tightCorner, 3),
        ]
        for pick in picks {
            let coordinate = planned.coordinates[min(count - 1, Int(Double(count) * pick.fraction))]
            context.insert(
                RoadFeature(
                    type: pick.type,
                    coordinate: coordinate,
                    note: "Demo",
                    severity: pick.severity
                )
            )
        }

        // Export the path for host-side GPS replay.
        if let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            let waypoints = planned.coordinates.map { [$0.latitude, $0.longitude] }
            if let data = try? JSONSerialization.data(withJSONObject: waypoints) {
                try? data.write(to: documents.appendingPathComponent("demo_path.json"))
            }
        }

        services.activeRoute = route
        services.startDrive()
    }
}
