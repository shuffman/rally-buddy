import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var locationService = LocationService()
    @State private var alertEngine = AlertEngine(speech: SpeechService())
    @State private var activeRoute: Route?
    @State private var importErrorMessage: String?
    @State private var showingImportError = false

    @Environment(\.modelContext) private var modelContext
    @Query private var allFeatures: [RoadFeature]

    var body: some View {
        TabView {
            DriveView(
                locationService: locationService,
                alertEngine: alertEngine,
                activeRoute: $activeRoute
            )
            .tabItem { Label("Drive", systemImage: "car.fill") }

            RoutesTab(activeRoute: $activeRoute)
                .tabItem {
                    Label(
                        "Routes",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }

            FeatureListTab()
                .tabItem { Label("Features", systemImage: "list.bullet") }
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
