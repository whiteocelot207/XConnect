import Foundation
import CoreLocation

enum Geo {
    static let earthR = 6_371_000.0

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * Double.pi / 180
        let p2 = b.latitude * Double.pi / 180
        let dp = p2 - p1
        let dl = (b.longitude - a.longitude) * Double.pi / 180
        let s1 = sin(dp / 2)
        let s2 = sin(dl / 2)
        let h = s1 * s1 + cos(p1) * cos(p2) * s2 * s2
        return 2 * earthR * asin(min(1.0, h.squareRoot()))
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * Double.pi / 180
        let p2 = b.latitude * Double.pi / 180
        let dl = (b.longitude - a.longitude) * Double.pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / Double.pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    static func destination(from a: CLLocationCoordinate2D, bearing deg: Double, meters d: Double) -> CLLocationCoordinate2D {
        let br = deg * Double.pi / 180
        let p1 = a.latitude * Double.pi / 180
        let l1 = a.longitude * Double.pi / 180
        let ang = d / earthR
        let p2 = asin(sin(p1) * cos(ang) + cos(p1) * sin(ang) * cos(br))
        let l2 = l1 + atan2(sin(br) * sin(ang) * cos(p1), cos(ang) - sin(p1) * sin(p2))
        return CLLocationCoordinate2D(latitude: p2 * 180 / Double.pi, longitude: l2 * 180 / Double.pi)
    }

    /// Proyeksi titik p ke segmen a-b (bidang lokal, meter). t = posisi 0...1 pada segmen.
    static func project(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> (t: Double, dist: Double) {
        let k = Double.pi / 180 * earthR
        let cl = cos(a.latitude * Double.pi / 180)
        let bx = (b.longitude - a.longitude) * cl * k
        let by = (b.latitude - a.latitude) * k
        let px = (p.longitude - a.longitude) * cl * k
        let py = (p.latitude - a.latitude) * k
        let l2 = bx * bx + by * by
        var t = l2 > 0 ? (px * bx + py * by) / l2 : 0
        t = max(0, min(1, t))
        let dx = px - t * bx
        let dy = py - t * by
        return (t, (dx * dx + dy * dy).squareRoot())
    }

    /// Google polyline; Valhalla memakai presisi 6 (1e6).
    static func decodePolyline(_ s: String, precision: Double = 1e6) -> [CLLocationCoordinate2D] {
        let b = Array(s.utf8)
        var i = 0
        var lat = 0
        var lon = 0
        var out = [CLLocationCoordinate2D]()

        func nextValue() -> Int? {
            var result = 0
            var shift = 0
            while i < b.count {
                let c = Int(b[i]) - 63
                i += 1
                result |= (c & 0x1F) << shift
                shift += 5
                if c < 0x20 {
                    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
                }
            }
            return nil
        }

        while i < b.count {
            guard let dlat = nextValue(), let dlon = nextValue() else { break }
            lat += dlat
            lon += dlon
            out.append(CLLocationCoordinate2D(latitude: Double(lat) / precision, longitude: Double(lon) / precision))
        }
        return out
    }

    /// Dash hanya menerima ASCII: buang diakritik dan karakter non-ASCII.
    static func ascii(_ s: String, maxLen: Int) -> String {
        let folded = s.folding(options: [.diacriticInsensitive], locale: nil)
        var out = ""
        for u in folded.unicodeScalars where u.value >= 32 && u.value < 127 {
            out.unicodeScalars.append(u)
        }
        return String(out.prefix(maxLen))
    }
}
