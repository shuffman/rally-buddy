import CoreLocation
import Foundation

/// Generates candidate loop drives from a start point and target distance.
///
/// Strategy: fetch mid-class roads + traffic signals around the start from
/// OpenStreetMap (Overpass), score ways for "fun" (curvy, paved, quiet),
/// place loop waypoints on high-scoring roads, connect them with
/// MKDirections via RouteBuilder (drivability + guidance for free), then
/// score the actual resulting polylines and return the best few.
enum RouteGenerator {
    // Tuning knobs (untested-on-real-roads guesses, like FeatureDetector's).
    /// Real loops are longer than the circle through their waypoints.
    static let detourFactor: Double = 1.25
    /// Loop headings attempted (diversity of candidates).
    static let headingAttempts = 6
    /// Hard cap on MKDirections legs per generation (throttle protection).
    static let legBudget = 28
    /// Pacing between MKDirections requests.
    static let interLegDelay: Duration = .milliseconds(800)
    /// Acceptable relative error vs the target distance.
    static let distanceTolerance = 0.25
    /// Ways shorter than this can't anchor a waypoint.
    static let minWayLength: Double = 400
    /// Deterministic per-heading jitter so loops don't all align to a grid.
    static let headingJitter: [Double] = [8, -12, 4, -6, 14, -9]

    // MARK: - Public types

    struct Stats {
        let distanceMeters: Double
        let expectedTravelTime: TimeInterval
        let turnDegreesPerKm: Double
        let cornerCount: Int
        let signalCount: Int
        /// Weighted fraction of the path on scored (fun, paved) roads.
        let goodRoadFraction: Double
        /// Fraction of the path that retraces itself.
        let doubleBackFraction: Double
    }

    struct Candidate: Identifiable {
        let id: Int
        let waypoints: [CLLocationCoordinate2D]
        let path: RouteBuilder.PlannedPath
        let stats: Stats
        let score: Double
    }

    enum Phase: Equatable {
        case fetchingRoads
        case planning(candidate: Int, of: Int)
        case refining(candidate: Int)
        case scoring
    }

    enum GenerationError: LocalizedError {
        case overpassUnavailable
        case noRoadsNearby
        case noCandidates

        var errorDescription: String? {
            switch self {
            case .overpassUnavailable:
                return "OpenStreetMap is unreachable — loop generation needs it. Try again online."
            case .noRoadsNearby:
                return "No suitable roads found around that start point."
            case .noCandidates:
                return "Couldn't build a loop of that length here — try a different distance or start point."
            }
        }
    }

    // MARK: - Entry point

    static func generate(
        from start: CLLocationCoordinate2D,
        targetMeters: Double,
        progress: @escaping @MainActor (Phase) -> Void
    ) async throws -> [Candidate] {
        let radius = targetMeters / (2 * .pi * detourFactor)

        await progress(.fetchingRoads)
        let network = try await fetchRoadNetwork(around: start, halfWidth: 1.6 * radius)
        let signalGrid = PointGrid(origin: start, cellSize: 1000)
        for (i, signal) in network.signals.enumerated() {
            signalGrid.insert(signal, payload: i)
        }
        let ways = network.ways.compactMap {
            scoreWay(tags: $0.tags, coordinates: $0.coordinates, signals: signalGrid)
        }
        guard !ways.isEmpty else { throw GenerationError.noRoadsNearby }
        let wayGrid = PointGrid(origin: start, cellSize: 2000)
        for (wayIndex, way) in ways.enumerated() {
            for sample in way.samples {
                wayGrid.insert(sample, payload: wayIndex)
            }
        }

        // Place loops for each heading; failures are free (no network spent).
        struct Attempt {
            let heading: Double
            let clockwise: Bool
            var waypoints: [CLLocationCoordinate2D]
        }
        var attempts: [Attempt] = []
        for k in 0..<headingAttempts {
            let heading = Double(k) * (360 / Double(headingAttempts)) + headingJitter[k % headingJitter.count]
            let clockwise = k.isMultiple(of: 2)
            if let waypoints = placeLoop(
                start: start, radius: radius, headingDegrees: heading,
                clockwise: clockwise, ways: ways, grid: wayGrid
            ) {
                attempts.append(Attempt(heading: heading, clockwise: clockwise, waypoints: waypoints))
            }
        }
        guard !attempts.isEmpty else { throw GenerationError.noCandidates }

        // Plan each surviving attempt, serialized and budgeted.
        let cache = RouteBuilder.LegCache()
        var legsUsed = 0
        var kept: [(waypoints: [CLLocationCoordinate2D], path: RouteBuilder.PlannedPath)] = []
        var resizable: [(attempt: Attempt, actualMeters: Double)] = []

        func planAttempt(_ attempt: Attempt) async throws -> RouteBuilder.PlannedPath? {
            legsUsed += attempt.waypoints.count - 1
            do {
                let path = try await RouteBuilder.plan(
                    through: attempt.waypoints,
                    interLegDelay: interLegDelay,
                    legCache: cache
                )
                return path.coordinates.isEmpty ? nil : path
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return nil  // this candidate dies; others continue
            }
        }

        for (i, attempt) in attempts.enumerated() {
            guard legsUsed + (attempt.waypoints.count - 1) <= legBudget else { break }
            await progress(.planning(candidate: i + 1, of: attempts.count))
            guard let path = try await planAttempt(attempt) else { continue }
            try Task.checkCancellation()
            let error = abs(path.distanceMeters - targetMeters) / targetMeters
            if error <= distanceTolerance {
                kept.append((attempt.waypoints, path))
            } else {
                resizable.append((attempt, path.distanceMeters))
            }
        }

        // Refinement: rescale the closest miss and try once more.
        resizable.sort {
            abs($0.actualMeters - targetMeters) < abs($1.actualMeters - targetMeters)
        }
        var refined = 0
        while kept.count < 3, let miss = resizable.first, legsUsed + 4 <= legBudget {
            resizable.removeFirst()
            refined += 1
            await progress(.refining(candidate: refined))
            let scale = (targetMeters / miss.actualMeters)
            let newRadius = min(max(radius * scale, 0.6 * radius), 1.6 * radius)
            guard
                let waypoints = placeLoop(
                    start: start, radius: newRadius,
                    headingDegrees: miss.attempt.heading,
                    clockwise: miss.attempt.clockwise,
                    ways: ways, grid: wayGrid
                ),
                let path = try await planAttempt(
                    Attempt(
                        heading: miss.attempt.heading,
                        clockwise: miss.attempt.clockwise,
                        waypoints: waypoints
                    )
                )
            else { continue }
            try Task.checkCancellation()
            let error = abs(path.distanceMeters - targetMeters) / targetMeters
            if error <= distanceTolerance {
                kept.append((waypoints, path))
            }
        }
        guard !kept.isEmpty else { throw GenerationError.noCandidates }

        await progress(.scoring)
        var candidates = kept.enumerated().map { index, item in
            score(
                id: index, waypoints: item.waypoints, path: item.path,
                targetMeters: targetMeters, ways: ways,
                wayGrid: wayGrid, signalGrid: signalGrid
            )
        }
        candidates.sort { $0.score > $1.score }
        return dropDuplicates(candidates).prefix(3).map { $0 }
    }

    // MARK: - Overpass

    struct OSMRoad {
        let tags: [String: String]
        let coordinates: [CLLocationCoordinate2D]
    }

    struct RoadNetwork {
        let ways: [OSMRoad]
        let signals: [CLLocationCoordinate2D]
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
            let lat: Double?
            let lon: Double?
        }
        let elements: [Element]
    }

    /// Explicitly-unpaved surfaces, excluded server-side.
    static let unpavedRegex =
        "^(unpaved|gravel|fine_gravel|dirt|ground|grass|sand|compacted|earth|mud|pebblestone|rock)$"

    static func fetchRoadNetwork(
        around start: CLLocationCoordinate2D,
        halfWidth: Double
    ) async throws -> RoadNetwork {
        guard let box = FeatureDetector.boundingBox(of: [start], paddingMeters: halfWidth)
        else { throw GenerationError.noRoadsNearby }
        // Big targets fetch a huge area; keep the payload sane by dropping
        // the (dense) unclassified network beyond a 60 km box side.
        let reduced = halfWidth > 30_000
        do {
            return try await fetchRoadNetwork(in: box, midClassOnly: reduced)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // One retry with the smaller query before giving up.
            do {
                return try await fetchRoadNetwork(in: box, midClassOnly: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw GenerationError.overpassUnavailable
            }
        }
    }

    private static func fetchRoadNetwork(
        in box: (south: Double, west: Double, north: Double, east: Double),
        midClassOnly: Bool
    ) async throws -> RoadNetwork {
        let bbox = String(
            format: "%.5f,%.5f,%.5f,%.5f", box.south, box.west, box.north, box.east
        )
        let classes = midClassOnly ? "secondary|tertiary" : "secondary|tertiary|unclassified"
        let query = """
        [out:json][timeout:60][maxsize:268435456];
        (
          way["highway"~"^(\(classes))$"]["surface"!~"\(unpavedRegex)"]["tracktype"!~"^grade[2-5]$"]["access"!~"^(private|no)$"](\(bbox));
          node["highway"="traffic_signals"](\(bbox));
        );
        out geom 15000;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        // overpass-api.de rejects requests without a descriptive User-Agent.
        request.setValue("RallyBuddy/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = "data=\(encoded)".data(using: .utf8)
        request.timeoutInterval = 70

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
        var ways: [OSMRoad] = []
        var signals: [CLLocationCoordinate2D] = []
        for element in decoded.elements {
            if element.type == "way", let geometry = element.geometry, geometry.count >= 2 {
                ways.append(
                    OSMRoad(
                        tags: element.tags ?? [:],
                        coordinates: geometry.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                        }
                    )
                )
            } else if element.type == "node", element.tags?["highway"] == "traffic_signals",
                let lat = element.lat, let lon = element.lon
            {
                signals.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        return RoadNetwork(ways: ways, signals: signals)
    }

    // MARK: - Spatial index

    /// Hash grid over points in a local planar projection. Reference type
    /// so building it is simple; treated as immutable after setup.
    final class PointGrid {
        struct Entry {
            let coordinate: CLLocationCoordinate2D
            let x: Double
            let y: Double
            let payload: Int
        }
        private struct Key: Hashable {
            let cx: Int
            let cy: Int
        }

        let projection: FeatureDetector.LocalProjection
        let cellSize: Double
        private var cells: [Key: [Entry]] = [:]

        init(origin: CLLocationCoordinate2D, cellSize: Double) {
            projection = FeatureDetector.LocalProjection(origin: origin)
            self.cellSize = cellSize
        }

        func insert(_ coordinate: CLLocationCoordinate2D, payload: Int) {
            let p = projection.project(coordinate)
            let key = Key(cx: Int((p.x / cellSize).rounded(.down)),
                          cy: Int((p.y / cellSize).rounded(.down)))
            cells[key, default: []].append(
                Entry(coordinate: coordinate, x: p.x, y: p.y, payload: payload)
            )
        }

        /// All entries within `radius` meters of `coordinate`, with distances.
        func neighbors(
            of coordinate: CLLocationCoordinate2D, within radius: Double
        ) -> [(entry: Entry, distance: Double)] {
            let p = projection.project(coordinate)
            let minCx = Int(((p.x - radius) / cellSize).rounded(.down))
            let maxCx = Int(((p.x + radius) / cellSize).rounded(.down))
            let minCy = Int(((p.y - radius) / cellSize).rounded(.down))
            let maxCy = Int(((p.y + radius) / cellSize).rounded(.down))
            var found: [(entry: Entry, distance: Double)] = []
            for cx in minCx...maxCx {
                for cy in minCy...maxCy {
                    guard let entries = cells[Key(cx: cx, cy: cy)] else { continue }
                    for entry in entries {
                        let d = hypot(entry.x - p.x, entry.y - p.y)
                        if d <= radius { found.append((entry, d)) }
                    }
                }
            }
            return found
        }
    }

    // MARK: - Way scoring (pure)

    struct ScoredWay {
        let coordinates: [CLLocationCoordinate2D]
        /// Points along the way at 25 m spacing (reused for grid + matching).
        let samples: [CLLocationCoordinate2D]
        let lengthMeters: Double
        /// 0…1 desirability.
        let score: Double
    }

    static func scoreWay(
        tags: [String: String],
        coordinates: [CLLocationCoordinate2D],
        signals: PointGrid
    ) -> ScoredWay? {
        let samples = FeatureDetector.resample(coordinates, spacing: 25)
        guard samples.count >= 3 else { return nil }
        let lengthMeters = Double(samples.count - 1) * 25
        guard lengthMeters >= minWayLength else { return nil }

        var totalTurn: Double = 0
        for k in 0..<(samples.count - 2) {
            let h1 = FeatureDetector.bearing(samples[k], samples[k + 1])
            let h2 = FeatureDetector.bearing(samples[k + 1], samples[k + 2])
            totalTurn += FeatureDetector.angleDelta(h1, h2)
        }
        let curvatureNorm = min(totalTurn / (lengthMeters / 1000) / 150, 1)

        let classWeight: Double
        switch tags["highway"] {
        case "tertiary": classWeight = 1.0
        case "secondary": classWeight = 0.9
        default: classWeight = 0.8  // unclassified
        }
        // Untagged surface on minor roads is a small gamble; discount it.
        let surfaceWeight = (tags["highway"] == "unclassified" && tags["surface"] == nil) ? 0.85 : 1.0

        var signalIndices = Set<Int>()
        for sample in samples {
            for (entry, _) in signals.neighbors(of: sample, within: 60) {
                signalIndices.insert(entry.payload)
            }
        }
        let signalsPerKm = Double(signalIndices.count) / (lengthMeters / 1000)
        let signalPenalty = min(signalsPerKm / 2, 1)

        let score = classWeight * surfaceWeight
            * (0.35 + 0.65 * curvatureNorm)
            * (1 - 0.5 * signalPenalty)
        return ScoredWay(
            coordinates: coordinates, samples: samples,
            lengthMeters: lengthMeters, score: score
        )
    }

    // MARK: - Loop placement (pure)

    /// Offsets a coordinate by `meters` along a compass bearing, using the
    /// same planar approximation as LocalProjection (fine at ≤50 km).
    static func offset(
        _ coordinate: CLLocationCoordinate2D, bearingDegrees: Double, meters: Double
    ) -> CLLocationCoordinate2D {
        let rad = bearingDegrees * .pi / 180
        let dNorth = cos(rad) * meters
        let dEast = sin(rad) * meters
        let metersPerLon = 111_320 * max(cos(coordinate.latitude * .pi / 180), 0.05)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dNorth / 110_540,
            longitude: coordinate.longitude + dEast / metersPerLon
        )
    }

    /// Places loop waypoints on the best roads around a circle through the
    /// start. Returns [start, w1, w2, w3, start], or nil if any circle
    /// quadrant has no scoreable road (candidate dies before any
    /// MKDirections spend).
    static func placeLoop(
        start: CLLocationCoordinate2D,
        radius: Double,
        headingDegrees: Double,
        clockwise: Bool,
        ways: [ScoredWay],
        grid: PointGrid
    ) -> [CLLocationCoordinate2D]? {
        let center = offset(start, bearingDegrees: headingDegrees, meters: radius)
        // Bearing from the center back to the start; waypoints sit at
        // quarter-turns around the circle from there.
        let startAngle = headingDegrees + 180
        let searchRadius = min(0.35 * radius, 8000)

        var snapped: [CLLocationCoordinate2D] = []
        for quarter in [90.0, 180.0, 270.0] {
            let angle = startAngle + (clockwise ? quarter : -quarter)
            let ideal = offset(center, bearingDegrees: angle, meters: radius)
            let near = grid.neighbors(of: ideal, within: searchRadius)
            let best = near.max { a, b in
                let scoreA = ways[a.entry.payload].score / (1 + a.distance / 2000)
                let scoreB = ways[b.entry.payload].score / (1 + b.distance / 2000)
                return scoreA < scoreB
            }
            guard let best else { return nil }
            snapped.append(best.entry.coordinate)
        }

        // Degenerate-loop guard: waypoints collapsing onto the same spot
        // make MKDirections produce out-and-back spurs.
        let projection = FeatureDetector.LocalProjection(origin: start)
        let xy = snapped.map(projection.project)
        for i in 0..<xy.count {
            for j in (i + 1)..<xy.count {
                if hypot(xy[i].x - xy[j].x, xy[i].y - xy[j].y) < 0.3 * radius { return nil }
            }
        }
        return [start] + snapped + [start]
    }

    // MARK: - Candidate scoring (pure)

    static func score(
        id: Int,
        waypoints: [CLLocationCoordinate2D],
        path: RouteBuilder.PlannedPath,
        targetMeters: Double,
        ways: [ScoredWay],
        wayGrid: PointGrid,
        signalGrid: PointGrid
    ) -> Candidate {
        let fine = FeatureDetector.resample(path.coordinates, spacing: 20)
        let coarse = FeatureDetector.resample(path.coordinates, spacing: 100)
        let lengthKm = max(path.distanceMeters / 1000, 0.001)

        var totalTurn: Double = 0
        for k in 0..<max(fine.count - 2, 0) {
            let h1 = FeatureDetector.bearing(fine[k], fine[k + 1])
            let h2 = FeatureDetector.bearing(fine[k + 1], fine[k + 2])
            totalTurn += FeatureDetector.angleDelta(h1, h2)
        }
        let turnPerKm = totalTurn / lengthKm
        let curvNorm = min(turnPerKm / 120, 1)

        // Weighted time on scored roads: per coarse sample, the best score
        // of any fetched way within ~40 m (samples are 25 m apart on ways,
        // so this approximates "within 30 m of the way itself").
        var goodRoadSum: Double = 0
        for sample in coarse {
            let near = wayGrid.neighbors(of: sample, within: 40)
            goodRoadSum += near.map { ways[$0.entry.payload].score }.max() ?? 0
        }
        let goodRoadFraction = coarse.isEmpty ? 0 : goodRoadSum / Double(coarse.count)

        var signalIndices = Set<Int>()
        for sample in fine {
            for (entry, _) in signalGrid.neighbors(of: sample, within: 45) {
                signalIndices.insert(entry.payload)
            }
        }
        let signalCount = signalIndices.count
        let signalsPer10Km = Double(signalCount) / lengthKm * 10
        let signalTerm = 1 - min(signalsPer10Km / 5, 1)

        // Retraced-road detector: fine samples with a non-adjacent sample
        // (>10 indices ≈ >200 m along the path) within 25 m.
        let sampleGrid = PointGrid(
            origin: path.coordinates.first ?? waypoints[0], cellSize: 100
        )
        for (i, sample) in fine.enumerated() {
            sampleGrid.insert(sample, payload: i)
        }
        var doubledBack = 0
        for (i, sample) in fine.enumerated() {
            let overlapping = sampleGrid.neighbors(of: sample, within: 25)
                .contains { abs($0.entry.payload - i) > 10 }
            if overlapping { doubledBack += 1 }
        }
        let doubleBackFraction = fine.isEmpty ? 0 : Double(doubledBack) / Double(fine.count)

        let distErr = abs(path.distanceMeters - targetMeters) / targetMeters
        let distTerm = 1 - min(distErr / distanceTolerance, 1)

        let score = 0.35 * curvNorm
            + 0.30 * goodRoadFraction
            + 0.10 * signalTerm
            + 0.10 * distTerm
            - 0.15 * min(doubleBackFraction / 0.3, 1)

        let stats = Stats(
            distanceMeters: path.distanceMeters,
            expectedTravelTime: path.expectedTravelTime,
            turnDegreesPerKm: turnPerKm,
            cornerCount: FeatureDetector.detectCorners(
                in: path.coordinates, excluding: path.maneuvers
            ).count,
            signalCount: signalCount,
            goodRoadFraction: goodRoadFraction,
            doubleBackFraction: doubleBackFraction
        )
        return Candidate(
            id: id, waypoints: waypoints, path: path, stats: stats, score: score
        )
    }

    /// Drops candidates that mostly retrace a higher-scored one.
    static func dropDuplicates(_ sorted: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        var keptSamples: [[CLLocationCoordinate2D]] = []
        for candidate in sorted {
            let samples = FeatureDetector.resample(candidate.path.coordinates, spacing: 100)
            guard !samples.isEmpty else { continue }
            let isDuplicate = keptSamples.contains { other in
                let grid = PointGrid(origin: samples[0], cellSize: 200)
                for (i, sample) in other.enumerated() {
                    grid.insert(sample, payload: i)
                }
                let overlapping = samples.filter {
                    !grid.neighbors(of: $0, within: 50).isEmpty
                }
                return Double(overlapping.count) / Double(samples.count) > 0.6
            }
            if !isDuplicate {
                kept.append(candidate)
                keptSamples.append(samples)
            }
        }
        return kept
    }
}
