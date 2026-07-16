import CoreLocation
import SwiftData
import SwiftUI
import UIKit

/// The main screen: a full-screen map with everything the driver needs in
/// one tap — quick-mark buttons, speed, and the next callout.
struct DriveView: View {
    var locationService: LocationService
    var alertEngine: AlertEngine
    @Binding var activeRoute: Route?

    @Environment(\.modelContext) private var modelContext
    @Query private var features: [RoadFeature]
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var pendingPoint: PendingPoint?
    @State private var recenterToken = 0
    @AppStorage("mapTheme") private var mapThemeRaw = MapTheme.standard.rawValue

    private var mapTheme: MapTheme {
        MapTheme(rawValue: mapThemeRaw) ?? .standard
    }

    var body: some View {
        MapLibreView(
            markers: features.map { feature in
                MapMarker(
                    id: "f-\(feature.createdAt.timeIntervalSince1970)",
                    coordinate: feature.coordinate,
                    kind: .feature(feature.type),
                    suggested: feature.isSuggested,
                    chevrons: feature.type == .tightCorner ? feature.chevronCount : nil
                )
            },
            pathCoordinates: activeRoute?.path ?? [],
            theme: mapTheme,
            followsCourse: locationService.isTracking,
            fitPathOnChange: true,
            recenterToken: recenterToken,
            onTap: { coordinate in
                // Map-tap annotation is a parked-car activity; while driving,
                // marking happens through the big buttons only.
                guard !locationService.isTracking else { return }
                pendingPoint = PendingPoint(coordinate: coordinate)
            }
        )
        .ignoresSafeArea()
        .overlay {
            if mapTheme == .explorer {
                ParchmentOverlay()
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .overlay(alignment: .top) {
            if let next = alertEngine.upcoming.first {
                CalloutBanner(item: next, serif: mapTheme == .explorer)
            }
        }
        .onAppear { locationService.requestPermission() }
        .sheet(item: $pendingPoint) { point in
            AddFeatureSheet(coordinate: point.coordinate, course: nil)
                .presentationDetents([.medium])
        }
        .toolbar(locationService.isTracking ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - Bottom controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            if locationService.isTracking {
                HStack(spacing: 10) {
                    SpeedPill(
                        speed: locationService.location?.speed,
                        serif: mapTheme == .explorer
                    )
                    QuickMarkButton(type: .passingLane) { quickMark(.passingLane) }
                    QuickMarkButton(type: .residentialZone) { quickMark(.residentialZone) }
                }
                HStack(spacing: 10) {
                    CornerQuickButton(chevrons: 1, label: "Mild") {
                        quickMark(.tightCorner, severity: 1)
                    }
                    CornerQuickButton(chevrons: 2, label: "Tight") {
                        quickMark(.tightCorner, severity: 2)
                    }
                    CornerQuickButton(chevrons: 3, label: "Hairpin") {
                        quickMark(.tightCorner, severity: 3)
                    }
                }
                Button {
                    endDrive()
                } label: {
                    Text("End Drive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                HStack(spacing: 12) {
                    if !routes.isEmpty {
                        routeMenu
                    }
                    Spacer()
                    Menu {
                        Picker("Map style", selection: $mapThemeRaw) {
                            ForEach(MapTheme.allCases) { theme in
                                Label(theme.label, systemImage: theme.systemImage)
                                    .tag(theme.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: mapTheme.systemImage)
                            .padding(6)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        recenterToken += 1
                    } label: {
                        Image(systemName: "location.fill")
                            .padding(6)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        startDrive()
                    } label: {
                        Label("Start Drive", systemImage: "flag.checkered")
                            .font(.headline)
                            .fixedSize()
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var routeMenu: some View {
        Menu {
            ForEach(routes) { route in
                Button {
                    activeRoute = route
                } label: {
                    if route == activeRoute {
                        Label(route.name, systemImage: "checkmark")
                    } else {
                        Text(route.name)
                    }
                }
            }
            if activeRoute != nil {
                Divider()
                Button("No route", role: .destructive) { activeRoute = nil }
            }
        } label: {
            Label(
                activeRoute?.name ?? "No route",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: activeRoute == nil ? nil : 130, alignment: .leading)
        }
        .disabled(routes.isEmpty)
    }

    // MARK: - Actions

    private func quickMark(_ type: RoadFeatureType, severity: Int = 2) {
        guard let location = locationService.location else { return }
        let feature = RoadFeature(
            type: type,
            coordinate: location.coordinate,
            bearing: location.course >= 0 ? location.course : nil,
            severity: severity
        )
        // Inserts and suppresses via the shared services so the CarPlay
        // scene and the live alert snapshot stay in sync.
        AppServices.shared.addFeature(feature)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        alertEngine.speech.say("Marked \(feature.spokenName.lowercased())")
    }

    private func startDrive() {
        AppServices.shared.startDrive()
    }

    private func endDrive() {
        AppServices.shared.endDrive()
    }
}

struct PendingPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Components

struct QuickMarkButton: View {
    let type: RoadFeatureType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.systemImage)
                    .font(.title2)
                Text(type.shortLabel)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(type.tint)
    }
}

struct CornerQuickButton: View {
    let chevrons: Int
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: -3) {
                    ForEach(0..<chevrons, id: \.self) { _ in
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.title3.bold())
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }
}

struct SpeedPill: View {
    let speed: CLLocationSpeed?
    var serif = false

    var body: some View {
        VStack(spacing: 0) {
            Text(speedText)
                .font(.system(size: 30, weight: .bold, design: serif ? .serif : .rounded))
                .monospacedDigit()
            Text("km/h")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64, minHeight: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var speedText: String {
        guard let speed, speed >= 0 else { return "--" }
        return String(Int(speed * 3.6))
    }
}

struct CalloutBanner: View {
    let item: UpcomingFeature
    var serif = false

    private var titleFont: Font {
        .system(.title3, design: serif ? .serif : .default).bold()
    }

    var body: some View {
        HStack(spacing: 14) {
            if item.feature.type == .tightCorner {
                HStack(spacing: -6) {
                    ForEach(0..<item.feature.chevronCount, id: \.self) { _ in
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.title.bold())
                .foregroundStyle(item.feature.type.tint)
            } else {
                Image(systemName: serif ? item.feature.type.explorerSymbol : item.feature.type.systemImage)
                    .font(.title)
                    .foregroundStyle(item.feature.type.tint)
            }
            Text(item.feature.displayLabel)
                .font(titleFont)
            Spacer()
            Text("\(Int(item.distance)) m")
                .font(titleFont)
                .monospacedDigit()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
