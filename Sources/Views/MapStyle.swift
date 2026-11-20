import SwiftUI
import MapLibre

/// Gaya peta untuk peta di dalam app (preview rute dan peta penuh), mengikuti "Tema aplikasi".
enum MapStyle {
    static let light = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let dark = URL(string: "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json")!

    /// theme: 0 = ikuti ponsel, 1 = gelap, 2 = terang
    static func isDark(theme: Int, system: ColorScheme) -> Bool {
        switch theme {
        case 1: return true
        case 2: return false
        default: return system == .dark
        }
    }

    static func url(dark: Bool) -> URL { dark ? Self.dark : Self.light }

    /// Sembunyikan logo dan tombol atribusi MapLibre.
    static func hideBranding(_ v: MLNMapView) {
        v.logoView.isHidden = true
        v.attributionButton.isHidden = true
    }
}
