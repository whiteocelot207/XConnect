import Foundation
import UIKit

/// Cek versi terbaru di GitHub Releases. Workflow GitHub Actions menerbitkan Release bertag
/// `build-<nomor>` berisi XConnect.ipa. App membandingkan nomor build-nya dengan build yang terpasang.
///
/// Catatan iOS: app tidak bisa memasang IPA sendiri (tidak ada API untuk itu, dan IPA ini tidak
/// bertanda tangan Apple). Jalur tercepat: tombol "Pasang update" membuka SideStore/AltStore dengan
/// URL IPA terbaru, sehingga cukup satu ketukan konfirmasi di sana.
final class UpdateService: ObservableObject {
    struct Release {
        var build: Int
        var name: String
        var notes: String
        var ipaURL: URL
        var pageURL: URL
    }

    @Published var checking = false
    @Published var latest: Release?
    @Published var message = ""
    @Published var lastChecked: Date?

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var updateAvailable: Bool {
        guard let l = latest else { return false }
        return l.build > UpdateService.currentBuild
    }

    func check(repo: String, silent: Bool = false) {
        let r = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.split(separator: "/").count == 2,
              let url = URL(string: "https://api.github.com/repos/\(r)/releases/latest") else {
            if !silent { message = "Isi repo GitHub dengan format pemilik/nama-repo" }
            return
        }
        checking = true
        if !silent { message = "Memeriksa…" }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("XConnect", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checking = false
                self.lastChecked = Date()
                if let err = err { if !silent { self.message = "Gagal: \(err.localizedDescription)" }; return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if !silent { self.message = code == 404 ? "Repo/Release tidak ditemukan (repo private tidak bisa dibaca app)" : "Gagal membaca info update (HTTP \(code))" }
                    return
                }
                let tag = obj["tag_name"] as? String ?? ""
                let digits = tag.filter { $0.isNumber }
                let assets = obj["assets"] as? [[String: Any]] ?? []
                let ipa = assets.first(where: { ($0["name"] as? String ?? "").hasSuffix(".ipa") })
                guard let build = Int(digits), let s = ipa?["browser_download_url"] as? String,
                      let ipaURL = URL(string: s) else {
                    if !silent { self.message = "Release terbaru tidak berisi file .ipa" }
                    return
                }
                let page = URL(string: obj["html_url"] as? String ?? "https://github.com/\(r)/releases") ?? url
                self.latest = Release(build: build, name: obj["name"] as? String ?? tag,
                                      notes: obj["body"] as? String ?? "", ipaURL: ipaURL, pageURL: page)
                if self.updateAvailable {
                    self.message = "Tersedia: \(self.latest?.name ?? tag)"
                } else if !silent {
                    self.message = "Sudah versi terbaru (build \(UpdateService.currentBuild))"
                }
            }
        }.resume()
    }

    /// Buka SideStore/AltStore dengan URL IPA. Bila tidak ada, buka halaman Release.
    func install(using app: Int) {
        guard let l = latest else { return }
        let enc = l.ipaURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let schemes = app == 1 ? ["altstore://install?url=\(enc)"] : ["sidestore://install?url=\(enc)"]
        for s in schemes {
            if let u = URL(string: s) {
                UIApplication.shared.open(u, options: [:]) { [weak self] ok in
                    if !ok { self?.message = "App \(app == 1 ? "AltStore" : "SideStore") tidak terpasang. Membuka halaman unduhan…"
                        UIApplication.shared.open(l.pageURL) }
                }
                return
            }
        }
    }

    func openDownloadPage() {
        if let l = latest { UIApplication.shared.open(l.pageURL) }
    }
}
