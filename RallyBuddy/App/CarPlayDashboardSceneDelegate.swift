import CarPlay
import UIKit

/// CarPlay Dashboard scene (the split-screen "widgets" home screen).
/// Navigation apps may draw their map here with up to two shortcut buttons.
/// Reuses `CarPlayMapViewController` — the same follow-the-driver map as the
/// full CarPlay app scene, sharing all state through `AppServices`.
@MainActor
final class CarPlayDashboardSceneDelegate: UIResponder,
    @preconcurrency CPTemplateApplicationDashboardSceneDelegate
{
    private var dashboardController: CPDashboardController?
    private var mapController: CarPlayMapViewController?
    private var refreshTimer: Timer?
    private var lastDriving: Bool?

    func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didConnect dashboardController: CPDashboardController,
        to window: UIWindow
    ) {
        self.dashboardController = dashboardController

        let mapVC = CarPlayMapViewController()
        window.rootViewController = mapVC
        mapController = mapVC

        updateButtons(driving: AppServices.shared.isDriving)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didDisconnect dashboardController: CPDashboardController,
        from window: UIWindow
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        mapController?.teardown()
        mapController = nil
        self.dashboardController = nil
    }

    private func tick() {
        mapController?.refresh()
        let driving = AppServices.shared.isDriving
        if lastDriving != driving {
            updateButtons(driving: driving)
        }
    }

    /// Two shortcut buttons: drive toggle + recenter. Rebuilt when the drive
    /// state changes so the toggle label stays correct.
    private func updateButtons(driving: Bool) {
        lastDriving = driving
        let drive = CPDashboardButton(
            titleVariants: [driving ? "End Drive" : "Start Drive"],
            subtitleVariants: ["Rally Buddy"],
            image: UIImage(systemName: driving ? "stop.circle" : "flag.checkered") ?? UIImage()
        ) { _ in
            MainActor.assumeIsolated { AppServices.shared.toggleDrive() }
        }
        let recenter = CPDashboardButton(
            titleVariants: ["Recenter"],
            subtitleVariants: ["Map"],
            image: UIImage(systemName: "location.fill") ?? UIImage()
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mapController?.recenter() }
        }
        dashboardController?.shortcutButtons = [drive, recenter]
    }
}
