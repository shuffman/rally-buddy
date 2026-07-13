import CoreLocation
import MapLibre
import SwiftUI
import UIKit

/// A marker shown on the map — either a road feature or a numbered
/// route-planning waypoint.
struct MapMarker: Equatable {
    enum Kind: Equatable {
        case feature(RoadFeatureType)
        case waypoint(Int)
    }

    let id: String
    let latitude: Double
    let longitude: Double
    let kind: Kind

    init(id: String, coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.kind = kind
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// SwiftUI wrapper around MLNMapView (MapLibre) used by both the drive
/// screen and the route planner. Renders OpenFreeMap vector tiles, which
/// the OfflineMapManager can download for offline use.
struct MapLibreView: UIViewRepresentable {
    var markers: [MapMarker] = []
    var pathCoordinates: [CLLocationCoordinate2D] = []
    var followsCourse: Bool = false
    /// When the path changes while not following, zoom to fit it.
    var fitPathOnChange: Bool = false
    /// Increment to snap the camera back to the user's location.
    var recenterToken: Int = 0
    var onTap: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: OfflineMapManager.styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        for recognizer in mapView.gestureRecognizers ?? []
        where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap

        if coordinator.markers != markers {
            coordinator.markers = markers
            if !coordinator.markerAnnotations.isEmpty {
                mapView.removeAnnotations(coordinator.markerAnnotations)
            }
            coordinator.markerAnnotations = markers.map { marker in
                let annotation = MarkerAnnotation()
                annotation.coordinate = marker.coordinate
                switch marker.kind {
                case .feature(let type):
                    annotation.reuseKey = "feature-\(type.rawValue)"
                    annotation.tint = UIColor(type.tint)
                    annotation.symbolName = type.systemImage
                case .waypoint(let number):
                    annotation.reuseKey = "waypoint-\(number)"
                    annotation.tint = .systemBlue
                    annotation.textLabel = "\(number)"
                }
                return annotation
            }
            mapView.addAnnotations(coordinator.markerAnnotations)
        }

        let path = pathCoordinates
        if coordinator.pathLatLons != path.map({ [$0.latitude, $0.longitude] }) {
            coordinator.pathLatLons = path.map { [$0.latitude, $0.longitude] }
            if let existing = coordinator.polyline {
                mapView.removeAnnotation(existing)
                coordinator.polyline = nil
            }
            if path.count >= 2 {
                var coords = path
                let polyline = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                coordinator.polyline = polyline
                mapView.addAnnotation(polyline)
                if fitPathOnChange, !followsCourse {
                    mapView.setVisibleCoordinates(
                        &coords,
                        count: UInt(coords.count),
                        edgePadding: UIEdgeInsets(top: 80, left: 50, bottom: 140, right: 50),
                        animated: true
                    )
                }
            }
        }

        let desiredMode: MLNUserTrackingMode = followsCourse ? .followWithCourse : .none
        if followsCourse != coordinator.wasFollowingCourse {
            coordinator.wasFollowingCourse = followsCourse
            mapView.setUserTrackingMode(desiredMode, animated: true, completionHandler: nil)
        }

        if recenterToken != coordinator.lastRecenterToken {
            coordinator.lastRecenterToken = recenterToken
            if let location = mapView.userLocation?.location {
                mapView.setCenter(location.coordinate, zoomLevel: 14, animated: true)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var onTap: ((CLLocationCoordinate2D) -> Void)?
        var markers: [MapMarker] = []
        var markerAnnotations: [MarkerAnnotation] = []
        var pathLatLons: [[Double]] = []
        var polyline: MLNPolyline?
        var wasFollowingCourse = false
        var lastRecenterToken = 0
        private var hasCenteredOnUser = false

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView, let onTap else { return }
            let point = gesture.location(in: mapView)
            onTap(mapView.convert(point, toCoordinateFrom: mapView))
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            guard !hasCenteredOnUser, !wasFollowingCourse,
                let coordinate = userLocation?.location?.coordinate
            else { return }
            hasCenteredOnUser = true
            mapView.setCenter(coordinate, zoomLevel: 13, animated: false)
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard let marker = annotation as? MarkerAnnotation else { return nil }
            if let reused = mapView.dequeueReusableAnnotationImage(withIdentifier: marker.reuseKey) {
                return reused
            }
            return MLNAnnotationImage(
                image: Self.markerImage(
                    symbolName: marker.symbolName,
                    textLabel: marker.textLabel,
                    tint: marker.tint
                ),
                reuseIdentifier: marker.reuseKey
            )
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            false
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            .systemBlue
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            0.75
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            5
        }

        static func markerImage(symbolName: String?, textLabel: String?, tint: UIColor) -> UIImage {
            let size = CGSize(width: 38, height: 38)
            return UIGraphicsImageRenderer(size: size).image { context in
                let circle = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                tint.setFill()
                UIColor.white.setStroke()
                let path = UIBezierPath(ovalIn: circle)
                path.lineWidth = 3
                path.fill()
                path.stroke()

                if let symbolName,
                    let symbol = UIImage(
                        systemName: symbolName,
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
                    )?.withTintColor(.white, renderingMode: .alwaysOriginal)
                {
                    let origin = CGPoint(
                        x: (size.width - symbol.size.width) / 2,
                        y: (size.height - symbol.size.height) / 2
                    )
                    symbol.draw(at: origin)
                } else if let textLabel {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 17, weight: .bold),
                        .foregroundColor: UIColor.white,
                    ]
                    let textSize = (textLabel as NSString).size(withAttributes: attributes)
                    (textLabel as NSString).draw(
                        at: CGPoint(
                            x: (size.width - textSize.width) / 2,
                            y: (size.height - textSize.height) / 2
                        ),
                        withAttributes: attributes
                    )
                }
            }
        }
    }
}

final class MarkerAnnotation: MLNPointAnnotation {
    var reuseKey = ""
    var tint: UIColor = .systemRed
    var symbolName: String?
    var textLabel: String?
}
