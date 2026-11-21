import Foundation

/// Nilai tetap app yang diatur lewat kode (bukan pengaturan pengguna).
enum AppConfig {
    /// Repo GitHub (pemilik/nama-repo) tempat Releases untuk update di dalam app.
    /// Untuk pindah sumber update di rilis berikutnya, cukup ubah nilai ini lalu build.
    /// Nilai lama yang pernah tersimpan di ponsel diabaikan, jadi perubahan di sini langsung berlaku
    /// setelah pengguna memasang rilis tersebut.
    static let updateRepo = "whiteocelot207/XConnect"
}
