import CoreLocation
import SwiftData
import SwiftUI

struct RoutesTab: View {
    private var services = AppServices.shared
    private var activeRoute: Route? { services.activeRoute }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Query private var features: [RoadFeature]
    @State private var showingPlanner = false
    @State private var showingGenerator = false
    @State private var isScanning = false
    @State private var scanMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(routes) { route in
                    HStack {
                        Button {
                            services.activeRoute = route == activeRoute ? nil : route
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
                    .swipeActions(edge: .leading) {
                        Button {
                            detectFeatures(on: route)
                        } label: {
                            Label("Detect", systemImage: "wand.and.stars")
                        }
                        .tint(.purple)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Plan a route by tapping waypoints on the map, auto-generate a loop drive, or open a .rallybuddy file shared with you.")
                    )
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                Menu("Add Route", systemImage: "plus") {
                    Button("Plan Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        showingPlanner = true
                    }
                    Button("Generate Loop", systemImage: "sparkles") {
                        showingGenerator = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingPlanner) {
                RoutePlannerView()
            }
            .fullScreenCover(isPresented: $showingGenerator) {
                RouteGeneratorView()
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
    /// suggested features (also runs automatically when a route is saved).
    private func detectFeatures(on route: Route) {
        isScanning = true
        let path = route.path
        let maneuvers = route.maneuvers
        Task {
            scanMessage = await FeatureDetector.scanAndInsert(
                path: path,
                maneuvers: maneuvers,
                existingFeatures: features,
                context: modelContext
            )
            isScanning = false
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if routes[index] == activeRoute {
                services.activeRoute = nil
            }
            modelContext.delete(routes[index])
        }
    }
}
