import Foundation
import CoreLocation

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

        var chain: [URL] = [url]
        var body = ""
        let host = (url.host ?? "").lowercased()
        if host.contains("goo.gl") || host.contains("app.goo") {
            let r = try await follow(url)
            chain = r.chain
            body = r.body
        }
        // halaman persetujuan Google membungkus tautan asli di parameter "continue"
        chain = chain.map { unwrapConsent($0) }

        // semua alamat di rantai pengalihan diperiksa: alamat pertama biasanya masih memuat nama dan koordinat,
        // alamat akhir bisa saja hanya google.com/maps
        let urls = chain.map { $0.absoluteString.removingPercentEncoding ?? $0.absoluteString }
        let last = chain.last ?? url
        debug = "\(last.host ?? "?")\(last.path.prefix(60)) · \(chain.count) alamat"
        let name = urls.compactMap { placeName(from: $0) }.first ?? ogTitle(body) ?? urls.compactMap { queryText($0) }.first
        let coord = urls.compactMap { coordinates(from: $0) }.first ?? coordinates(fromBody: body)
        if let c = coord {
            return Place(name: name ?? "Lokasi dari Google Maps", subtitle: "Google Maps",
                         lat: c.latitude, lon: c.longitude)
        }
        if let n = name {
            let found = try await PlaceSearch.search(n, near: near)
            if let f = found.first { return Place(name: n, subtitle: f.subtitle, lat: f.lat, lon: f.lon) }
        }
        throw LinkError.noPlace
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

    private static func follow(_ url: URL) async throws -> (chain: [URL], body: String) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
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

    private static func coordinates(from s: String) -> CLLocationCoordinate2D? {
        if let m = match("!3d(-?\\d+\\.\\d+)!4d(-?\\d+\\.\\d+)", in: s), let c = coord(m[0], m[1]) { return c }
        if let m = match("@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)", in: s), let c = coord(m[0], m[1]) { return c }
        if let m = match("[?&](?:q|query|ll|destination|daddr|center)=(-?\\d+\\.\\d+),\\s*(-?\\d+\\.\\d+)", in: s),
           let c = coord(m[0], m[1]) { return c }
        return nil
    }

    private static func coordinates(fromBody b: String) -> CLLocationCoordinate2D? {
        if b.isEmpty { return nil }
        if let m = match("!3d(-?\\d+\\.\\d+)!4d(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("center=(-?\\d+\\.\\d+)%2C(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)", in: b), let c = coord(m[0], m[1]) { return c }
        if let m = match("\\[null,null,(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)\\]", in: b), let c = coord(m[0], m[1]) { return c }
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
