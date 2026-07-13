import CoreLocation
import SwiftData
import SwiftUI

struct RoutesTab: View {
    @Binding var activeRoute: Route?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Query private var features: [RoadFeature]
    @State private var showingPlanner = false
    @State private var isScanning = false
    @State private var scanMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(routes) { route in
                    HStack {
                        Button {
                            activeRoute = route == activeRoute ? nil : route
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                        .font(.headline)
                                    Text("\(route.formattedDistance) · \(route.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if route == activeRoute {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        ShareLink(
                            item: RouteExport(route: route, features: features),
                            preview: SharePreview(route.name)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button {
                            detectFeatures(on: route)
                        } label: {
                            Label("Detect Features", systemImage: "wand.and.stars")
                        }
                        .disabled(isScanning)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Plan a route by tapping waypoints on the map, or open a .rallybuddy file shared with you.")
                    )
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                Button("Plan Route", systemImage: "plus") {
                    showingPlanner = true
                }
            }
            .fullScreenCover(isPresented: $showingPlanner) {
                RoutePlannerView()
            }
            .overlay {
                if isScanning {
                    ProgressView("Scanning route…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(
                "Feature scan",
                isPresented: Binding(
                    get: { scanMessage != nil },
                    set: { if !$0 { scanMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanMessage ?? "")
            }
        }
    }

    /// Runs the detector over a route and inserts new findings as
    /// suggested features (long-press a route to trigger).
    private func detectFeatures(on route: Route) {
        isScanning = true
        let path = route.path
        let maneuvers = route.maneuvers
        Task {
            let result = await FeatureDetector.scan(path: path, maneuvers: maneuvers)
            var added: [RoadFeatureType: Int] = [:]
            for detected in result.features {
                let location = CLLocation(
                    latitude: detected.latitude,
                    longitude: detected.longitude
                )
                let isDuplicate = features.contains { existing in
                    existing.type == detected.type
                        && CLLocation(
                            latitude: existing.latitude,
                            longitude: existing.longitude
                        ).distance(from: location) < 60
                }
                guard !isDuplicate else { continue }
                modelContext.insert(
                    RoadFeature(
                        type: detected.type,
                        coordinate: detected.coordinate,
                        bearing: detected.bearing,
                        note: detected.note,
                        isSuggested: true
                    )
                )
                added[detected.type, default: 0] += 1
            }
            var lines = RoadFeatureType.allCases.compactMap { type -> String? in
                guard let count = added[type], count > 0 else { return nil }
                return "\(count) \(type.label.lowercased())\(count == 1 ? "" : "s")"
            }
            if lines.isEmpty { lines = ["Nothing new found"] }
            var message = "Added as suggestions: " + lines.joined(separator: ", ")
            if !result.osmReachable {
                message += "\n\nOpenStreetMap was unreachable — only corners were detected."
            }
            scanMessage = message
            isScanning = false
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if routes[index] == activeRoute {
                activeRoute = nil
            }
            modelContext.delete(routes[index])
        }
    }
}
