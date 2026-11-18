import UIKit
import CoreImage
import CoreLocation

enum DashScreen: Int, CaseIterable {
    case mapData = 0, mapOnly = 1, dashboard = 2, music = 3, slideshow = 4

    var title: String {
        switch self {
        case .mapData: return "Peta + data"
        case .mapOnly: return "Peta saja"
        case .dashboard: return "Speedometer"
        case .music: return "Musik"
        case .slideshow: return "Foto"
        }
    }
}

struct MusicInfo {
    var title = ""
    var artist = ""
    var duration: Double = 0
    var position: Double = 0
    var playing = false
    var artwork: UIImage?
}

struct NavHUD {
    var icon: UInt8
    var text: String        // "Belok kanan"
    var dist: String        // "65 m"
    var summary: String     // "10,5 km · 22:32"
    var street: String
}

struct DashContent {
    var night = false
    var speedKmh = 0
    var speedFromBike = false
    var phoneBattery = -1
    var fuelL: Double?
    var batteryV: Double?
    var odoKm: Double?
    var tempC: Int?
    var weatherText = ""
    var greeting = ""
    var clock = ""
    var nav: NavHUD?
    var showCards = true
    var routeColor = UIColor(red: 0.95, green: 0.2, blue: 0.5, alpha: 1)
    var music: MusicInfo?
    var slide: UIImage?
    var coolantC: Int?
    var airC: Int?
    var rpm: Int?
    var rangeKm: Int?
    var ignitionOn: Bool?
    var card = CardConfig()
    var musicBlurBG = true
    var routeWidth: CGFloat = 5
    var routeBorder: CGFloat = 1.5
    var markerScale: CGFloat = 1
    var markerRing = true
    var markerY: CGFloat = 0.68
    var navScale: CGFloat = 1
    var etaScale: CGFloat = 1
    var infoDashL = 10
    var infoDashR = 13
    var infoMusicL = 10
    var infoMusicR = 8
    var infoPhotoL = 10
    var infoPhotoR = 8
    var photoShift: CGFloat = 0
}

struct DashHUD {
    var size: CGSize
    var screen: DashScreen
    var content: DashContent
    var center: CLLocationCoordinate2D
    var bearing: Double
    var zoom: Double
    var route: [CLLocationCoordinate2D]
    var destination: CLLocationCoordinate2D?
}

enum DashRenderer {
    private static let queue = DispatchQueue(label: "dash.render", qos: .userInitiated)

    static func render(_ hud: DashHUD, completion: @escaping (UIImage) -> Void) {
        queue.async {
            let img = DashComposer.image(hud)
            DispatchQueue.main.async { completion(img) }
        }
    }
}

enum DashComposer {
    // Dash menutup sekitar 6 px di atas dan 54 px di bawah bingkai (header dan bar nama jalan).
    private static let visTop: CGFloat = 6
    private static let visHeight: CGFloat = 174

    static func image(_ hud: DashHUD) -> UIImage {
        let size = hud.size
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let vis = CGRect(x: 0, y: visTop, width: size.width, height: visHeight)
            switch hud.screen {
            case .dashboard: drawDashboard(cg, hud, vis)
            case .mapOnly: drawMapScreen(cg, hud, vis, cards: false)
            case .mapData: drawMapScreen(cg, hud, vis, cards: true)
            case .music: drawMusic(cg, hud, vis)
            case .slideshow: drawSlideshow(cg, hud, vis)
            }
        }
    }

    // MARK: - Layar peta

    private static func drawMapScreen(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect, cards: Bool) {
        let c = hud.content
        let withCards = cards && c.showCards
        let full = CGRect(origin: .zero, size: hud.size)
        // area peta bebas = kiri panel kartu; titik motor di tengahnya (bukan terlalu kiri)
        let anchor = CGPoint(x: withCards ? 192 : hud.size.width / 2,
                             y: vis.minY + vis.height * c.markerY)
        let vp = VMapViewport(rect: full, anchor: anchor, zoom: hud.zoom, bearing: hud.bearing,
                              center: hud.center, night: c.night, route: hud.route,
                              destination: hud.destination, routeColor: c.routeColor,
                              routeWidth: c.routeWidth, routeBorder: c.routeBorder,
                              markerScale: c.markerScale, markerRing: c.markerRing)
        VectorMapRenderer.draw(vp, in: cg)

        if let n = c.nav {
            let green = UIColor(red: 0.04, green: 0.45, blue: 0.30, alpha: 0.96)
            let k = max(0.6, min(1.4, c.navScale))
            // panel belokan di kiri atas (sedikit ke tengah supaya tidak tertutup tombol zoom dash)
            cg.saveGState()
            cg.translateBy(x: 8, y: vis.minY + 2)
            cg.scaleBy(x: k, y: k)
            let r = CGRect(x: 0, y: 0, width: 200, height: 54)
            fillRound(r, radius: 10, color: green)
            TurnGlyph.draw(cg, code: n.icon, in: CGRect(x: 14, y: 3, width: 48, height: 48), color: .white)
            text(n.text, CGRect(x: 68, y: 6, width: 128, height: 22), size: 15, bold: true)
            text(n.dist, CGRect(x: 68, y: 28, width: 128, height: 22), size: 17, bold: true,
                 color: UIColor(white: 1, alpha: 0.9))
            cg.restoreGState()

            // jarak + ETA: pil di bawah, digeser ke kanan dari tombol zoom
            cg.saveGState()
            let ke = max(0.6, min(1.4, c.etaScale))
            let pw: CGFloat = 150 * ke, ph: CGFloat = 26 * ke
            cg.translateBy(x: 54, y: vis.maxY - ph - 4)
            cg.scaleBy(x: ke, y: ke)
            let pill = CGRect(x: 0, y: 0, width: 150, height: 26)
            fillRound(pill, radius: 13, color: green)
            text(n.summary, pill, size: 13, bold: true, align: .center, inset: 4)
            cg.restoreGState()
            _ = pw
        }

        if withCards { drawCards(cg, c, vis, hud.size) }
    }

    // MARK: - Kotak data (fleksibel)

    private static func drawCards(_ cg: CGContext, _ c: DashContent, _ vis: CGRect, _ size: CGSize) {
        let cfg = c.card
        let x: CGFloat = 338, w: CGFloat = 140
        let top = vis.minY + 2
        let total = vis.height - 4
        let gap: CGFloat = 4
        func field(_ i: Int) -> DashField { DashField(rawValue: i) ?? .none }

        // lapisan hampir hitam di belakang kolom kotak (seperti NConnect)
        fillRound(CGRect(x: x - 5, y: top - 2, width: size.width - (x - 5), height: total + 4), radius: 14,
                  color: UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 0.86))

        var smallRects = [CGRect]()
        var y = top
        if cfg.layout == 0 || cfg.layout == 1 {
            let bigH: CGFloat = cfg.layout == 0 ? 104 : 80
            drawBig(cg, field(cfg.big), c, CGRect(x: x, y: top, width: w, height: bigH))
            y = top + bigH + gap
        }
        let rest = top + total - y
        switch cfg.layout {
        case 0:
            let sw = (w - gap) / 2
            for i in 0..<2 { smallRects.append(CGRect(x: x + CGFloat(i) * (sw + gap), y: y, width: sw, height: rest)) }
        default:
            let rows: CGFloat = 2
            let sh = (rest - gap * (rows - 1)) / rows
            let sw = (w - gap) / 2
            for r in 0..<2 { for col in 0..<2 {
                smallRects.append(CGRect(x: x + CGFloat(col) * (sw + gap), y: y + CGFloat(r) * (sh + gap), width: sw, height: sh))
            } }
        }
        for (i, r) in smallRects.enumerated() {
            let f = field(i < cfg.small.count ? cfg.small[i] : DashField.none.rawValue)
            drawSmall(cg, f, c, r)
        }
    }

    private static func drawBig(_ cg: CGContext, _ f: DashField, _ c: DashContent, _ r: CGRect) {
        guard f != .none else { return }
        cg.saveGState()
        UIBezierPath(roundedRect: r, cornerRadius: 12).addClip()
        let cols: [CGColor] = c.night
            ? [UIColor(red: 0.20, green: 0.17, blue: 0.44, alpha: 1).cgColor, UIColor(red: 0.50, green: 0.20, blue: 0.46, alpha: 1).cgColor]
            : [UIColor(red: 0.40, green: 0.27, blue: 0.64, alpha: 1).cgColor, UIColor(red: 0.80, green: 0.32, blue: 0.52, alpha: 1).cgColor]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: [0, 1]) {
            cg.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        }
        cg.restoreGState()
        if f == .weather {
            text("Halo", CGRect(x: r.minX + 10, y: r.minY + 5, width: r.width - 20, height: 13), size: 11,
                 color: UIColor(white: 1, alpha: 0.85))
            text(c.greeting.isEmpty ? "Pengendara" : c.greeting,
                 CGRect(x: r.minX + 10, y: r.minY + 17, width: r.width - 20, height: 20), size: 16, bold: true)
            let big = c.tempC.map { "\($0)°" } ?? "--°"
            text(big, CGRect(x: r.minX + 10, y: r.minY + 37, width: 70, height: 32), size: 28, bold: true)
            text(c.weatherText.isEmpty ? "Cuaca" : c.weatherText,
                 CGRect(x: r.minX + 10, y: r.maxY - 18, width: r.width - 20, height: 14), size: 12,
                 color: UIColor(white: 1, alpha: 0.9))
        } else {
            let (label, value, unit, color) = f.resolve(c)
            text(label, CGRect(x: r.minX + 10, y: r.minY + 8, width: r.width - 20, height: 14), size: 12,
                 color: UIColor(white: 1, alpha: 0.85))
            text(value, CGRect(x: r.minX + 10, y: r.minY + 26, width: r.width - 60, height: 40), size: 34, bold: true,
                 color: color)
            text(unit, CGRect(x: r.maxX - 52, y: r.maxY - 28, width: 44, height: 18), size: 14, bold: true,
                 color: UIColor(white: 1, alpha: 0.85), align: .right)
        }
    }

    private static func drawSmall(_ cg: CGContext, _ f: DashField, _ c: DashContent, _ r: CGRect) {
        guard f != .none else { return }
        fillRound(r, radius: 10, color: UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 0.94))
        UIColor(white: 1, alpha: 0.10).setStroke()
        let b = UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
        b.lineWidth = 1
        b.stroke()
        let (label, value, unit, color) = f == .weather ? ("Suhu", c.tempC.map { "\($0)" } ?? "--", "°C", UIColor.white) : f.resolve(c)
        text(label, CGRect(x: r.minX + 4, y: r.minY + 5, width: r.width - 8, height: 11), size: 9,
             color: UIColor(white: 1, alpha: 0.7), align: .center)
        let tall = r.height > 60
        let shown = (unit.isEmpty || tall) ? value : "\(value) \(unit)"
        let n = shown.count
        let fs: CGFloat = n <= 4 ? 19 : (n <= 6 ? 16 : (n <= 8 ? 13 : 11))
        let area = CGRect(x: r.minX + 2, y: r.minY + 17, width: r.width - 4, height: tall ? r.height - 34 : r.height - 21)
        text(shown, area, size: fs, bold: true, color: color, align: .center)
        if tall && !unit.isEmpty {
            text(unit, CGRect(x: r.minX + 2, y: r.maxY - 16, width: r.width - 4, height: 12), size: 10,
                 color: UIColor(white: 1, alpha: 0.7), align: .center)
        }
    }

    /// Teks untuk slot info pojok atas (kosong bila dipilih "Kosong").
    private static func slotText(_ raw: Int, _ c: DashContent) -> String {
        let f = DashField(rawValue: raw) ?? .none
        if f == .none { return "" }
        let (_, v, u, _) = f.resolve(c)
        return u.isEmpty ? v : "\(v) \(u)"
    }

    // MARK: - Layar dasbor

    private static func drawDashboard(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect) {
        let c = hud.content
        let bg = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        bg.setFill()
        cg.fill(CGRect(origin: .zero, size: hud.size))

        text(slotText(c.infoDashL, c), CGRect(x: 8, y: vis.minY + 3, width: 130, height: 20), size: 17, bold: true)
        text(slotText(c.infoDashR, c), CGRect(x: 140, y: vis.minY + 5, width: 198, height: 16), size: 13,
             align: .right)

        // bilah kecepatan
        let barX: CGFloat = 8
        let barY = vis.minY + 40
        let barW: CGFloat = 330
        let barH: CGFloat = 20
        let marks: [(Int, String)] = [(0, "0"), (40, "40"), (80, "80"), (120, "120"), (160, "160")]
        for (v, label) in marks {
            let x = barX + barW * CGFloat(v) / 160
            let color = v >= 120 ? UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1) : UIColor(white: 0.8, alpha: 1)
            let r = CGRect(x: min(max(x - 15, 0), barX + barW - 30), y: barY - 14, width: 30, height: 12)
            text(label, r, size: 9, color: color, align: v == 0 ? .left : (v == 160 ? .right : .center))
        }
        let segs = 40
        let gap: CGFloat = 1
        let segW = (barW - gap * CGFloat(segs - 1)) / CGFloat(segs)
        let lit = min(segs, max(0, Int(Double(c.speedKmh) / 160.0 * Double(segs))))
        for i in 0..<segs {
            let red = i >= 30
            let color: UIColor
            if i < lit {
                color = red ? UIColor(red: 1, green: 0.25, blue: 0.25, alpha: 1) : UIColor(red: 0.25, green: 0.65, blue: 1, alpha: 1)
            } else {
                color = red ? UIColor(red: 0.45, green: 0.12, blue: 0.12, alpha: 1) : UIColor(white: 0.28, alpha: 1)
            }
            color.setFill()
            cg.fill(CGRect(x: barX + CGFloat(i) * (segW + gap), y: barY, width: segW, height: barH))
        }
        text(c.speedFromBike ? "km/h · MOTOR" : "km/h · GPS",
             CGRect(x: 200, y: barY + barH + 2, width: 138, height: 12), size: 8,
             color: UIColor(white: 0.7, alpha: 1), align: .right)

        // kecepatan besar
        text("\(c.speedKmh)", CGRect(x: 66, y: barY + 24, width: 190, height: 58), size: 52, bold: true, align: .center)
        text("km/h", CGRect(x: 258, y: barY + 52, width: 80, height: 20), size: 15, color: UIColor(white: 0.85, alpha: 1))

        // kartu bawah
        let cardY = vis.minY + 124
        let cardH: CGFloat = 48
        let items: [(String, String)] = [
            ("BATERAI HP", c.phoneBattery >= 0 ? "\(c.phoneBattery)%" : "—"),
            ("SISA BENSIN", c.fuelL.map { Fmt.liters($0) } ?? "—"),
            ("AKI", c.batteryV.map { String(format: "%.1f V", $0) } ?? "—")
        ]
        for (i, it) in items.enumerated() {
            let r = CGRect(x: 8 + CGFloat(i) * 112, y: cardY, width: 106, height: cardH)
            fillRound(r, radius: 8, color: UIColor(white: 0.14, alpha: 1))
            text(it.0, CGRect(x: r.minX + 8, y: r.minY + 5, width: 92, height: 11), size: 8,
                 color: UIColor(white: 0.7, alpha: 1))
            text(it.1, CGRect(x: r.minX + 8, y: r.minY + 18, width: 92, height: 26), size: 21, bold: true)
        }

        // panel kanan: navigasi + peta mini
        let panelX: CGFloat = 346
        let panelW: CGFloat = 130
        var mapTop = vis.minY + 2
        if let n = c.nav {
            let r = CGRect(x: panelX, y: mapTop, width: panelW, height: 70)
            fillRound(r, radius: 10, color: UIColor(red: 0.04, green: 0.45, blue: 0.30, alpha: 1))
            TurnGlyph.draw(cg, code: n.icon, in: CGRect(x: r.minX + 6, y: r.minY + 6, width: 34, height: 34), color: .white)
            text(n.text, CGRect(x: r.minX + 44, y: r.minY + 5, width: 82, height: 16), size: 12, bold: true)
            text(n.dist, CGRect(x: r.minX + 44, y: r.minY + 22, width: 82, height: 20), size: 17, bold: true)
            text(n.summary, CGRect(x: r.minX + 6, y: r.minY + 48, width: 118, height: 16), size: 11, bold: true,
                 align: .center)
            mapTop = r.maxY + 4
        }
        let mapRect = CGRect(x: panelX, y: mapTop, width: panelW, height: vis.maxY - mapTop - 2)
        cg.saveGState()
        UIBezierPath(roundedRect: mapRect, cornerRadius: 10).addClip()
        let vp = VMapViewport(rect: mapRect, anchor: CGPoint(x: mapRect.width / 2, y: mapRect.height * 0.62),
                              zoom: hud.zoom - 0.6, bearing: hud.bearing, center: hud.center, night: c.night,
                              route: hud.route, destination: hud.destination, routeColor: c.routeColor,
                              routeWidth: max(3, c.routeWidth * 0.7), routeBorder: c.routeBorder * 0.7,
                              markerScale: c.markerScale * 0.7, markerRing: false)
        VectorMapRenderer.draw(vp, in: cg)
        cg.restoreGState()
    }

    // MARK: - Layar musik dan foto

    private static func mmss(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func drawFill(_ img: UIImage, in r: CGRect) {
        guard img.size.width > 0, img.size.height > 0 else { return }
        let k = max(r.width / img.size.width, r.height / img.size.height)
        let w = img.size.width * k
        let h = img.size.height * k
        img.draw(in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
    }

    private static var softKey: UIImage?
    private static var softVal: UIImage?

    private static let ciContext = CIContext(options: nil)

    /// Blur halus: kecilkan sampul ke 96 px, blur Gaussian (Core Image), lalu rentangkan. Di-cache per sampul.
    private static func softBackground(_ img: UIImage) -> UIImage? {
        if softKey === img { return softVal }
        let small = CGSize(width: 96, height: 96)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let base = UIGraphicsImageRenderer(size: small, format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            img.draw(in: CGRect(origin: .zero, size: small))
        }
        var result = base
        if let cgBase = base.cgImage {
            let ci = CIImage(cgImage: cgBase)
            let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: 7).cropped(to: ci.extent)
            if let out = ciContext.createCGImage(blurred, from: ci.extent) { result = UIImage(cgImage: out) }
        }
        softKey = img
        softVal = result
        return result
    }

    private static func drawMusic(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect) {
        let c = hud.content
        UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1).setFill()
        cg.fill(CGRect(origin: .zero, size: hud.size))
        if c.musicBlurBG, let img = c.music?.artwork, let soft = softBackground(img) {
            // sampul diperbesar + blur (cache), lalu digelapkan seperti di NConnect
            cg.interpolationQuality = .high
            drawFill(soft, in: CGRect(origin: .zero, size: hud.size))
            UIColor(white: 0, alpha: 0.42).setFill()
            cg.fill(CGRect(origin: .zero, size: hud.size))
        }
        text(slotText(c.infoMusicL, c), CGRect(x: 8, y: vis.minY + 3, width: 130, height: 20), size: 17, bold: true)
        text(slotText(c.infoMusicR, c), CGRect(x: 300, y: vis.minY + 5, width: 174, height: 18), size: 14, bold: true,
             align: .right)
        guard let m = c.music, !m.title.isEmpty else {
            text("Tidak ada musik", CGRect(x: 0, y: vis.minY + 58, width: hud.size.width, height: 28), size: 21,
                 bold: true, align: .center)
            text("Putar lagu lewat app Musik di iPhone", CGRect(x: 0, y: vis.minY + 92, width: hud.size.width, height: 18),
                 size: 12, color: UIColor(white: 0.7, alpha: 1), align: .center)
            return
        }
        let art = CGRect(x: 70, y: vis.minY + 28, width: 130, height: 130)
        cg.saveGState()
        UIBezierPath(roundedRect: art, cornerRadius: 12).addClip()
        if let img = m.artwork {
            drawFill(img, in: art)
        } else {
            UIColor(white: 0.18, alpha: 1).setFill()
            cg.fill(art)
            text("♪", art, size: 54, bold: true, color: UIColor(white: 0.6, alpha: 1), align: .center)
        }
        cg.restoreGState()

        let x: CGFloat = 214
        let w: CGFloat = 258
        text(m.title, CGRect(x: x, y: vis.minY + 30, width: w, height: 52), size: 20, bold: true, lines: 2)
        text(m.artist, CGRect(x: x, y: vis.minY + 86, width: w, height: 18), size: 14,
             color: UIColor(white: 0.75, alpha: 1))
        let bar = CGRect(x: x, y: vis.minY + 116, width: w, height: 5)
        UIColor(white: 0.3, alpha: 1).setFill()
        UIBezierPath(roundedRect: bar, cornerRadius: 2.5).fill()
        let frac = m.duration > 0 ? CGFloat(min(1, max(0, m.position / m.duration))) : 0
        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * frac, height: bar.height),
                     cornerRadius: 2.5).fill()
        text(mmss(m.position), CGRect(x: x, y: vis.minY + 124, width: 80, height: 14), size: 11,
             color: UIColor(white: 0.7, alpha: 1))
        text(mmss(m.duration), CGRect(x: x + w - 80, y: vis.minY + 124, width: 80, height: 14), size: 11,
             color: UIColor(white: 0.7, alpha: 1), align: .right)
        text(m.playing ? "▶  Diputar" : "❚❚  Jeda", CGRect(x: x, y: vis.minY + 144, width: w, height: 16), size: 12,
             bold: true, color: UIColor(white: 0.85, alpha: 1))
    }

    private static func drawSlideshow(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect) {
        let c = hud.content
        let full = CGRect(origin: .zero, size: hud.size)
        UIColor.black.setFill()
        cg.fill(full)
        if let img = c.slide {
            // isi hanya area yang terlihat di dash (di luar itu tertutup header dan bar jalan)
            cg.saveGState()
            cg.clip(to: vis)
            drawFill(img, in: vis.offsetBy(dx: 0, dy: c.photoShift))
            cg.restoreGState()
        } else {
            text("Belum ada foto", CGRect(x: 0, y: vis.minY + 62, width: hud.size.width, height: 26), size: 20, bold: true,
                 align: .center)
            text("Tambahkan di Pengaturan > Foto slideshow", CGRect(x: 0, y: vis.minY + 94, width: hud.size.width, height: 16),
                 size: 12, color: UIColor(white: 0.7, alpha: 1), align: .center)
        }
        let left = slotText(c.infoPhotoL, c)
        if !left.isEmpty {
            let w = max(62, CGFloat(left.count) * 8 + 24)
            let clock = CGRect(x: 8, y: vis.minY + 4, width: w, height: 22)
            fillRound(clock, radius: 11, color: UIColor(white: 0, alpha: 0.5))
            text(left, clock, size: 13, bold: true, align: .center)
        }
        let right = slotText(c.infoPhotoR, c)
        if !right.isEmpty {
            let w = max(62, CGFloat(right.count) * 8 + 24)
            let spd = CGRect(x: hud.size.width - w - 8, y: vis.maxY - 28, width: w, height: 24)
            fillRound(spd, radius: 12, color: UIColor(white: 0, alpha: 0.5))
            text(right, spd, size: 13, bold: true, align: .center)
        }
    }

    // MARK: - Alat gambar

    private static func fillRound(_ r: CGRect, radius: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
    }

    private static func text(_ s: String, _ r: CGRect, size: CGFloat, bold: Bool = false,
                             color: UIColor = .white, align: NSTextAlignment = .left, inset: CGFloat = 0,
                             lines: Int = 1) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        ps.lineBreakMode = .byTruncatingTail
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
        var rr = r.insetBy(dx: inset, dy: 0)
        let h = font.lineHeight * CGFloat(lines)
        if rr.height > h {
            if lines == 1 && align == .center { rr.origin.y += (r.height - h) / 2 }
            rr.size.height = h + 2
        }
        (s as NSString).draw(in: rr, withAttributes: attrs)
    }
}

/// Ikon belok sederhana yang digambar dengan jalur vektor.
enum TurnGlyph {
    static func draw(_ cg: CGContext, code: UInt8, in r: CGRect, color: UIColor) {
        let s = min(r.width, r.height)
        cg.saveGState()
        cg.translateBy(x: r.midX, y: r.midY)
        cg.scaleBy(x: s / 100, y: s / 100)
        color.setStroke()
        color.setFill()

        switch code {
        case 0, 1, 2:
            let pole = UIBezierPath()
            pole.move(to: CGPoint(x: -16, y: 44))
            pole.addLine(to: CGPoint(x: -16, y: -42))
            pole.lineWidth = 9
            pole.lineCapStyle = .round
            pole.stroke()
            let flag = UIBezierPath()
            flag.move(to: CGPoint(x: -16, y: -42))
            flag.addLine(to: CGPoint(x: 34, y: -26))
            flag.addLine(to: CGPoint(x: -16, y: -8))
            flag.close()
            flag.fill()

        case 14:
            let ring = UIBezierPath(arcCenter: .zero, radius: 20, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            ring.lineWidth = 9
            ring.stroke()
            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: 0, y: 46))
            tail.addLine(to: CGPoint(x: 0, y: 22))
            tail.lineWidth = 9
            tail.lineCapStyle = .round
            tail.stroke()
            let out = UIBezierPath()
            out.move(to: CGPoint(x: 0, y: -20))
            out.addLine(to: CGPoint(x: 0, y: -34))
            out.lineWidth = 9
            out.lineCapStyle = .round
            out.stroke()
            arrowHead(at: CGPoint(x: 0, y: -34), dir: CGPoint(x: 0, y: -1))

        case 36, 37:
            if code == 36 { cg.scaleBy(x: -1, y: 1) }
            let u = UIBezierPath()
            u.move(to: CGPoint(x: 18, y: 44))
            u.addLine(to: CGPoint(x: 18, y: -8))
            u.addArc(withCenter: CGPoint(x: 0, y: -8), radius: 18, startAngle: 0, endAngle: CGFloat.pi, clockwise: false)
            u.addLine(to: CGPoint(x: -18, y: 14))
            u.lineWidth = 10
            u.lineCapStyle = .round
            u.lineJoinStyle = .round
            u.stroke()
            arrowHead(at: CGPoint(x: -18, y: 14), dir: CGPoint(x: 0, y: 1))

        default:
            var ang = 0.0
            switch code {
            case 7: ang = 40
            case 6: ang = -40
            case 35: ang = 90
            case 34: ang = -90
            case 33: ang = 135
            case 32: ang = -135
            default: ang = 0
            }
            let rad = ang * Double.pi / 180
            let dir = CGPoint(x: CGFloat(sin(rad)), y: CGFloat(-cos(rad)))
            let pivot = CGPoint(x: 0, y: 8)
            let end = CGPoint(x: pivot.x + dir.x * 34, y: pivot.y + dir.y * 34)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: 46))
            path.addLine(to: pivot)
            path.addLine(to: end)
            path.lineWidth = 11
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            arrowHead(at: end, dir: dir)
        }
        cg.restoreGState()
    }

    private static func arrowHead(at p: CGPoint, dir: CGPoint) {
        let perp = CGPoint(x: -dir.y, y: dir.x)
        let tip = CGPoint(x: p.x + dir.x * 18, y: p.y + dir.y * 18)
        let b1 = CGPoint(x: p.x + perp.x * 20, y: p.y + perp.y * 20)
        let b2 = CGPoint(x: p.x - perp.x * 20, y: p.y - perp.y * 20)
        let h = UIBezierPath()
        h.move(to: tip)
        h.addLine(to: b1)
        h.addLine(to: b2)
        h.close()
        h.fill()
    }
}
