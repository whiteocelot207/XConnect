import SwiftUI
import MapLibre
import CoreLocation

struct NavMapView: UIViewRepresentable {
    let nav: NavigationController
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> MLNMapView {
        let v = MLNMapView(frame: .zero, styleURL: URL(string: "https://tiles.openfreemap.org/styles/liberty"))
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.delegate = context.coordinator
        v.showsUserLocation = true
        v.setCenter(CLLocationCoordinate2D(latitude: -6.2, longitude: 106.82), zoomLevel: 11, animated: false)
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleLongPress(_:)))
        v.addGestureRecognizer(lp)
        context.coordinator.mapView = v
        return v
    }

    func updateUIView(_ v: MLNMapView, context: Context) {
        context.coordinator.update(v, nav: nav)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        let onLongPress: (CLLocationCoordinate2D) -> Void
        weak var mapView: MLNMapView?
        private var centered = false
        private var lineVersion = -1
        private var line: MLNPolyline?
        private var destAnno: MLNPointAnnotation?
        private var destID = ""
        private var lastPhase: NavigationController.Phase = .idle

        init(onLongPress: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let v = mapView else { return }
            let pt = g.location(in: v)
            onLongPress(v.convert(pt, toCoordinateFrom: v))
        }

        func update(_ v: MLNMapView, nav: NavigationController) {
            if lineVersion != nav.routeVersion {
                lineVersion = nav.routeVersion
                if let l = line {
                    v.removeAnnotation(l)
                    line = nil
                }
                if let r = nav.route {
                    var coords = r.points
                    let l = MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                    v.addAnnotation(l)
                    line = l
                    if nav.phase == .previewing {
                        var fit = r.points
                        v.setVisibleCoordinates(&fit, count: UInt(fit.count),
                                                edgePadding: UIEdgeInsets(top: 170, left: 40, bottom: 240, right: 40),
                                                animated: true)
                    }
                }
            }

            let did = nav.destination?.id ?? ""
            if did != destID {
                destID = did
                if let a = destAnno {
                    v.removeAnnotation(a)
                    destAnno = nil
                }
                if let d = nav.destination {
                    let a = MLNPointAnnotation()
                    a.coordinate = d.coordinate
                    a.title = d.name
                    v.addAnnotation(a)
                    destAnno = a
                }
            }

            if nav.phase != lastPhase {
                lastPhase = nav.phase
                if nav.phase == .navigating {
                    v.userTrackingMode = .followWithCourse
                    v.zoomLevel = 16
                } else {
                    v.userTrackingMode = .none
                }
            }
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            if !centered, let c = userLocation?.coordinate, CLLocationCoordinate2DIsValid(c),
               c.latitude != 0 || c.longitude != 0 {
                centered = true
                mapView.setCenter(c, zoomLevel: 14, animated: false)
            }
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            UIColor(red: 0.10, green: 0.42, blue: 0.95, alpha: 1)
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            6
        }
    }
}
