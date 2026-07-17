import CoreLocation
import Foundation
import Observation
import SwiftData

/// Shared services used by both the phone UI and the CarPlay scene.
/// Owning the location→alert/guidance wiring here (instead of in a SwiftUI
/// view) keeps callouts and navigation running when no UI is on screen.
@MainActor
@Observable
final class AppServices {
    static let shared = AppServices()

    @ObservationIgnored let container: ModelContainer
    let locationService = LocationService()
    @ObservationIgnored let speech = SpeechService()
    let alertEngine: AlertEngine
    let navigationEngine = NavigationEngine()

    /// The route drawn on the drive screen and navigated when a drive starts.
    var activeRoute: Route?

    /// Snapshot of features used for alerting during the active drive.
    @ObservationIgnored private var activeFeatures: [RoadFeature] = []

    private init() {
        do {
            container = try ModelContainer(for: RoadFeature.self, Route.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        alertEngine = AlertEngine(speech: speech)
        navigationEngine.announce = { [speech] text in speech.say(text) }
        locationService.onLocationUpdate = { [weak self] location in
            self?.handleLocation(location)
        }
    }

    var isDriving: Bool { locationService.isTracking }

    func startDrive() {
        activeFeatures =
            (try? container.mainContext.fetch(FetchDescriptor<RoadFeature>())) ?? []
        if let route = activeRoute {
            navigationEngine.start(route: route)
        }
        locationService.startTracking()
    }

    func endDrive() {
        locationService.stopTracking()
        navigationEngine.stop()
        alertEngine.reset()
    }

    func toggleDrive() {
        isDriving ? endDrive() : startDrive()
    }

    /// One-tap marking at the current location (drive screen buttons and
    /// the CarPlay Mark tab). Confirms out loud; no-op without a GPS fix.
    @discardableResult
    func quickMark(type: RoadFeatureType, severity: Int = 2) -> RoadFeature? {
        guard let location = locationService.location else { return nil }
        let feature = RoadFeature(
            type: type,
            coordinate: location.coordinate,
            bearing: location.course >= 0 ? location.course : nil,
            severity: severity
        )
        addFeature(feature)
        speech.say("Marked \(feature.spokenName.lowercased())")
        return feature
    }

    /// Insert a quick-marked feature and keep the live alert snapshot
    /// current so it isn't announced back to the driver.
    func addFeature(_ feature: RoadFeature) {
        container.mainContext.insert(feature)
        alertEngine.suppress(feature)
        if locationService.isTracking {
            activeFeatures.append(feature)
        }
    }

    private func handleLocation(_ location: CLLocation) {
        guard locationService.isTracking else { return }
        alertEngine.update(location: location, features: activeFeatures)
        navigationEngine.update(location: location)
    }
}
