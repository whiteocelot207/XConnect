import Foundation
import UIKit

final class AppSettings: ObservableObject {
    @Published var autoConnect: Bool { didSet { put("autoConnect", autoConnect) } }
    /// 0 = otomatis (18.00-05.00 malam), 1 = siang, 2 = malam
    @Published var nightMode: Int { didSet { put("nightMode", nightMode) } }
    @Published var costing: String { didSet { put("costing", costing) } }
    @Published var routingBase: String { didSet { put("routingBase", routingBase) } }
    @Published var keepScreenOn: Bool { didSet { put("keepScreenOn", keepScreenOn) } }
    /// 0 = ikuti ponsel, 1 = gelap, 2 = terang
    @Published var theme: Int { didSet { put("theme", theme) } }
    @Published var userName: String { didSet { put("userName", userName) } }
    /// bit 0 = Peta + data, 1 = Peta saja, 2 = Speedometer, 3 = Musik, 4 = Foto
    @Published var screenMask: Int { didSet { put("screenMask", screenMask) } }
    /// 0 = 1x tekan ganti tampilan, 2x zoom (seperti NConnect); 1 = 1x zoom, 2x ganti tampilan
    @Published var buttonScheme: Int { didSet { put("buttonScheme", buttonScheme) } }
    @Published var slideSeconds: Int { didSet { put("slideSeconds", slideSeconds) } }
    @Published var saveBattery: Bool { didSet { put("saveBattery", saveBattery) } }
    @Published var showCards: Bool { didSet { put("showCards", showCards) } }
    @Published var routeColor: Int { didSet { put("routeColor", routeColor) } }
    @Published var autoZoom: Bool { didSet { put("autoZoom", autoZoom) } }
    @Published var defaultKmPerL: Double { didSet { put("defaultKmPerL", defaultKmPerL) } }
    /// Format pemilik/nama-repo, mis. "histrox/xconnect"
    @Published var updateRepo: String { didSet { put("updateRepo", updateRepo) } }
    /// 0 = SideStore, 1 = AltStore
    @Published var updater: Int { didSet { put("updater", updater) } }
    @Published var autoCheckUpdate: Bool { didSet { put("autoCheckUpdate", autoCheckUpdate) } }
    @Published var ccuEnabled: Bool { didSet { put("ccuEnabled", ccuEnabled) } }
    /// garis rute di peta dash (px)
    @Published var routeWidth: Double { didSet { put("routeWidth", routeWidth) } }
    @Published var routeBorder: Double { didSet { put("routeBorder", routeBorder) } }
    /// titik posisi motor di peta
    @Published var markerSize: Double { didSet { put("markerSize", markerSize) } }
    @Published var markerRing: Bool { didSet { put("markerRing", markerRing) } }
    /// posisi vertikal titik motor, 0.3 (atas) - 0.9 (bawah) dari area peta
    @Published var markerY: Double { didSet { put("markerY", markerY) } }
    @Published var navPanelScale: Double { didSet { put("navPanelScale", navPanelScale) } }
    @Published var musicBlurBG: Bool { didSet { put("musicBlurBG", musicBlurBG) } }
    /// 0 = 2 kotak kecil, 1 = 1 kotak besar + 4 kecil, 2 = 4 kotak kecil
    @Published var cardLayout: Int { didSet { put("cardLayout", cardLayout) } }
    @Published var cardBig: Int { didSet { put("cardBig", cardBig) } }
    @Published var cardS1: Int { didSet { put("cardS1", cardS1) } }
    @Published var cardS2: Int { didSet { put("cardS2", cardS2) } }
    @Published var cardS3: Int { didSet { put("cardS3", cardS3) } }
    @Published var cardS4: Int { didSet { put("cardS4", cardS4) } }
    /// skala pil jarak + ETA (terpisah dari panel belokan)
    @Published var etaScale: Double { didSet { put("etaScale", etaScale) } }
    /// data di pojok kiri/kanan atas tiap layar (nilai = DashField.rawValue)
    @Published var infoDashL: Int { didSet { put("infoDashL", infoDashL) } }
    @Published var infoDashR: Int { didSet { put("infoDashR", infoDashR) } }
    @Published var infoMusicL: Int { didSet { put("infoMusicL", infoMusicL) } }
    @Published var infoMusicR: Int { didSet { put("infoMusicR", infoMusicR) } }
    @Published var infoPhotoL: Int { didSet { put("infoPhotoL", infoPhotoL) } }
    @Published var infoPhotoR: Int { didSet { put("infoPhotoR", infoPhotoR) } }
    /// geser foto slideshow ke atas (negatif) / bawah (positif), px
    @Published var photoShift: Double { didSet { put("photoShift", photoShift) } }

    private func put(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "autoConnect": true, "nightMode": 0, "costing": "motor_scooter",
            "routingBase": "https://valhalla1.openstreetmap.de", "keepScreenOn": false,
            "theme": 0, "userName": "", "screenMask": 29, "buttonScheme": 1, "slideSeconds": 6, "saveBattery": false,
            "showCards": true, "routeColor": 0, "autoZoom": true, "defaultKmPerL": 30.0,
            "updateRepo": "", "updater": 0, "autoCheckUpdate": true, "ccuEnabled": true,
            "routeWidth": 5.0, "routeBorder": 1.5, "markerSize": 1.0, "markerRing": true, "markerY": 0.68,
            "navPanelScale": 1.0, "musicBlurBG": true,
            "cardLayout": 1, "cardBig": 0, "cardS1": 1, "cardS2": 2, "cardS3": 3, "cardS4": 4,
            "etaScale": 1.0, "infoDashL": 10, "infoDashR": 13, "infoMusicL": 10, "infoMusicR": 8,
            "infoPhotoL": 10, "infoPhotoR": 8, "photoShift": 0.0
        ])
        autoConnect = d.bool(forKey: "autoConnect")
        nightMode = d.integer(forKey: "nightMode")
        costing = d.string(forKey: "costing") ?? "motor_scooter"
        routingBase = d.string(forKey: "routingBase") ?? "https://valhalla1.openstreetmap.de"
        keepScreenOn = d.bool(forKey: "keepScreenOn")
        theme = d.integer(forKey: "theme")
        userName = d.string(forKey: "userName") ?? ""
        screenMask = d.integer(forKey: "screenMask")
        buttonScheme = d.integer(forKey: "buttonScheme")
        slideSeconds = max(2, d.integer(forKey: "slideSeconds"))
        saveBattery = d.bool(forKey: "saveBattery")
        showCards = d.bool(forKey: "showCards")
        routeColor = d.integer(forKey: "routeColor")
        autoZoom = d.bool(forKey: "autoZoom")
        defaultKmPerL = d.double(forKey: "defaultKmPerL")
        updateRepo = d.string(forKey: "updateRepo") ?? ""
        updater = d.integer(forKey: "updater")
        autoCheckUpdate = d.bool(forKey: "autoCheckUpdate")
        ccuEnabled = d.bool(forKey: "ccuEnabled")
        routeWidth = d.double(forKey: "routeWidth")
        routeBorder = d.double(forKey: "routeBorder")
        markerSize = d.double(forKey: "markerSize")
        markerRing = d.bool(forKey: "markerRing")
        markerY = d.double(forKey: "markerY")
        navPanelScale = d.double(forKey: "navPanelScale")
        musicBlurBG = d.bool(forKey: "musicBlurBG")
        cardLayout = d.integer(forKey: "cardLayout")
        cardBig = d.integer(forKey: "cardBig")
        cardS1 = d.integer(forKey: "cardS1")
        cardS2 = d.integer(forKey: "cardS2")
        cardS3 = d.integer(forKey: "cardS3")
        cardS4 = d.integer(forKey: "cardS4")
        etaScale = d.double(forKey: "etaScale")
        infoDashL = d.integer(forKey: "infoDashL")
        infoDashR = d.integer(forKey: "infoDashR")
        infoMusicL = d.integer(forKey: "infoMusicL")
        infoMusicR = d.integer(forKey: "infoMusicR")
        infoPhotoL = d.integer(forKey: "infoPhotoL")
        infoPhotoR = d.integer(forKey: "infoPhotoR")
        photoShift = d.double(forKey: "photoShift")
    }

    /// Muat ulang semua nilai dari UserDefaults (dipakai setelah memulihkan cadangan).
    func reloadFromDefaults() {
        let d = UserDefaults.standard
        autoConnect = d.bool(forKey: "autoConnect")
        nightMode = d.integer(forKey: "nightMode")
        costing = d.string(forKey: "costing") ?? "motor_scooter"
        routingBase = d.string(forKey: "routingBase") ?? "https://valhalla1.openstreetmap.de"
        keepScreenOn = d.bool(forKey: "keepScreenOn")
        theme = d.integer(forKey: "theme")
        userName = d.string(forKey: "userName") ?? ""
        screenMask = d.integer(forKey: "screenMask")
        buttonScheme = d.integer(forKey: "buttonScheme")
        slideSeconds = max(2, d.integer(forKey: "slideSeconds"))
        saveBattery = d.bool(forKey: "saveBattery")
        showCards = d.bool(forKey: "showCards")
        routeColor = d.integer(forKey: "routeColor")
        autoZoom = d.bool(forKey: "autoZoom")
        defaultKmPerL = d.double(forKey: "defaultKmPerL")
        updateRepo = d.string(forKey: "updateRepo") ?? ""
        updater = d.integer(forKey: "updater")
        autoCheckUpdate = d.bool(forKey: "autoCheckUpdate")
        ccuEnabled = d.bool(forKey: "ccuEnabled")
        routeWidth = d.double(forKey: "routeWidth")
        routeBorder = d.double(forKey: "routeBorder")
        markerSize = d.double(forKey: "markerSize")
        markerRing = d.bool(forKey: "markerRing")
        markerY = d.double(forKey: "markerY")
        navPanelScale = d.double(forKey: "navPanelScale")
        musicBlurBG = d.bool(forKey: "musicBlurBG")
        cardLayout = d.integer(forKey: "cardLayout")
        cardBig = d.integer(forKey: "cardBig")
        cardS1 = d.integer(forKey: "cardS1")
        cardS2 = d.integer(forKey: "cardS2")
        cardS3 = d.integer(forKey: "cardS3")
        cardS4 = d.integer(forKey: "cardS4")
        etaScale = d.double(forKey: "etaScale")
        infoDashL = d.integer(forKey: "infoDashL")
        infoDashR = d.integer(forKey: "infoDashR")
        infoMusicL = d.integer(forKey: "infoMusicL")
        infoMusicR = d.integer(forKey: "infoMusicR")
        infoPhotoL = d.integer(forKey: "infoPhotoL")
        infoPhotoR = d.integer(forKey: "infoPhotoR")
        photoShift = d.double(forKey: "photoShift")
    }

    func isNight(now: Date = Date()) -> Bool {
        switch nightMode {
        case 1: return false
        case 2: return true
        default:
            let h = Calendar.current.component(.hour, from: now)
            return h >= 18 || h < 5
        }
    }

    var enabledScreens: [DashScreen] {
        let list = DashScreen.allCases.filter { screenMask & (1 << $0.rawValue) != 0 }
        return list.isEmpty ? [.mapData] : list
    }

    var maxFps: Double { saveBattery ? 4 : 10 }

    var routeUIColor: UIColor {
        switch routeColor {
        case 1: return UIColor(red: 0.12, green: 0.45, blue: 0.98, alpha: 1)
        case 2: return UIColor(red: 0.1, green: 0.7, blue: 0.35, alpha: 1)
        default: return UIColor(red: 0.95, green: 0.2, blue: 0.5, alpha: 1)
        }
    }
}
