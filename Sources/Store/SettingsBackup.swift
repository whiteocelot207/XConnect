import SwiftUI
import UniformTypeIdentifiers

/// Dokumen JSON untuk cadangan pengaturan.
struct SettingsBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, .data] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension AppSettings {
    /// Data motor berupa nilai sederhana (nama, tipe, tahun, plat, tangki, ODO, level bensin).
    static let vehicleValueKeys: [String] = [
        "veh.name", "veh.model", "veh.year", "veh.tank",
        "maint.odo.v3", "fuel.level", "fuel.odo", "fuel.mayBeOff"
    ]

    /// Data berupa JSON biner: tempat tersimpan (Rumah, Kantor, favorit; "Terakhir" tidak ikut), perawatan, isi bensin, pemakaian BBM, perjalanan.
    static let blobKeys: [String] = [
        "places.v1", "maint.items.v3", "fuel.fills", "fuel.useDays", "trips.v1"
    ]

    /// Foto motor disimpan sebagai file; ikut dicadangkan (base64).
    private static let photoName = "motor.jpg"

    /// Semua kunci pengaturan app (dari `defaultValues`, jadi pengaturan baru otomatis ikut) + data motor.
    static var backupKeys: [String] { defaultValues.keys.sorted() + vehicleValueKeys }

    func exportBackup() -> Data {
        let d = UserDefaults.standard
        var out: [String: Any] = [:]
        for k in AppSettings.backupKeys {
            if let v = d.object(forKey: k) { out[k] = v }
        }
        var blobs: [String: String] = [:]
        for k in AppSettings.blobKeys {
            guard var data = d.data(forKey: k) else { continue }
            if k == "places.v1" { data = PlaceStore.backupBlob(data) ?? data }   // tempat "Terakhir" tidak ikut
            blobs[k] = data.base64EncodedString()
        }
        var files: [String: String] = [:]
        if let photo = try? Data(contentsOf: VehicleStore.photoURL) {
            files[AppSettings.photoName] = photo.base64EncodedString()
        }
        let wrapper: [String: Any] = ["app": "XConnect", "format": 2, "settings": out, "data": blobs, "files": files]
        return (try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Mengembalikan jumlah item yang diterapkan, atau nil bila file bukan cadangan XConnect.
    /// Cadangan format 1 (hanya pengaturan) tetap bisa dipulihkan.
    func importBackup(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["app"] as? String == "XConnect",
              let s = obj["settings"] as? [String: Any] else { return nil }
        let d = UserDefaults.standard
        var n = 0
        for k in AppSettings.backupKeys {
            if let v = s[k] { d.set(v, forKey: k); n += 1 }
        }
        if let blobs = obj["data"] as? [String: String] {
            for k in AppSettings.blobKeys {
                guard let b64 = blobs[k], var raw = Data(base64Encoded: b64) else { continue }
                if k == "places.v1" { raw = PlaceStore.restoreBlob(raw, keepingRecentsFrom: d.data(forKey: k)) ?? raw }
                d.set(raw, forKey: k)
                n += 1
            }
        }
        if let files = obj["files"] as? [String: String], let b64 = files[AppSettings.photoName],
           let raw = Data(base64Encoded: b64) {
            try? raw.write(to: VehicleStore.photoURL)
            n += 1
        }
        reloadFromDefaults()
        AppModel.shared.reloadStores()
        return n
    }
}
