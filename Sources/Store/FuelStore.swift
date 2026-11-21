import Foundation

struct FuelFill: Codable, Identifiable {
    var id: String
    var date: Date
    var odoKm: Double
    var liters: Double
    var full: Bool
}

/// Pemakaian bensin terukur per hari (dari rata-rata konsumsi dash), dipakai menghitung konsumsi 30 hari terakhir.
struct FuelUseDay: Codable {
    var day: String
    var km: Double
    var liters: Double
}

/// Perkiraan sisa bensin: motor tidak melaporkan level tangki, jadi dihitung dari isi terakhir dan jarak tempuh.
final class FuelStore: ObservableObject {
    @Published var fills: [FuelFill] { didSet { save() } }
    @Published var levelL: Double { didSet { UserDefaults.standard.set(levelL, forKey: "fuel.level") } }
    @Published var odoAtLevel: Double { didSet { UserDefaults.standard.set(odoAtLevel, forKey: "fuel.odo") } }
    /// pemakaian terukur per hari (hanya dari rata-rata dash), maksimal 45 hari terakhir disimpan
    @Published var useDays: [FuelUseDay] { didSet { saveDays() } }
    /// true bila motor menempuh lebih dari satu tangki tanpa app terhubung: angka sisa bensin mungkin salah
    @Published var mayBeOff: Bool { didSet { UserDefaults.standard.set(mayBeOff, forKey: "fuel.mayBeOff") } }

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "fuel.fills"), let f = try? JSONDecoder().decode([FuelFill].self, from: data) {
            fills = f
        } else {
            fills = []
        }
        levelL = d.double(forKey: "fuel.level")
        odoAtLevel = d.double(forKey: "fuel.odo")
        if let data = d.data(forKey: "fuel.useDays"), let u = try? JSONDecoder().decode([FuelUseDay].self, from: data) {
            useDays = u
        } else {
            useDays = []
        }
        mayBeOff = d.bool(forKey: "fuel.mayBeOff")
    }

    /// Muat ulang dari UserDefaults (setelah memulihkan cadangan).
    func reload() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "fuel.fills"), let f = try? JSONDecoder().decode([FuelFill].self, from: data) { fills = f } else { fills = [] }
        levelL = d.double(forKey: "fuel.level")
        odoAtLevel = d.double(forKey: "fuel.odo")
        if let data = d.data(forKey: "fuel.useDays"), let u = try? JSONDecoder().decode([FuelUseDay].self, from: data) { useDays = u } else { useDays = [] }
        mayBeOff = d.bool(forKey: "fuel.mayBeOff")
    }

    private func saveDays() {
        if let data = try? JSONEncoder().encode(useDays) { UserDefaults.standard.set(data, forKey: "fuel.useDays") }
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func save() {
        if let data = try? JSONEncoder().encode(fills) { UserDefaults.standard.set(data, forKey: "fuel.fills") }
    }

    /// Rata-rata konsumsi (km/L) dari CCU motor bila diaktifkan di Pengaturan dan datanya valid. Diisi dari AppModel.
    var ccuKmPerL: () -> Double? = { nil }

    /// km per liter dari pemakaian terukur 30 hari terakhir (jarak dibagi bensin yang dihitung dari rata-rata dash).
    /// nil bila datanya belum cukup (kurang dari 20 km).
    private func ownKmPerL() -> Double? {
        guard let from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }
        let first = FuelStore.dayFmt.string(from: from)
        let recent = useDays.filter { $0.day >= first }
        let km = recent.reduce(0) { $0 + $1.km }
        let liters = recent.reduce(0) { $0 + $1.liters }
        guard km >= 20, liters > 0.3 else { return nil }
        return min(80, max(5, km / liters))
    }

    /// Konsumsi yang dipakai menghitung sisa bensin, seperti NConnect: rata-rata konsumsi dari dash (CCU) bila terbaca,
    /// lalu konsumsi Anda sendiri 30 hari terakhir, lalu nilai bawaan.
    func kmPerL(default def: Double) -> Double {
        kmPerLSource(default: def).value
    }

    /// Konsumsi beserta asalnya (untuk keterangan di layar Motor). `measured` = berasal dari rata-rata dash.
    func kmPerLSource(default def: Double) -> (value: Double, source: String, measured: Bool) {
        if let c = ccuKmPerL() { return (min(80, max(5, c)), tr("average on the dash (CCU)"), true) }
        if let o = ownKmPerL() { return (o, tr("your consumption over the last 30 days"), false) }
        return (def, tr("default value"), false)
    }

    private func record(km: Double, liters: Double) {
        let key = FuelStore.dayFmt.string(from: Date())
        if let i = useDays.lastIndex(where: { $0.day == key }) {
            useDays[i].km += km
            useDays[i].liters += liters
        } else {
            useDays.append(FuelUseDay(day: key, km: km, liters: liters))
            if let cut = Calendar.current.date(byAdding: .day, value: -45, to: Date()) {
                let old = FuelStore.dayFmt.string(from: cut)
                useDays.removeAll { $0.day < old }
            }
        }
    }

    func remainingL(odo: Double, tank: Double, def: Double) -> Double {
        let used = max(0, odo - odoAtLevel) / kmPerL(default: def)
        return max(0, min(tank, levelL - used))
    }

    func rangeKm(odo: Double, tank: Double, def: Double) -> Int {
        Int((remainingL(odo: odo, tank: tank, def: def) * kmPerL(default: def)).rounded())
    }

    /// Dipanggil tiap ODO bertambah: bensin yang terpakai dihitung dari jarak dan konsumsi SAAT ITU (rata-rata dash bila ada),
    /// lalu dikurangkan dari sisa. Pemakaian terukur dari dash dicatat untuk konsumsi 30 hari.
    func advance(odo: Double, tank: Double, def: Double) {
        guard levelL > 0 else { return }
        if odo < odoAtLevel { odoAtLevel = odo; return }          // ODO direset/turun: mulai dari sini
        let km = odo - odoAtLevel
        guard km >= 0.1 else { return }
        let src = kmPerLSource(default: def)
        let used = km / src.value
        if used >= tank { mayBeOff = true }                       // lebih dari satu tangki tanpa app: angka mungkin salah
        levelL = max(0.01, min(tank, levelL - used))             // 0,01 supaya "ada data" (levelL > 0) tetap berlaku
        odoAtLevel = odo
        // lompatan jarak besar (app lama tidak terhubung) tidak dicatat: rata-rata dash saat itu belum tentu mewakili
        if src.measured, km <= 5 { record(km: km, liters: used) }
    }

    func markFull(odo: Double, tank: Double, def: Double) {
        let before = remainingL(odo: odo, tank: tank, def: def)
        let added = max(0, tank - before)
        fills.append(FuelFill(id: UUID().uuidString, date: Date(), odoKm: odo, liters: added, full: true))
        levelL = tank
        odoAtLevel = odo
        mayBeOff = false
    }

    /// Atur sisa bensin langsung (mis. dari indikator di dash). Perhitungan berikutnya berangkat dari sini.
    func setLevel(_ l: Double, odo: Double, tank: Double) {
        levelL = max(0, min(tank, l))
        odoAtLevel = odo
        mayBeOff = false
    }

    func addLiters(_ l: Double, odo: Double, tank: Double, def: Double) {
        guard l > 0 else { return }
        let before = remainingL(odo: odo, tank: tank, def: def)
        fills.append(FuelFill(id: UUID().uuidString, date: Date(), odoKm: odo, liters: l, full: false))
        levelL = min(tank, before + l)
        odoAtLevel = odo
    }
}
