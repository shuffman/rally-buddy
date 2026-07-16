import CoreLocation
import Foundation
import SwiftData

/// Shared services used by both the phone UI and the CarPlay scene.
/// Owning the location→alert wiring here (instead of in a SwiftUI view)
/// keeps callouts running when the phone UI isn't on screen.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let locationService = LocationService()
    let speech = SpeechService()
    let alertEngine: AlertEngine

    /// Snapshot of features used for alerting during the active drive.
    private var activeFeatures: [RoadFeature] = []

    private init() {
        do {
            container = try ModelContainer(for: RoadFeature.self, Route.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        alertEngine = AlertEngine(speech: speech)
        locationService.onLocationUpdate = { [weak self] location in
            self?.handleLocation(location)
        }
    }

    var isDriving: Bool { locationService.isTracking }

    func startDrive() {
        activeFeatures =
            (try? container.mainContext.fetch(FetchDescriptor<RoadFeature>())) ?? []
        locationService.startTracking()
    }

    func endDrive() {
        locationService.stopTracking()
        alertEngine.reset()
    }

    func toggleDrive() {
        isDriving ? endDrive() : startDrive()
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
    }
}
