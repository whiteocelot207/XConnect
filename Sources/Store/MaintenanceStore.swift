import Foundation
import UserNotifications

struct MaintLog: Codable, Identifiable {
    var id: String
    var date: Date
    var odoKm: Double
}

struct MaintItem: Codable, Identifiable {
    var id: String
    var name: String
    var icon: String            // nama SF Symbol
    var intervalKm: Int
    var lastServiceKm: Double
    /// tanggal penggantian terakhir (nil bila belum pernah dicatat)
    var lastServiceDate: Date?
    var history: [MaintLog]

    /// Item bawaan (kelima perawatan standar): tidak bisa dihapus, namanya mengikuti bahasa app.
    var isDefault: Bool { MaintenanceStore.defaultKeys[id] != nil }

    /// Nama yang ditampilkan: item bawaan diterjemahkan sesuai bahasa aktif, item tambahan memakai nama buatan pengguna.
    var title: String {
        if let key = MaintenanceStore.defaultKeys[id] { return tr(key) }
        return name
    }
}

final class MaintenanceStore: ObservableObject {
    /// id item bawaan -> kunci terjemahan namanya (Translations.tsv)
    static let defaultKeys: [String: String] = [
        "oli-mesin": "Engine oil", "oli-gardan": "Gear oil", "filter-udara": "Air filter",
        "busi": "Spark plug", "v-belt": "V-belt"
    ]

    /// Pastikan kelima item bawaan selalu ada (urutan tetap di depan), diikuti item tambahan pengguna.
    /// Item bawaan yang hilang dari data lama dikembalikan dengan nilai awal.
    static func normalized(_ saved: [MaintItem]) -> [MaintItem] {
        var out: [MaintItem] = []
        for d in defaults() {
            out.append(saved.first(where: { $0.id == d.id }) ?? d)
        }
        out += saved.filter { !$0.isDefault }
        return out
    }

    /// Interval bawaan hanya perkiraan umum. Sesuaikan dengan buku manual motor Anda.
    static func defaults() -> [MaintItem] {
        [
            MaintItem(id: "oli-mesin", name: tr("Engine oil"), icon: "drop.fill", intervalKm: 4000, lastServiceKm: 0, lastServiceDate: nil, history: []),
            MaintItem(id: "oli-gardan", name: tr("Gear oil"), icon: "gearshape.fill", intervalKm: 8000, lastServiceKm: 0, lastServiceDate: nil, history: []),
            MaintItem(id: "filter-udara", name: tr("Air filter"), icon: "wind", intervalKm: 12000, lastServiceKm: 0, lastServiceDate: nil, history: []),
            MaintItem(id: "busi", name: tr("Spark plug"), icon: "bolt.fill", intervalKm: 12000, lastServiceKm: 0, lastServiceDate: nil, history: []),
            MaintItem(id: "v-belt", name: tr("V-belt"), icon: "arrow.triangle.2.circlepath", intervalKm: 24000, lastServiceKm: 0, lastServiceDate: nil, history: [])
        ]
    }

    @Published var odometerKm: Double {
        didSet { UserDefaults.standard.set(odometerKm, forKey: "maint.odo.v3"); checkReminders() }
    }
    @Published var odometerAuto = false
    @Published var items: [MaintItem] { didSet { save(); checkReminders() } }

    init() {
        let d = UserDefaults.standard
        odometerKm = d.double(forKey: "maint.odo.v3")
        if let data = d.data(forKey: "maint.items.v3"),
           let it = try? JSONDecoder().decode([MaintItem].self, from: data) {
            items = MaintenanceStore.normalized(it)
        } else {
            items = MaintenanceStore.defaults()
        }
    }

    /// Muat ulang dari UserDefaults (setelah memulihkan cadangan).
    func reload() {
        let d = UserDefaults.standard
        odometerKm = d.double(forKey: "maint.odo.v3")
        if let data = d.data(forKey: "maint.items.v3"),
           let it = try? JSONDecoder().decode([MaintItem].self, from: data) {
            items = MaintenanceStore.normalized(it)
        } else {
            items = MaintenanceStore.defaults()
        }
    }

    // MARK: - Pengingat perawatan

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Kirim notifikasi lokal saat sebuah item masuk batas pengingat atau lewat jadwal. Hanya saat status BERUBAH;
    /// evaluasi pertama setelah ODO terbaca hanya mencatat status (tanpa notifikasi) agar tidak membanjiri.
    func checkReminders() {
        let d = UserDefaults.standard
        guard odometerKm > 0, (d.object(forKey: "maintNotify") as? Bool) ?? true else { return }
        let warn = (d.object(forKey: "maintWarnKm") as? Int) ?? 100
        var state = (d.dictionary(forKey: "maint.notified") as? [String: String]) ?? [:]
        for item in items {
            let rem = remainingKm(item)
            let level = rem < 0 ? "over" : (rem <= warn ? "warn" : "ok")
            let before = state[item.id]
            if before == level { continue }
            state[item.id] = level
            guard before != nil, level != "ok" else { continue }
            let c = UNMutableNotificationContent()
            c.title = tr("Maintenance due")
            c.body = rem < 0 ? tr("{0}: overdue {1} km", item.title, -rem) : tr("{0}: {1} km left", item.title, rem)
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "maint." + item.id + "." + level, content: c, trigger: nil))
        }
        d.set(state, forKey: "maint.notified")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "maint.items.v3")
        }
    }

    func remainingKm(_ item: MaintItem) -> Int {
        Int((item.lastServiceKm + Double(item.intervalKm) - odometerKm).rounded())
    }

    /// Sisa km terkecil di antara semua item (untuk ringkasan).
    var nearestRemainingKm: Int? {
        items.map { remainingKm($0) }.min()
    }

    /// Catat penggantian: tanggal (bawaan hari ini) dan ODO saat diganti (bawaan ODO sekarang). Sisa km dihitung dari ODO ini.
    func markServiced(_ id: String, date: Date = Date(), odoKm: Double? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let odo = odoKm ?? odometerKm
        items[i].lastServiceKm = odo
        items[i].lastServiceDate = date
        items[i].history.insert(MaintLog(id: UUID().uuidString, date: date, odoKm: odo), at: 0)
        items[i].history.sort { $0.date > $1.date }
    }

    func addItem(name: String, intervalKm: Int, lastKm: Double? = nil, lastDate: Date? = nil) {
        items.append(MaintItem(id: UUID().uuidString, name: name, icon: "wrench.fill", intervalKm: intervalKm,
                               lastServiceKm: lastKm ?? odometerKm, lastServiceDate: lastDate ?? Date(), history: []))
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id && !$0.isDefault }     // item bawaan tidak bisa dihapus
    }
}
