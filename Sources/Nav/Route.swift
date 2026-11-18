import Foundation
import CoreLocation

struct Maneuver {
    let type: Int
    let instruction: String
    let street: String
    let lengthM: Double
    let beginIdx: Int
}

struct Route {
    let points: [CLLocationCoordinate2D]
    let cum: [Double]          // jarak kumulatif (m) di tiap titik
    let maneuvers: [Maneuver]
    let totalM: Double
    let totalS: Double
    /// nama jalan utama rute (untuk membedakan alternatif)
    var via: String = ""
}

enum RouteError: LocalizedError {
    case badURL
    case server(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "Alamat server routing tidak valid"
        case .server(let m): return "Server routing: \(m)"
        case .empty: return "Rute tidak ditemukan"
        }
    }
}

enum DashIcon {
    /// Tipe maneuver Valhalla -> kode ikon panah dash (docs/bike-protocol.md 3.3).
    static func forValhalla(_ t: Int) -> UInt8 {
        switch t {
        case 4: return 0                 // tiba
        case 5: return 2                 // tiba di kanan
        case 6: return 1                 // tiba di kiri
        case 9, 23, 37: return 7         // serong kanan / tetap kanan
        case 16, 24, 38: return 6        // serong kiri / tetap kiri
        case 10, 18, 20: return 35       // belok kanan, ramp/keluar kanan
        case 15, 19, 21: return 34       // belok kiri, ramp/keluar kiri
        case 11: return 33               // tajam kanan
        case 14: return 32               // tajam kiri
        case 12: return 37               // putar balik kanan
        case 13: return 36               // putar balik kiri
        case 26, 27: return 14           // bundaran
        default: return 8                // lurus
        }
    }

    /// Teks pendek untuk banner belok di dash.
    static func shortText(_ code: UInt8) -> String {
        switch code {
        case 0: return "Tiba di tujuan"
        case 1: return "Tujuan di kiri"
        case 2: return "Tujuan di kanan"
        case 6: return "Serong kiri"
        case 7: return "Serong kanan"
        case 32: return "Belok kiri tajam"
        case 33: return "Belok kanan tajam"
        case 34: return "Belok kiri"
        case 35: return "Belok kanan"
        case 36, 37: return "Putar balik"
        case 14: return "Bundaran"
        default: return "Lurus"
        }
    }

    /// Nama SF Symbol untuk tampilan di ponsel.
    static func symbol(_ t: Int) -> String {
        switch t {
        case 4, 5, 6: return "flag.checkered"
        case 9, 23, 37: return "arrow.up.right"
        case 16, 24, 38: return "arrow.up.left"
        case 10, 18, 20, 11: return "arrow.turn.up.right"
        case 15, 19, 21, 14: return "arrow.turn.up.left"
        case 12: return "arrow.uturn.right"
        case 13: return "arrow.uturn.left"
        case 26, 27: return "arrow.triangle.2.circlepath"
        default: return "arrow.up"
        }
    }
}

private struct VResponse: Decodable {
    struct Trip: Decodable {
        struct Leg: Decodable {
            struct Man: Decodable {
                let type: Int
                let instruction: String?
                let street_names: [String]?
                let length: Double
                let time: Double
                let begin_shape_index: Int
            }
            let shape: String
            let maneuvers: [Man]
        }
        struct Summary: Decodable {
            let length: Double
            let time: Double
        }
        let legs: [Leg]
        let summary: Summary
    }
    struct Alt: Decodable {
        let trip: Trip
    }
    let trip: Trip
    let alternates: [Alt]?
}

enum ValhallaClient {
    /// Rute tercepat (indeks 0) diikuti alternatif bila ada (maks 2).
    static func routes(base: String, costing: String, from: CLLocationCoordinate2D,
                       to: CLLocationCoordinate2D, heading: Double?, alternatives: Int) async throws -> [Route] {
        let trimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: trimmed + "/route") else { throw RouteError.badURL }

        var start: [String: Any] = ["lat": from.latitude, "lon": from.longitude, "type": "break"]
        if let h = heading {
            start["heading"] = Int(h.rounded())
            start["heading_tolerance"] = 45
        }
        let end: [String: Any] = ["lat": to.latitude, "lon": to.longitude, "type": "break"]
        let locations: [[String: Any]] = [start, end]
        let opts: [String: Any] = ["units": "kilometers", "language": "id-ID"]
        var body: [String: Any] = ["locations": locations, "costing": costing, "directions_options": opts]
        if alternatives > 0 { body["alternates"] = alternatives }

        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("XConnect/0.6 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            var msg = "HTTP \(http.statusCode)"
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = o["error"] as? String {
                msg += " - \(e)"
            }
            throw RouteError.server(msg)
        }

        let r = try JSONDecoder().decode(VResponse.self, from: data)
        var trips = [r.trip]
        for a in r.alternates ?? [] { trips.append(a.trip) }
        var out = [Route]()
        for t in trips {
            if let route = build(t) { out.append(route) }
        }
        guard !out.isEmpty else { throw RouteError.empty }
        // urutkan: tercepat dulu (untuk motor), alternatif sesudahnya
        out.sort { $0.totalS < $1.totalS }
        return out
    }

    private static func build(_ trip: VResponse.Trip) -> Route? {
        guard let leg = trip.legs.first else { return nil }
        let pts = Geo.decodePolyline(leg.shape)
        guard pts.count >= 2 else { return nil }

        var cum = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            cum[i] = cum[i - 1] + Geo.distance(pts[i - 1], pts[i])
        }
        var mans = [Maneuver]()
        var longest = 0.0
        var via = ""
        for m in leg.maneuvers {
            let street = m.street_names?.first ?? ""
            mans.append(Maneuver(type: m.type,
                                 instruction: m.instruction ?? "",
                                 street: street,
                                 lengthM: m.length * 1000,
                                 beginIdx: min(max(0, m.begin_shape_index), pts.count - 1)))
            if !street.isEmpty, m.length > longest { longest = m.length; via = street }
        }
        var route = Route(points: pts, cum: cum, maneuvers: mans,
                          totalM: cum[cum.count - 1], totalS: trip.summary.time)
        route.via = via
        return route
    }

    /// Kompatibel dengan pemanggil lama: hanya rute tercepat.
    static func route(base: String, costing: String, from: CLLocationCoordinate2D,
                      to: CLLocationCoordinate2D, heading: Double?) async throws -> Route {
        let all = try await routes(base: base, costing: costing, from: from, to: to, heading: heading, alternatives: 0)
        return all[0]
    }
}
