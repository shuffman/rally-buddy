import CarPlay
import UIKit

/// CarPlay (driving-task category): template UI only — a real map on the
/// car screen requires the navigation entitlement (see CLAUDE.md).
/// Two tabs: "Ahead" (upcoming features, speed, drive toggle) and "Mark"
/// (one-tap feature marking from the car screen).
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

        let info = CPInformationTemplate(
            title: "Ahead",
            layout: .leading,
            items: Self.currentItems(),
            actions: Self.currentActions()
        )
        info.tabTitle = "Ahead"
        info.tabImage = UIImage(systemName: "road.lanes")
        infoTemplate = info

        let grid = CPGridTemplate(title: "Mark", gridButtons: Self.markButtons())
        grid.tabTitle = "Mark"
        grid.tabImage = UIImage(systemName: "plus.circle")

        let tabBar = CPTabBarTemplate(templates: [info, grid])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

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

    // MARK: - Ahead tab

    private static func currentItems() -> [CPInformationItem] {
        let services = AppServices.shared
        guard services.isDriving else {
            return [
                CPInformationItem(
                    title: "Ready",
                    detail: "Start a drive to get callouts. Mark features any time from the Mark tab."
                )
            ]
        }

        var items: [CPInformationItem] = []
        let upcoming = services.alertEngine.upcoming.prefix(3)
        if upcoming.isEmpty {
            items.append(CPInformationItem(title: "Road clear", detail: "No marked features ahead"))
        }
        for entry in upcoming {
            var title = entry.feature.displayLabel
            if entry.feature.type == .tightCorner {
                title = String(repeating: "›", count: entry.feature.chevronCount) + " " + title
            }
            items.append(CPInformationItem(title: title, detail: "\(Int(entry.distance)) m"))
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

    // MARK: - Mark tab

    private struct MarkButton {
        let title: String
        let type: RoadFeatureType
        let severity: Int
        let chevrons: Int?
        let symbol: String?
    }

    private static let markButtonSpecs: [MarkButton] = [
        MarkButton(title: "Mild corner", type: .tightCorner, severity: 1, chevrons: 1, symbol: nil),
        MarkButton(title: "Tight corner", type: .tightCorner, severity: 2, chevrons: 2, symbol: nil),
        MarkButton(title: "Hairpin", type: .tightCorner, severity: 3, chevrons: 3, symbol: nil),
        MarkButton(title: "Passing lane", type: .passingLane, severity: 2, chevrons: nil, symbol: "car.2"),
        MarkButton(title: "Residential", type: .residentialZone, severity: 2, chevrons: nil, symbol: "house.fill"),
    ]

    private static func markButtons() -> [CPGridButton] {
        markButtonSpecs.map { spec in
            let image = MapLibreView.Coordinator.markerImage(
                symbolName: spec.symbol,
                textLabel: nil,
                tint: UIColor(spec.type.tint),
                explorer: false,
                chevrons: spec.chevrons
            )
            return CPGridButton(titleVariants: [spec.title], image: image) { _ in
                MainActor.assumeIsolated {
                    AppServices.shared.quickMark(type: spec.type, severity: spec.severity)
                }
            }
        }
    }
}
