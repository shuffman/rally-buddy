import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct MapTab: View {
    var locationService: LocationService

    @Query private var features: [RoadFeature]
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pendingPoint: PendingPoint?

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(features) { feature in
                        Marker(
                            feature.type.label,
                            systemImage: feature.type.systemImage,
                            coordinate: feature.coordinate
                        )
                        .tint(feature.type.tint)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        pendingPoint = PendingPoint(coordinate: coordinate)
                    }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { locationService.requestPermission() }
            .sheet(item: $pendingPoint) { point in
                AddFeatureSheet(
                    coordinate: point.coordinate,
                    course: currentCourse
                )
                .presentationDetents([.medium])
            }
        }
    }

    private var currentCourse: Double? {
        guard let course = locationService.location?.course, course >= 0 else {
            return nil
        }
        return course
    }
}

struct PendingPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
