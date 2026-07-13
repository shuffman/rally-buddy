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

    init(
        type: RoadFeatureType,
        coordinate: CLLocationCoordinate2D,
        bearing: Double? = nil,
        note: String = ""
    ) {
        self.type = type
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.bearing = bearing
        self.note = note
        self.createdAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
