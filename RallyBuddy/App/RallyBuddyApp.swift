import SwiftUI
import SwiftData

@main
struct RallyBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AppServices.shared.container)
    }
}
