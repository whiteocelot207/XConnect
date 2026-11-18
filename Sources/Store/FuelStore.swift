import Foundation

struct FuelFill: Codable, Identifiable {
    var id: String
    var date: Date
    var odoKm: Double
    var liters: Double
    var full: Bool
}

/// Perkiraan sisa bensin: motor tidak melaporkan level tangki, jadi dihitung dari isi terakhir dan jarak tempuh.
final class FuelStore: ObservableObject {
    @Published var fills: [FuelFill] { didSet { save() } }
    @Published var levelL: Double { didSet { UserDefaults.standard.set(levelL, forKey: "fuel.level") } }
    @Published var odoAtLevel: Double { didSet { UserDefaults.standard.set(odoAtLevel, forKey: "fuel.odo") } }

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "fuel.fills"), let f = try? JSONDecoder().decode([FuelFill].self, from: data) {
            fills = f
        } else {
            fills = []
        }
        levelL = d.double(forKey: "fuel.level")
        odoAtLevel = d.double(forKey: "fuel.odo")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(fills) { UserDefaults.standard.set(data, forKey: "fuel.fills") }
    }

    /// km per liter dari riwayat pengisian; kembali ke nilai bawaan bila data belum cukup.
    func kmPerL(default def: Double) -> Double {
        let sorted = fills.sorted { $0.odoKm < $1.odoKm }
        guard sorted.count >= 3, let first = sorted.first, let last = sorted.last else { return def }
        let km = last.odoKm - first.odoKm
        let liters = sorted.dropFirst().reduce(0) { $0 + $1.liters }
        guard km > 80, liters > 1 else { return def }
        return min(80, max(10, km / liters))
    }

    func remainingL(odo: Double, tank: Double, def: Double) -> Double {
        let used = max(0, odo - odoAtLevel) / kmPerL(default: def)
        return max(0, min(tank, levelL - used))
    }

    func rangeKm(odo: Double, tank: Double, def: Double) -> Int {
        Int((remainingL(odo: odo, tank: tank, def: def) * kmPerL(default: def)).rounded())
    }

    func markFull(odo: Double, tank: Double, def: Double) {
        let before = remainingL(odo: odo, tank: tank, def: def)
        let added = max(0, tank - before)
        fills.append(FuelFill(id: UUID().uuidString, date: Date(), odoKm: odo, liters: added, full: true))
        levelL = tank
        odoAtLevel = odo
    }

    /// Atur sisa bensin langsung (mis. dari indikator di dash). Perhitungan berikutnya berangkat dari sini.
    func setLevel(_ l: Double, odo: Double, tank: Double) {
        levelL = max(0, min(tank, l))
        odoAtLevel = odo
    }

    func addLiters(_ l: Double, odo: Double, tank: Double, def: Double) {
        guard l > 0 else { return }
        let before = remainingL(odo: odo, tank: tank, def: def)
        fills.append(FuelFill(id: UUID().uuidString, date: Date(), odoKm: odo, liters: l, full: false))
        levelL = min(tank, before + l)
        odoAtLevel = odo
    }
}
