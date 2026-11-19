import Foundation
import CoreLocation
import MapKit

/// Routing lewat Apple MapKit (MKDirections). Hasilnya diubah ke struktur Route/Maneuver yang sama dengan Valhalla,
/// jadi dash, suara, dan peta tidak perlu tahu sumbernya.
/// Penyesuaian untuk motor: tol dan jalan bebas hambatan dihindari, dan estimasi waktu dibatasi batas kecepatan maksimal.
/// Batasan MapKit: tetap rute mobil (tanpa profil skuter/motor), tanpa heading, dan tanpa slider jalan utama/tanjakan/gang.
/// Jam tiba sudah memperhitungkan lalu lintas.
enum MapKitRouter {
    static func routes(costing: String, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                       alternatives: Int, profile: RouteProfile) async throws -> [Route] {
        let isMotor = costing != "auto"
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.transportType = .automobile
        req.requestsAlternateRoutes = alternatives > 0
        req.departureDate = Date()
        if #available(iOS 16.0, *) {
            // Skuter/motor: tol dan jalan bebas hambatan selalu dihindari (motor tidak boleh masuk tol di Indonesia).
            // Mobil: ikut pengaturan.
            req.tollPreference = (isMotor || profile.avoidTolls) ? .avoid : .any
            req.highwayPreference = (isMotor || profile.highways < 0.3) ? .avoid : .any
        }

        let response: MKDirections.Response = try await withCheckedThrowingContinuation { cont in
            MKDirections(request: req).calculate { resp, err in
                if let resp = resp {
                    cont.resume(returning: resp)
                } else {
                    cont.resume(throwing: RouteError.server(err?.localizedDescription ?? "Apple Maps tidak memberi rute"))
                }
            }
        }

        var out = [Route]()
        for r in response.routes.prefix(1 + max(0, min(alternatives, 2))) {
            if let route = build(r, topSpeedKmh: profile.topSpeed) { out.append(route) }
        }
        guard !out.isEmpty else { throw RouteError.empty }
        out.sort { $0.totalS < $1.totalS }
        return out
    }

    private static func coords(_ poly: MKPolyline) -> [CLLocationCoordinate2D] {
        let n = poly.pointCount
        guard n > 0 else { return [] }
        var arr = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
        poly.getCoordinates(&arr, range: NSRange(location: 0, length: n))
        return arr
    }

    private static func build(_ r: MKRoute, topSpeedKmh: Int) -> Route? {
        // Titik rute disusun dari polyline tiap langkah supaya indeks belokan pasti cocok dengan titiknya.
        var pts = [CLLocationCoordinate2D]()
        var stepStart = [Int]()
        for s in r.steps {
            let c = coords(s.polyline)
            if c.isEmpty { stepStart.append(max(0, pts.count - 1)); continue }
            if pts.isEmpty {
                stepStart.append(0)
                pts.append(contentsOf: c)
            } else {
                stepStart.append(pts.count - 1)   // langkah baru mulai di titik terakhir langkah sebelumnya
                pts.append(contentsOf: c.dropFirst())
            }
        }
        guard pts.count >= 2 else { return nil }

        var cum = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count { cum[i] = cum[i - 1] + Geo.distance(pts[i - 1], pts[i]) }

        var mans = [Maneuver]()
        var longest = 0.0
        var via = ""
        for (k, s) in r.steps.enumerated() {
            let text = s.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let begin = min(max(0, stepStart[k]), pts.count - 1)
            let isLast = k == r.steps.count - 1
            if text.isEmpty { continue }      // langkah pertama biasanya kosong
            let street = streetName(from: text)
            let (type, exitNo) = classify(text: text, pts: pts, begin: begin, isLast: isLast)
            mans.append(Maneuver(type: type, instruction: text, street: street, lengthM: s.distance,
                                 beginIdx: begin, exitCount: exitNo, verbal: text))
            if !street.isEmpty, s.distance > longest { longest = s.distance; via = street }
        }
        // pastikan ada penanda tiba di ujung rute
        if mans.last.map({ $0.type != 4 && $0.type != 5 && $0.type != 6 }) ?? true {
            mans.append(Maneuver(type: 4, instruction: "", street: "", lengthM: 0, beginIdx: pts.count - 1))
        }
        // Batas kecepatan maksimal (Pengaturan): bila rata-rata Apple lebih cepat dari batas itu, waktu dilebarkan
        // sampai rata-ratanya sama dengan batas, supaya estimasi mendekati motor.
        let totalM = cum[cum.count - 1]
        let capS = totalM / (Double(min(max(topSpeedKmh, 20), 120)) / 3.6)
        var route = Route(points: pts, cum: cum, maneuvers: mans,
                          totalM: totalM, totalS: max(1, r.expectedTravelTime, capS))
        route.via = via
        return route
    }

    /// Nama jalan dari kalimat petunjuk Apple (bahasa mengikuti ponsel): "Belok kanan ke Jalan X", "Turn right onto X".
    private static func streetName(from text: String) -> String {
        let patterns = [" ke ", " onto ", " menuju ", " toward ", " towards ", " into ", " on ", " di "]
        let lower = text.lowercased()
        // ambil kata sambung yang paling awal muncul, supaya "Ke" di dalam nama jalan tidak salah dipotong
        var best: Range<String.Index>? = nil
        for p in patterns {
            if let r = lower.range(of: p), best == nil || r.lowerBound < best!.lowerBound { best = r }
        }
        guard let r = best else { return "" }
        let idx = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: r.upperBound))
        var s = String(text[idx...]).trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        if let cut = s.range(of: ", ") { s = String(s[..<cut.lowerBound]) }
        let skip = ["kanan", "kiri", "right", "left", "bundaran", "the roundabout", "tujuan"]
        return (s.isEmpty || skip.contains(s.lowercased())) ? "" : s
    }

    /// Tipe maneuver ala Valhalla. Dasarnya sudut belok dari geometri; teks dipakai untuk bundaran, putar balik, dan tiba.
    private static func classify(text: String, pts: [CLLocationCoordinate2D], begin: Int, isLast: Bool) -> (Int, Int) {
        let t = text.lowercased()
        let right = t.contains("kanan") || t.contains("right")
        let left = t.contains("kiri") || t.contains("left")

        if isLast || t.contains("tiba") || t.contains("arrive") || t.contains("destination") || t.contains("tujuan anda") {
            return (right && !left ? 5 : (left && !right ? 6 : 4), 0)
        }
        if t.contains("bundaran") || t.contains("roundabout") || t.contains("rotary") || t.contains("traffic circle") {
            return (26, exitNumber(t))
        }
        if t.contains("putar balik") || t.contains("u-turn") || t.contains("make a u") {
            return (left && !right ? 13 : 12, 0)
        }
        if t.contains("bergabung") || t.contains("merge") {
            return (left && !right ? 38 : (right && !left ? 37 : 25), 0)
        }
        if t.contains("jalan keluar") || t.contains("take the exit") || t.contains("exit") || t.contains("ramp") {
            return (left && !right ? 21 : 20, 0)
        }
        // sudut belok dari geometri (+ = kanan/searah jarum jam)
        guard begin > 0, begin < pts.count - 1 else {
            return (right && !left ? 10 : (left && !right ? 15 : 8), 0)
        }
        let inB = Geo.bearing(from: backPoint(pts, begin), to: pts[begin])
        let outB = Geo.bearing(from: pts[begin], to: forwardPoint(pts, begin))
        var d = outB - inB
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        let ad = abs(d)
        if ad < 20 { return (8, 0) }
        let isR = d > 0
        if ad < 60 { return (isR ? 9 : 16, 0) }
        if ad < 125 { return (isR ? 10 : 15, 0) }
        if ad < 160 { return (isR ? 11 : 14, 0) }
        return (isR ? 12 : 13, 0)
    }

    /// Titik sekitar 25 m sebelum belokan (arah datang).
    private static func backPoint(_ pts: [CLLocationCoordinate2D], _ i: Int) -> CLLocationCoordinate2D {
        var j = i - 1, d = 0.0
        while j > 0, d < 25 { d += Geo.distance(pts[j], pts[j + 1]); j -= 1 }
        return pts[max(0, j)]
    }

    /// Titik sekitar 25 m sesudah belokan (arah pergi).
    private static func forwardPoint(_ pts: [CLLocationCoordinate2D], _ i: Int) -> CLLocationCoordinate2D {
        var j = i + 1, d = 0.0
        while j < pts.count - 1, d < 25 { d += Geo.distance(pts[j - 1], pts[j]); j += 1 }
        return pts[min(pts.count - 1, j)]
    }

    /// Nomor jalan keluar bundaran: "ambil jalan keluar ke-3", "take the 3rd exit".
    private static func exitNumber(_ t: String) -> Int {
        let words: [(String, Int)] = [("pertama", 1), ("kedua", 2), ("ketiga", 3), ("keempat", 4), ("kelima", 5),
                                      ("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("fifth", 5)]
        for (w, n) in words where t.contains(w) { return n }
        let digits = t.split(whereSeparator: { !$0.isNumber })
        if let f = digits.first, let n = Int(f), (1...9).contains(n) { return n }
        return 0
    }
}
