import CarPlay
import CoreLocation
import MapLibre
import UIKit

/// Draws the MapLibre map on the CarPlay screen: the OpenFreeMap tiles (or
/// the Explorer parchment style), the active route as a line, and marked
/// features as annotations. Follows the driver heading-up while driving.
@MainActor
final class CarPlayMapViewController: UIViewController, @preconcurrency MLNMapViewDelegate {
    private var mapView: MLNMapView!
    private let services = AppServices.shared

    private static let routeSourceID = "carplay-route-source"
    private static let routeLayerID = "carplay-route-line"

    private var shownRoute: [[Double]] = []
    private var shownFeatureIDs: [String] = []
    private var featureAnnotations: [CarPlayMarkerAnnotation] = []

    private var theme: MapTheme {
        MapTheme(rawValue: UserDefaults.standard.string(forKey: "mapTheme") ?? "") ?? .standard
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let map = MLNMapView(frame: view.bounds, styleURL: theme.styleURL)
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.delegate = self
        map.showsUserLocation = true
        map.allowsRotating = true
        map.setUserTrackingMode(.followWithHeading, animated: false, completionHandler: nil)
        view.addSubview(map)
        mapView = map
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        shownRoute = []
        shownFeatureIDs = []
        featureAnnotations = []
        refresh()
    }

    /// Re-center on the driver (map button action).
    func recenter() {
        let mode: MLNUserTrackingMode = services.isDriving ? .followWithHeading : .follow
        mapView.setUserTrackingMode(mode, animated: true, completionHandler: nil)
    }

    /// Redraw the route and feature markers if they've changed. Cheap to
    /// call every refresh tick — it diffs before touching the map.
    func refresh() {
        guard let style = mapView.style else { return }
        updateRoute(on: style)
        updateFeatures()
    }

    // MARK: - Route line

    private func updateRoute(on style: MLNStyle) {
        let path = services.activeRoute?.path ?? []
        let latLons = path.map { [$0.latitude, $0.longitude] }
        guard latLons != shownRoute else { return }
        shownRoute = latLons

        if let existing = style.source(withIdentifier: Self.routeSourceID) as? MLNShapeSource {
            existing.shape = polyline(from: path)
        } else {
            let source = MLNShapeSource(
                identifier: Self.routeSourceID, shape: polyline(from: path), options: nil
            )
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: Self.routeLayerID, source: source)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineWidth = NSExpression(forConstantValue: 7)
            let color: UIColor = theme == .explorer
                ? UIColor(red: 0.35, green: 0.23, blue: 0.10, alpha: 1) : .systemBlue
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineOpacity = NSExpression(forConstantValue: 0.8)
            style.addLayer(layer)
        }
    }

    private func polyline(from path: [CLLocationCoordinate2D]) -> MLNShape {
        guard path.count >= 2 else { return MLNShapeCollectionFeature(shapes: []) }
        var coords = path
        return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
    }

    // MARK: - Feature markers

    private func updateFeatures() {
        let features = services.currentFeatures()
        let ids = features.map { "\($0.createdAt.timeIntervalSince1970)-\($0.isSuggested)" }
        guard ids != shownFeatureIDs else { return }
        shownFeatureIDs = ids

        if !featureAnnotations.isEmpty {
            mapView.removeAnnotations(featureAnnotations)
        }
        featureAnnotations = features.map { feature in
            let annotation = CarPlayMarkerAnnotation()
            annotation.coordinate = feature.coordinate
            annotation.tint = UIColor(feature.type.tint)
            if feature.type == .tightCorner {
                annotation.chevrons = feature.chevronCount
                annotation.reuseKey = "corner-\(feature.chevronCount)-\(feature.isSuggested)"
            } else {
                annotation.symbolName = feature.type.systemImage
                annotation.reuseKey = "\(feature.type.rawValue)-\(feature.isSuggested)"
            }
            annotation.suggested = feature.isSuggested
            return annotation
        }
        mapView.addAnnotations(featureAnnotations)
    }

    func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
        guard let marker = annotation as? CarPlayMarkerAnnotation else { return nil }
        if let reused = mapView.dequeueReusableAnnotationImage(withIdentifier: marker.reuseKey) {
            return reused
        }
        let image = MapLibreView.Coordinator.markerImage(
            symbolName: marker.symbolName,
            textLabel: nil,
            tint: marker.tint,
            explorer: false,
            suggested: marker.suggested,
            chevrons: marker.chevrons
        )
        return MLNAnnotationImage(image: image, reuseIdentifier: marker.reuseKey)
    }

    func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
        false
    }
}

final class CarPlayMarkerAnnotation: MLNPointAnnotation {
    var reuseKey = ""
    var tint: UIColor = .systemRed
    var symbolName: String?
    var chevrons: Int?
    var suggested = false
}
