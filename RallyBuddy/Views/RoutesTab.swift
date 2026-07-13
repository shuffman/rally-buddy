import SwiftData
import SwiftUI

struct RoutesTab: View {
    @Binding var activeRoute: Route?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Query private var features: [RoadFeature]
    @State private var showingPlanner = false

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
