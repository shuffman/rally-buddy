import CoreLocation
import SwiftData
import SwiftUI

struct DriveTab: View {
    var locationService: LocationService
    var alertEngine: AlertEngine

    @Query private var features: [RoadFeature]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()

                Text(speedText)
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Spacer()

                if let next = alertEngine.upcoming.first {
                    UpcomingFeatureCard(item: next)
                } else if locationService.isTracking {
                    Label("No marked features ahead", systemImage: "road.lanes")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    toggleDrive()
                } label: {
                    Text(locationService.isTracking ? "End Drive" : "Start Drive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(locationService.isTracking ? .red : .green)
                .padding(.horizontal)
            }
            .padding(.bottom)
            .navigationTitle("Drive")
            .onAppear { locationService.requestPermission() }
            .onChange(of: locationService.location) { _, newLocation in
                guard let newLocation, locationService.isTracking else { return }
                alertEngine.update(location: newLocation, features: features)
            }
        }
    }

    private var speedText: String {
        guard let speed = locationService.location?.speed, speed >= 0 else {
            return "--"
        }
        return String(Int(speed * 3.6))
    }

    private func toggleDrive() {
        if locationService.isTracking {
            locationService.stopTracking()
            alertEngine.reset()
        } else {
            locationService.startTracking()
        }
    }
}

struct UpcomingFeatureCard: View {
    let item: UpcomingFeature

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: item.feature.type.systemImage)
                .font(.largeTitle)
                .foregroundStyle(item.feature.type.tint)
            VStack(alignment: .leading) {
                Text(item.feature.type.label)
                    .font(.title2.bold())
                Text("\(Int(item.distance)) m")
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
