import Foundation
import CoreLocation
import MapKit

enum LinkError: LocalizedError {
    case noURL
    case noPlace

    var errorDescription: String? {
        switch self {
        case .noURL: return "Tautan tidak dikenali"
        case .noPlace: return "Lokasi tidak ditemukan di tautan itu" + (MapsLink.debug.isEmpty ? "" : " (\(MapsLink.debug))")
        }
    }
}

/// Membaca tautan Google Maps (termasuk tautan pendek maps.app.goo.gl) dan koordinat polos menjadi tempat.
enum MapsLink {
    /// Info singkat tautan terakhir (host + path) untuk membantu diagnosis bila gagal.
    static var debug = ""

    static func isLikely(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("http") && (t.contains("goo.gl") || t.contains("google.") || t.contains("maps")) { return true }
        if t.hasPrefix("geo:") { return true }
        return parseCoordinatePair(text) != nil
    }

    static func resolve(_ input: String, near: CLLocationCoordinate2D) async throws -> Place {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = parseCoordinatePair(raw) {
            return Place(name: "Titik dari tautan", subtitle: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                         lat: c.latitude, lon: c.longitude)
        }
        if raw.lowercased().hasPrefix("geo:"), let c = parseCoordinatePair(String(raw.dropFirst(4))) {
            return Place(name: "Titik dari tautan", subtitle: String(format: "%.5f, %.5f", c.latitude, c.longitude),
                         lat: c.latitude, lon: c.longitude)
        }
        guard let url = firstURL(in: raw) else { throw LinkError.noURL }

        let host = (url.host ?? "").lowercased()
        let isShort = host.contains("goo.gl") || host.contains("app.goo")
        let isGoogle = isShort || host.contains("google.")

        func decoded(_ u: URL) -> String {
            let w = unwrapConsent(u).absoluteString
            return w.removingPercentEncoding ?? w
        }
        func hasLocation(_ urls: [String]) -> Bool {
            urls.contains { pinCoordinate(from: $0) != nil || placeCenter(from: $0) != nil }
        }

        var chainURLs = [decoded(url)]      // alamat dari rantai pengalihan (tepercaya)
        var bodyLinks = [String]()          // alamat yang tersembunyi di isi halaman (kurang tepercaya)
        var bodies = [String]()
        var hops = 1
        var failure = ""
        func updateDebug(_ extra: String = "") {
            let last = chainURLs.last.flatMap { URL(string: $0) }
            let lastHost = last.map { "\($0.host ?? "?")\($0.path.prefix(40))" } ?? (url.host ?? "?")
            debug = "\(lastHost) · \(hops) alamat" + (failure.isEmpty ? "" : " · \(failure)") + extra
        }

        // TAHAP CEPAT (seperti NConnect): ikuti pengalihan tautan pendek satu per satu dengan membaca header
        // Location saja, tanpa mengunduh halaman, dan berhenti begitu koordinat terlihat. Biasanya < 1 dtk.
        if isGoogle, !hasLocation(chainURLs) {
            let q = await quickChain(url)
            chainURLs += q.urls.map { decoded($0) }
            hops += q.urls.count
            failure = q.failure
        }
        updateDebug()

        var name = chainURLs.compactMap { placeName(from: $0) }.first
            ?? chainURLs.reversed().compactMap { queryText($0) }.first      // alamat akhir (q=…) paling dipercaya

        func made(_ method: String, _ c: CLLocationCoordinate2D, _ title: String? = nil) -> Place {
            Place(name: title ?? name ?? "Lokasi dari Google Maps",
                  subtitle: "\(method) · garis lurus \(Fmt.distance(Geo.distance(near, c)))",
                  lat: c.latitude, lon: c.longitude)
        }

        // 1) Titik pin tempat (!3d!4d) atau koordinat eksplisit (q=lat,lon, destination=): paling akurat.
        if let c = chainURLs.compactMap({ pinCoordinate(from: $0) }).first { return made("Google Maps", c) }
        // 2) Pusat peta pada tautan /maps/place/…/@lat,lon (umumnya tepat di tempatnya).
        if let c = chainURLs.compactMap({ placeCenter(from: $0) }).first { return made("Google Maps", c) }

        // 3) Tautan hanya memuat nama tempat: cari namanya langsung (Apple + OpenStreetMap berjalan bersamaan)
        //    dan terima bila namanya cocok hampir seluruhnya. Ini yang membuat tautan "Bagikan" dari app Google Maps cepat.
        if isGoogle, let n = name, let hit = await geocodeText(n, near: near, fast: true) {
            return Place(name: hit.name,
                         subtitle: "\(hit.source) (dari nama) · garis lurus \(Fmt.distance(Geo.distance(near, hit.coord)))",
                         lat: hit.coord.latitude, lon: hit.coord.longitude)
        }

        // ---- CARA LAMBAT: hanya dipakai bila cara cepat tidak menghasilkan titik yang meyakinkan ----

        // 4) Unduh halaman (peramban PC, lalu peramban iPhone untuk tautan pendek) dan baca alamat/isinya.
        if isGoogle {
            let agents = isShort ? [desktopUA, mobileUA] : [desktopUA]
            for ua in agents {
                do {
                    let r = try await follow(url, ua: ua)
                    let ch = r.chain.map { decoded($0) }       // halaman persetujuan Google membungkus tautan asli
                    chainURLs += ch
                    hops += ch.count
                    bodyLinks += linksInBody(r.body)
                    bodies.append(r.body)
                    if hasLocation(ch) { break }
                } catch {
                    failure = error.localizedDescription
                }
            }
            updateDebug()
            if name == nil {
                name = chainURLs.compactMap { placeName(from: $0) }.first
                    ?? chainURLs.reversed().compactMap { queryText($0) }.first
            }
            if let c = chainURLs.compactMap({ pinCoordinate(from: $0) }).first { return made("Google Maps", c) }
            if let c = chainURLs.compactMap({ placeCenter(from: $0) }).first { return made("Google Maps", c) }
        }
        name = name ?? bodyLinks.compactMap { placeName(from: $0) }.first ?? bodies.compactMap { ogTitle($0) }.first

        // 5) Buka seperti peramban PC (WKWebView tersembunyi) dan tangkap perubahan alamat yang dibuat
        //    JavaScript Google: ?q=…&ftid=… berubah menjadi /maps/place/NAMA/@lat,lon/data=…!3d…!4d….
        if isGoogle {
            let web = await MapsWebResolver.run(url, ua: desktopUA)
            let wurls = web.urls.map { unwrapConsent(URL(string: $0) ?? url).absoluteString.removingPercentEncoding ?? $0 }
            chainURLs += web.urls + wurls
            bodies.append(web.html)
            updateDebug(" · web \(web.urls.count) alamat")
            if let n = web.urls.compactMap({ placeName(from: $0) }).first { name = n }
            if let c = web.urls.compactMap({ pinCoordinate(from: $0) }).first { return made("Google Maps (peramban)", c) }
            if let c = web.urls.compactMap({ placeCenter(from: $0) }).first { return made("Google Maps (peramban)", c) }
        }
        // 6) ID tempat (ftid / cid) dibuka lewat maps.google.com/?cid=
        if let cid = cidDecimal(in: chainURLs + bodyLinks + bodies),
           let u = URL(string: "https://maps.google.com/?cid=\(cid)"),
           let r = try? await follow(u, ua: desktopUA) {
            let urls = r.chain.map { unwrapConsent($0) }.map { $0.absoluteString.removingPercentEncoding ?? $0.absoluteString }
            if let c = urls.compactMap({ pinCoordinate(from: $0) }).first ?? urls.compactMap({ placeCenter(from: $0) }).first {
                return made("Google Maps (ID tempat)", c)
            }
        }
        // 7) Pencarian nama dengan syarat lebih longgar (skor ≥ 0,5) dan cadangan geocoder alamat.
        if let n = name, let hit = await geocodeText(n, near: near, fast: false) {
            return Place(name: hit.name, subtitle: "\(hit.source) · garis lurus \(Fmt.distance(Geo.distance(near, hit.coord)))",
                         lat: hit.coord.latitude, lon: hit.coord.longitude)
        }
        // 8) Terakhir: tebakan dari isi halaman (hanya pusat tampilan peta, bisa jauh). Diberi tanda.
        let weak = bodyLinks.compactMap { pinCoordinate(from: $0) ?? placeCenter(from: $0) }.first
            ?? bodies.compactMap { coordinates(fromBody: $0) }.first
        if let c = weak { return made("Perkiraan, periksa lokasinya", c) }
        throw LinkError.noPlace
    }

    // MARK: - Pengalihan cepat (tanpa mengunduh halaman)

    /// Delegate yang MENOLAK mengikuti pengalihan: tanggapan 30x dikembalikan apa adanya sehingga header
    /// Location bisa dibaca langsung. Tanpa ini URLSession mengikuti semua pengalihan lalu mengunduh halaman Google
    /// yang besar, dan itulah bagian yang lambat.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Mengikuti rantai pengalihan satu per satu (maks. 6 langkah, tiap langkah maks. 6 dtk) dan berhenti begitu
    /// alamat yang sampai sudah memuat koordinat. Isi halaman tidak pernah diunduh.
    private static func quickChain(_ start: URL) async -> (urls: [URL], failure: String) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 10
        let session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var urls = [URL]()
        var current = start
        var failure = ""
        for _ in 0..<6 {
            var req = URLRequest(url: current, timeoutInterval: 6)
            req.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
            req.setValue("id-ID,id;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            req.setValue("CONSENT=YES+cb.20210720-07-p0.id+FX+410", forHTTPHeaderField: "Cookie")
            do {
                // bytes(for:) kembali begitu header diterima; isi halaman dibatalkan, tidak diunduh
                let (bytes, resp) = try await session.bytes(for: req)
                bytes.task.cancel()
                guard let http = resp as? HTTPURLResponse, (300...399).contains(http.statusCode),
                      let loc = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else { break }
                let n = unwrapConsent(next)
                urls.append(n)
                let s = n.absoluteString.removingPercentEncoding ?? n.absoluteString
                if pinCoordinate(from: s) != nil || placeCenter(from: s) != nil { break }
                current = n
            } catch {
                failure = error.localizedDescription
                break
            }
        }
        return (urls, failure)
    }

    // MARK: - Teks → titik

    private struct Hit { let name: String; let coord: CLLocationCoordinate2D; let source: String; let score: Double }

    private static let stopWords: Set<String> = ["pt", "cv", "jl", "jalan", "kec", "kecamatan", "kel", "kab", "kota", "no", "rt", "rw",
                                                  "dan", "the", "and", "of", "di", "lot", "blok"]

    private static func tokens(_ s: String) -> Set<String> {
        let parts = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 2 && !stopWords.contains($0) })
    }

    /// Porsi kata pada `target` yang ditemukan di `candidate` (0...1).
    private static func similarity(_ target: String, _ candidate: String) -> Double {
        let t = tokens(target)
        if t.isEmpty { return 0 }
        return Double(t.intersection(tokens(candidate)).count) / Double(t.count)
    }

    /// `fast` = jalur cepat: hanya diterima bila nama cocok hampir seluruhnya (skor ≥ 0,75), maks. 5 dtk.
    /// Semua pencarian (tiap variasi kata kunci × Apple/OpenStreetMap) berjalan BERSAMAAN dan berhenti begitu ada
    /// yang cukup yakin. Bukan fast: syarat dilonggarkan (≥ 0,5), ditambah cadangan geocoder alamat.
    private static func geocodeText(_ text: String, near: CLLocationCoordinate2D, fast: Bool) async -> Hit? {
        let segs = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let head = segs.first else { return nil }
        let city = segs.count >= 3 ? segs[segs.count - 2] : (segs.count == 2 ? segs[1] : "")
        var queries = [String]()
        func add(_ q: String) { let t = q.trimmingCharacters(in: .whitespaces); if !t.isEmpty && !queries.contains(t) { queries.append(t) } }
        add(city.isEmpty ? head : "\(head) \(city)")
        add(head)
        if segs.count > 1, segs[1] != head { add(city.isEmpty ? segs[1] : "\(segs[1]) \(city)") }
        if segs.count > 3 { add(text) }

        let budget: UInt64 = fast ? 5_000_000_000 : 12_000_000_000
        var all = [Hit]()
        var early: Hit?
        await withTaskGroup(of: (Bool, [Hit]).self, returning: Void.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: budget)
                return (true, [])
            }
            for q in queries {
                group.addTask {
                    async let apple = appleSearch(q, near: near)
                    async let osm = osmSearch(q, near: near)
                    let (a, o) = await (apple, osm)
                    var found = [Hit]()
                    for (title, c, src) in a {
                        found.append(Hit(name: title.0, coord: c, source: src, score: max(similarity(head, title.0), similarity(head, title.1))))
                    }
                    for p in o {
                        let sc = max(similarity(head, p.name), similarity(head, p.name + " " + p.subtitle))
                        found.append(Hit(name: p.name, coord: p.coordinate, source: "OpenStreetMap", score: sc))
                    }
                    return (false, found)
                }
            }
            for await (isTimer, found) in group {
                if isTimer { group.cancelAll(); break }
                all += found
                // cukup yakin: nama cocok hampir seluruhnya
                if let best = pick(found, near: near), best.score >= 0.75 {
                    early = best
                    group.cancelAll()
                    break
                }
            }
        }
        if let e = early { return e }
        if fast { return nil }
        if let best = pick(all, near: near), best.score >= 0.5 { return best }

        // alamat jalan lengkap → geocoder Apple (setidaknya dekat, bukan puluhan km)
        if segs.count >= 3, let marks = try? await CLGeocoder().geocodeAddressString(text),
           let m = marks.first, let loc = m.location {
            return Hit(name: head, coord: loc.coordinate, source: "Alamat (Apple)", score: 0.4)
        }
        return nil
    }

    private static func osmSearch(_ q: String, near: CLLocationCoordinate2D) async -> [Place] {
        (try? await PlaceSearch.search(q, near: near)) ?? []
    }

    /// Skor tertinggi dulu; bila selisih kecil, pilih yang terdekat dari posisi Anda.
    private static func pick(_ hits: [Hit], near: CLLocationCoordinate2D) -> Hit? {
        guard let top = hits.map({ $0.score }).max(), top > 0 else { return nil }
        return hits.filter { $0.score >= top - 0.1 }
            .min { Geo.distance(near, $0.coord) < Geo.distance(near, $1.coord) }
    }

    private static func appleSearch(_ q: String, near: CLLocationCoordinate2D) async -> [((String, String), CLLocationCoordinate2D, String)] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        req.region = MKCoordinateRegion(center: near, span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
        guard let resp = try? await MKLocalSearch(request: req).start() else { return [] }
        return resp.mapItems.prefix(10).map { item in
            ((item.name ?? "", item.placemark.title ?? ""), item.placemark.coordinate, "Apple Maps")
        }
    }

    // MARK: - Alat

    private static func firstURL(in text: String) -> URL? {
        if let m = match("(https?://[^\\s]+)", in: text), let u = URL(string: m[0]) { return u }
        return nil
    }

    private final class RedirectCollector: NSObject, URLSessionTaskDelegate {
        var urls: [URL] = []
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            if let u = request.url { urls.append(u) }
            completionHandler(request)
        }
    }

    private static func unwrapConsent(_ u: URL) -> URL {
        if (u.host ?? "").contains("consent."),
           let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
           let cont = items.first(where: { $0.name == "continue" })?.value, let n = URL(string: cont) {
            return n
        }
        return u
    }

    private static let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

    private static func follow(_ url: URL, ua: String) async throws -> (chain: [URL], body: String) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("id-ID,id;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue("CONSENT=YES+cb.20210720-07-p0.id+FX+410", forHTTPHeaderField: "Cookie")
        let collector = RedirectCollector()
        let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, resp) = try await session.data(for: req)
        var chain = [url] + collector.urls
        if let f = resp.url, chain.last != f { chain.append(f) }
        let body = String(decoding: data.prefix(200_000), as: UTF8.self)
        return (chain, body)
    }

    private static func placeName(from s: String) -> String? {
        guard let m = match("/maps/place/([^/@?]+)", in: s) else { return nil }
        let n = m[0].replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }

    /// Titik pin tempat atau koordinat eksplisit pada tautan.
    static func pinCoordinate(from s: String) -> CLLocationCoordinate2D? {
        if let m = match("!3d(-?\\d+\\.\\d+)!4d(-?\\d+\\.\\d+)", in: s), let c = coord(m[0], m[1]) { return c }
        if let m = match("[?&](?:q|query|ll|destination|daddr)=(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", in: s),
           let c = coord(m[0], m[1]) { return c }
        return nil
    }

    /// Pusat peta (@lat,lon) hanya dipercaya pada tautan /maps/place/, bukan pada pencarian.
    static func placeCenter(from s: String) -> CLLocationCoordinate2D? {
        guard s.contains("/maps/place/") else { return nil }
        if let m = match("@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)", in: s), let c = coord(m[0], m[1]) { return c }
        return nil
    }

    private static func coordinates(fromBody b: String) -> CLLocationCoordinate2D? {
        if b.isEmpty { return nil }
        if let m = match("!3d(-?\\d+\\.\\d+)!4d(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("center=(-?\\d+\\.\\d+)%2C(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("\\[null,null,(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)\\]", in: b), let c = coord(m[0], m[1]) { return c }
        // APP_INITIALIZATION_STATE: [[[jarak,bujur,lintang],…
        if let m = match("\\[\\[\\[-?[\\d.]+,(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)\\]", in: b), let c = coord(m[1], m[0]) { return c }
        if let m = match("(?:latitude|lat)\\\"?[:=]\\s*(-?\\d+\\.\\d+)[,&\\s\\\"]+(?:longitude|lng|lon)\\\"?[:=]\\s*(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        return nil
    }

    private static func ogTitle(_ b: String) -> String? {
        guard let m = match(#"property="og:title"\s+content="([^"]+)""#, in: b) ?? match("<title>([^<]+)</title>", in: b) else { return nil }
        var t = m[0].replacingOccurrences(of: " - Google Maps", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
        return t.isEmpty || t == "Google Maps" ? nil : t
    }

    /// Teks pencarian pada tautan seperti /maps/search/NAMA atau ?q=NAMA
    private static func queryText(_ s: String) -> String? {
        if let m = match("/maps/search/([^/@?]+)", in: s) { return m[0].replacingOccurrences(of: "+", with: " ") }
        if let m = match("[?&](?:q|query)=([^&]+)", in: s), parseCoordinatePair(m[0]) == nil {
            return m[0].replacingOccurrences(of: "+", with: " ")
        }
        return nil
    }

    /// Alamat Google Maps yang tersembunyi di isi halaman (pengalihan lewat JavaScript / meta refresh).
    private static func linksInBody(_ b: String) -> [String] {
        if b.isEmpty { return [] }
        var t = b.replacingOccurrences(of: "\\u003d", with: "=")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        t = t.removingPercentEncoding ?? t
        guard let re = try? NSRegularExpression(pattern: "https?://(?:www\\.)?(?:google\\.[a-z.]+|maps\\.google\\.[a-z.]+)/maps[^\"'\\s<>\\\\]+") else { return [] }
        let ns = t as NSString
        var out = [String]()
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).prefix(12) {
            out.append(ns.substring(with: m.range))
        }
        return out
    }

    /// ID tempat Google (0x…:0x…) menjadi angka desimal untuk alamat ?cid=
    private static func cidDecimal(in texts: [String]) -> String? {
        for t in texts {
            if let m = match("0x[0-9a-fA-F]+:0x([0-9a-fA-F]{6,16})", in: t), let v = UInt64(m[0], radix: 16) {
                return String(v)
            }
        }
        return nil
    }

    private static func parseCoordinatePair(_ text: String) -> CLLocationCoordinate2D? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = match("^(-?\\d{1,3}\\.\\d+)\\s*[,;]\\s*(-?\\d{1,3}\\.\\d+)", in: t) else { return nil }
        return coord(m[0], m[1])
    }

    private static func coord(_ a: String, _ b: String) -> CLLocationCoordinate2D? {
        guard let lat = Double(a), let lon = Double(b), abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func match(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out = [String]()
        for i in 1..<max(1, m.numberOfRanges) {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }
}
