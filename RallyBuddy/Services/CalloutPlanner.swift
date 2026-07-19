import CoreLocation
import Foundation

/// Generates the AI co-driver script for a route: orders the user's
/// confirmed features along the path, sends the sequence to Claude once,
/// and returns phrased pace-note lines anchored to feature coordinates.
/// Runs at planning time only — drives replay the stored script offline.
@MainActor
enum CalloutPlanner {
    struct OrderedFeature {
        let feature: RoadFeature
        let distanceAlongRoute: CLLocationDistance
        var coordinate: CLLocationCoordinate2D { feature.coordinate }
    }

    /// Features farther than this from the path are not part of the route.
    static let corridorWidth: CLLocationDistance = 100
    /// Features whose own bearing points more than this many degrees away
    /// from the route's direction of travel at their location are skipped.
    private static let directionTolerance: Double = 90

    enum PlannerError: LocalizedError {
        case noFeatures
        case missingAPIKey
        case api(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noFeatures:
                "No confirmed features found along this route. Mark or detect features first."
            case .missingAPIKey:
                "Enter a Claude API key to generate the script."
            case .api(let message):
                message
            case .badResponse:
                "Claude returned an unexpected response. Try again."
            }
        }
    }

    // MARK: - Feature ordering

    /// Confirmed features within the route corridor, ordered by distance
    /// along the path. Suggested (unconfirmed) features are excluded.
    static func orderedFeatures(
        route: Route,
        features: [RoadFeature]
    ) -> [OrderedFeature] {
        let path = route.path
        guard path.count >= 2 else { return [] }
        let cumulative = NavigationEngine.cumulativeDistances(path)

        var results: [OrderedFeature] = []
        for feature in features where !feature.isSuggested {
            let index = NavigationEngine.nearestIndex(on: path, to: feature.coordinate)
            let nearest = path[index]
            let offPath = CLLocation(latitude: nearest.latitude, longitude: nearest.longitude)
                .distance(
                    from: CLLocation(
                        latitude: feature.latitude,
                        longitude: feature.longitude
                    )
                )
            guard offPath < corridorWidth else { continue }

            if let featureBearing = feature.bearing {
                let from = path[max(index - 1, 0)]
                let to = path[min(index + 1, path.count - 1)]
                let routeBearing = AlertEngine.bearing(from: from, to: to)
                guard
                    AlertEngine.angleDelta(featureBearing, routeBearing)
                        <= directionTolerance
                else { continue }
            }

            results.append(
                OrderedFeature(feature: feature, distanceAlongRoute: cumulative[index])
            )
        }
        return results.sorted { $0.distanceAlongRoute < $1.distanceAlongRoute }
    }

    // MARK: - Script generation

    static func generateScript(
        route: Route,
        features: [RoadFeature],
        apiKey: String
    ) async throws -> [PaceNote] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PlannerError.missingAPIKey }
        let ordered = orderedFeatures(route: route, features: features)
        guard !ordered.isEmpty else { throw PlannerError.noFeatures }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(route: route, ordered: ordered)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlannerError.badResponse
        }
        guard http.statusCode == 200 else {
            let error = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw PlannerError.api(
                error?.error.message ?? "Claude API request failed (HTTP \(http.statusCode))"
            )
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        if decoded.stop_reason == "refusal" {
            throw PlannerError.api("Claude declined to generate this script.")
        }
        if decoded.stop_reason == "max_tokens" {
            throw PlannerError.api("The script was cut off. Try a route with fewer features.")
        }
        guard
            let text = decoded.content.first(where: { $0.type == "text" })?.text,
            let payload = try? JSONDecoder().decode(
                ScriptPayload.self, from: Data(text.utf8)
            )
        else { throw PlannerError.badResponse }

        // Lines reference features by index; anchor each line to that
        // feature's coordinate and keep route order.
        var notes: [PaceNote] = []
        var seen: Set<Int> = []
        for line in payload.lines.sorted(by: { $0.index < $1.index }) {
            guard ordered.indices.contains(line.index), seen.insert(line.index).inserted
            else { continue }
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            notes.append(
                PaceNote(coordinate: ordered[line.index].coordinate, text: trimmed)
            )
        }
        guard !notes.isEmpty else { throw PlannerError.badResponse }
        return notes
    }

    // MARK: - Request assembly

    private static func requestBody(
        route: Route,
        ordered: [OrderedFeature]
    ) -> [String: Any] {
        let system = """
            You are a rally co-driver writing a pace-note script for a road \
            drive. You receive the ordered list of road features the driver \
            marked along a planned route, with distances along the route. \
            Write one spoken callout per feature.

            Rules:
            - Return one line per feature, referencing it by its index.
            - Each line is plain spoken language, at most 14 words, no \
            abbreviations, no coordinates.
            - Never state a numeric distance to the feature itself (the app \
            triggers each line a few hundred meters early); "ahead" or \
            "coming up" is fine.
            - When the gap to the next feature is under 400 meters, link the \
            phrasing so the callouts flow ("...then clear to pass", \
            "tightens into the hairpin").
            - Corners: severity 3 is a hairpin — demand urgency and say \
            "slow down"; severity 2 is tight; severity 1 is mild.
            - Residential zones: call for calm speed, watch for people.
            - Passing lanes: point out the overtaking opportunity.
            - Work the driver's own note into the callout when one is given.
            """

        var lines: [String] = [
            "Route: \(route.name), total distance \(route.formattedDistance).",
            "Features in route order:",
        ]
        for (index, item) in ordered.enumerated() {
            var parts: [String] = []
            let kmFromStart = item.distanceAlongRoute / 1000
            parts.append(String(format: "%.1f km from start", kmFromStart))
            if index + 1 < ordered.count {
                let gap = ordered[index + 1].distanceAlongRoute - item.distanceAlongRoute
                parts.append("gap to next: \(Int(gap)) m")
            } else {
                parts.append("last feature")
            }
            let note = item.feature.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                parts.append("driver note: \"\(note)\"")
            }
            let severity =
                item.feature.type == .tightCorner
                ? " (severity \(item.feature.chevronCount) of 3)" : ""
            lines.append(
                "\(index). \(item.feature.displayLabel)\(severity) — "
                    + parts.joined(separator: " — ")
            )
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "lines": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "index": [
                                "type": "integer",
                                "description": "The feature index this line belongs to",
                            ],
                            "text": [
                                "type": "string",
                                "description": "The spoken callout",
                            ],
                        ],
                        "required": ["index", "text"],
                        "additionalProperties": false,
                    ],
                ]
            ],
            "required": ["lines"],
            "additionalProperties": false,
        ]

        return [
            "model": "claude-opus-4-8",
            "max_tokens": 8192,
            "thinking": ["type": "adaptive"],
            "system": system,
            "messages": [
                ["role": "user", "content": lines.joined(separator: "\n")]
            ],
            "output_config": [
                "format": ["type": "json_schema", "schema": schema]
            ],
        ]
    }

    // MARK: - Wire types

    private struct ScriptPayload: Decodable {
        struct Line: Decodable {
            let index: Int
            let text: String
        }
        let lines: [Line]
    }

    private struct APIResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }
}
