import MapLibre

/// Gaya peta untuk peta di dalam app (preview rute dan peta penuh): selalu terang.
enum MapStyle {
    static let light = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// Sembunyikan logo dan tombol atribusi MapLibre.
    static func hideBranding(_ v: MLNMapView) {
        v.logoView.isHidden = true
        v.attributionButton.isHidden = true
    }
}
