import Foundation

/// Visual skin for the map. Standard is the full OpenFreeMap style;
/// Explorer is a stripped-down parchment style with old-map dressing.
enum MapTheme: String, CaseIterable, Identifiable {
    case standard
    case explorer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .explorer: "Explorer's Map"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .explorer: "scroll"
        }
    }

    var styleURL: URL {
        switch self {
        case .standard:
            OfflineMapManager.styleURL
        case .explorer:
            Bundle.main.url(forResource: "ParchmentStyle", withExtension: "json")
                ?? OfflineMapManager.styleURL
        }
    }
}
