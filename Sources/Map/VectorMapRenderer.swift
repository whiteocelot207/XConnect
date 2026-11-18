import UIKit
import CoreLocation

private func hex(_ v: Int, _ a: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

struct MapPalette {
    let background: UIColor
    let fills: [FillKind: UIColor]
    let buildingLine: UIColor
    let water: UIColor
    let casing: UIColor
    let roads: [LineKind: UIColor]
    let text: UIColor
    let halo: UIColor

    static let day = MapPalette(
        background: hex(0xF1EDE4),
        fills: [.grass: hex(0xDDEBC8), .wood: hex(0xC9E0B3), .farm: hex(0xECE8D6), .sand: hex(0xF2E8C8),
                .residential: hex(0xEAE6DE), .commercial: hex(0xF0E2E0), .industrial: hex(0xE6E2EC),
                .hospital: hex(0xF3DEDE), .school: hex(0xF0E8C8), .cemetery: hex(0xCFE0C4),
                .park: hex(0xC8E6B0), .water: hex(0xA8D0EE), .building: hex(0xD9D2C8)],
        buildingLine: hex(0xC4BCB0), water: hex(0x9CC8EA), casing: hex(0xB4AFA3),
        roads: [.rail: hex(0x8A8A8A), .path: hex(0xE0B8B0), .service: hex(0xFFFFFF), .minor: hex(0xFFFFFF),
                .tertiary: hex(0xFFFFFF), .secondary: hex(0xFFF0A8), .primary: hex(0xFFD88A),
                .trunk: hex(0xFCBF6B), .motorway: hex(0xF9A65A)],
        text: hex(0x333333), halo: hex(0xFFFFFF))

    static let night = MapPalette(
        background: hex(0x1B2029),
        fills: [.grass: hex(0x202A26), .wood: hex(0x1D2B24), .farm: hex(0x232722), .sand: hex(0x2A2A24),
                .residential: hex(0x222730), .commercial: hex(0x262A34), .industrial: hex(0x242632),
                .hospital: hex(0x2C2530), .school: hex(0x292A2A), .cemetery: hex(0x202A26),
                .park: hex(0x1F2E27), .water: hex(0x14243A), .building: hex(0x2A303B)],
        buildingLine: hex(0x343B48), water: hex(0x1B3350), casing: hex(0x10141A),
        roads: [.rail: hex(0x555B66), .path: hex(0x3A404C), .service: hex(0x3D4452), .minor: hex(0x4A5262),
                .tertiary: hex(0x566075), .secondary: hex(0x6A6F80), .primary: hex(0x8A7A60),
                .trunk: hex(0x9A7E58), .motorway: hex(0xA8804F)],
        text: hex(0xE8E8F0), halo: hex(0x11151B))
}

struct VMapViewport {
    var rect: CGRect
    var anchor: CGPoint          // posisi pengguna di dalam rect
    var zoom: Double             // skala tile 256 px
    var bearing: Double
    var center: CLLocationCoordinate2D
    var night: Bool
    var route: [CLLocationCoordinate2D]
    var destination: CLLocationCoordinate2D?
    var routeColor: UIColor
    var routeWidth: CGFloat = 5          // lebar garis rute (px)
    var routeBorder: CGFloat = 1.5       // tebal tepi putih tiap sisi (px)
    var markerScale: CGFloat = 1
    var markerRing = true
}

/// Penggambar peta vektor berbasis CPU (CoreGraphics). Tidak memakai GPU, jadi tetap jalan saat app di latar belakang.
enum VectorMapRenderer {
    static func mercator(_ c: CLLocationCoordinate2D, zoom: Double) -> (Double, Double) {
        let n = 256.0 * pow(2.0, zoom)
        let x = (c.longitude + 180) / 360 * n
        let lat = min(85.0511, max(-85.0511, c.latitude)) * Double.pi / 180
        let y = (1 - log(tan(lat) + 1 / cos(lat)) / Double.pi) / 2 * n
        return (x, y)
    }

    static func draw(_ vp: VMapViewport, in cg: CGContext, store: VectorTileStore = VectorTileStore.shared) {
        let pal = vp.night ? MapPalette.night : MapPalette.day
        cg.saveGState()
        cg.clip(to: vp.rect)
        cg.setFillColor(pal.background.cgColor)
        cg.fill(vp.rect)

        let tilePx = 256.0 * pow(2.0, vp.zoom - 14)
        let (cx, cy) = mercator(vp.center, zoom: vp.zoom)
        let rad = Double(hypot(vp.rect.width, vp.rect.height))
        let x0 = Int(floor((cx - rad) / tilePx))
        let x1 = Int(floor((cx + rad) / tilePx))
        let y0 = Int(floor((cy - rad) / tilePx))
        let y1 = Int(floor((cy + rad) / tilePx))
        if x1 - x0 > 6 || y1 - y0 > 6 {
            cg.restoreGState()
            return
        }

        let fx = vp.rect.minX + vp.anchor.x
        let fy = vp.rect.minY + vp.anchor.y
        let rot = CGFloat(-vp.bearing * Double.pi / 180)
        let s = CGFloat(tilePx / 4096.0)
        let n = 1 << 14

        var items = [(tile: VTile, t: CGAffineTransform)]()
        for ty in (y0 - 1)...(y1 + 1) {
            for tx in (x0 - 1)...(x1 + 1) {
                if tx < 0 || ty < 0 || tx >= n || ty >= n { continue }
                guard let tile = store.tile(tx, ty) else { continue }
                if tx < x0 || tx > x1 || ty < y0 || ty > y1 { continue }
                var t = CGAffineTransform(translationX: fx, y: fy)
                t = t.rotated(by: rot)
                t = t.translatedBy(x: CGFloat(Double(tx) * tilePx - cx), y: CGFloat(Double(ty) * tilePx - cy))
                t = t.scaledBy(x: s, y: s)
                items.append((tile, t))
            }
        }

        let zf = CGFloat(max(0.5, min(2.0, pow(2.0, (vp.zoom - 17) * 0.55))))

        // 1. area
        for kind in FillKind.allCases {
            guard let color = pal.fills[kind] else { continue }
            cg.setFillColor(color.cgColor)
            for it in items {
                guard let p = it.tile.fills[kind.rawValue] else { continue }
                cg.saveGState()
                cg.concatenate(it.t)
                cg.addPath(p)
                cg.fillPath(using: .evenOdd)
                cg.restoreGState()
            }
        }
        if vp.zoom >= 16.2 {
            let buildingKey = FillKind.building.rawValue
            cg.setStrokeColor(pal.buildingLine.cgColor)
            for it in items {
                guard let p = it.tile.fills[buildingKey] else { continue }
                cg.saveGState()
                cg.concatenate(it.t)
                cg.setLineWidth(1 / s)
                cg.addPath(p)
                cg.strokePath()
                cg.restoreGState()
            }
        }

        // 2. sungai
        cg.setStrokeColor(pal.water.cgColor)
        for it in items {
            guard let p = it.tile.lines[LineKind.waterway.rawValue] else { continue }
            cg.saveGState()
            cg.concatenate(it.t)
            cg.setLineWidth(2.5 * zf / s)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(p)
            cg.strokePath()
            cg.restoreGState()
        }

        // 3. jalan: rel, jalan setapak, lalu per kelas (selubung lalu isi)
        let widths: [LineKind: CGFloat] = [.service: 3.2, .minor: 5.0, .tertiary: 6.0, .secondary: 7.5,
                                           .primary: 9.0, .trunk: 10.5, .motorway: 11.0]
        func stroke(_ kind: LineKind, color: UIColor, width: CGFloat, dash: [CGFloat]? = nil) {
            cg.setStrokeColor(color.cgColor)
            for it in items {
                guard let p = it.tile.lines[kind.rawValue] else { continue }
                cg.saveGState()
                cg.concatenate(it.t)
                cg.setLineWidth(width / s)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                if let d = dash { cg.setLineDash(phase: 0, lengths: d.map { $0 / s }) }
                cg.addPath(p)
                cg.strokePath()
                cg.restoreGState()
            }
        }
        if let c = pal.roads[.rail] { stroke(.rail, color: c, width: 1.6 * zf, dash: [5, 4]) }
        if let c = pal.roads[.path] { stroke(.path, color: c, width: 1.6 * zf, dash: [3, 2]) }
        for kind in LineKind.roadOrder {
            guard let w = widths[kind], let c = pal.roads[kind] else { continue }
            stroke(kind, color: pal.casing, width: (w + 2) * zf)
            stroke(kind, color: c, width: w * zf)
        }

        // 4. rute (koordinat layar)
        var base = CGAffineTransform(translationX: fx, y: fy)
        base = base.rotated(by: rot)
        base = base.translatedBy(x: CGFloat(-cx), y: CGFloat(-cy))
        func screen(_ c: CLLocationCoordinate2D) -> CGPoint {
            let (wx, wy) = mercator(c, zoom: vp.zoom)
            return CGPoint(x: CGFloat(wx), y: CGFloat(wy)).applying(base)
        }
        if vp.route.count >= 2 {
            let path = UIBezierPath()
            for (i, c) in vp.route.enumerated() {
                let pt = screen(c)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if vp.routeBorder > 0 {
                UIColor.white.setStroke()
                path.lineWidth = vp.routeWidth + vp.routeBorder * 2
                path.stroke()
            }
            vp.routeColor.setStroke()
            path.lineWidth = vp.routeWidth
            path.stroke()
        }

        // 5. SPBU
        for it in items {
            for f in it.tile.fuel {
                let pt = f.applying(it.t)
                if !vp.rect.contains(pt) { continue }
                let dot = UIBezierPath(arcCenter: pt, radius: 6, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
                UIColor(red: 0.98, green: 0.55, blue: 0.1, alpha: 1).setFill()
                dot.fill()
                UIColor.white.setStroke()
                dot.lineWidth = 1.5
                dot.stroke()
            }
        }

        // 6. tujuan
        if let d = vp.destination {
            let pt = screen(d)
            let dot = UIBezierPath(arcCenter: pt, radius: 9, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            UIColor.systemRed.setFill()
            dot.fill()
            UIColor.white.setStroke()
            dot.lineWidth = 3
            dot.stroke()
        }

        // 7. label
        let halo = pal.halo
        var used = [CGRect]()
        let placeAttrs: (CGFloat) -> [NSAttributedString.Key: Any] = { size in
            [.font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: pal.text,
             .strokeColor: halo, .strokeWidth: -3.0]
        }
        for it in items {
            for pl in it.tile.places {
                let size: CGFloat
                switch pl.cls {
                case "city": size = 16
                case "town": size = 14
                case "village", "suburb": size = 12
                default: size = 11
                }
                let pt = pl.p.applying(it.t)
                let attrs = placeAttrs(size)
                let ts = (pl.text as NSString).size(withAttributes: attrs)
                let box = CGRect(x: pt.x - ts.width / 2, y: pt.y - ts.height / 2, width: ts.width, height: ts.height)
                if !vp.rect.insetBy(dx: 6, dy: 6).contains(CGPoint(x: box.midX, y: box.midY)) { continue }
                if used.contains(where: { $0.intersects(box.insetBy(dx: -3, dy: -2)) }) { continue }
                used.append(box)
                (pl.text as NSString).draw(at: box.origin, withAttributes: attrs)
            }
        }
        let roadAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: pal.text,
            .strokeColor: halo, .strokeWidth: -3.0]
        var roadCount = 0
        for it in items {
            for lb in it.tile.roadLabels {
                if roadCount >= 28 { break }
                let a = lb.a.applying(it.t)
                let b = lb.b.applying(it.t)
                let seg = hypot(b.x - a.x, b.y - a.y)
                let ts = (lb.text as NSString).size(withAttributes: roadAttrs)
                if seg < ts.width * 0.8 { continue }
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if !vp.rect.insetBy(dx: 12, dy: 10).contains(mid) { continue }
                var ang = atan2(b.y - a.y, b.x - a.x)
                if ang > CGFloat.pi / 2 { ang -= CGFloat.pi } else if ang < -CGFloat.pi / 2 { ang += CGFloat.pi }
                let side = max(ts.width, 14)
                let box = CGRect(x: mid.x - side / 2, y: mid.y - side / 2, width: side, height: side)
                if used.contains(where: { $0.intersects(box) }) { continue }
                used.append(box)
                roadCount += 1
                cg.saveGState()
                cg.translateBy(x: mid.x, y: mid.y)
                cg.rotate(by: ang)
                (lb.text as NSString).draw(at: CGPoint(x: -ts.width / 2, y: -ts.height / 2), withAttributes: roadAttrs)
                cg.restoreGState()
            }
        }

        // 8. penanda posisi (ukuran & lingkaran bisa diatur)
        let c = CGPoint(x: fx, y: fy)
        let k = max(0.4, vp.markerScale)
        if vp.markerRing {
            let ring = UIBezierPath(arcCenter: c, radius: 22 * k, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            UIColor.systemBlue.withAlphaComponent(0.18).setFill()
            ring.fill()
            UIColor.systemBlue.withAlphaComponent(0.55).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
        let p = UIBezierPath()
        p.move(to: CGPoint(x: c.x, y: c.y - 16 * k))
        p.addLine(to: CGPoint(x: c.x + 11 * k, y: c.y + 12 * k))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 6 * k))
        p.addLine(to: CGPoint(x: c.x - 11 * k, y: c.y + 12 * k))
        p.close()
        UIColor.systemBlue.setFill()
        p.fill()
        UIColor.white.setStroke()
        p.lineWidth = 2
        p.stroke()

        cg.restoreGState()
    }
}
