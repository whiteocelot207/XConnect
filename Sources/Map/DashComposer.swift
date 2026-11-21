import UIKit
import CoreImage
import CoreLocation

enum DashScreen: Int, CaseIterable {
    /// rawValue 1 (Peta saja) dan 5 (Tes tombol) sudah dihapus; nilai lain tetap supaya pengaturan lama tetap cocok.
    case mapData = 0, dashboard = 2, music = 3, slideshow = 4

    var title: String {
        switch self {
        case .mapData: return tr("Map")
        case .dashboard: return tr("Speedometer")
        case .music: return tr("Music")
        case .slideshow: return tr("Photos")
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
    var text: String        // "Jalan Lingkar Luar Jakarta" / "Ambil jalan keluar ke 3" (arah belok diwakili ikon)
    var dist: String        // "65 m"
    var summary: String     // "10,5 km · 22:32"
}

struct DashContent {
    var night = false
    /// gradasi tema warna (kotak data besar)
    var themeA = UIColor(red: 0.40, green: 0.27, blue: 0.64, alpha: 1)
    var themeB = UIColor(red: 0.80, green: 0.32, blue: 0.52, alpha: 1)
    var speedKmh = 0
    var speedFromBike = false
    var phoneBattery = -1
    var fuelL: Double?
    var batteryV: Double?
    var odoKm: Double?
    var tempC: Int?
    var weatherText = ""
    /// nama simbol SF Symbols ikon cuaca ("" = tanpa ikon)
    var weatherSymbol = ""
    var greeting = ""
    var warn = WarnThresholds()
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
    var greetingWord = tr("Hello")
    var cardBgAlpha: CGFloat = 0.78
    var markerX: CGFloat = 0
    var navDX: CGFloat = 0
    var navDY: CGFloat = 0
    var etaDX: CGFloat = 0
    var etaDY: CGFloat = 0
    var dtcCount: Int?
    var ccuSpeedKmh: Int?
    var ccuRaw: [UInt8] = []
    var phoneVolume = -1
    /// pesan singkat di layar Musik (mis. "Lagu berikutnya")
    var musicToast = ""
    var audioOut = ""
    var network = ""
    var dateText = ""
    var headingText = ""
    var altitudeM: Int?
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

    /// Gambar + encode JPEG di antrean render (bukan di thread utama, supaya tombol stang dan stream tidak tertahan).
    static func renderJPEG(_ hud: DashHUD, quality: CGFloat, completion: @escaping (UIImage, [UInt8]) -> Void) {
        queue.async {
            let img = DashComposer.image(hud)
            let jpeg = encode(img, quality: quality)
            DispatchQueue.main.async { completion(img, jpeg) }
        }
    }

    static func encode(_ image: UIImage, quality: CGFloat) -> [UInt8] {
        var jpeg = image.jpegData(compressionQuality: quality) ?? Data()
        if jpeg.count <= 2048, let hq = image.jpegData(compressionQuality: 0.95) {
            jpeg = hq
            if jpeg.count < 2050 { jpeg.append(Data(count: 2050 - jpeg.count)) }
        }
        return [UInt8](jpeg)
    }
}

enum DashComposer {
    // Dash menutup sekitar 6 px di atas dan 54 px di bawah bingkai (header dan bar nama jalan).
    static let visTop: CGFloat = 6
    static let visHeight: CGFloat = 174

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
            case .mapData: drawMapScreen(cg, hud, vis)
            case .music: drawMusic(cg, hud, vis)
            case .slideshow: drawSlideshow(cg, hud, vis)
            }
        }
    }

    // MARK: - Layar peta

    private static func drawMapScreen(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect) {
        let c = hud.content
        let withCards = c.showCards
        let full = CGRect(origin: .zero, size: hud.size)
        // area peta bebas = kiri panel kartu; titik motor di tengahnya (bukan terlalu kiri)
        let anchor = CGPoint(x: (withCards ? 192 : hud.size.width / 2) + c.markerX,
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
            // batas kanan area peta (kolom kotak data dimulai di x = 332)
            let rightLimit: CGFloat = withCards ? 326 : hud.size.width - 6

            // panel belokan: ikon arah di kiri; teks = judul ("Jalan Lingkar Luar Jakarta" / "Ambil jalan keluar ke 3")
            // lalu jarak. Arah belok tidak ditulis karena sudah diwakili ikon.
            let panelH: CGFloat = 54
            let textW = max(textWidth(n.text, size: 15, bold: true), textWidth(n.dist, size: 17, bold: true))
            let baseX = max(8 + c.navDX, 0)
            let avail = max(150, (rightLimit - baseX) / k)
            let panelW = min(max(150, 68 + textW + 12), avail)
            let navX = max(0, min(baseX, hud.size.width - panelW * k))
            let navY = min(max(vis.minY + 2 + c.navDY, vis.minY), vis.maxY - panelH * k)
            cg.saveGState()
            cg.translateBy(x: navX, y: navY)
            cg.scaleBy(x: k, y: k)
            fillRound(CGRect(x: 0, y: 0, width: panelW, height: panelH), radius: 10, color: green)
            TurnGlyph.draw(cg, code: n.icon, in: CGRect(x: 14, y: (panelH - 48) / 2, width: 48, height: 48), color: .white)
            let tw = panelW - 68 - 8
            let titleSize = fitSize(n.text, bold: true, maxSize: 15, width: tw, minSize: 9)
            text(n.text, CGRect(x: 68, y: 6, width: tw, height: 22), size: titleSize, bold: true)
            text(n.dist, CGRect(x: 68, y: 28, width: tw, height: 22), size: 17, bold: true,
                 color: UIColor(white: 1, alpha: 0.9))
            cg.restoreGState()

            // jarak + ETA: kotak di bawah, lebar mengikuti isi, sudut sama seperti panel belokan
            if !n.summary.isEmpty {
            let ke = max(0.6, min(1.4, c.etaScale))
            let pillW = max(70, textWidth(n.summary, size: 13, bold: true) + 20)
            let pillH: CGFloat = 28
            let pw = pillW * ke, ph = pillH * ke
            let etaX = max(0, min(max(54 + c.etaDX, 0), rightLimit - pw))
            let etaY = min(max(vis.maxY - ph - 4 + c.etaDY, vis.minY), vis.maxY - ph)
            cg.saveGState()
            cg.translateBy(x: etaX, y: etaY)
            cg.scaleBy(x: ke, y: ke)
            let pill = CGRect(x: 0, y: 0, width: pillW, height: pillH)
            fillRound(pill, radius: 6, color: green)
            text(n.summary, pill, size: 13, bold: true, align: .center, inset: 4)
            cg.restoreGState()
            }
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

        // lapisan gelap setinggi layar di belakang kolom kotak, tepi kirinya memudar (seperti NConnect)
        let panelX = x - 6
        let panelAlpha = min(1, max(0, c.cardBgAlpha))
        let panelColor = UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: panelAlpha)
        let fadeW: CGFloat = 14
        let clear = UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 0)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [clear.cgColor, panelColor.cgColor] as CFArray, locations: [0, 1]) {
            cg.saveGState()
            cg.clip(to: CGRect(x: panelX - fadeW, y: 0, width: fadeW, height: size.height))
            cg.drawLinearGradient(g, start: CGPoint(x: panelX - fadeW, y: 0), end: CGPoint(x: panelX, y: 0), options: [])
            cg.restoreGState()
        }
        panelColor.setFill()
        cg.fill(CGRect(x: panelX, y: 0, width: size.width - panelX, height: size.height))

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
        // gradasi dari tema warna; malam hari digelapkan agar tidak menyilaukan
        func shade(_ u: UIColor) -> CGColor {
            guard c.night else { return u.cgColor }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r * 0.5, green: g * 0.5, blue: b * 0.5, alpha: 1).cgColor
        }
        let cols: [CGColor] = [shade(c.themeA), shade(c.themeB)]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols as CFArray, locations: [0, 1]) {
            cg.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
        }
        cg.restoreGState()
        let k = max(0.5, min(1.5, c.card.bigScale))
        if f == .weather {
            // susunan teks vertikal; skala diturunkan otomatis bila tinggi kotak tidak cukup
            let sizes: [CGFloat] = [10, 15, 26, 11]
            let gap: CGFloat = 2
            let natural = sizes.reduce(CGFloat(0)) { $0 + $1 * 1.2 } + gap * 3
            let ke = min(k, (r.height - 8) / natural)
            let w = r.width - 20
            var y = r.minY + 4
            // ikon cuaca di kanan baris suhu + keterangan
            let icon: UIImage? = c.weatherSymbol.isEmpty ? nil : UIImage(
                systemName: c.weatherSymbol,
                withConfiguration: UIImage.SymbolConfiguration.preferringMulticolor())?.withRenderingMode(.alwaysOriginal)
            let iconSide = icon == nil ? CGFloat(0) : min(34 * ke, r.width * 0.3)
            func line(_ str: String, _ base: CGFloat, bold: Bool, alpha: CGFloat, width: CGFloat? = nil) {
                let lw = width ?? w
                let size = fitSize(str, bold: bold, maxSize: base * ke, width: lw, minSize: 7)
                let h = ceil(size * 1.2)
                text(str, CGRect(x: r.minX + 10, y: y, width: lw, height: h), size: size, bold: bold,
                     color: UIColor(white: 1, alpha: alpha))
                y += h + gap
            }
            line(c.greetingWord, sizes[0], bold: false, alpha: 0.85)
            line(c.greeting.isEmpty ? tr("Rider") : c.greeting, sizes[1], bold: true, alpha: 1)
            let iconTop = y
            let tw = w - (iconSide > 0 ? iconSide * 1.3 + 4 : 0)
            line(c.tempC.map { "\($0)°" } ?? "--°", sizes[2], bold: true, alpha: 1, width: tw)
            line(c.weatherText.isEmpty ? tr("Weather") : c.weatherText, sizes[3], bold: false, alpha: 0.9, width: tw)
            if let img = icon, iconSide > 0 {
                let aspect = img.size.height > 0 ? img.size.width / img.size.height : 1
                let ih = iconSide, iw = min(iconSide * 1.3, iconSide * aspect)
                let bandH = y - iconTop
                img.draw(in: CGRect(x: r.maxX - 10 - iw, y: iconTop + max(0, (bandH - ih) / 2), width: iw, height: ih))
            }
        } else {
            let (label, value, unit, color) = f.resolve(c)
            let labelSize = fitSize(label, bold: false, maxSize: 12 * k, width: r.width - 20, minSize: 7)
            text(label, CGRect(x: r.minX + 10, y: r.minY + 6, width: r.width - 20, height: ceil(labelSize * 1.2)),
                 size: labelSize, color: UIColor(white: 1, alpha: 0.85))
            let unitSize = 14 * min(k, 1.2)
            let unitW = unit.isEmpty ? 0 : textWidth(unit, size: unitSize, bold: true) + 6
            let top = r.minY + 6 + ceil(labelSize * 1.2)
            let bandH = max(10, r.maxY - 6 - top)
            let valW = r.width - 20 - unitW
            let maxV = min(34 * k, bandH / 1.2)
            let vs = fitSize(value, bold: true, maxSize: maxV, width: valW, minSize: 9)
            text(value, CGRect(x: r.minX + 10, y: top, width: valW, height: bandH), size: vs, bold: true,
                 color: color, vcenter: true)
            if !unit.isEmpty {
                text(unit, CGRect(x: r.maxX - unitW - 6, y: r.maxY - 8 - ceil(unitSize * 1.2), width: unitW, height: ceil(unitSize * 1.2)),
                     size: unitSize, bold: true, color: UIColor(white: 1, alpha: 0.85), align: .right)
            }
        }
    }

    private static func drawSmall(_ cg: CGContext, _ f: DashField, _ c: DashContent, _ r: CGRect) {
        guard f != .none else { return }
        fillRound(r, radius: 10, color: UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 0.94))
        UIColor(white: 1, alpha: 0.10).setStroke()
        let b = UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
        b.lineWidth = 1
        b.stroke()
        let k = max(0.5, min(1.5, c.card.smallScale))
        let (label, value, unit, color) = f == .weather ? (tr("Temp"), c.tempC.map { "\($0)" } ?? "--", "°C", UIColor.white) : f.resolve(c)
        let labelSize = fitSize(label, bold: false, maxSize: 9 * min(k, 1.3), width: r.width - 8, minSize: 6)
        let labelH = ceil(labelSize * 1.2)
        text(label, CGRect(x: r.minX + 4, y: r.minY + 4, width: r.width - 8, height: labelH), size: labelSize,
             color: UIColor(white: 1, alpha: 0.7), align: .center)
        let tall = r.height > 60
        let unitSize = 10 * min(k, 1.3)
        let unitH = (tall && !unit.isEmpty) ? ceil(unitSize * 1.2) + 2 : 0
        let shown = (unit.isEmpty || tall) ? value : "\(value) \(unit)"
        let areaTop = r.minY + 4 + labelH
        let area = CGRect(x: r.minX + 2, y: areaTop, width: r.width - 4, height: max(10, r.maxY - 3 - unitH - areaTop))
        let cap = (tall ? 26 : 20) * k
        let fs = fitSize(shown, bold: true, maxSize: min(cap, area.height / 1.2), width: area.width - 2, minSize: 7)
        text(shown, area, size: fs, bold: true, color: color, align: .center)
        if tall && !unit.isEmpty {
            text(unit, CGRect(x: r.minX + 2, y: r.maxY - 3 - unitH + 2, width: r.width - 4, height: unitH),
                 size: unitSize, color: UIColor(white: 1, alpha: 0.7), align: .center)
        }
    }

    /// Teks untuk slot info pojok atas (kosong bila dipilih "Kosong").
    private static func slotText(_ raw: Int, _ c: DashContent) -> String {
        let f = DashField(rawValue: raw) ?? .none
        if f == .none { return "" }
        let (_, v, u, _) = f.resolve(c)
        return u.isEmpty ? v : "\(v) \(u)"
    }

    /// Warna nilai untuk slot info pojok: mengikuti batas peringatan (merah/kuning/hijau), bukan selalu putih.
    private static func slotColor(_ raw: Int, _ c: DashContent) -> UIColor {
        let f = DashField(rawValue: raw) ?? .none
        if f == .none { return .white }
        return f.resolve(c).3
    }

    /// Info pojok dengan nama: "Kecepatan 40 km/h" (nama kecil abu-abu, nilai tebal putih). Mengecil bila tidak muat.
    private static func drawLabeledSlot(_ raw: Int, _ c: DashContent, in r: CGRect, size: CGFloat, align: NSTextAlignment) {
        let f = DashField(rawValue: raw) ?? .none
        if f == .none { return }
        let (label, v, u, valueColor) = f.resolve(c)
        let value = u.isEmpty ? v : "\(v) \(u)"
        if label.isEmpty { text(value, r, size: size, bold: true, color: valueColor, align: align); return }
        var sz = size
        // kecilkan sampai muat: nama berukuran 0,72x nilai
        func width(_ s: CGFloat) -> CGFloat {
            textWidth(label + " ", size: s * 0.72, bold: false) + textWidth(value, size: s, bold: true)
        }
        while sz > 10, width(sz) > r.width { sz -= 0.5 }
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        ps.lineBreakMode = .byTruncatingTail
        let out = NSMutableAttributedString(string: label + " ", attributes: [
            .font: UIFont.systemFont(ofSize: sz * 0.72), .foregroundColor: UIColor(white: 0.72, alpha: 1), .paragraphStyle: ps])
        out.append(NSAttributedString(string: value, attributes: [
            .font: UIFont.boldSystemFont(ofSize: sz), .foregroundColor: valueColor, .paragraphStyle: ps]))
        // sejajarkan dasar teks nama dan nilai dengan kotak yang sama
        out.draw(in: CGRect(x: r.minX, y: r.minY + (size - sz) * 0.35, width: r.width, height: r.height))
    }

    // MARK: - Layar dasbor

    private static func drawDashboard(_ cg: CGContext, _ hud: DashHUD, _ vis: CGRect) {
        let c = hud.content
        let bg = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        bg.setFill()
        cg.fill(CGRect(origin: .zero, size: hud.size))

        text(slotText(c.infoDashL, c), CGRect(x: 8, y: vis.minY + 3, width: 130, height: 20), size: 17, bold: true,
             color: slotColor(c.infoDashL, c))
        text(slotText(c.infoDashR, c), CGRect(x: 140, y: vis.minY + 5, width: 198, height: 16), size: 13,
             color: slotColor(c.infoDashR, c), align: .right)

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
        text(c.speedFromBike ? tr("km/h · BIKE") : "km/h · GPS",
             CGRect(x: 200, y: barY + barH + 2, width: 138, height: 12), size: 8,
             color: UIColor(white: 0.7, alpha: 1), align: .right)

        // kecepatan besar
        text("\(c.speedKmh)", CGRect(x: 66, y: barY + 24, width: 190, height: 58), size: 52, bold: true, align: .center)
        text("km/h", CGRect(x: 258, y: barY + 52, width: 80, height: 20), size: 15, color: UIColor(white: 0.85, alpha: 1))

        // kartu bawah
        let cardY = vis.minY + 124
        let cardH: CGFloat = 48
        // warna nilai mengikuti batas peringatan di Pengaturan > Motor dan BBM (sama dengan kartu data)
        let items: [(String, String, UIColor)] = [
            (tr("PHONE BATT"), c.phoneBattery >= 0 ? "\(c.phoneBattery)%" : "—", DashField.phoneBattery.resolve(c).3),
            (tr("FUEL LEFT"), c.fuelL.map { Fmt.liters($0) } ?? "—", DashField.fuel.resolve(c).3),
            (tr("12V BATT"), c.batteryV.map { String(format: "%.1f V", $0) } ?? "—", DashField.batteryV.resolve(c).3)
        ]
        for (i, it) in items.enumerated() {
            let r = CGRect(x: 8 + CGFloat(i) * 112, y: cardY, width: 106, height: cardH)
            fillRound(r, radius: 8, color: UIColor(white: 0.14, alpha: 1))
            text(it.0, CGRect(x: r.minX + 8, y: r.minY + 5, width: 92, height: 11), size: 8,
                 color: UIColor(white: 0.7, alpha: 1))
            text(it.1, CGRect(x: r.minX + 8, y: r.minY + 18, width: 92, height: 26), size: 21, bold: true, color: it.2)
        }

        // panel kanan: navigasi + peta mini
        let panelX: CGFloat = 346
        let panelW: CGFloat = 130
        var mapTop = vis.minY + 2
        if let n = c.nav {
            let r = CGRect(x: panelX, y: mapTop, width: panelW, height: 86)
            fillRound(r, radius: 10, color: UIColor(red: 0.04, green: 0.45, blue: 0.30, alpha: 1))
            let titleSize = fitSize(n.text, bold: true, maxSize: 12, width: 118, minSize: 8)
            text(n.text, CGRect(x: r.minX + 6, y: r.minY + 4, width: 118, height: 16), size: titleSize, bold: true)
            TurnGlyph.draw(cg, code: n.icon, in: CGRect(x: r.minX + 6, y: r.minY + 24, width: 34, height: 34), color: .white)
            text(n.dist, CGRect(x: r.minX + 44, y: r.minY + 29, width: 82, height: 24), size: 19, bold: true)
            text(n.summary, CGRect(x: r.minX + 6, y: r.minY + 64, width: 118, height: 16), size: 11, bold: true,
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
        // pojok kiri/kanan atas: tampilkan NAMA data beserta nilainya (mis. "Kecepatan 40 km/h")
        drawLabeledSlot(c.infoMusicL, c, in: CGRect(x: 8, y: vis.minY + 4, width: 228, height: 22), size: 16, align: .left)
        drawLabeledSlot(c.infoMusicR, c, in: CGRect(x: 244, y: vis.minY + 4, width: 230, height: 22), size: 16, align: .right)
        defer {
            if !c.musicToast.isEmpty {
                let w = max(150, CGFloat(c.musicToast.count) * 9 + 30)
                let pill = CGRect(x: (hud.size.width - w) / 2, y: vis.maxY - 34, width: w, height: 26)
                fillRound(pill, radius: 13, color: UIColor(white: 0, alpha: 0.65))
                text(c.musicToast, pill, size: 14, bold: true, align: .center)
            }
        }
        guard let m = c.music, !m.title.isEmpty else {
            text(tr("No music"), CGRect(x: 0, y: vis.minY + 58, width: hud.size.width, height: 28), size: 21,
                 bold: true, align: .center)
            text(tr("Play a song in the Music app on the iPhone"), CGRect(x: 0, y: vis.minY + 92, width: hud.size.width, height: 18),
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
        text(m.playing ? tr("▶  Playing") : tr("❚❚  Paused"), CGRect(x: x, y: vis.minY + 144, width: w, height: 16), size: 12,
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
            text(tr("No photos yet"), CGRect(x: 0, y: vis.minY + 62, width: hud.size.width, height: 26), size: 20, bold: true,
                 align: .center)
            text(tr("Add them in Settings > Dash screens > Photos"), CGRect(x: 0, y: vis.minY + 94, width: hud.size.width, height: 16),
                 size: 12, color: UIColor(white: 0.7, alpha: 1), align: .center)
        }
        let left = slotText(c.infoPhotoL, c)
        if !left.isEmpty {
            let w = max(62, CGFloat(left.count) * 8 + 24)
            let clock = CGRect(x: 8, y: vis.minY + 4, width: w, height: 22)
            fillRound(clock, radius: 11, color: UIColor(white: 0, alpha: 0.5))
            text(left, clock, size: 13, bold: true, color: slotColor(c.infoPhotoL, c), align: .center)
        }
        let right = slotText(c.infoPhotoR, c)
        if !right.isEmpty {
            let w = max(62, CGFloat(right.count) * 8 + 24)
            let spd = CGRect(x: hud.size.width - w - 8, y: vis.maxY - 28, width: w, height: 24)
            fillRound(spd, radius: 12, color: UIColor(white: 0, alpha: 0.5))
            text(right, spd, size: 13, bold: true, color: slotColor(c.infoPhotoR, c), align: .center)
        }
    }

    // MARK: - Alat gambar

    private static func font(_ size: CGFloat, bold: Bool) -> UIFont {
        bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }

    private static func textWidth(_ s: String, size: CGFloat, bold: Bool) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font(size, bold: bold)]).width)
    }

    /// Ukuran huruf terbesar (maks `maxSize`) yang masih muat dalam `width`; tidak lebih kecil dari `minSize`.
    private static func fitSize(_ s: String, bold: Bool, maxSize: CGFloat, width: CGFloat, minSize: CGFloat) -> CGFloat {
        var size = maxSize
        while size > minSize, textWidth(s, size: size, bold: bold) > width { size -= 0.5 }
        return max(minSize, size)
    }

    private static func fillRound(_ r: CGRect, radius: CGFloat, color: UIColor) {
        color.setFill()
        UIBezierPath(roundedRect: r, cornerRadius: radius).fill()
    }

    private static func text(_ s: String, _ r: CGRect, size: CGFloat, bold: Bool = false,
                             color: UIColor = .white, align: NSTextAlignment = .left, inset: CGFloat = 0,
                             lines: Int = 1, vcenter: Bool = false) {
        let ps = NSMutableParagraphStyle()
        ps.alignment = align
        ps.lineBreakMode = .byTruncatingTail
        let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
        var rr = r.insetBy(dx: inset, dy: 0)
        let h = font.lineHeight * CGFloat(lines)
        if rr.height > h {
            if lines == 1 && (align == .center || vcenter) { rr.origin.y += (r.height - h) / 2 }
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
            // jalur dasar melengkung ke KIRI (36 = putar balik kiri, 37 = putar balik kanan -> dicerminkan)
            if code == 37 { cg.scaleBy(x: -1, y: 1) }
            cg.translateBy(x: 0, y: -9)      // pusatkan secara vertikal
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
            // pusatkan seluruh bentuk (ekor, tekukan, kepala panah) di tengah kotak ikon
            let perp = CGPoint(x: -dir.y, y: dir.x)
            let pts = [CGPoint(x: 0, y: 46), pivot, end,
                       CGPoint(x: end.x + dir.x * 18, y: end.y + dir.y * 18),
                       CGPoint(x: end.x + perp.x * 20, y: end.y + perp.y * 20),
                       CGPoint(x: end.x - perp.x * 20, y: end.y - perp.y * 20)]
            let minX = pts.map { $0.x }.min() ?? 0, maxX = pts.map { $0.x }.max() ?? 0
            let minY = pts.map { $0.y }.min() ?? 0, maxY = pts.map { $0.y }.max() ?? 0
            cg.translateBy(x: -(minX + maxX) / 2, y: -(minY + maxY) / 2)
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
