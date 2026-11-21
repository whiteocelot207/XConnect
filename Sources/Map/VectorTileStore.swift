import Foundation
import CoreGraphics

enum FillKind: Int, CaseIterable {
    case grass = 0, wood, farm, sand, residential, commercial, industrial, hospital, school, cemetery, park, water, building
}

enum LineKind: Int {
    case rail = 0, path, service, minor, tertiary, secondary, primary, trunk, motorway
    case waterway = 100
    static let roadOrder: [LineKind] = [.service, .minor, .tertiary, .secondary, .primary, .trunk, .motorway]
}

/// Satu tile OpenMapTiles z14 yang sudah dikelompokkan per gaya, siap digambar dengan CoreGraphics.
final class VTile {
    struct RoadLabel { let text: String; let a: CGPoint; let b: CGPoint }
    struct PlaceLabel { let text: String; let p: CGPoint; let cls: String }

    var fills = [Int: CGPath]()
    var lines = [Int: CGPath]()
    var roadLabels = [RoadLabel]()
    var places = [PlaceLabel]()
    var fuel = [CGPoint]()

    private static func fillKind(_ layer: String, _ cls: String) -> FillKind? {
        switch layer {
        case "water": return .water
        case "building": return .building
        case "park": return .park
        case "landcover":
            switch cls {
            case "grass", "wetland": return .grass
            case "wood": return .wood
            case "farmland": return .farm
            case "sand": return .sand
            default: return nil
            }
        case "landuse":
            switch cls {
            case "residential": return .residential
            case "commercial", "retail": return .commercial
            case "industrial": return .industrial
            case "hospital": return .hospital
            case "school", "university", "college", "kindergarten": return .school
            case "cemetery": return .cemetery
            case "park", "playground", "pitch", "stadium", "track", "recreation_ground": return .park
            default: return nil
            }
        default: return nil
        }
    }

    private static func roadKind(_ cls: String) -> LineKind? {
        switch cls {
        case "motorway": return .motorway
        case "trunk": return .trunk
        case "primary": return .primary
        case "secondary": return .secondary
        case "tertiary": return .tertiary
        case "minor": return .minor
        case "service", "track": return .service
        case "path": return .path
        case "rail", "transit": return .rail
        default: return nil
        }
    }

    static func build(_ layers: [MVTLayer]) -> VTile {
        let tile = VTile()
        var fp = [Int: CGMutablePath]()
        var lp = [Int: CGMutablePath]()
        var best = [String: (len: Double, a: CGPoint, b: CGPoint)]()

        func fillPath(_ k: FillKind) -> CGMutablePath {
            if let p = fp[k.rawValue] { return p }
            let p = CGMutablePath()
            fp[k.rawValue] = p
            return p
        }
        func linePath(_ k: LineKind) -> CGMutablePath {
            if let p = lp[k.rawValue] { return p }
            let p = CGMutablePath()
            lp[k.rawValue] = p
            return p
        }

        for layer in layers {
            for f in layer.features {
                let cls = f.tags["class"] ?? ""
                switch layer.name {
                case "water", "building", "park", "landcover", "landuse":
                    guard f.type == 3, let k = fillKind(layer.name, cls) else { continue }
                    let p = fillPath(k)
                    for ring in f.parts where ring.count >= 3 {
                        p.addLines(between: ring)
                        p.closeSubpath()
                    }
                case "waterway":
                    guard f.type == 2 else { continue }
                    let p = linePath(.waterway)
                    for l in f.parts where l.count >= 2 { p.addLines(between: l) }
                case "transportation":
                    guard f.type == 2, let k = roadKind(cls) else { continue }
                    let p = linePath(k)
                    for l in f.parts where l.count >= 2 { p.addLines(between: l) }
                case "transportation_name":
                    guard f.type == 2 else { continue }
                    let name = f.tags["name"] ?? f.tags["name:latin"] ?? ""
                    if name.isEmpty { continue }
                    for l in f.parts where l.count >= 2 {
                        for i in 1..<l.count {
                            let dx = Double(l[i].x - l[i - 1].x)
                            let dy = Double(l[i].y - l[i - 1].y)
                            let len = (dx * dx + dy * dy).squareRoot()
                            if len > (best[name]?.len ?? 0) { best[name] = (len, l[i - 1], l[i]) }
                        }
                    }
                case "place":
                    guard f.type == 1, let pt = f.parts.first?.first else { continue }
                    let name = f.tags["name"] ?? f.tags["name:latin"] ?? ""
                    if !name.isEmpty { tile.places.append(PlaceLabel(text: name, p: pt, cls: cls)) }
                case "poi":
                    guard f.type == 1, cls == "fuel", let pt = f.parts.first?.first else { continue }
                    tile.fuel.append(pt)
                default:
                    break
                }
            }
        }
        tile.fills = fp.mapValues { $0 as CGPath }
        tile.lines = lp.mapValues { $0 as CGPath }
        for (name, v) in best where v.len > 150 {
            tile.roadLabels.append(RoadLabel(text: name, a: v.a, b: v.b))
        }
        return tile
    }
}

/// Mengunduh (dengan cache disk), mendekode, dan menyimpan tile vektor OpenFreeMap (z14).
final class VectorTileStore {
    static let shared = VectorTileStore()

    var log: (String) -> Void = { _ in }

    private let lock = NSLock()
    private var cache = [String: VTile]()
    private var order = [String]()
    private var pending = Set<String>()
    private var failed = [String: Date]()
    private var template: String?
    private var templateTime = Date.distantPast
    private let session: URLSession
    private let queue = DispatchQueue(label: "vtile.decode", qos: .userInitiated)

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 300_000_000, diskPath: "vtiles")
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
        template = UserDefaults.standard.string(forKey: "vtile.template")
        refreshTemplate()
    }

    /// TileJSON berubah tiap versi data baru, jadi selalu diambil ulang (tanpa cache).
    func refreshTemplate() {
        lock.lock()
        let recent = Date().timeIntervalSince(templateTime) < 6 * 3600
        if !recent { templateTime = Date() }
        lock.unlock()
        if recent { return }
        guard let url = URL(string: "https://tiles.openfreemap.org/planet") else { return }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else { return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tiles = obj["tiles"] as? [String], let t = tiles.first else {
                self.log(tr("Map: failed to fetch TileJSON"))
                self.lock.lock(); self.templateTime = Date.distantPast; self.lock.unlock()
                return
            }
            self.lock.lock()
            self.template = t
            self.lock.unlock()
            UserDefaults.standard.set(t, forKey: "vtile.template")
        }.resume()
    }

    /// Mengembalikan tile bila sudah ada; bila belum, memicu pengunduhan dan mengembalikan nil.
    func tile(_ x: Int, _ y: Int) -> VTile? {
        let key = "\(x)/\(y)"
        lock.lock()
        let hit = cache[key]
        let tpl = template
        var need = false
        if hit == nil && !pending.contains(key) {
            if let t = failed[key], Date().timeIntervalSince(t) < 20 {
                need = false
            } else {
                need = true
                pending.insert(key)
            }
        }
        lock.unlock()
        if need { load(key, x, y, tpl) }
        return hit
    }

    /// Dekode data tile (MVT, bisa gzip) di antrean dekode, lalu simpan di cache memori.
    private func decodeAndStore(_ key: String, _ data: Data) {
        queue.async {
            var bytes = [UInt8](data)
            if bytes.count > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B {
                bytes = VectorTileStore.gunzip(bytes) ?? bytes
            }
            let tile = VTile.build(MVT.decode(bytes))
            self.lock.lock()
            self.cache[key] = tile
            self.order.append(key)
            if self.order.count > 80 {
                let drop = self.order.removeFirst()
                self.cache[drop] = nil
            }
            self.pending.remove(key)
            self.lock.unlock()
        }
    }

    private func load(_ key: String, _ x: Int, _ y: Int, _ tpl: String?) {
        // peta offline yang sudah diunduh dipakai lebih dulu (tanpa jaringan)
        if let local = OfflineMapStore.shared.data(x: x, y: y) {
            decodeAndStore(key, local)
            return
        }
        guard let tpl = tpl else {
            lock.lock(); pending.remove(key); lock.unlock()
            refreshTemplate()
            return
        }
        let urlStr = tpl.replacingOccurrences(of: "{z}", with: "14")
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        guard let url = URL(string: urlStr) else {
            lock.lock(); pending.remove(key); lock.unlock()
            return
        }
        session.dataTask(with: url) { [weak self] data, resp, _ in
            guard let self = self else { return }
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            guard ok, let data = data, !data.isEmpty else {
                self.lock.lock()
                self.pending.remove(key)
                self.failed[key] = Date()
                self.lock.unlock()
                return
            }
            self.decodeAndStore(key, data)
        }.resume()
    }

    /// Cadangan bila server mengirim gzip tanpa header Content-Encoding.
    private static func gunzip(_ b: [UInt8]) -> [UInt8]? {
        guard b.count > 18 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 {
            guard i + 2 <= b.count else { return nil }
            i += 2 + Int(b[i]) + (Int(b[i + 1]) << 8)
        }
        if flags & 8 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count && b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        let body = Data(b[i..<(b.count - 8)])
        guard let out = try? (body as NSData).decompressed(using: .zlib) else { return nil }
        return [UInt8](out as Data)
    }
}
