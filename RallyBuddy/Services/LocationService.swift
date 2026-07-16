import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false

    /// Called on every location fix, independent of any UI being visible.
    @ObservationIgnored var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startTracking() {
        // Requires the 'location' background mode so callouts keep working
        // with the screen off or the app in the background.
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        if let last = locations.last {
            onLocationUpdate?(last)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. kCLErrorLocationUnknown) resolve on their own;
        // keep the last known location.
    }
}
