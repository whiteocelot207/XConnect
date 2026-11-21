import Foundation
import UIKit

/// Cek versi terbaru di GitHub Releases. Workflow GitHub Actions menerbitkan Release bertag
/// `v<x.y.z>` berisi XConnect.ipa, dengan nama "XConnect x.y.z". App membandingkan versi (x.y.z)
/// pada nama Release dengan versi yang terpasang; nomor build hanya cadangan bila nama tidak memuat versi.
///
/// Catatan iOS: app tidak bisa memasang IPA sendiri (tidak ada API untuk itu, dan IPA ini tidak
/// bertanda tangan Apple). Jalur tercepat: tombol "Pasang update" membuka SideStore, AltStore, atau
/// LiveContainer dengan URL IPA terbaru, sehingga cukup satu ketukan konfirmasi di sana.
final class UpdateService: ObservableObject {
    struct Release {
        var version: String
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
        if !l.version.isEmpty {
            return l.version.compare(UpdateService.currentVersion, options: .numeric) == .orderedDescending
        }
        return l.build > UpdateService.currentBuild
    }

    func check(repo: String, silent: Bool = false) {
        let r = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.split(separator: "/").count == 2,
              let url = URL(string: "https://api.github.com/repos/\(r)/releases/latest") else {
            if !silent { message = tr("Enter the GitHub repo as owner/repo-name") }
            return
        }
        checking = true
        if !silent { message = tr("Checking…") }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("XConnect", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checking = false
                self.lastChecked = Date()
                if let err = err { if !silent { self.message = tr("Failed: {0}", err.localizedDescription) }; return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if !silent { self.message = code == 404 ? tr("Repo/Release not found (the app cannot read private repos)") : tr("Failed to read update info (HTTP {0})", code) }
                    return
                }
                let tag = obj["tag_name"] as? String ?? ""
                let digits = tag.filter { $0.isNumber }
                let assets = obj["assets"] as? [[String: Any]] ?? []
                let ipa = assets.first(where: { ($0["name"] as? String ?? "").hasSuffix(".ipa") })
                let build = Int(digits) ?? 0
                guard let s = ipa?["browser_download_url"] as? String,
                      let ipaURL = URL(string: s) else {
                    if !silent { self.message = tr("The latest release has no .ipa file") }
                    return
                }
                let page = URL(string: obj["html_url"] as? String ?? "https://github.com/\(r)/releases") ?? url
                let relName = obj["name"] as? String ?? tag
                var ver = ""
                if let r = relName.range(of: "[0-9]+(\\.[0-9]+)+", options: .regularExpression) { ver = String(relName[r]) }
                else if let r = tag.range(of: "[0-9]+(\\.[0-9]+)+", options: .regularExpression) { ver = String(tag[r]) }
                self.latest = Release(version: ver, build: build, name: relName,
                                      notes: obj["body"] as? String ?? "", ipaURL: ipaURL, pageURL: page)
                if self.updateAvailable {
                    self.message = tr("Available: {0}", self.latest?.name ?? tag)
                } else if !silent {
                    self.message = tr("You are up to date ({0})", UpdateService.currentVersion)
                }
            }
        }.resume()
    }

    /// Aplikasi pemasang yang didukung; angkanya disimpan di pengaturan (`AppSettings.updater`).
    /// 0 = SideStore, 1 = AltStore, 2 = LiveContainer.
    static func storeName(_ app: Int) -> String {
        switch app {
        case 1: return "AltStore"
        case 2: return "LiveContainer"
        default: return "SideStore"
        }
    }

    /// Buka SideStore/AltStore/LiveContainer dengan URL IPA. Bila tidak ada, buka halaman Release.
    func install(using app: Int) {
        guard let l = latest else { return }
        let raw = l.ipaURL.absoluteString
        let enc = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let scheme: String
        switch app {
        case 1: scheme = "altstore://install?url=\(enc)"
        // LiveContainer: livecontainer://install?url=<URL IPA>. URL IPA dari GitHub Releases tidak berisi
        // karakter khusus query (& # ?), jadi dikirim apa adanya; cara ini jalan baik bila LiveContainer
        // membaca parameter lewat URLComponents maupun memotong string secara manual. Bila bundle ID sudah
        // ada, LiveContainer menawarkan "ganti" (data app tetap) atau pasang sebagai app baru.
        case 2: scheme = "livecontainer://install?url=\(raw)"
        default: scheme = "sidestore://install?url=\(enc)"
        }
        guard let u = URL(string: scheme) else { openDownloadPage(); return }
        let name = UpdateService.storeName(app)
        UIApplication.shared.open(u, options: [:]) { [weak self] ok in
            if !ok {
                self?.message = tr("The {0} app is not installed. Opening the download page…", name)
                UIApplication.shared.open(l.pageURL)
            }
        }
    }

    /// Tambahkan repo ini sebagai sumber di SideStore/AltStore/LiveContainer (cukup sekali). Setelah itu update
    /// muncul di app tersebut dengan bundle ID yang benar, tanpa error "bundle ID tidak cocok".
    /// Di LiveContainer sumber masuk ke tab Sources (fitur sumber ada di LiveContainer 3.7 ke atas).
    func addSource(repo: String, using app: Int) {
        let r = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.split(separator: "/").count == 2 else { message = tr("Enter the GitHub repo first (owner/repo-name)"); return }
        let src = "https://github.com/\(r)/releases/latest/download/source.json"
        let enc = src.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let scheme: String
        switch app {
        case 1: scheme = "altstore"
        case 2: scheme = "livecontainer"
        default: scheme = "sidestore"
        }
        let name = UpdateService.storeName(app)
        guard let u = URL(string: "\(scheme)://source?url=\(enc)") else { return }
        UIApplication.shared.open(u, options: [:]) { [weak self] ok in
            if !ok { self?.message = tr("The {0} app did not open. Add it manually: {1}", name, src) }
        }
    }

    func openDownloadPage() {
        if let l = latest { UIApplication.shared.open(l.pageURL) }
    }
}
