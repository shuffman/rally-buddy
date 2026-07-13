import CoreLocation
import MapKit
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

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pendingPoint: PendingPoint?

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                if let activeRoute {
                    MapPolyline(coordinates: activeRoute.path)
                        .stroke(
                            .blue.opacity(0.7),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                }
                ForEach(features) { feature in
                    Marker(
                        feature.type.label,
                        systemImage: feature.type.systemImage,
                        coordinate: feature.coordinate
                    )
                    .tint(feature.type.tint)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onTapGesture(coordinateSpace: .local) { point in
                // Map-tap annotation is a parked-car activity; while driving,
                // marking happens through the big buttons only.
                guard !locationService.isTracking else { return }
                if let coordinate = proxy.convert(point, from: .local) {
                    pendingPoint = PendingPoint(coordinate: coordinate)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .overlay(alignment: .top) {
            if let next = alertEngine.upcoming.first {
                CalloutBanner(item: next)
            }
        }
        .onAppear { locationService.requestPermission() }
        .onChange(of: locationService.location) { _, newLocation in
            guard let newLocation, locationService.isTracking else { return }
            alertEngine.update(location: newLocation, features: features)
        }
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
                    SpeedPill(speed: locationService.location?.speed)
                    ForEach(RoadFeatureType.allCases) { type in
                        QuickMarkButton(type: type) { quickMark(type) }
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
                    routeMenu
                    Spacer()
                    Button {
                        startDrive()
                    } label: {
                        Label("Start Drive", systemImage: "flag.checkered")
                            .font(.headline)
                            .padding(.horizontal, 8)
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
        }
        .disabled(routes.isEmpty)
    }

    // MARK: - Actions

    private func quickMark(_ type: RoadFeatureType) {
        guard let location = locationService.location else { return }
        let feature = RoadFeature(
            type: type,
            coordinate: location.coordinate,
            bearing: location.course >= 0 ? location.course : nil
        )
        modelContext.insert(feature)
        // Don't call out the feature the driver just marked themselves.
        alertEngine.suppress(feature)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        alertEngine.speech.say("Marked \(type.spokenName.lowercased())")
    }

    private func startDrive() {
        position = .userLocation(followsHeading: true, fallback: .automatic)
        locationService.startTracking()
    }

    private func endDrive() {
        locationService.stopTracking()
        alertEngine.reset()
        position = .userLocation(fallback: .automatic)
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

struct SpeedPill: View {
    let speed: CLLocationSpeed?

    var body: some View {
        VStack(spacing: 0) {
            Text(speedText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.feature.type.systemImage)
                .font(.title)
                .foregroundStyle(item.feature.type.tint)
            Text(item.feature.type.label)
                .font(.title3.bold())
            Spacer()
            Text("\(Int(item.distance)) m")
                .font(.title3.bold())
                .monospacedDigit()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
