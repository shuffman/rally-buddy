import CarPlay
import CoreLocation
import MapKit
import UIKit

/// CarPlay (navigation category): draws the MapLibre map on the car screen
/// via `CarPlayMapViewController`, overlaid with a `CPMapTemplate` for
/// controls and a turn-by-turn maneuver panel driven by NavigationEngine.
/// Spoken feature callouts play through the car speakers as usual.
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var mapController: CarPlayMapViewController?
    private var mapTemplate: CPMapTemplate?
    private var refreshTimer: Timer?

    private var navigationSession: CPNavigationSession?
    private var currentManeuver: CPManeuver?
    private var lastInstruction: String?

    // MARK: - Scene lifecycle (navigation variant — provides a car window)

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController

        let mapVC = CarPlayMapViewController()
        window.rootViewController = mapVC
        mapController = mapVC

        let template = CPMapTemplate()
        template.mapButtons = [recenterButton()]
        template.trailingNavigationBarButtons = [driveButton()]
        template.leadingNavigationBarButtons = [markButton()]
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
        mapTemplate = template

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        navigationSession = nil
        currentManeuver = nil
        mapTemplate = nil
        mapController = nil
        self.interfaceController = nil
    }

    // MARK: - Per-tick refresh

    private func refresh() {
        mapController?.refresh()
        updateControls()
        updateGuidance()
    }

    private func updateControls() {
        mapTemplate?.trailingNavigationBarButtons = [driveButton()]
        mapTemplate?.leadingNavigationBarButtons = [markButton()]
    }

    // MARK: - Turn-by-turn

    private func updateGuidance() {
        guard let mapTemplate else { return }
        let nav = AppServices.shared.navigationEngine

        // End the session when the drive/route is done.
        guard AppServices.shared.isDriving, nav.isNavigating,
            let instruction = nav.nextInstruction
        else {
            if let session = navigationSession {
                session.finishTrip()
                navigationSession = nil
                currentManeuver = nil
                lastInstruction = nil
            }
            return
        }

        if navigationSession == nil {
            navigationSession = mapTemplate.startNavigationSession(for: currentTrip())
        }

        // Rebuild the maneuver only when the instruction text changes.
        if instruction != lastInstruction {
            lastInstruction = instruction
            let maneuver = CPManeuver()
            maneuver.instructionVariants = [instruction]
            maneuver.symbolImage = UIImage(systemName: "arrow.turn.up.right")
            if let distance = nav.nextManeuverDistance {
                maneuver.initialTravelEstimates = estimates(toManeuver: distance)
            }
            currentManeuver = maneuver
            navigationSession?.upcomingManeuvers = [maneuver]
        }

        if let maneuver = currentManeuver, let distance = nav.nextManeuverDistance {
            navigationSession?.updateEstimates(estimates(toManeuver: distance), for: maneuver)
        }
    }

    /// Travel estimates to the next maneuver; time is distance over current
    /// speed (floored so it never divides by a near-zero speed).
    private func estimates(toManeuver distance: CLLocationDistance) -> CPTravelEstimates {
        let speed = max(AppServices.shared.locationService.location?.speed ?? 0, 8)
        return CPTravelEstimates(
            distanceRemaining: Measurement(value: distance, unit: .meters),
            timeRemaining: distance / speed
        )
    }

    /// A CPTrip describing the active route (origin → destination). The
    /// summary carries the route name and remaining distance.
    private func currentTrip() -> CPTrip {
        let route = AppServices.shared.activeRoute
        let path = route?.path ?? []
        let origin = MKMapItem(
            placemark: MKPlacemark(coordinate: path.first ?? .init(latitude: 0, longitude: 0))
        )
        let destination = MKMapItem(
            placemark: MKPlacemark(coordinate: path.last ?? .init(latitude: 0, longitude: 0))
        )
        let choice = CPRouteChoice(
            summaryVariants: [route?.name ?? "Route"],
            additionalInformationVariants: [],
            selectionSummaryVariants: []
        )
        return CPTrip(origin: origin, destination: destination, routeChoices: [choice])
    }

    // MARK: - Buttons

    private func recenterButton() -> CPMapButton {
        let button = CPMapButton { [weak self] _ in
            MainActor.assumeIsolated { self?.mapController?.recenter() }
        }
        button.image = UIImage(systemName: "location.fill")
        return button
    }

    private func driveButton() -> CPBarButton {
        let driving = AppServices.shared.isDriving
        return CPBarButton(title: driving ? "End Drive" : "Start Drive") { _ in
            MainActor.assumeIsolated { AppServices.shared.toggleDrive() }
        }
    }

    private func markButton() -> CPBarButton {
        CPBarButton(title: "Mark") { [weak self] _ in
            MainActor.assumeIsolated { self?.presentMarkGrid() }
        }
    }

    // MARK: - Marking

    private func presentMarkGrid() {
        guard let interfaceController else { return }
        let grid = CPGridTemplate(title: "Mark Feature", gridButtons: markGridButtons())
        interfaceController.pushTemplate(grid, animated: true, completion: nil)
    }

    private struct MarkSpec {
        let title: String
        let type: RoadFeatureType
        let severity: Int
        let chevrons: Int?
        let symbol: String?
    }

    private static let markSpecs: [MarkSpec] = [
        MarkSpec(title: "Mild", type: .tightCorner, severity: 1, chevrons: 1, symbol: nil),
        MarkSpec(title: "Tight", type: .tightCorner, severity: 2, chevrons: 2, symbol: nil),
        MarkSpec(title: "Hairpin", type: .tightCorner, severity: 3, chevrons: 3, symbol: nil),
        MarkSpec(title: "Passing lane", type: .passingLane, severity: 2, chevrons: nil, symbol: "car.2"),
        MarkSpec(title: "Residential", type: .residentialZone, severity: 2, chevrons: nil, symbol: "house.fill"),
    ]

    private func markGridButtons() -> [CPGridButton] {
        Self.markSpecs.map { spec in
            let image = MapLibreView.Coordinator.markerImage(
                symbolName: spec.symbol,
                textLabel: nil,
                tint: UIColor(spec.type.tint),
                explorer: false,
                chevrons: spec.chevrons
            )
            return CPGridButton(titleVariants: [spec.title], image: image) { [weak self] _ in
                MainActor.assumeIsolated {
                    AppServices.shared.quickMark(type: spec.type, severity: spec.severity)
                    self?.interfaceController?.popTemplate(animated: true, completion: nil)
                }
            }
        }
    }
}
