import SwiftUI

struct ContentView: View {
    @State private var locationService = LocationService()
    @State private var alertEngine = AlertEngine(speech: SpeechService())

    var body: some View {
        TabView {
            DriveTab(locationService: locationService, alertEngine: alertEngine)
                .tabItem { Label("Drive", systemImage: "gauge.with.needle") }
            MapTab(locationService: locationService)
                .tabItem { Label("Map", systemImage: "map") }
            FeatureListTab()
                .tabItem { Label("Features", systemImage: "list.bullet") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: RoadFeature.self, inMemory: true)
}
