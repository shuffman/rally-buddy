import MapLibre
import SwiftData
import SwiftUI

struct OfflineMapsTab: View {
    var locationService: LocationService
    var offlineManager: OfflineMapManager

    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        downloadAroundMe()
                    } label: {
                        Label("Area around me (40 km)", systemImage: "location.circle")
                    }
                    .disabled(locationService.location == nil)

                    ForEach(routes) { route in
                        Button {
                            downloadRoute(route)
                        } label: {
                            Label(
                                "Route: \(route.name)",
                                systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                        }
                    }
                } header: {
                    Text("Download")
                } footer: {
                    Text("Downloads cover street detail up to close zoom. A 40 km area is roughly 30–60 MB. Map data © OpenStreetMap contributors, tiles by OpenFreeMap.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionDisplay)
                } header: {
                    Text("About")
                }

                Section("Downloaded areas") {
                    if offlineManager.packs.isEmpty {
                        Text("Nothing downloaded yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(offlineManager.packs.enumerated()), id: \.offset) { _, pack in
                        OfflinePackRow(pack: pack, manager: offlineManager)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            offlineManager.delete(offlineManager.packs[index])
                        }
                    }
                }
            }
            .navigationTitle("Offline Maps")
            .onAppear {
                locationService.requestPermission()
                offlineManager.reload()
            }
        }
    }

    private func downloadAroundMe() {
        guard let location = locationService.location else { return }
        offlineManager.download(
            name: "Around me — \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            bounds: OfflineMapManager.bounds(around: location.coordinate, radiusKm: 40)
        )
    }

    private func downloadRoute(_ route: Route) {
        guard let bounds = OfflineMapManager.bounds(of: route.path, paddingKm: 8) else { return }
        offlineManager.download(name: route.name, bounds: bounds)
    }
}

extension Bundle {
    /// "0.2.0 (6)" — semantic version plus App Store build number.
    var versionDisplay: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

struct OfflinePackRow: View {
    let pack: MLNOfflinePack
    let manager: OfflineMapManager

    var body: some View {
        // Reading progressTick makes this row refresh on download progress.
        let _ = manager.progressTick
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.name(of: pack))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pack.state == .active {
                ProgressView()
            } else if pack.state == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var statusText: String {
        let progress = pack.progress
        let megabytes = Double(progress.countOfBytesCompleted) / 1_000_000
        switch pack.state {
        case .complete:
            return String(format: "%.0f MB · %d tiles", megabytes, progress.countOfResourcesCompleted)
        case .active:
            if progress.countOfResourcesExpected > 0 {
                let percent = 100 * progress.countOfResourcesCompleted
                    / progress.countOfResourcesExpected
                return String(format: "Downloading… %d%% · %.0f MB", percent, megabytes)
            }
            return "Downloading…"
        case .inactive:
            return "Paused"
        default:
            return "Waiting…"
        }
    }
}
