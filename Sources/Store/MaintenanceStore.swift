import Foundation

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
    var history: [MaintLog]
}

final class MaintenanceStore: ObservableObject {
    /// Interval bawaan hanya perkiraan umum. Sesuaikan dengan buku manual motor Anda.
    static func defaults() -> [MaintItem] {
        [
            MaintItem(id: "oli-mesin", name: "Oli mesin", icon: "drop.fill", intervalKm: 4000, lastServiceKm: 0, history: []),
            MaintItem(id: "oli-gardan", name: "Oli gardan", icon: "gearshape.fill", intervalKm: 8000, lastServiceKm: 0, history: []),
            MaintItem(id: "filter-udara", name: "Filter udara", icon: "wind", intervalKm: 12000, lastServiceKm: 0, history: []),
            MaintItem(id: "busi", name: "Busi", icon: "bolt.fill", intervalKm: 12000, lastServiceKm: 0, history: []),
            MaintItem(id: "v-belt", name: "V-belt", icon: "arrow.triangle.2.circlepath", intervalKm: 24000, lastServiceKm: 0, history: [])
        ]
    }

    @Published var odometerKm: Double {
        didSet { UserDefaults.standard.set(odometerKm, forKey: "maint.odo.v3") }
    }
    @Published var odometerAuto = false
    @Published var items: [MaintItem] { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        odometerKm = d.double(forKey: "maint.odo.v3")
        if let data = d.data(forKey: "maint.items.v3"),
           let it = try? JSONDecoder().decode([MaintItem].self, from: data) {
            items = it
        } else {
            items = MaintenanceStore.defaults()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "maint.items.v3")
        }
    }

    func addKm(_ km: Double) {
        if km > 0 { odometerKm += km }
    }

    func remainingKm(_ item: MaintItem) -> Int {
        Int((item.lastServiceKm + Double(item.intervalKm) - odometerKm).rounded())
    }

    /// Sisa km terkecil di antara semua item (untuk ringkasan).
    var nearestRemainingKm: Int? {
        items.map { remainingKm($0) }.min()
    }

    func markServiced(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastServiceKm = odometerKm
        items[i].history.insert(MaintLog(id: UUID().uuidString, date: Date(), odoKm: odometerKm), at: 0)
    }

    func addItem(name: String, intervalKm: Int) {
        items.append(MaintItem(id: UUID().uuidString, name: name, icon: "wrench.fill", intervalKm: intervalKm,
                               lastServiceKm: odometerKm, history: []))
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }
}
