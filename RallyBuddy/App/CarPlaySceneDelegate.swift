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
        template.mapButtons = [zoomInButton(), zoomOutButton(), recenterButton()]
        template.trailingNavigationBarButtons = [driveButton()]
        template.leadingNavigationBarButtons = [markButton()]
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
        mapTemplate = template

        // .common mode so the tick keeps firing during CarPlay interactions.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
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
        mapController?.teardown()
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

    private func zoomInButton() -> CPMapButton {
        let button = CPMapButton { [weak self] _ in
            MainActor.assumeIsolated { self?.mapController?.zoomIn() }
        }
        button.image = UIImage(systemName: "plus.magnifyingglass")
        return button
    }

    private func zoomOutButton() -> CPMapButton {
        let button = CPMapButton { [weak self] _ in
            MainActor.assumeIsolated { self?.mapController?.zoomOut() }
        }
        button.image = UIImage(systemName: "minus.magnifyingglass")
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
            MainActor.assumeIsolated { self?.presentMarkOptions() }
        }
    }

    // MARK: - Marking

    /// Present the mark choices as a modal action sheet — the supported way
    /// to offer a choice over a navigation map. (Pushing a CPGridTemplate onto
    /// the map-template stack crashed on selection.) The sheet auto-dismisses
    /// when an action is chosen.
    private func presentMarkOptions() {
        guard let interfaceController else { return }
        var actions = Self.markSpecs.map { spec in
            CPAlertAction(title: spec.title, style: .default) { _ in
                MainActor.assumeIsolated {
                    AppServices.shared.quickMark(type: spec.type, severity: spec.severity)
                }
            }
        }
        actions.append(CPAlertAction(title: "Cancel", style: .cancel) { _ in })
        let sheet = CPActionSheetTemplate(title: "Mark Feature", message: nil, actions: actions)
        interfaceController.presentTemplate(sheet, animated: true, completion: nil)
    }

    private struct MarkSpec {
        let title: String
        let type: RoadFeatureType
        let severity: Int
    }

    private static let markSpecs: [MarkSpec] = [
        MarkSpec(title: "Mild corner \u{203A}", type: .tightCorner, severity: 1),
        MarkSpec(title: "Tight corner \u{203A}\u{203A}", type: .tightCorner, severity: 2),
        MarkSpec(title: "Hairpin \u{203A}\u{203A}\u{203A}", type: .tightCorner, severity: 3),
        MarkSpec(title: "Passing lane", type: .passingLane, severity: 2),
        MarkSpec(title: "Residential zone", type: .residentialZone, severity: 2),
    ]
}
