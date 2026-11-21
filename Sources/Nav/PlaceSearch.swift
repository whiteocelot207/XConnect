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

    /// Server Overpass (gratis). Semuanya ditanya BERSAMAAN dan yang menjawab lebih dulu dipakai, jadi satu server
    /// yang sibuk/lambat tidak membuat pencarian menunggu lama.
    private static let overpassServers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    // MARK: Cache SPBU (supaya dash dan daftar di app langsung terisi)

    private static var fuelCache: (lat: Double, lon: Double, at: Date, places: [Place])?
    private static let cacheLock = NSLock()

    /// Hasil terakhir bila masih segar (maks `maxAge` detik) dan lokasinya masih dekat (maks `maxMeters`).
    static func cachedFuel(near: CLLocationCoordinate2D, maxAge: TimeInterval = 900, maxMeters: Double = 1500) -> [Place]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard let c = fuelCache, !c.places.isEmpty, Date().timeIntervalSince(c.at) < maxAge,
              Geo.distance(near, CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)) < maxMeters else { return nil }
        return c.places
    }

    /// Cadangan bila server gagal: hasil lama (maks 6 jam, maks 30 km dari lokasi sekarang).
    static func staleFuel(near: CLLocationCoordinate2D) -> [Place]? {
        cachedFuel(near: near, maxAge: 6 * 3600, maxMeters: 30000)
    }

    private static func storeFuel(_ places: [Place], near: CLLocationCoordinate2D) {
        guard !places.isEmpty else { return }
        cacheLock.lock(); defer { cacheLock.unlock() }
        fuelCache = (near.latitude, near.longitude, Date(), places)
    }

    /// SPBU (amenity=fuel) terdekat lewat Overpass API. Mulai dari `radius`; bila kosong diperluas ke 15 km.
    /// Melempar error hanya bila semua server gagal (agar tampilan bisa membedakan "server sibuk" dari "tidak ada SPBU").
    static func fuelStations(near: CLLocationCoordinate2D, radius: Int) async throws -> [Place] {
        var reachedServer = false
        var lastError: Error = URLError(.cannotConnectToHost)
        for r in [radius, max(radius, 15000)] {
            do {
                let res = try await queryFuel(near: near, radius: r)
                reachedServer = true
                if !res.isEmpty {
                    storeFuel(res, near: near)
                    return res
                }
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
        let ql = "[out:json][timeout:9];(node[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon));way[\"amenity\"=\"fuel\"](around:\(radius),\(lat),\(lon)););out center 40;"
        let enc = ql.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let body = ("data=" + enc).data(using: .utf8)

        return try await withThrowingTaskGroup(of: [Place].self, returning: [Place].self) { group in
            for server in overpassServers {
                group.addTask { try await PlaceSearch.fetchFuel(server: server, body: body, near: near) }
            }
            var lastError: Error = URLError(.cannotConnectToHost)
            while true {
                do {
                    if let r = try await group.next() {
                        group.cancelAll()
                        return r
                    }
                    break
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    private static func fetchFuel(server: String, body: Data?, near: CLLocationCoordinate2D) async throws -> [Place] {
        guard let url = URL(string: server) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("XConnect/0.1 (personal navigation app; iOS)", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        // 429 / 5xx = server sibuk
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let els = obj["elements"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        // server kewalahan kadang membalas elemen kosong + "remark" berisi error
        if els.isEmpty, let remark = (obj["remark"] as? String)?.lowercased(),
           remark.contains("error") || remark.contains("timed out") || remark.contains("out of memory") {
            throw URLError(.timedOut)
        }
        return PlaceSearch.parseFuel(els, near: near)
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
