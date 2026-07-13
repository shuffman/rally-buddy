import CoreLocation
import Foundation

/// A feature found by scanning a route, before it becomes a RoadFeature.
struct DetectedFeature {
    let type: RoadFeatureType
    let latitude: Double
    let longitude: Double
    /// Direction of travel the feature applies to (nil = both).
    let bearing: Double?
    let note: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Scans a planned route for road features:
/// - Tight corners: pure geometry on the road-snapped path (offline).
/// - Residential zones & passing lanes: OpenStreetMap tags via the
///   Overpass API (online, best-effort — OSM lane tagging is patchy).
enum FeatureDetector {
    struct ScanResult {
        var features: [DetectedFeature] = []
        /// False when the Overpass query failed (offline etc.) — corners
        /// are still detected, zones/lanes are not.
        var osmReachable = true
    }

    // Tuning knobs (all meters/degrees; untested-on-real-roads guesses).
    static let cornerRadiusThreshold: Double = 110
    static let cornerMinTurnDegrees: Double = 40
    static let maneuverExclusionRadius: Double = 45
    static let sampleSpacing: Double = 15

    // MARK: - Entry point

    static func scan(
        path: [CLLocationCoordinate2D],
        maneuvers: [CLLocationCoordinate2D]
    ) async -> ScanResult {
        var result = ScanResult()
        result.features += detectCorners(in: path, excluding: maneuvers)

        guard let box = boundingBox(of: path, paddingMeters: 300) else { return result }
        do {
            let ways = try await fetchOSMWays(in: box)
            let samples = resample(path, spacing: 25)
            let residential = ways.filter { $0.tags["landuse"] == "residential" }
            if !residential.isEmpty {
                result.features += detectEntries(
                    along: samples,
                    type: .residentialZone,
                    note: "Auto: residential area (OpenStreetMap)"
                ) { point in
                    residential.contains { contains(polygon: $0.coordinates, point: point) }
                }
            }
            // Lane-tagged ways minus obvious false positives: urban turn
            // lanes and roads explicitly tagged no-overtaking.
            let laneWays = ways.filter { way in
                way.tags["landuse"] == nil
                    && way.tags["overtaking"] != "no"
                    && way.tags["junction"] != "roundabout"
                    && !way.tags.keys.contains { $0.hasPrefix("turn:lanes") }
            }
            if !laneWays.isEmpty {
                result.features += detectEntries(
                    along: samples,
                    type: .passingLane,
                    note: "Auto: extra lane tagged (OpenStreetMap)"
                ) { point in
                    laneWays.contains { isWithin(18, of: $0.coordinates, point: point) }
                }
            }
        } catch {
            result.osmReachable = false
        }
        return result
    }

    // MARK: - Corner detection

    static func detectCorners(
        in path: [CLLocationCoordinate2D],
        excluding maneuvers: [CLLocationCoordinate2D] = []
    ) -> [DetectedFeature] {
        let points = resample(path, spacing: sampleSpacing)
        guard points.count >= 5 else { return [] }

        let projection = LocalProjection(origin: points[0])
        let xy = points.map(projection.project)

        var radii = [Double](repeating: .infinity, count: points.count)
        for i in 1..<(points.count - 1) {
            radii[i] = circumradius(xy[i - 1], xy[i], xy[i + 1])
        }

        let maneuverLocations = maneuvers.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }

        var corners: [DetectedFeature] = []
        var lastCorner: CLLocation?
        var i = 1
        while i < points.count - 1 {
            guard radii[i] < cornerRadiusThreshold else {
                i += 1
                continue
            }
            // Extend the group, tolerating a single straighter sample.
            var j = i
            while j + 2 < points.count - 1,
                radii[j + 1] < cornerRadiusThreshold || radii[j + 2] < cornerRadiusThreshold
            {
                j += 1
            }

            // Accumulated turn across the group.
            var totalTurn: Double = 0
            for k in max(i - 1, 0)...min(j, points.count - 2) where k + 2 < points.count {
                let h1 = bearing(points[k], points[k + 1])
                let h2 = bearing(points[k + 1], points[k + 2])
                totalTurn += angleDelta(h1, h2)
            }

            let apexIndex = (i...j).min { radii[$0] < radii[$1] } ?? i
            let apex = points[apexIndex]
            let apexLocation = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
            let minRadius = radii[apexIndex]

            let nearManeuver = maneuverLocations.contains {
                $0.distance(from: apexLocation) < maneuverExclusionRadius
            }
            let nearPrevious = lastCorner.map { $0.distance(from: apexLocation) < 60 } ?? false

            if totalTurn >= cornerMinTurnDegrees, !nearManeuver, !nearPrevious {
                corners.append(
                    DetectedFeature(
                        type: .tightCorner,
                        latitude: apex.latitude,
                        longitude: apex.longitude,
                        bearing: nil,
                        note: "Auto: ~\(Int(minRadius)) m radius"
                    )
                )
                lastCorner = apexLocation
            }
            i = j + 2
        }
        return corners
    }

    /// Walks the sampled path and emits a feature each time it transitions
    /// from outside to inside the predicate region.
    private static func detectEntries(
        along samples: [CLLocationCoordinate2D],
        type: RoadFeatureType,
        note: String,
        isInside: (CLLocationCoordinate2D) -> Bool
    ) -> [DetectedFeature] {
        var features: [DetectedFeature] = []
        var wasInside = samples.first.map(isInside) ?? false
        for k in 1..<samples.count {
            let inside = isInside(samples[k])
            defer { wasInside = inside }
            guard inside, !wasInside else { continue }
            features.append(
                DetectedFeature(
                    type: type,
                    latitude: samples[k].latitude,
                    longitude: samples[k].longitude,
                    bearing: bearing(samples[k - 1], samples[k]),
                    note: note
                )
            )
        }
        return features
    }

    // MARK: - Overpass

    struct OSMWay {
        let tags: [String: String]
        let coordinates: [CLLocationCoordinate2D]
    }

    private struct OverpassResponse: Codable {
        struct Element: Codable {
            struct Point: Codable {
                let lat: Double
                let lon: Double
            }
            let type: String
            let tags: [String: String]?
            let geometry: [Point]?
        }
        let elements: [Element]
    }

    static func fetchOSMWays(
        in box: (south: Double, west: Double, north: Double, east: Double)
    ) async throws -> [OSMWay] {
        let bbox = String(
            format: "%.5f,%.5f,%.5f,%.5f", box.south, box.west, box.north, box.east
        )
        let query = """
        [out:json][timeout:25];
        (
          way["landuse"="residential"](\(bbox));
          way["highway"~"^(trunk|primary|secondary|tertiary)$"]["lanes:forward"~"^[2-9]"](\(bbox));
          way["highway"~"^(trunk|primary|secondary)$"]["lanes"~"^[3-9]"]["oneway"!="yes"](\(bbox));
        );
        out geom 3000;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        // overpass-api.de rejects requests without a descriptive User-Agent.
        request.setValue("RallyBuddy/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
        return decoded.elements.compactMap { element in
            guard element.type == "way", let geometry = element.geometry,
                geometry.count >= 2
            else { return nil }
            return OSMWay(
                tags: element.tags ?? [:],
                coordinates: geometry.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
            )
        }
    }

    // MARK: - Geometry helpers

    struct LocalProjection {
        let originLat: Double
        let originLon: Double
        let metersPerLon: Double

        init(origin: CLLocationCoordinate2D) {
            originLat = origin.latitude
            originLon = origin.longitude
            metersPerLon = 111_320 * max(cos(origin.latitude * .pi / 180), 0.05)
        }

        func project(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - originLon) * metersPerLon, (c.latitude - originLat) * 110_540)
        }
    }

    static func circumradius(
        _ p1: (x: Double, y: Double),
        _ p2: (x: Double, y: Double),
        _ p3: (x: Double, y: Double)
    ) -> Double {
        let a = hypot(p3.x - p2.x, p3.y - p2.y)
        let b = hypot(p3.x - p1.x, p3.y - p1.y)
        let c = hypot(p2.x - p1.x, p2.y - p1.y)
        let area = abs((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y)) / 2
        guard area > 0.01 else { return .infinity }
        return a * b * c / (4 * area)
    }

    static func resample(
        _ path: [CLLocationCoordinate2D],
        spacing: Double
    ) -> [CLLocationCoordinate2D] {
        guard path.count >= 2 else { return path }
        var points = [path[0]]
        var sinceLast = 0.0
        for k in 1..<path.count {
            let a = path[k - 1]
            let b = path[k]
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            guard d > 0 else { continue }
            var consumed = 0.0
            while sinceLast + (d - consumed) >= spacing {
                let need = spacing - sinceLast
                consumed += need
                let t = consumed / d
                points.append(
                    CLLocationCoordinate2D(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t
                    )
                )
                sinceLast = 0
            }
            sinceLast += d - consumed
        }
        return points
    }

    static func boundingBox(
        of path: [CLLocationCoordinate2D],
        paddingMeters: Double
    ) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard let first = path.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in path {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let dLat = paddingMeters / 110_540
        let midLat = (minLat + maxLat) / 2
        let dLon = paddingMeters / (111_320 * max(cos(midLat * .pi / 180), 0.05))
        return (minLat - dLat, minLon - dLon, maxLat + dLat, maxLon + dLon)
    }

    /// Ray-casting point-in-polygon.
    static func contains(polygon: [CLLocationCoordinate2D], point: CLLocationCoordinate2D) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let intersect = (b.longitude - a.longitude)
                    * (point.latitude - a.latitude)
                    / (b.latitude - a.latitude) + a.longitude
                if point.longitude < intersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Whether `point` lies within `meters` of any segment of `line`.
    static func isWithin(
        _ meters: Double,
        of line: [CLLocationCoordinate2D],
        point: CLLocationCoordinate2D
    ) -> Bool {
        guard line.count >= 2 else { return false }
        let projection = LocalProjection(origin: point)
        let p = projection.project(point)
        var prev = projection.project(line[0])
        for k in 1..<line.count {
            let cur = projection.project(line[k])
            let dx = cur.x - prev.x
            let dy = cur.y - prev.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0
                ? max(0, min(1, ((p.x - prev.x) * dx + (p.y - prev.y) * dy) / lengthSquared))
                : 0
            let nearest = (x: prev.x + t * dx, y: prev.y + t * dy)
            if hypot(p.x - nearest.x, p.y - nearest.y) <= meters { return true }
            prev = cur
        }
        return false
    }

    static func bearing(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
