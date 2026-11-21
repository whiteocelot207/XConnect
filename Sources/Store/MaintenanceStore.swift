import Foundation
import UserNotifications

struct MaintLog: Codable, Identifiable {
    var id: String
    var date: Date
    var odoKm: Double
}

/// Acuan jadwal sebuah item perawatan.
enum MaintBasis: String, Codable {
    case km      // berdasarkan kilometer (ODO)
    case time    // berdasarkan waktu / tanggal jatuh tempo (mis. masa berlaku STNK)
}

/// Tingkat kedekatan jadwal: aman, mendekati (masuk batas peringatan item), terlambat.
enum MaintLevel: Int { case ok = 0, warn, over }

/// Hasil hitung status satu item: tingkat, teks sisa ("120 km left", "3 months left", "Overdue 5 days"), dan porsi terpakai 0...1.
struct MaintStatus {
    var level: MaintLevel
    var text: String
    var fraction: Double
}

struct MaintItem: Codable, Identifiable {
    var id: String
    var name: String
    /// ikon: nama SF Symbol, atau "e:" + emoji (lihat MaintIcons)
    var icon: String
    /// acuan: kilometer atau waktu
    var basis: MaintBasis
    var intervalKm: Int
    var lastServiceKm: Double
    /// tanggal penggantian terakhir (nil bila belum pernah dicatat)
    var lastServiceDate: Date?
    var history: [MaintLog]
    /// acuan KM: peringatan muncul saat sisa jarak <= nilai ini (per item)
    var warnKm: Int
    /// acuan WAKTU: berulang (ada selang dan jatuh tempo berikutnya dihitung otomatis) atau sekali (hanya satu tanggal jatuh tempo)
    var repeats: Bool
    /// acuan WAKTU (berulang): selang (bulan) dari penggantian terakhir sampai jatuh tempo berikutnya
    var intervalMonths: Int
    /// acuan WAKTU: tanggal jatuh tempo / masa berlaku habis
    var dueDate: Date?
    /// acuan WAKTU: peringatan muncul sekian bulan sebelum jatuh tempo (1, 3, 6)
    var warnMonths: Int

    init(id: String, name: String, icon: String, basis: MaintBasis = .km, intervalKm: Int, lastServiceKm: Double,
         lastServiceDate: Date?, history: [MaintLog], warnKm: Int = 100, repeats: Bool = false,
         intervalMonths: Int = 12, dueDate: Date? = nil, warnMonths: Int = 1) {
        self.repeats = repeats
        self.id = id; self.name = name; self.icon = icon; self.basis = basis
        self.intervalKm = intervalKm; self.lastServiceKm = lastServiceKm
        self.lastServiceDate = lastServiceDate; self.history = history
        self.warnKm = warnKm; self.intervalMonths = intervalMonths
        self.dueDate = dueDate; self.warnMonths = warnMonths
    }

    /// Data versi lama (tanpa kolom acuan/peringatan per item) tetap terbaca: acuan KM, batas peringatan
    /// memakai nilai pengaturan global lama (bila ada).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "wrench.fill"
        basis = try c.decodeIfPresent(MaintBasis.self, forKey: .basis) ?? .km
        intervalKm = try c.decodeIfPresent(Int.self, forKey: .intervalKm) ?? 5000
        lastServiceKm = try c.decodeIfPresent(Double.self, forKey: .lastServiceKm) ?? 0
        lastServiceDate = try c.decodeIfPresent(Date.self, forKey: .lastServiceDate)
        history = try c.decodeIfPresent([MaintLog].self, forKey: .history) ?? []
        let oldGlobal = UserDefaults.standard.integer(forKey: "maintWarnKm")
        warnKm = try c.decodeIfPresent(Int.self, forKey: .warnKm) ?? (oldGlobal > 0 ? oldGlobal : 100)
        repeats = try c.decodeIfPresent(Bool.self, forKey: .repeats) ?? false
        intervalMonths = try c.decodeIfPresent(Int.self, forKey: .intervalMonths) ?? 12
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        warnMonths = try c.decodeIfPresent(Int.self, forKey: .warnMonths) ?? 1
    }

    /// Item bawaan (kelima perawatan standar): tidak bisa dihapus, namanya mengikuti bahasa app.
    var isDefault: Bool { MaintenanceStore.defaultKeys[id] != nil }

    /// Nama yang ditampilkan: item bawaan diterjemahkan sesuai bahasa aktif, item tambahan memakai nama buatan pengguna.
    var title: String {
        if let key = MaintenanceStore.defaultKeys[id] { return tr(key) }
        return name
    }

    /// Tanggal jatuh tempo acuan waktu: `dueDate`, atau penggantian terakhir + selang bila belum diisi.
    var effectiveDueDate: Date? {
        if let d = dueDate { return d }
        guard repeats, let last = lastServiceDate else { return nil }
        return Calendar.current.date(byAdding: .month, value: intervalMonths, to: last)
    }
}

final class MaintenanceStore: ObservableObject {
    /// id item bawaan -> kunci terjemahan namanya (Translations.tsv)
    static let defaultKeys: [String: String] = [
        "oli-mesin": "Engine oil", "oli-gardan": "Gear oil", "filter-udara": "Air filter",
        "busi": "Spark plug", "v-belt": "V-belt"
    ]

    /// Pilihan selang (bulan) dan peringatan sebelum jatuh tempo (bulan) untuk acuan waktu.
    static let intervalMonthChoices = [1, 3, 6, 12, 24, 36, 60]
    static let warnMonthChoices = [1, 3, 6]

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
    @Published var items: [MaintItem] { didSet { save(); checkReminders(); scheduleTimeNotifications() } }

    init() {
        let d = UserDefaults.standard
        odometerKm = d.double(forKey: "maint.odo.v3")
        if let data = d.data(forKey: "maint.items.v3"),
           let it = try? JSONDecoder().decode([MaintItem].self, from: data) {
            items = MaintenanceStore.normalized(it)
        } else {
            items = MaintenanceStore.defaults()
        }
        scheduleTimeNotifications()
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

    // MARK: - Status

    func remainingKm(_ item: MaintItem) -> Int {
        Int((item.lastServiceKm + Double(item.intervalKm) - odometerKm).rounded())
    }

    /// Sisa hari sampai jatuh tempo (negatif = terlambat); nil bila tanggal belum bisa dihitung.
    func remainingDays(_ item: MaintItem, now: Date = Date()) -> Int? {
        guard let due = item.effectiveDueDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day
    }

    /// Tingkat, teks sisa, dan porsi terpakai sebuah item menurut acuannya (KM atau waktu).
    func status(_ item: MaintItem, now: Date = Date()) -> MaintStatus {
        switch item.basis {
        case .km:
            let rem = remainingKm(item)
            let used = max(0, odometerKm - item.lastServiceKm)
            let level: MaintLevel = rem < 0 ? .over : (rem <= item.warnKm ? .warn : .ok)
            return MaintStatus(level: level,
                               text: rem < 0 ? tr("Overdue {0} km", -rem) : tr("{0} km left", rem),
                               fraction: min(1, used / Double(max(1, item.intervalKm))))
        case .time:
            guard let due = item.effectiveDueDate, let days = remainingDays(item, now: now) else {
                return MaintStatus(level: .ok, text: tr("Set a due date"), fraction: 0)
            }
            let cal = Calendar.current
            let warnStart = cal.date(byAdding: .month, value: -item.warnMonths, to: due) ?? due
            let level: MaintLevel = days < 0 ? .over : (now >= warnStart ? .warn : .ok)
            let text: String
            if days < 0 { text = tr("Overdue {0} days", -days) }
            else if days == 0 { text = tr("Due today") }
            else if days <= 60 { text = tr("{0} days left", days) }
            else { text = tr("{0} months left", Int((Double(days) / 30.4).rounded())) }
            let start = (item.repeats ? item.lastServiceDate : nil) ?? (cal.date(byAdding: .month, value: -item.intervalMonths, to: due) ?? now)
            let total = max(1, due.timeIntervalSince(start))
            return MaintStatus(level: level, text: text, fraction: min(1, max(0, now.timeIntervalSince(start) / total)))
        }
    }

    /// Sisa km terkecil di antara item beracuan KM (untuk ringkasan).
    /// Item beracuan kilometer yang paling dekat jadwalnya (untuk label "Sisa jarak <nama>").
    var nearestKmItem: MaintItem? {
        items.filter { $0.basis == .km }.min { remainingKm($0) < remainingKm($1) }
    }

    var nearestRemainingKm: Int? {
        items.filter { $0.basis == .km }.map { remainingKm($0) }.min()
    }

    // MARK: - Pengingat perawatan

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Kirim notifikasi lokal saat sebuah item masuk batas peringatannya sendiri atau lewat jadwal. Hanya saat status BERUBAH;
    /// evaluasi pertama hanya mencatat status (tanpa notifikasi) agar tidak membanjiri. Item beracuan KM butuh ODO terbaca.
    func checkReminders() {
        let d = UserDefaults.standard
        guard (d.object(forKey: "maintNotify") as? Bool) ?? true else { return }
        var state = (d.dictionary(forKey: "maint.notified") as? [String: String]) ?? [:]
        for item in items {
            if item.basis == .km && odometerKm <= 0 { continue }
            let st = status(item)
            let level = st.level == .over ? "over" : (st.level == .warn ? "warn" : "ok")
            let before = state[item.id]
            if before == level { continue }
            state[item.id] = level
            guard before != nil, level != "ok" else { continue }
            let c = UNMutableNotificationContent()
            c.title = tr("Maintenance due")
            c.body = item.title + ": " + st.text
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "maint." + item.id + "." + level, content: c, trigger: nil))
        }
        d.set(state, forKey: "maint.notified")
    }

    private var scheduleWork: DispatchWorkItem?

    /// Jadwalkan notifikasi untuk item beracuan waktu (muncul walau app tidak dibuka): satu saat masuk batas peringatan,
    /// satu saat jatuh tempo, pukul 09.00. Dijadwalkan ulang tiap data berubah (ditunda sebentar).
    func scheduleTimeNotifications() {
        scheduleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.applyTimeNotifications() }
        scheduleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    private func applyTimeNotifications() {
        let center = UNUserNotificationCenter.current()
        let enabled = (UserDefaults.standard.object(forKey: "maintNotify") as? Bool) ?? true
        let snapshot = items.filter { $0.basis == .time }
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map { $0.identifier }.filter { $0.hasPrefix("maint.time.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard enabled else { return }
            let cal = Calendar.current
            for item in snapshot {
                guard let due = item.effectiveDueDate else { continue }
                let warnDate = cal.date(byAdding: .month, value: -item.warnMonths, to: due) ?? due
                for (tag, date, body) in [("warn", warnDate, tr("{0} months left", item.warnMonths)),
                                          ("due", due, tr("Due today"))] {
                    var comps = cal.dateComponents([.year, .month, .day], from: date)
                    comps.hour = 9
                    guard let fire = cal.date(from: comps), fire > Date() else { continue }
                    let c = UNMutableNotificationContent()
                    c.title = tr("Maintenance due")
                    c.body = item.title + ": " + (tag == "warn" ? tr("Due on {0}", MaintHistorySheet.dateString(due)) : body)
                    c.sound = .default
                    let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: "maint.time.\(item.id).\(tag)", content: c, trigger: trig))
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "maint.items.v3")
        }
    }

    // MARK: - Perubahan data

    /// Catat penggantian/perpanjangan: tanggal (bawaan hari ini) dan ODO saat diganti (bawaan ODO sekarang).
    /// Acuan KM: sisa km dihitung dari ODO ini. Acuan waktu berulang: jatuh tempo berikutnya = tanggal ini + selang; tidak berulang: tanggal baru diisi pengguna.
    /// Item waktu yang tidak berulang tidak punya jatuh tempo berikutnya otomatis: isi `newDue` (tanggal baru di dokumen).
    func markServiced(_ id: String, date: Date = Date(), odoKm: Double? = nil, newDue: Date? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let odo = odoKm ?? odometerKm
        items[i].lastServiceKm = odo
        items[i].lastServiceDate = date
        if items[i].basis == .time {
            if items[i].repeats {
                items[i].dueDate = Calendar.current.date(byAdding: .month, value: items[i].intervalMonths, to: date)
            } else if let n = newDue {
                items[i].dueDate = n
            }
        }
        items[i].history.insert(MaintLog(id: UUID().uuidString, date: date, odoKm: odo), at: 0)
        items[i].history.sort { $0.date > $1.date }
    }

    func addItem(_ item: MaintItem) {
        items.append(item)
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id && !$0.isDefault }     // item bawaan tidak bisa dihapus
    }
}
