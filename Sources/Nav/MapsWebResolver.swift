import Foundation
import UIKit
import WebKit

/// Membuka tautan Google Maps di WKWebView tersembunyi dengan identitas peramban PC, lalu menunggu
/// JavaScript Google mengubah alamatnya menjadi /maps/place/NAMA/@lat,lon/data=…!3d…!4d….
/// Pengambilan HTTP biasa tidak menjalankan JavaScript, jadi alamat itu tidak pernah terlihat di sana.
@MainActor
final class MapsWebResolver: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var urls = [String]()
    private var cont: CheckedContinuation<(urls: [String], html: String), Never>?
    private var timer: Timer?
    private var started = Date()
    private var centerSince: Date?
    private var timeout: TimeInterval = 14

    /// Mengembalikan semua alamat yang dilewati/terbentuk selama halaman dimuat, plus HTML akhirnya.
    static func run(_ url: URL, ua: String, timeout: TimeInterval = 14) async -> (urls: [String], html: String) {
        let r = MapsWebResolver()
        return await r.start(url, ua: ua, timeout: timeout)
    }

    private func start(_ url: URL, ua: String, timeout: TimeInterval) async -> (urls: [String], html: String) {
        await withCheckedContinuation { (c: CheckedContinuation<(urls: [String], html: String), Never>) in
            cont = c
            self.timeout = timeout
            started = Date()

            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 360, height: 640), configuration: cfg)
            w.customUserAgent = ua
            w.navigationDelegate = self
            w.alpha = 0.01
            w.isUserInteractionEnabled = false
            web = w
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.addSubview(w)

            let load = { w.load(URLRequest(url: url, timeoutInterval: 15)) }
            let props: [HTTPCookiePropertyKey: Any] = [.domain: ".google.com", .path: "/", .name: "CONSENT",
                                                       .value: "YES+cb.20210720-07-p0.id+FX+410", .secure: "TRUE"]
            if let ck = HTTPCookie(properties: props) {
                cfg.websiteDataStore.httpCookieStore.setCookie(ck) { load() }
            } else {
                load()
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    private func note(_ s: String) {
        let d = s.removingPercentEncoding ?? s
        if d != "about:blank", urls.last != d { urls.append(d) }
    }

    private func tick() {
        guard cont != nil, let w = web else { return }
        if let u = w.url?.absoluteString { note(u) }
        // alamat yang diubah JavaScript lewat history API (tanpa memuat ulang halaman)
        w.evaluateJavaScript("location.href") { [weak self] r, _ in
            Task { @MainActor in
                if let s = r as? String { self?.note(s) }
                self?.evaluate()
            }
        }
        evaluate()
    }

    private func evaluate() {
        guard cont != nil else { return }
        // titik pin tempat (!3d!4d): selesai
        if urls.contains(where: { MapsLink.pinCoordinate(from: $0) != nil }) { finish(); return }
        // baru ada @lat,lon: beri waktu sebentar menunggu !3d!4d yang lebih tepat
        if urls.contains(where: { MapsLink.placeCenter(from: $0) != nil }) {
            if centerSince == nil { centerSince = Date() }
            if let t = centerSince, Date().timeIntervalSince(t) > 3 { finish(); return }
        }
        if Date().timeIntervalSince(started) > timeout { finish() }
    }

    private func finish() {
        guard let c = cont else { return }
        cont = nil
        timer?.invalidate()
        timer = nil
        let w = web
        web = nil
        let collected = urls
        guard let view = w else { c.resume(returning: (collected, "")); return }
        view.evaluateJavaScript("document.documentElement.outerHTML") { r, _ in
            let html = String(((r as? String) ?? "").prefix(200_000))
            view.stopLoading()
            view.removeFromSuperview()
            c.resume(returning: (collected, html))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = navigationAction.request.url {
            note(u.absoluteString)
            let sc = (u.scheme ?? "").lowercased()
            // jangan biarkan Google membuka app lain (comgooglemaps://, intent://)
            if sc != "http" && sc != "https" && sc != "about" { decisionHandler(.cancel); return }
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish() }
}
