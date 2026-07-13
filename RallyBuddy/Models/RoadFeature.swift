import CoreLocation
import Foundation
import SwiftData
import SwiftUI

enum RoadFeatureType: String, Codable, CaseIterable, Identifiable {
    case passingLane
    case residentialZone
    case tightCorner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .passingLane: "Passing lane"
        case .residentialZone: "Residential zone"
        case .tightCorner: "Tight corner"
        }
    }

    /// Short label for the one-tap quick-mark buttons on the drive screen.
    var shortLabel: String {
        switch self {
        case .passingLane: "Pass"
        case .residentialZone: "Homes"
        case .tightCorner: "Corner"
        }
    }

    /// How the feature is named in spoken callouts.
    var spokenName: String {
        switch self {
        case .passingLane: "Passing lane"
        case .residentialZone: "Residential zone"
        case .tightCorner: "Tight corner"
        }
    }

    var systemImage: String {
        switch self {
        case .passingLane: "car.2"
        case .residentialZone: "house.fill"
        case .tightCorner: "arrow.turn.up.right"
        }
    }

    /// Marker glyph on the Explorer's Map skin — old-map flavored.
    var explorerSymbol: String {
        switch self {
        case .passingLane: "arrow.left.arrow.right"
        case .residentialZone: "house.fill"
        case .tightCorner: "lizard.fill"  // here be dragons
        }
    }

    var tint: Color {
        switch self {
        case .passingLane: .green
        case .residentialZone: .orange
        case .tightCorner: .red
        }
    }
}

@Model
final class RoadFeature {
    var type: RoadFeatureType
    var latitude: Double
    var longitude: Double
    /// Direction of travel (compass degrees) this feature applies to.
    /// nil means it applies in both directions.
    var bearing: Double?
    var note: String
    var createdAt: Date
    /// True for auto-detected features awaiting the user's confirmation.
    var isSuggested: Bool = false
    /// Corner severity in rally chevrons: 1 = mild, 2 = tight, 3 = hairpin.
    /// Only meaningful for .tightCorner.
    var severity: Int = 2

    init(
        type: RoadFeatureType,
        coordinate: CLLocationCoordinate2D,
        bearing: Double? = nil,
        note: String = "",
        isSuggested: Bool = false,
        severity: Int = 2
    ) {
        self.type = type
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.bearing = bearing
        self.note = note
        self.createdAt = .now
        self.isSuggested = isSuggested
        self.severity = severity
    }

    var chevronCount: Int { min(max(severity, 1), 3) }

    /// Severity-aware display name ("Corner ›" family for corners).
    var displayLabel: String {
        guard type == .tightCorner else { return type.label }
        switch chevronCount {
        case 3: return "Hairpin"
        case 2: return "Tight corner"
        default: return "Corner"
        }
    }

    /// Severity-aware name used in spoken callouts.
    var spokenName: String {
        guard type == .tightCorner else { return type.spokenName }
        switch chevronCount {
        case 3: return "Hairpin"
        case 2: return "Tight corner"
        default: return "Corner"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
