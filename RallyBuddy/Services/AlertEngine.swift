import CoreLocation
import Foundation
import Observation
import SwiftData

struct UpcomingFeature: Identifiable {
    let feature: RoadFeature
    let distance: CLLocationDistance

    var id: PersistentIdentifier { feature.id }

    var announcement: String {
        let rounded = Int(max(50, (distance / 50).rounded() * 50))
        return "\(feature.type.spokenName) in \(rounded) meters"
    }
}

/// Watches the driver's position and decides which marked features are
/// coming up, announcing each one once per approach.
@Observable
final class AlertEngine {
    /// How far ahead (meters) to look for features.
    var lookaheadDistance: CLLocationDistance = 600
    /// A feature must lie within this many degrees of the direction of
    /// travel to count as "ahead".
    private let headingCone: Double = 50
    /// Tolerance when matching a feature's own direction of travel.
    private let directionTolerance: Double = 70

    private(set) var upcoming: [UpcomingFeature] = []

    private var announced: Set<PersistentIdentifier> = []
    let speech: SpeechService

    init(speech: SpeechService) {
        self.speech = speech
    }

    func update(location: CLLocation, features: [RoadFeature]) {
        let course = location.course
        var results: [UpcomingFeature] = []

        for feature in features {
            let featureLocation = CLLocation(
                latitude: feature.latitude,
                longitude: feature.longitude
            )
            let distance = location.distance(from: featureLocation)

            guard distance <= lookaheadDistance else {
                // Once well clear of a feature it becomes announceable again.
                if distance > lookaheadDistance * 1.5 {
                    announced.remove(feature.id)
                }
                continue
            }

            // course is negative when the device has no valid heading (e.g.
            // stationary); in that case skip the directional filtering.
            if course >= 0 {
                let bearingToFeature = Self.bearing(
                    from: location.coordinate,
                    to: feature.coordinate
                )
                guard Self.angleDelta(course, bearingToFeature) <= headingCone
                    || distance < 30
                else { continue }

                if let featureBearing = feature.bearing,
                    Self.angleDelta(course, featureBearing) > directionTolerance
                { continue }
            }

            results.append(UpcomingFeature(feature: feature, distance: distance))
        }

        results.sort { $0.distance < $1.distance }
        upcoming = results

        for item in results where !announced.contains(item.id) {
            announced.insert(item.id)
            speech.say(item.announcement)
        }
    }

    /// Prevents a feature from being announced on the current approach,
    /// e.g. one the driver just marked themselves.
    func suppress(_ feature: RoadFeature) {
        announced.insert(feature.id)
    }

    func reset() {
        upcoming = []
        announced = []
    }

    // MARK: - Geometry

    /// Initial great-circle bearing from one coordinate to another, in
    /// compass degrees [0, 360).
    static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Smallest angle between two compass headings, in degrees [0, 180].
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
