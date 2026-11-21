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

    /// Server Overpass (gratis). Dicoba berurutan: bila satu sibuk/lambat/error, lanjut ke server berikutnya.
    private static let overpassServers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    /// SPBU (amenity=fuel) terdekat lewat Overpass API. Radius diperluas otomatis (radius -> 10 km -> 25 km)
    /// bila belum ada hasil, dan server cadangan dipakai bila server utama sibuk. Melempar error hanya bila
    /// semua server gagal (supaya tampilan bisa membedakan "server sibuk" dari "memang tidak ada SPBU").
    static func fuelStations(near: CLLocationCoordinate2D, radius: Int) async throws -> [Place] {
        var lastError: Error = URLError(.cannotConnectToHost)
        var reachedServer = false
        for r in [radius, max(radius, 10000), max(radius, 25000)] {
            do {
                let res = try await queryFuel(near: near, radius: r)
                reachedServer = true
                if !res.isEmpty { return res }
            } catch {
                lastError = error
                break
            }
        }
        if reachedServer { return [] }
        throw lastError
    }

    private static func queryFuel(near: CLLocationCoordinate2D, radius: Int) async throws -> [Place] {
        let lat = near.latitude
        let lon = near.longitude
        let ql = "[out:json][timeout:20];(node[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon));way[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon)););out center 60;"
        let enc = ql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let body = ("data=" + enc).data(using: .utf8)

        var lastError: Error = URLError(.cannotConnectToHost)
        for server in overpassServers {
            guard let url = URL(string: server) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("XConnect/0.1 (personal navigation app; iOS)", forHTTPHeaderField: "User-Agent")
            req.httpBody = body
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                // 429 / 5xx = server sibuk -> coba server berikutnya
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                // server sibuk kadang membalas HTML atau JSON dengan "remark" tanpa elemen
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let els = obj["elements"] as? [[String: Any]] else {
                    lastError = URLError(.cannotParseResponse)
                    continue
                }
                if els.isEmpty, let remark = obj["remark"] as? String, remark.lowercased().contains("error") || remark.lowercased().contains("timed out") {
                    lastError = URLError(.timedOut)
                    continue
                }
                return parseFuel(els, near: near)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func parseFuel(_ els: [[String: Any]], near: CLLocationCoordinate2D) -> [Place] {
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
