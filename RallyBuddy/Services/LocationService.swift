import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false

    /// Number of active standby requesters (e.g. the CarPlay map showing
    /// position without a drive). Standby delivers fixes but does not set
    /// isTracking, so `isDriving` stays false and no callouts fire.
    @ObservationIgnored private var standbyCount = 0

    /// Best location available right now, including the location manager's
    /// cached fix — populated before our first delegate callback, so the map
    /// can center immediately instead of at the style's default.
    var lastKnownLocation: CLLocation? { location ?? manager.location }

    /// Called on every location fix, independent of any UI being visible.
    @ObservationIgnored var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
    }

    func requestPermission() {
        // The screenshot/demo harness (--demo-nav) uses simulated location,
        // which the simulator delivers without authorization; skip the
        // prompt so it doesn't block captures.
        guard !ProcessInfo.processInfo.arguments.contains("--demo-nav") else { return }
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
        isTracking = false
        // Keep updates (and background updates) running if standby still
        // wants position; otherwise fully stop.
        if standbyCount == 0 {
            manager.allowsBackgroundLocationUpdates = false
            manager.stopUpdatingLocation()
        }
    }

    /// Start delivering fixes for showing position without a drive (e.g. the
    /// CarPlay map). Balanced by `stopStandby()`. Enables background updates
    /// so the car map keeps following with the phone locked, but does not set
    /// isTracking — `isDriving` stays false and no callouts fire.
    func startStandby() {
        standbyCount += 1
        requestPermission()
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func stopStandby() {
        standbyCount = max(0, standbyCount - 1)
        if standbyCount == 0, !isTracking {
            manager.allowsBackgroundLocationUpdates = false
            manager.stopUpdatingLocation()
        }
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
