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
    /// Theme the current style was loaded for, so a switch on the phone is
    /// picked up by the car map instead of leaving it on the old style.
    private var shownTheme: MapTheme?
    /// Target zoom, adjusted by the zoom buttons and applied on every camera
    /// snap (so a zoom change persists as the camera keeps following).
    private var desiredZoom: Double = 15
    /// The user's coordinate, so the center dot can be pinned to exactly where
    /// that point projects on screen (accounting for CarPlay safe-area insets
    /// that shift the map's rendered center — otherwise the dot sits off-road).
    private var lastUserCoordinate: CLLocationCoordinate2D?

    /// Fixed dot at the screen center marks the driver. We drive the camera
    /// from LocationService ourselves (below); MLNMapView's own user dot and
    /// tracking modes don't update reliably in the CarPlay scene, so they're
    /// off and the driver is simply always at screen center.
    private let userDot = UIView()

    private var theme: MapTheme {
        MapTheme(rawValue: UserDefaults.standard.string(forKey: "mapTheme") ?? "") ?? .standard
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Deliver position (in the background too) even when not driving so
        // the map can follow; balanced by teardown() on scene disconnect.
        services.locationService.startStandby()

        let map = MLNMapView(frame: view.bounds, styleURL: theme.styleURL)
        shownTheme = theme
        map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.delegate = self
        map.showsUserLocation = false
        map.allowsRotating = true
        view.addSubview(map)
        mapView = map

        userDot.backgroundColor = .systemBlue
        userDot.layer.borderColor = UIColor.white.cgColor
        userDot.layer.borderWidth = 3
        userDot.layer.cornerRadius = 10
        userDot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userDot)
        NSLayoutConstraint.activate([
            userDot.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            userDot.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            userDot.widthAnchor.constraint(equalToConstant: 20),
            userDot.heightAnchor.constraint(equalToConstant: 20),
        ])

        applyCamera(animated: false)
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        // Annotations outlive a style reload, so they must be removed rather
        // than just forgotten — otherwise a theme switch doubles every marker.
        if !featureAnnotations.isEmpty {
            mapView.removeAnnotations(featureAnnotations)
        }
        shownRoute = []
        shownFeatureIDs = []
        featureAnnotations = []
        applyCamera(animated: false)
        refresh()
    }

    /// Stop standby location when the CarPlay scene disconnects.
    func teardown() {
        services.locationService.stopStandby()
    }

    // MARK: - Camera (driven from LocationService, not MLNMapView tracking)

    /// Snap the camera onto the driver, heading-up while driving, at the
    /// desired zoom. No-op until a location is available.
    private func applyCamera(animated: Bool) {
        guard let map = mapView,
            let location = services.locationService.lastKnownLocation
        else { return }
        lastUserCoordinate = location.coordinate
        let direction = (services.isDriving && location.course >= 0)
            ? location.course : map.direction
        map.setCenter(
            location.coordinate, zoomLevel: desiredZoom, direction: direction, animated: animated
        )
        positionDot()
    }

    /// Pin the driver dot to where the user's coordinate actually projects on
    /// screen, not the geometric center. Updated continuously as the map moves
    /// (see the region delegate callbacks below) so it stays glued to the road.
    private func positionDot() {
        guard let map = mapView, let coord = lastUserCoordinate else {
            userDot.isHidden = true
            return
        }
        userDot.isHidden = false
        userDot.center = map.convert(coord, toPointTo: view)
    }

    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        positionDot()
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        positionDot()
    }

    /// Re-center at the default zoom (recenter map button).
    func recenter() {
        desiredZoom = 15
        applyCamera(animated: true)
    }

    func zoomIn() {
        desiredZoom = min(desiredZoom + 1, 18)
        applyCamera(animated: true)
    }

    func zoomOut() {
        desiredZoom = max(desiredZoom - 1, 3)
        applyCamera(animated: true)
    }

    /// Follow the driver and redraw the route/features. Called every tick by
    /// the scene delegate.
    func refresh() {
        applyCamera(animated: true)
        // Pick up a map-style switch made on the phone. Reloading the style
        // wipes our layers; didFinishLoading re-adds them.
        if theme != shownTheme {
            shownTheme = theme
            mapView.styleURL = theme.styleURL
            return
        }
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
        let ids = features.map { "\($0.stableID)-\($0.isSuggested)" }
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
