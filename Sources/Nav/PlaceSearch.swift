import Foundation
import CoreLocation

enum PlaceSearch {
    /// Photon (OpenStreetMap), dibatasi ke Indonesia. Gratis, untuk pemakaian ringan.
    static func search(_ q: String, near: CLLocationCoordinate2D) async throws -> [Place] {
        var c = URLComponents(string: "https://photon.komoot.io/api/")!
        c.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "lat", value: String(near.latitude)),
            URLQueryItem(name: "lon", value: String(near.longitude)),
            URLQueryItem(name: "bbox", value: "95.0,-11.5,141.5,6.5")
        ]
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("XConnect/0.2 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feats = obj["features"] as? [[String: Any]] else { return [] }

        var out = [Place]()
        for f in feats {
            guard let geom = f["geometry"] as? [String: Any],
                  let coords = geom["coordinates"] as? [Double], coords.count >= 2,
                  let props = f["properties"] as? [String: Any] else { continue }
            let street = props["street"] as? String
            let name = (props["name"] as? String) ?? street ?? tr("Unnamed")
            var parts = [String]()
            if let st = street, st != name { parts.append(st) }
            for key in ["district", "city", "state"] {
                if let v = props[key] as? String, !parts.contains(v), v != name { parts.append(v) }
            }
            out.append(Place(name: name, subtitle: parts.joined(separator: ", "),
                             lat: coords[1], lon: coords[0]))
        }
        return out
    }

    /// SPBU (amenity=fuel) dalam radius tertentu lewat Overpass API (gratis, pakai wajar).
    static func fuelStations(near: CLLocationCoordinate2D, radius: Int) async throws -> [Place] {
        let lat = near.latitude
        let lon = near.longitude
        let ql = "[out:json][timeout:15];(node[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon));way[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon)););out center 60;"
        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XConnect/0.2 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        let enc = ql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        req.httpBody = ("data=" + enc).data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let els = obj["elements"] as? [[String: Any]] else { return [] }

        var items = [(Place, Double)]()
        for e in els {
            var plat = e["lat"] as? Double
            var plon = e["lon"] as? Double
            if plat == nil, let c = e["center"] as? [String: Any] {
                plat = c["lat"] as? Double
                plon = c["lon"] as? Double
            }
            guard let la = plat, let lo = plon else { continue }
            let tags = (e["tags"] as? [String: Any]) ?? [:]
            let name = (tags["name"] as? String) ?? (tags["brand"] as? String)
                ?? (tags["operator"] as? String) ?? tr("Gas station")
            let street = (tags["addr:street"] as? String) ?? ""
            let d = Geo.distance(near, CLLocationCoordinate2D(latitude: la, longitude: lo))
            let sub = street.isEmpty ? tr("Gas station") : tr("Gas station, ") + street
            items.append((Place(name: name, subtitle: sub, lat: la, lon: lo), d))
        }
        items.sort { $0.1 < $1.1 }
        return items.prefix(30).map { $0.0 }
    }
}
