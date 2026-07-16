import CarPlay
import UIKit

/// CarPlay (driving-task category): a glanceable card with the next
/// callout, live distance, and speed, plus a drive start/stop button.
/// Templates only — custom map drawing needs the navigation entitlement.
@MainActor
final class CarPlaySceneDelegate: UIResponder, @preconcurrency CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var infoTemplate: CPInformationTemplate?
    private var refreshTimer: Timer?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        let template = CPInformationTemplate(
            title: "Rally Buddy",
            layout: .leading,
            items: Self.currentItems(),
            actions: Self.currentActions()
        )
        infoTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        self.interfaceController = nil
        infoTemplate = nil
    }

    private func refresh() {
        infoTemplate?.items = Self.currentItems()
        infoTemplate?.actions = Self.currentActions()
    }

    private static func currentItems() -> [CPInformationItem] {
        let services = AppServices.shared
        guard services.isDriving else {
            return [
                CPInformationItem(
                    title: "Ready",
                    detail: "Start a drive to get callouts for marked corners, passing lanes, and residential zones."
                )
            ]
        }

        var items: [CPInformationItem] = []
        if let next = services.alertEngine.upcoming.first {
            var title = next.feature.displayLabel
            if next.feature.type == .tightCorner {
                title = String(repeating: "›", count: next.feature.chevronCount) + " " + title
            }
            items.append(CPInformationItem(title: title, detail: "\(Int(next.distance)) m ahead"))
        } else {
            items.append(CPInformationItem(title: "Road clear", detail: "No marked features ahead"))
        }

        let speedText: String
        if let speed = services.locationService.location?.speed, speed >= 0 {
            speedText = "\(Int(speed * 3.6)) km/h"
        } else {
            speedText = "—"
        }
        items.append(CPInformationItem(title: "Speed", detail: speedText))
        return items
    }

    private static func currentActions() -> [CPTextButton] {
        let driving = AppServices.shared.isDriving
        return [
            CPTextButton(
                title: driving ? "End Drive" : "Start Drive",
                textStyle: driving ? .cancel : .confirm
            ) { _ in
                MainActor.assumeIsolated {
                    AppServices.shared.toggleDrive()
                }
            }
        ]
    }
}
