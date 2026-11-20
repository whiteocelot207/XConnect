import Foundation

/// Satu aturan zoom otomatis: bila kecepatan GPS di bawah `below` km/j, peta memakai zoom `zoom`.
/// Aturan diurutkan menurut `below` saat dipakai, jadi urutan di daftar tidak berpengaruh.
struct ZoomRule: Identifiable, Equatable {
    var id = UUID()
    var below: Double
    var zoom: Double

    static let defaults = [ZoomRule(below: 15, zoom: 17.8), ZoomRule(below: 35, zoom: 17.0), ZoomRule(below: 55, zoom: 16.3)]

    /// "15:17.8,35:17.0,55:16.3"
    static func encode(_ rules: [ZoomRule]) -> String {
        rules.map { String(format: "%.1f:%.2f", $0.below, $0.zoom) }.joined(separator: ",")
    }

    static func decode(_ s: String) -> [ZoomRule] {
        s.split(separator: ",").compactMap { part in
            let p = part.split(separator: ":")
            guard p.count == 2, let b = Double(p[0]), let z = Double(p[1]) else { return nil }
            return ZoomRule(below: b, zoom: z)
        }
    }
}

/// Memuluskan perpindahan zoom: nilai bergerak ke target secara eksponensial (konstanta waktu `tau` detik),
/// jadi zoom tidak melompat saat kecepatan melewati batas. tau <= 0 = langsung.
final class ZoomSmoother {
    private var value: Double?
    private var last = Date()

    func step(to target: Double, tau: Double, now: Date = Date()) -> Double {
        guard tau > 0, let v = value else {
            value = target
            last = now
            return target
        }
        let dt = min(1.0, max(0, now.timeIntervalSince(last)))
        last = now
        var nv = v + (target - v) * (1 - exp(-dt / tau))
        if abs(target - nv) < 0.004 { nv = target }
        value = nv
        return nv
    }

    func reset() { value = nil }
}
