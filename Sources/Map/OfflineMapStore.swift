import Foundation
import CoreLocation
import UIKit

/// Satu area peta offline: lingkaran dengan radius tertentu di sekitar titik pusat (tile vektor z14).
struct OfflineArea: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var radiusKm: Int
    var tileCount: Int
    var bytes: Int64
    var failed: Int
    var date: Date
}

/// Menyimpan tile peta dash (OpenFreeMap, z14) ke penyimpanan permanen supaya dash tetap punya peta tanpa jaringan.
final class OfflineMapStore: ObservableObject {
    static let shared = OfflineMapStore()

    static let zoom = 14
    /// perkiraan rata-rata ukuran satu tile (untuk estimasi sebelum unduh)
    static let avgTileBytes = 17_000.0

    @Published private(set) var areas: [OfflineArea] = []
    @Published private(set) var downloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var downloadName = ""
    @Published var message = ""

    private let dir: URL
    private var task: Task<Void, Never>?
    private let session: URLSession

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var d = base.appendingPathComponent("OfflineTiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? d.setResourceValues(rv)
        dir = d

        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 20
        cfg.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: cfg)
        loadAreas()
    }

    // MARK: - Tile matematika

    struct TileID: Hashable { let x: Int; let y: Int }

    static func tileXY(_ c: CLLocationCoordinate2D) -> TileID {
        let n = Double(1 << zoom)
        let lat = max(-85.05, min(85.05, c.latitude)) * Double.pi / 180
        let x = (c.longitude + 180) / 360 * n
        let y = (1 - log(tan(lat) + 1 / cos(lat)) / Double.pi) / 2 * n
        return TileID(x: max(0, min(Int(n) - 1, Int(floor(x)))), y: max(0, min(Int(n) - 1, Int(floor(y)))))
    }

    static func tileCenter(_ t: TileID) -> CLLocationCoordinate2D {
        let n = Double(1 << zoom)
        let lon = (Double(t.x) + 0.5) / n * 360 - 180
        let latRad = atan(sinh(Double.pi * (1 - 2 * (Double(t.y) + 0.5) / n)))
        return CLLocationCoordinate2D(latitude: latRad * 180 / Double.pi, longitude: lon)
    }

    /// Semua tile z14 yang menyentuh lingkaran (radius km) di sekitar pusat.
    static func tiles(center: CLLocationCoordinate2D, radiusKm: Int) -> [TileID] {
        let r = Double(radiusKm) * 1000
        let n = Geo.destination(from: center, bearing: 0, meters: r)
        let s = Geo.destination(from: center, bearing: 180, meters: r)
        let e = Geo.destination(from: center, bearing: 90, meters: r)
        let w = Geo.destination(from: center, bearing: 270, meters: r)
        let a = tileXY(CLLocationCoordinate2D(latitude: n.latitude, longitude: w.longitude))
        let b = tileXY(CLLocationCoordinate2D(latitude: s.latitude, longitude: e.longitude))
        let slack = 1_800.0                       // setengah diagonal tile (~1,7 km)
        var out = [TileID]()
        for y in min(a.y, b.y)...max(a.y, b.y) {
            for x in min(a.x, b.x)...max(a.x, b.x) {
                let t = TileID(x: x, y: y)
                if Geo.distance(center, tileCenter(t)) <= r + slack { out.append(t) }
            }
        }
        return out
    }

    static func estimateMB(center: CLLocationCoordinate2D, radiusKm: Int) -> Int {
        let c = tiles(center: center, radiusKm: radiusKm).count
        return max(1, Int((Double(c) * avgTileBytes / 1_000_000).rounded()))
    }

    private static func covers(_ a: OfflineArea, _ t: TileID) -> Bool {
        let c = CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon)
        return Geo.distance(c, tileCenter(t)) <= Double(a.radiusKm) * 1000 + 1_800
    }

    // MARK: - Berkas

    private func file(_ t: TileID) -> URL {
        dir.appendingPathComponent("\(t.x)_\(t.y).pbf")
    }

    /// Data tile dari penyimpanan offline, nil bila belum diunduh.
    func data(x: Int, y: Int) -> Data? {
        try? Data(contentsOf: file(TileID(x: x, y: y)), options: .mappedIfSafe)
    }

    private var indexURL: URL { dir.appendingPathComponent("areas.json") }

    private func loadAreas() {
        guard let d = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([OfflineArea].self, from: d) else { return }
        areas = list
    }

    private func saveAreas() {
        if let d = try? JSONEncoder().encode(areas) { try? d.write(to: indexURL, options: .atomic) }
    }

    var totalBytes: Int64 { areas.reduce(0) { $0 + $1.bytes } }

    static func mbText(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }

    // MARK: - Unduh

    func start(name: String, center: CLLocationCoordinate2D, radiusKm: Int) {
        guard !downloading else { return }
        let list = Self.tiles(center: center, radiusKm: radiusKm)
        guard !list.isEmpty else { return }
        downloading = true
        progress = 0
        downloadName = name
        message = ""
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task { [weak self] in
            await self?.run(name: name, center: center, radiusKm: radiusKm, tiles: list)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func template() async -> String? {
        if let url = URL(string: "https://tiles.openfreemap.org/planet"),
           let (data, _) = try? await session.data(from: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tiles = obj["tiles"] as? [String], let t = tiles.first {
            UserDefaults.standard.set(t, forKey: "vtile.template")
            return t
        }
        return UserDefaults.standard.string(forKey: "vtile.template")
    }

    /// Hasil satu tile: ukuran byte (0 = kosong/tidak ada), gagal?
    private func fetch(_ t: TileID, tpl: String) async -> (Int64, Bool) {
        let f = file(t)
        if let attr = try? FileManager.default.attributesOfItem(atPath: f.path), let sz = attr[.size] as? Int64 {
            return (sz, false)
        }
        let s = tpl.replacingOccurrences(of: "{z}", with: String(Self.zoom))
            .replacingOccurrences(of: "{x}", with: String(t.x))
            .replacingOccurrences(of: "{y}", with: String(t.y))
        guard let url = URL(string: s) else { return (0, true) }
        for attempt in 0..<3 {
            if Task.isCancelled { return (0, true) }
            do {
                let (data, resp) = try await session.data(from: url)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200, !data.isEmpty {
                    try data.write(to: f, options: .atomic)
                    return (Int64(data.count), false)
                }
                if code == 404 || code == 204 || (code == 200 && data.isEmpty) { return (0, false) }   // tile kosong (laut dll)
            } catch {
                if Task.isCancelled { return (0, true) }
            }
            try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
        }
        return (0, true)
    }

    private func run(name: String, center: CLLocationCoordinate2D, radiusKm: Int, tiles: [TileID]) async {
        guard let tpl = await template() else {
            await finish { $0.message = "Tidak ada jaringan, atau server peta tidak bisa dihubungi." }
            return
        }
        var done = 0, failed = 0
        var bytes: Int64 = 0
        let total = tiles.count
        var next = 0
        let window = 8

        await withTaskGroup(of: (Int64, Bool).self) { group in
            while next < min(window, total) {
                let t = tiles[next]; next += 1
                group.addTask { await self.fetch(t, tpl: tpl) }
            }
            while let r = await group.next() {
                done += 1
                bytes += r.0
                if r.1 { failed += 1 }
                if Task.isCancelled { group.cancelAll(); continue }
                if done % 20 == 0 || done == total {
                    let p = Double(done) / Double(total)
                    await MainActor.run { self.progress = p }
                }
                if next < total {
                    let t = tiles[next]; next += 1
                    group.addTask { await self.fetch(t, tpl: tpl) }
                }
            }
        }

        if Task.isCancelled {
            // batal: buang tile area ini yang tidak dipakai area lain
            let probe = OfflineArea(id: "", name: name, lat: center.latitude, lon: center.longitude,
                                    radiusKm: radiusKm, tileCount: total, bytes: 0, failed: 0, date: Date())
            removeFiles(of: probe, tiles: tiles, keeping: areas)
            await finish { $0.message = "Pengunduhan dibatalkan." }
            return
        }

        let area = OfflineArea(id: UUID().uuidString, name: name, lat: center.latitude, lon: center.longitude,
                               radiusKm: radiusKm, tileCount: total, bytes: bytes, failed: failed, date: Date())
        await finish {
            $0.areas.append(area)
            $0.saveAreas()
            $0.message = failed == 0
                ? "Area \"\(name)\" tersimpan (\(Self.mbText(bytes)))."
                : "Area \"\(name)\" tersimpan, tetapi \(failed) tile gagal diunduh. Simpan ulang area yang sama untuk melengkapi."
        }
    }

    private func finish(_ update: @escaping (OfflineMapStore) -> Void) async {
        await MainActor.run {
            update(self)
            self.downloading = false
            self.progress = 0
            self.task = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Hapus

    func delete(_ area: OfflineArea) {
        areas.removeAll { $0.id == area.id }
        saveAreas()
        let rest = areas
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let c = CLLocationCoordinate2D(latitude: area.lat, longitude: area.lon)
            self.removeFiles(of: area, tiles: Self.tiles(center: c, radiusKm: area.radiusKm), keeping: rest)
        }
    }

    private func removeFiles(of area: OfflineArea, tiles: [TileID], keeping rest: [OfflineArea]) {
        for t in tiles where !rest.contains(where: { Self.covers($0, t) }) {
            try? FileManager.default.removeItem(at: file(t))
        }
    }
}
