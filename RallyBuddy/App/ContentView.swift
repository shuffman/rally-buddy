import SwiftData
import SwiftUI

struct ContentView: View {
    private let locationService = AppServices.shared.locationService
    private let alertEngine = AppServices.shared.alertEngine
    @State private var offlineManager = OfflineMapManager()
    @State private var importErrorMessage: String?
    @State private var showingImportError = false

    @Environment(\.modelContext) private var modelContext
    @Query private var allFeatures: [RoadFeature]

    var body: some View {
        TabView {
            DriveView(
                locationService: locationService,
                alertEngine: alertEngine
            )
            .tabItem { Label("Drive", systemImage: "car.fill") }

            RoutesTab()
                .tabItem {
                    Label(
                        "Routes",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

            FeatureListTab()
                .tabItem { Label("Features", systemImage: "list.bullet") }

            OfflineMapsTab(
                locationService: locationService,
                offlineManager: offlineManager
            )
            .tabItem { Label("Offline", systemImage: "arrow.down.circle") }
        }
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "rallybuddy" else { return }
            do {
                try RouteShareImporter.importRoute(
                    from: url,
                    into: modelContext,
                    existingFeatures: allFeatures
                )
            } catch {
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        }
        .task { await DemoSeeder.runIfRequested() }
        .alert("Couldn't import route", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "The file couldn't be read.")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [RoadFeature.self, Route.self], inMemory: true)
}
