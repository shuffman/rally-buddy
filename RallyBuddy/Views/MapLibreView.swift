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
    /// Auto-detected, not yet confirmed by the user — drawn dashed/faded.
    let suggested: Bool
    /// Rally chevron count for corner markers (1–3); nil for other kinds.
    let chevrons: Int?

    init(
        id: String,
        coordinate: CLLocationCoordinate2D,
        kind: Kind,
        suggested: Bool = false,
        chevrons: Int? = nil
    ) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.kind = kind
        self.suggested = suggested
        self.chevrons = chevrons
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// SwiftUI wrapper around MLNMapView (MapLibre) used by both the drive
/// screen and the route planner. Renders OpenFreeMap vector tiles, which
/// the OfflineMapManager can download for offline use. The route is drawn
/// as a style layer so it can be dashed (Explorer's dotted trail).
struct MapLibreView: UIViewRepresentable {
    var markers: [MapMarker] = []
    var pathCoordinates: [CLLocationCoordinate2D] = []
    var theme: MapTheme = .standard
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
        let mapView = MLNMapView(frame: .zero, styleURL: theme.styleURL)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.theme = theme

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

        let themeChanged = coordinator.theme != theme
        if themeChanged {
            coordinator.theme = theme
            // Style reload wipes layers; didFinishLoading re-adds the route.
            mapView.styleURL = theme.styleURL
        }

        if coordinator.markers != markers || themeChanged {
            coordinator.markers = markers
            if !coordinator.markerAnnotations.isEmpty {
                mapView.removeAnnotations(coordinator.markerAnnotations)
            }
            coordinator.markerAnnotations = markers.map { marker in
                let annotation = MarkerAnnotation()
                annotation.coordinate = marker.coordinate
                let suffix = marker.suggested ? "-suggested" : ""
                switch marker.kind {
                case .feature(let type):
                    let chevronKey = marker.chevrons.map { "-c\($0)" } ?? ""
                    annotation.reuseKey =
                        "\(theme.rawValue)-feature-\(type.rawValue)\(chevronKey)\(suffix)"
                    annotation.tint = UIColor(type.tint)
                    if type == .tightCorner, let chevrons = marker.chevrons {
                        // Here be dragons: Explorer draws hairpins as one.
                        if theme == .explorer, chevrons == 3 {
                            annotation.symbolName = "lizard.fill"
                        } else {
                            annotation.chevronCount = chevrons
                        }
                    } else {
                        annotation.symbolName = theme == .explorer
                            ? type.explorerSymbol : type.systemImage
                    }
                case .waypoint(let number):
                    annotation.reuseKey = "\(theme.rawValue)-waypoint-\(number)\(suffix)"
                    annotation.tint = .systemBlue
                    annotation.textLabel = "\(number)"
                }
                annotation.isExplorer = theme == .explorer
                annotation.isSuggestedMarker = marker.suggested
                return annotation
            }
            mapView.addAnnotations(coordinator.markerAnnotations)
        }

        let pathLatLons = pathCoordinates.map { [$0.latitude, $0.longitude] }
        if coordinator.pathLatLons != pathLatLons || themeChanged {
            let pathChanged = coordinator.pathLatLons != pathLatLons
            coordinator.pathLatLons = pathLatLons
            if let style = mapView.style {
                coordinator.updateRouteLayer(on: style)
            }
            if pathChanged, fitPathOnChange, !followsCourse, pathCoordinates.count >= 2 {
                var coords = pathCoordinates
                mapView.setVisibleCoordinates(
                    &coords,
                    count: UInt(coords.count),
                    edgePadding: UIEdgeInsets(top: 80, left: 50, bottom: 140, right: 50),
                    animated: true
                )
            }
        }

        if followsCourse != coordinator.wasFollowingCourse {
            coordinator.wasFollowingCourse = followsCourse
            mapView.setUserTrackingMode(
                followsCourse ? .followWithCourse : .none,
                animated: true,
                completionHandler: nil
            )
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
        var theme: MapTheme = .standard
        var markers: [MapMarker] = []
        var markerAnnotations: [MarkerAnnotation] = []
        var pathLatLons: [[Double]] = []
        var wasFollowingCourse = false
        var lastRecenterToken = 0
        private var hasCenteredOnUser = false

        private static let routeSourceID = "rallybuddy-route-source"
        private static let routeLayerID = "rallybuddy-route-line"

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView, let onTap else { return }
            let point = gesture.location(in: mapView)
            onTap(mapView.convert(point, toCoordinateFrom: mapView))
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            updateRouteLayer(on: style)
        }

        /// Creates or refreshes the route source + line layer to match the
        /// current path and theme.
        func updateRouteLayer(on style: MLNStyle) {
            let coordinates = pathLatLons.map {
                CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1])
            }

            let shape: MLNShape
            if coordinates.count >= 2 {
                var coords = coordinates
                shape = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            } else {
                shape = MLNShapeCollectionFeature(shapes: [])
            }

            let source: MLNShapeSource
            if let existing = style.source(withIdentifier: Self.routeSourceID) as? MLNShapeSource {
                source = existing
                source.shape = shape
            } else {
                source = MLNShapeSource(identifier: Self.routeSourceID, shape: shape, options: nil)
                style.addSource(source)
            }

            if let old = style.layer(withIdentifier: Self.routeLayerID) {
                style.removeLayer(old)
            }
            let layer = MLNLineStyleLayer(identifier: Self.routeLayerID, source: source)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            switch theme {
            case .standard:
                layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
                layer.lineOpacity = NSExpression(forConstantValue: 0.75)
                layer.lineWidth = NSExpression(forConstantValue: 5)
            case .explorer:
                // Dotted trail, like footprints across a treasure map.
                layer.lineColor = NSExpression(
                    forConstantValue: UIColor(red: 0.35, green: 0.23, blue: 0.10, alpha: 1)
                )
                layer.lineOpacity = NSExpression(forConstantValue: 0.9)
                layer.lineWidth = NSExpression(forConstantValue: 6)
                layer.lineDashPattern = NSExpression(forConstantValue: [0.1, 1.9])
            }
            style.addLayer(layer)
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
                    tint: marker.tint,
                    explorer: marker.isExplorer,
                    suggested: marker.isSuggestedMarker,
                    chevrons: marker.chevronCount
                ),
                reuseIdentifier: marker.reuseKey
            )
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            false
        }

        static func markerImage(
            symbolName: String?,
            textLabel: String?,
            tint: UIColor,
            explorer: Bool,
            suggested: Bool = false,
            chevrons: Int? = nil
        ) -> UIImage {
            let size = CGSize(width: 38, height: 38)
            let parchment = UIColor(red: 0.95, green: 0.91, blue: 0.80, alpha: 1)
            let ink = UIColor(red: 0.31, green: 0.23, blue: 0.13, alpha: 1)
            let alpha: CGFloat = suggested ? 0.65 : 1
            let fill = (explorer ? parchment : tint).withAlphaComponent(alpha)
            let stroke = (explorer ? ink : UIColor.white).withAlphaComponent(alpha)
            let content = (explorer ? ink : UIColor.white).withAlphaComponent(alpha)

            return UIGraphicsImageRenderer(size: size).image { _ in
                let circle = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                fill.setFill()
                stroke.setStroke()
                let path = UIBezierPath(ovalIn: circle)
                path.lineWidth = explorer ? 2.5 : 3
                if suggested {
                    path.setLineDash([4, 3], count: 2, phase: 0)
                }
                path.fill()
                path.stroke()

                if let chevrons {
                    // Rally corner chevrons: », nested, pointing right.
                    content.setStroke()
                    let chevronPath = UIBezierPath()
                    let armHeight: CGFloat = 6.5
                    let armWidth: CGFloat = 6
                    let spacing: CGFloat = 6
                    let total = CGFloat(chevrons - 1) * spacing + armWidth
                    var x = (size.width - total) / 2 - 1
                    let cy = size.height / 2
                    for _ in 0..<chevrons {
                        chevronPath.move(to: CGPoint(x: x, y: cy - armHeight))
                        chevronPath.addLine(to: CGPoint(x: x + armWidth, y: cy))
                        chevronPath.addLine(to: CGPoint(x: x, y: cy + armHeight))
                        x += spacing
                    }
                    chevronPath.lineWidth = 3
                    chevronPath.lineCapStyle = .round
                    chevronPath.lineJoinStyle = .round
                    chevronPath.stroke()
                } else if let symbolName,
                    let symbol = UIImage(
                        systemName: symbolName,
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
                    )?.withTintColor(content, renderingMode: .alwaysOriginal)
                {
                    symbol.draw(at: CGPoint(
                        x: (size.width - symbol.size.width) / 2,
                        y: (size.height - symbol.size.height) / 2
                    ))
                } else if let textLabel {
                    let font = explorer
                        ? UIFont(name: "TimesNewRomanPS-BoldMT", size: 17)
                            ?? UIFont.systemFont(ofSize: 17, weight: .bold)
                        : UIFont.systemFont(ofSize: 17, weight: .bold)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: content,
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
    var isExplorer = false
    var isSuggestedMarker = false
    var chevronCount: Int?
}
