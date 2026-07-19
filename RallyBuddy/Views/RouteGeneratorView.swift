import CoreLocation
import SwiftData
import SwiftUI

/// Auto-generate loop drives: pick a start and a distance, and the
/// generator proposes up to three loops built from OpenStreetMap data
/// (curvy, paved, quiet roads), road-snapped via MKDirections. The user
/// picks one to save as a normal Route.
struct RouteGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingFeatures: [RoadFeature]
    @AppStorage("mapTheme") private var mapThemeRaw = MapTheme.standard.rawValue

    enum Stage {
        case setup
        case generating(RouteGenerator.Phase)
        case results([RouteGenerator.Candidate], selected: Int)
        case failed(String)
    }

    @State private var stage: Stage = .setup
    @State private var startPoint: CLLocationCoordinate2D?
    @State private var targetKm: Double = 60
    @State private var generateTask: Task<Void, Never>?
    @State private var showingSavePrompt = false
    @State private var routeName = ""

    private var theme: MapTheme { MapTheme(rawValue: mapThemeRaw) ?? .standard }

    /// Card colors matching MapLibreView's overlay palettes.
    private var cardColors: [Color] {
        theme == .explorer
            ? [Color(red: 0.35, green: 0.23, blue: 0.10),
               Color(red: 0.55, green: 0.15, blue: 0.12),
               Color(red: 0.18, green: 0.32, blue: 0.16)]
            : [.blue, .orange, .purple]
    }

    var body: some View {
        NavigationStack {
            MapLibreView(
                markers: startMarkers,
                overlays: candidateOverlays,
                theme: theme,
                fitPathOnChange: true,
                onTap: { coordinate in
                    if case .setup = stage { startPoint = coordinate }
                }
            )
            .navigationTitle("Generate Loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        generateTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { showingSavePrompt = true }
                        .disabled(selectedCandidate == nil)
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .alert("Name this route", isPresented: $showingSavePrompt) {
                TextField("Route name", text: $routeName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if startPoint == nil {
                    startPoint = AppServices.shared.locationService.location?.coordinate
                }
            }
            .onDisappear { generateTask?.cancel() }
        }
    }

    private var startMarkers: [MapMarker] {
        guard let startPoint else { return [] }
        return [MapMarker(id: "loop-start", coordinate: startPoint, kind: .waypoint(1))]
    }

    private var candidateOverlays: [PathOverlay] {
        guard case .results(let candidates, let selected) = stage else { return [] }
        return candidates.enumerated().map { index, candidate in
            PathOverlay(
                id: "candidate-\(candidate.id)",
                coordinates: candidate.path.coordinates,
                colorIndex: index,
                emphasized: index == selected
            )
        }
    }

    private var selectedCandidate: RouteGenerator.Candidate? {
        guard case .results(let candidates, let selected) = stage,
            candidates.indices.contains(selected)
        else { return nil }
        return candidates[selected]
    }

    // MARK: - Bottom controls

    @ViewBuilder
    private var controls: some View {
        switch stage {
        case .setup:
            setupControls
        case .generating(let phase):
            generatingControls(phase)
        case .results(let candidates, let selected):
            resultControls(candidates, selected: selected)
        case .failed(let message):
            failedControls(message)
        }
    }

    private var setupControls: some View {
        VStack(spacing: 12) {
            Text(
                startPoint == nil
                    ? "Tap the map to choose a start point"
                    : "Loop starts at the marker — tap the map to move it"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack {
                Slider(value: $targetKm, in: 20...200, step: 5)
                Text("\(Int(targetKm)) km")
                    .bold()
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            Button {
                generate()
            } label: {
                Label("Generate", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(startPoint == nil)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func generatingControls(_ phase: RouteGenerator.Phase) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(phaseText(phase))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                generateTask?.cancel()
                stage = .setup
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func phaseText(_ phase: RouteGenerator.Phase) -> String {
        switch phase {
        case .fetchingRoads:
            return "Fetching roads from OpenStreetMap…"
        case .planning(let candidate, let of):
            return "Planning loop \(candidate) of \(of)…"
        case .refining:
            return "Adjusting loop size…"
        case .scoring:
            return "Scoring candidates…"
        }
    }

    private func resultControls(_ candidates: [RouteGenerator.Candidate], selected: Int) -> some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        candidateCard(candidate, color: cardColors[index % cardColors.count],
                                      isSelected: index == selected)
                            .onTapGesture {
                                stage = .results(candidates, selected: index)
                            }
                    }
                }
                .padding(.horizontal)
            }
            Button {
                stage = .setup
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func candidateCard(
        _ candidate: RouteGenerator.Candidate, color: Color, isSelected: Bool
    ) -> some View {
        let stats = candidate.stats
        let time = Duration.seconds(stats.expectedTravelTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(String(format: "%.0f km", stats.distanceMeters / 1000))
                    .bold()
                Text("· \(time)")
                    .foregroundStyle(.secondary)
            }
            Text("\(stats.cornerCount) corners · \(stats.signalCount) signals")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.opacity(isSelected ? 1 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
        )
    }

    private func failedControls(_ message: String) -> some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
            Button("Try Again") { stage = .setup }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    // MARK: - Actions

    private func generate() {
        guard let start = startPoint else { return }
        generateTask?.cancel()
        stage = .generating(.fetchingRoads)
        let target = targetKm * 1000
        generateTask = Task {
            do {
                let candidates = try await RouteGenerator.generate(
                    from: start, targetMeters: target
                ) { phase in
                    // A progress call can land just after Cancel resets the
                    // stage; only update while still generating.
                    if case .generating = stage { stage = .generating(phase) }
                }
                guard !Task.isCancelled else { return }
                stage = .results(candidates, selected: 0)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                stage = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let candidate = selectedCandidate else { return }
        let name = routeName.trimmingCharacters(in: .whitespaces)
        let route = Route(
            name: name.isEmpty
                ? String(format: "Generated loop — %.0f km", candidate.stats.distanceMeters / 1000)
                : name,
            waypoints: candidate.waypoints,
            path: candidate.path.coordinates,
            distanceMeters: candidate.stats.distanceMeters,
            maneuvers: candidate.path.maneuvers,
            guidanceSteps: candidate.path.guidanceSteps
        )
        modelContext.insert(route)

        // Auto-detect features on the new route, same as the planner: the
        // detached task outlives this view.
        let path = candidate.path.coordinates
        let maneuvers = candidate.path.maneuvers
        let existing = existingFeatures
        let context = modelContext
        Task { @MainActor in
            _ = await FeatureDetector.scanAndInsert(
                path: path,
                maneuvers: maneuvers,
                existingFeatures: existing,
                context: context
            )
        }
        dismiss()
    }
}
