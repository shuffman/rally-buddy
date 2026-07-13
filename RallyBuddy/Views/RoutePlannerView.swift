import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Plan a route ahead of time: tap waypoints on the map and MKDirections
/// snaps the path to public roads after each tap.
struct RoutePlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var waypoints: [CLLocationCoordinate2D] = []
    @State private var plannedPath: [CLLocationCoordinate2D] = []
    @State private var distanceMeters: Double = 0
    @State private var isPlanning = false
    @State private var planningError: String?
    @State private var showingSavePrompt = false
    @State private var routeName = ""
    @State private var planTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map {
                    UserAnnotation()
                    if !plannedPath.isEmpty {
                        MapPolyline(coordinates: plannedPath)
                            .stroke(
                                .blue.opacity(0.7),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                    }
                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, coordinate in
                        Marker("\(index + 1)", coordinate: coordinate)
                            .tint(.blue)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        addWaypoint(coordinate)
                    }
                }
            }
            .navigationTitle("Plan Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        undoWaypoint()
                    }
                    .disabled(waypoints.isEmpty)
                    Button("Save") { showingSavePrompt = true }
                        .disabled(waypoints.count < 2 || isPlanning || plannedPath.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { statusBar }
            .alert("Name this route", isPresented: $showingSavePrompt) {
                TextField("Route name", text: $routeName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if isPlanning {
                ProgressView()
                Text("Finding roads…")
                    .foregroundStyle(.secondary)
            } else if let planningError {
                Label(planningError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else if waypoints.isEmpty {
                Text("Tap the map to add waypoints")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(waypoints.count) waypoints")
                Spacer()
                Text(String(format: "%.1f km", distanceMeters / 1000))
                    .bold()
                    .monospacedDigit()
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        waypoints.append(coordinate)
        replan()
    }

    private func undoWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        replan()
    }

    private func replan() {
        planTask?.cancel()
        planningError = nil
        guard waypoints.count >= 2 else {
            plannedPath = []
            distanceMeters = 0
            isPlanning = false
            return
        }
        isPlanning = true
        let snapshot = waypoints
        planTask = Task {
            do {
                let planned = try await RouteBuilder.plan(through: snapshot)
                guard !Task.isCancelled else { return }
                plannedPath = planned.coordinates
                distanceMeters = planned.distanceMeters
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                planningError = "No drivable road found for that leg"
            }
            isPlanning = false
        }
    }

    private func save() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        let route = Route(
            name: name.isEmpty
                ? "Route \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                : name,
            waypoints: waypoints,
            path: plannedPath,
            distanceMeters: distanceMeters
        )
        modelContext.insert(route)
        dismiss()
    }
}
