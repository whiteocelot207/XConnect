import Foundation
import UIKit

/// Cadangan otomatis semua pengaturan dan data motor (bensin, ODO, perawatan, tempat tersimpan, dll.) di satu file.
///
/// Mengapa perlu: iOS meluncurkan app di latar belakang saat motor dinyalakan, termasuk SEBELUM ponsel dibuka kuncinya
/// sekali sejak restart. Pada saat itu berkas UserDefaults masih terenkripsi dan terbaca KOSONG; app memuat nilai bawaan,
/// lalu tulisan berikutnya menimpa berkas yang asli, sehingga data bensin dan pengaturan tampak "belum diatur".
/// File ini memakai proteksi `none` (terbaca kapan saja). Saat peluncuran, nilai yang hilang dari UserDefaults dipulihkan
/// dari file ini SEBELUM store membacanya.
enum Vault {
    private static let queue = DispatchQueue(label: "xconnect.vault", qos: .utility)
    private static var pending: DispatchWorkItem?
    private static var started = false
    /// jumlah item yang dipulihkan dari file pada peluncuran ini (0 = UserDefaults utuh)
    private(set) static var restoredCount = 0

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("XConnect", isDirectory: true)
            .appendingPathComponent("vault.plist")
    }

    /// Kunci yang dicadangkan. Nilai bawaan yang belum pernah diubah tidak ikut (hanya yang benar-benar tersimpan).
    private static var keys: [String] {
        Array(Set(AppSettings.backupKeys + AppSettings.blobKeys + ["ccu.peripheral"]))
    }

    private static func persistedDefaults() -> [String: Any] {
        guard let id = Bundle.main.bundleIdentifier else { return [:] }
        return UserDefaults.standard.persistentDomain(forName: id) ?? [:]
    }

    private static func read() -> [String: Any] {
        guard let u = url, let data = try? Data(contentsOf: u),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// Panggil PALING AWAL saat app diluncurkan, sebelum AppSettings dan semua store membaca UserDefaults.
    static func restore() {
        let saved = read()
        guard !saved.isEmpty else { return }
        let persisted = persistedDefaults()
        let d = UserDefaults.standard
        var n = 0
        for k in keys where persisted[k] == nil {
            if let v = saved[k] {
                d.set(v, forKey: k)
                n += 1
            }
        }
        restoredCount = n
    }

    /// Mulai mencadangkan otomatis: tiap UserDefaults berubah (ditunda 2 dtk), dan saat app ke latar belakang/ditutup.
    static func start() {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in schedule(after: 2) }
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            nc.addObserver(forName: name, object: nil, queue: nil) { _ in flush() }
        }
        schedule(after: 3)
    }

    private static func schedule(after seconds: TimeInterval) {
        queue.async {
            pending?.cancel()
            let w = DispatchWorkItem { write() }
            pending = w
            queue.asyncAfter(deadline: .now() + seconds, execute: w)
        }
    }

    /// Tulis sekarang juga (app akan ke latar belakang atau ditutup).
    static func flush() {
        UserDefaults.standard.synchronize()
        queue.sync {
            pending?.cancel()
            pending = nil
            write()
        }
    }

    private static func write() {
        guard let u = url else { return }
        // gabungkan dengan isi file lama: kunci yang sedang tidak terbaca di UserDefaults tidak boleh hilang dari cadangan
        var out = read()
        let persisted = persistedDefaults()
        for k in keys {
            guard var v = persisted[k] else { continue }
            // tempat "Terakhir" tidak ikut dicadangkan (Rumah, Kantor, dan favorit tetap ikut)
            if k == "places.v1", let data = v as? Data, let stripped = PlaceStore.backupBlob(data) { v = stripped }
            out[k] = v
        }
        guard !out.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])
            let data = try PropertyListSerialization.data(fromPropertyList: out, format: .binary, options: 0)
            try data.write(to: u, options: [.atomic, .noFileProtection])
        } catch {
            // cadangan gagal ditulis: UserDefaults tetap menjadi sumber utama
        }
    }
}
