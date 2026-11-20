import SwiftUI
import MapLibre
import CoreLocation

/// Peta kecil di kotak pemilihan rute: menampilkan semua rute (yang dipilih berwarna biru, alternatif abu-abu)
/// dan tujuan, otomatis diperbesar agar seluruh rute terlihat. Peta ini tidak bisa digeser/dizoom supaya tidak
/// berebut gestur dengan daftar. Ketuk garis rute lain = pilih rute itu; ketuk di tempat lain = buka peta penuh.
struct RoutePreviewMap: UIViewRepresentable {
    let routes: [Route]
    let selected: Int
    let destination: Place?
    let onSelect: (Int) -> Void
    let onOpen: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let v = MLNMapView(frame: .zero, styleURL: MapStyle.light)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.delegate = context.coordinator
        v.showsUserLocation = true
        v.allowsScrolling = false
        v.allowsZooming = false
        v.allowsRotating = false
        v.allowsTilting = false
        v.compassView.isHidden = true
        MapStyle.hideBranding(v)
        v.setCenter(CLLocationCoordinate2D(latitude: -6.2, longitude: 106.82), zoomLevel: 10, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        v.addGestureRecognizer(tap)
        context.coordinator.mapView = v
        return v
    }

    func updateUIView(_ v: MLNMapView, context: Context) {
        let c = context.coordinator
        c.onSelect = onSelect
        c.onOpen = onOpen
        c.update(v, routes: routes, selected: selected, destination: destination)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        weak var mapView: MLNMapView?
        var onSelect: (Int) -> Void = { _ in }
        var onOpen: () -> Void = {}

        private var routes = [Route]()
        private var selected = 0
        private var lines = [MLNPolyline]()
        private var destAnno: MLNPointAnnotation?
        private var routesKey = ""
        private var needsFit = false

        func update(_ v: MLNMapView, routes newRoutes: [Route], selected newSelected: Int, destination: Place?) {
            let key = newRoutes.map { "\(Int($0.totalM))-\($0.points.count)" }.joined(separator: ",")
                + "|" + (destination?.id ?? "")
            let routesChanged = key != routesKey
            if !routesChanged && newSelected == selected { return }
            routes = newRoutes
            selected = newSelected
            redrawLines(v)

            if routesChanged {
                routesKey = key
                if let a = destAnno { v.removeAnnotation(a); destAnno = nil }
                if let d = destination {
                    let a = MLNPointAnnotation()
                    a.coordinate = d.coordinate
                    a.title = d.name
                    v.addAnnotation(a)
                    destAnno = a
                }
                needsFit = true
                fit(v)
                // ukuran view bisa baru final setelah layout berikutnya
                DispatchQueue.main.async { [weak self, weak v] in
                    guard let self = self, let v = v else { return }
                    self.fit(v)
                }
            }
        }

        /// Alternatif digambar dulu (di bawah), rute terpilih terakhir (di atas).
        private func redrawLines(_ v: MLNMapView) {
            if !lines.isEmpty { v.removeAnnotations(lines) }
            lines = []
            var order = Array(routes.indices).filter { $0 != selected }
            if routes.indices.contains(selected) { order.append(selected) }
            var made = [(Int, MLNPolyline)]()
            for i in order {
                var coords = routes[i].points
                guard coords.count >= 2 else { continue }
                made.append((i, MLNPolyline(coordinates: &coords, count: UInt(coords.count))))
            }
            lines = made.map { $0.1 }
            lineIndex = Dictionary(uniqueKeysWithValues: made.map { (ObjectIdentifier($0.1), $0.0) })
            if !lines.isEmpty { v.addAnnotations(lines) }
        }

        private var lineIndex = [ObjectIdentifier: Int]()

        private func fit(_ v: MLNMapView) {
            guard needsFit, v.bounds.width > 10, v.bounds.height > 10 else { return }
            var all = [CLLocationCoordinate2D]()
            for r in routes {
                let step = max(1, r.points.count / 300)
                var i = 0
                while i < r.points.count { all.append(r.points[i]); i += step }
                if let last = r.points.last { all.append(last) }
            }
            guard all.count >= 2 else { return }
            v.setVisibleCoordinates(&all, count: UInt(all.count),
                                    edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28),
                                    animated: false)
            needsFit = false
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            if !routes.isEmpty { needsFit = true; fit(mapView) }
        }

        // MARK: - Ketuk

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let v = mapView else { return }
            let p = g.location(in: v)
            var best = -1
            var bestD: CGFloat = 28            // toleransi ketukan (pt)
            for i in routes.indices {
                let d = minDistance(from: p, to: routes[i], in: v)
                if d < bestD { bestD = d; best = i }
            }
            if best >= 0 && best != selected { onSelect(best) } else { onOpen() }
        }

        private func minDistance(from p: CGPoint, to r: Route, in v: MLNMapView) -> CGFloat {
            let step = max(1, r.points.count / 200)
            var prev: CGPoint?
            var best = CGFloat.greatestFiniteMagnitude
            var i = 0
            while i < r.points.count {
                let s = v.convert(r.points[i], toPointTo: v)
                if let a = prev {
                    best = min(best, segmentDistance(p, a, s))
                } else {
                    best = min(best, hypot(p.x - s.x, p.y - s.y))
                }
                prev = s
                i += step
            }
            return best
        }

        private func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            if len2 < 0.0001 { return hypot(p.x - a.x, p.y - a.y) }
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
        }

        // MARK: - Tampilan garis

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let i = lineIndex[ObjectIdentifier(annotation)], i == selected {
                return UIColor(red: 0.10, green: 0.42, blue: 0.95, alpha: 1)
            }
            return UIColor(red: 0.55, green: 0.58, blue: 0.64, alpha: 0.95)
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            if let i = lineIndex[ObjectIdentifier(annotation)], i == selected { return 6 }
            return 5
        }
    }
}
