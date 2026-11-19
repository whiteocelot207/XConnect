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
    /// 0 = SideStore, 1 = AltStore, 2 = LiveContainer
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
    /// kata sapaan di kotak cuaca dash (mis. "Halo")
    @Published var greetingWord: String { didSet { put("greetingWord", greetingWord) } }
    /// 0 = transparan, 1 = hitam pekat (latar kolom kotak data di layar Peta + data)
    @Published var cardBgAlpha: Double { didSet { put("cardBgAlpha", cardBgAlpha) } }
    /// geser titik motor ke kiri (negatif) / kanan (positif), px
    @Published var markerX: Double { didSet { put("markerX", markerX) } }
    /// geser panel belokan (kotak hijau), px dari posisi bawaan
    @Published var navDX: Double { didSet { put("navDX", navDX) } }
    @Published var navDY: Double { didSet { put("navDY", navDY) } }
    /// geser pil jarak + ETA, px dari posisi bawaan
    @Published var etaDX: Double { didSet { put("etaDX", etaDX) } }
    @Published var etaDY: Double { didSet { put("etaDY", etaDY) } }
    /// layar yang tampil pertama saat motor dinyalakan (DashScreen.rawValue), -1 = layar pertama yang aktif
    @Published var startScreen: Int { didSet { put("startScreen", startScreen) } }
    /// jendela klik cepat 2x di tombol stang (milidetik)
    @Published var doubleClickMs: Int { didSet { put("doubleClickMs", doubleClickMs) } }
    /// true = jam 24 jam, false = 12 jam (untuk jam dan ETA yang digambar app)
    @Published var clock24: Bool { didSet { put("clock24", clock24); Fmt.clock24 = clock24 } }
    /// ID data CCU tambahan yang ikut dilanggan (dipisah koma), untuk eksperimen
    @Published var ccuExtraIds: String { didSet { put("ccuExtraIds", ccuExtraIds) } }
    /// kirim nama jalan saat ini ke bar bawah dash walau tidak sedang navigasi
    @Published var showRoadName: Bool { didSet { put("showRoadName", showRoadName) } }
    /// skala huruf kotak data besar dan kecil di dash (0.5 - 1.5)
    @Published var cardFontBig: Double { didSet { put("cardFontBig", cardFontBig) } }
    @Published var cardFontSmall: Double { didSet { put("cardFontSmall", cardFontSmall) } }
    /// kualitas JPEG frame dash (lebih kecil = frame lebih ringan, lebih cepat sampai ke dash)
    @Published var dashQuality: Double { didSet { put("dashQuality", dashQuality) } }
    /// putar audio senyap supaya app tetap aktif di latar belakang dan data HP (volume dll) tetap berubah
    @Published var keepAliveAudio: Bool { didSet { put("keepAliveAudio", keepAliveAudio) } }

    /// isi kotak estimasi di dash: jarak tersisa, durasi tersisa, jam tiba
    @Published var etaShowDistance: Bool { didSet { put("etaShowDistance", etaShowDistance) } }
    @Published var etaShowDuration: Bool { didSet { put("etaShowDuration", etaShowDuration) } }
    @Published var etaShowArrival: Bool { didSet { put("etaShowArrival", etaShowArrival) } }

    /// suara petunjuk arah ("Dalam 100 meter, belok kanan ke ...")
    @Published var guideVoice: Bool { didSet { put("guideVoice", guideVoice) } }
    /// kecilkan volume musik/audio app lain selama suara berbunyi, lalu kembalikan
    @Published var guideDuck: Bool { didSet { put("guideDuck", guideDuck) } }
    /// volume musik saat pemberitahuan, sebagai bagian dari volume sekarang (0.5 = separuh)
    @Published var guideDuckLevel: Double { didSet { put("guideDuckLevel", guideDuckLevel) } }
    /// volume suara petunjuk arah (0.2 - 1.0, relatif terhadap volume ponsel)
    @Published var guideVolume: Double { didSet { put("guideVolume", guideVolume) } }

    /// Profil rute (dikirim ke Valhalla): lihat RouteProfile
    @Published var routePrimary: Double { didSet { put("routePrimary", routePrimary) } }
    @Published var routeTopSpeed: Int { didSet { put("routeTopSpeed", routeTopSpeed) } }
    @Published var routeHills: Double { didSet { put("routeHills", routeHills) } }
    @Published var routeLiving: Double { didSet { put("routeLiving", routeLiving) } }
    @Published var routeTrails: Double { didSet { put("routeTrails", routeTrails) } }
    @Published var routeFerry: Double { didSet { put("routeFerry", routeFerry) } }
    @Published var routeAvoidTolls: Bool { didSet { put("routeAvoidTolls", routeAvoidTolls) } }
    @Published var routeHighways: Double { didSet { put("routeHighways", routeHighways) } }
    @Published var routeShortest: Bool { didSet { put("routeShortest", routeShortest) } }

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
            "infoPhotoL": 10, "infoPhotoR": 8, "photoShift": 0.0,
            "greetingWord": "Halo", "cardBgAlpha": 0.78, "markerX": 0.0,
            "navDX": 0.0, "navDY": 0.0, "etaDX": 0.0, "etaDY": 0.0,
            "startScreen": -1, "doubleClickMs": 800, "clock24": true, "ccuExtraIds": "",
            "showRoadName": true,
            "cardFontBig": 1.0, "cardFontSmall": 1.0, "dashQuality": 0.7, "keepAliveAudio": true, "etaShowDistance": true, "etaShowDuration": false, "etaShowArrival": true, "guideVoice": true, "guideDuck": true, "guideDuckLevel": 0.5, "guideVolume": 1.0,
            "routePrimary": 1.0, "routeTopSpeed": 80, "routeHills": 0.0, "routeLiving": 0.5,
            "routeTrails": 0.0, "routeFerry": 0.5, "routeAvoidTolls": true, "routeHighways": 1.0,
            "routeShortest": false
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
        greetingWord = d.string(forKey: "greetingWord") ?? "Halo"
        cardBgAlpha = d.double(forKey: "cardBgAlpha")
        markerX = d.double(forKey: "markerX")
        navDX = d.double(forKey: "navDX")
        navDY = d.double(forKey: "navDY")
        etaDX = d.double(forKey: "etaDX")
        etaDY = d.double(forKey: "etaDY")
        startScreen = d.integer(forKey: "startScreen")
        doubleClickMs = max(300, d.integer(forKey: "doubleClickMs"))
        clock24 = d.bool(forKey: "clock24")
        Fmt.clock24 = d.bool(forKey: "clock24")
        ccuExtraIds = d.string(forKey: "ccuExtraIds") ?? ""
        showRoadName = d.bool(forKey: "showRoadName")
        cardFontBig = min(max(0.5, d.double(forKey: "cardFontBig")), 1.5)
        cardFontSmall = min(max(0.5, d.double(forKey: "cardFontSmall")), 1.5)
        dashQuality = min(max(0.4, d.double(forKey: "dashQuality")), 0.95)
        keepAliveAudio = d.bool(forKey: "keepAliveAudio")
        etaShowDistance = d.bool(forKey: "etaShowDistance")
        etaShowDuration = d.bool(forKey: "etaShowDuration")
        etaShowArrival = d.bool(forKey: "etaShowArrival")
        guideVoice = d.bool(forKey: "guideVoice")
        guideDuck = d.bool(forKey: "guideDuck")
        guideDuckLevel = min(max(0.2, d.double(forKey: "guideDuckLevel")), 0.9)
        guideVolume = min(max(0.2, d.double(forKey: "guideVolume")), 1.0)
        routePrimary = d.double(forKey: "routePrimary")
        routeTopSpeed = min(max(20, d.integer(forKey: "routeTopSpeed")), 120)
        routeHills = d.double(forKey: "routeHills")
        routeLiving = d.double(forKey: "routeLiving")
        routeTrails = d.double(forKey: "routeTrails")
        routeFerry = d.double(forKey: "routeFerry")
        routeAvoidTolls = d.bool(forKey: "routeAvoidTolls")
        routeHighways = d.double(forKey: "routeHighways")
        routeShortest = d.bool(forKey: "routeShortest")
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
        greetingWord = d.string(forKey: "greetingWord") ?? "Halo"
        cardBgAlpha = d.double(forKey: "cardBgAlpha")
        markerX = d.double(forKey: "markerX")
        navDX = d.double(forKey: "navDX")
        navDY = d.double(forKey: "navDY")
        etaDX = d.double(forKey: "etaDX")
        etaDY = d.double(forKey: "etaDY")
        startScreen = d.integer(forKey: "startScreen")
        doubleClickMs = max(300, d.integer(forKey: "doubleClickMs"))
        clock24 = d.bool(forKey: "clock24")
        Fmt.clock24 = clock24
        ccuExtraIds = d.string(forKey: "ccuExtraIds") ?? ""
        showRoadName = d.bool(forKey: "showRoadName")
        cardFontBig = min(max(0.5, d.double(forKey: "cardFontBig")), 1.5)
        cardFontSmall = min(max(0.5, d.double(forKey: "cardFontSmall")), 1.5)
        dashQuality = min(max(0.4, d.double(forKey: "dashQuality")), 0.95)
        keepAliveAudio = d.bool(forKey: "keepAliveAudio")
        etaShowDistance = d.bool(forKey: "etaShowDistance")
        etaShowDuration = d.bool(forKey: "etaShowDuration")
        etaShowArrival = d.bool(forKey: "etaShowArrival")
        guideVoice = d.bool(forKey: "guideVoice")
        guideDuck = d.bool(forKey: "guideDuck")
        guideDuckLevel = min(max(0.2, d.double(forKey: "guideDuckLevel")), 0.9)
        guideVolume = min(max(0.2, d.double(forKey: "guideVolume")), 1.0)
        routePrimary = d.double(forKey: "routePrimary")
        routeTopSpeed = min(max(20, d.integer(forKey: "routeTopSpeed")), 120)
        routeHills = d.double(forKey: "routeHills")
        routeLiving = d.double(forKey: "routeLiving")
        routeTrails = d.double(forKey: "routeTrails")
        routeFerry = d.double(forKey: "routeFerry")
        routeAvoidTolls = d.bool(forKey: "routeAvoidTolls")
        routeHighways = d.double(forKey: "routeHighways")
        routeShortest = d.bool(forKey: "routeShortest")
    }

    var routeProfile: RouteProfile {
        RouteProfile(primary: routePrimary, topSpeed: routeTopSpeed, hills: routeHills, living: routeLiving,
                     trails: routeTrails, ferry: routeFerry, avoidTolls: routeAvoidTolls,
                     highways: routeHighways, shortest: routeShortest)
    }

    func applyRouteProfile(_ p: RouteProfile) {
        routePrimary = p.primary
        routeTopSpeed = p.topSpeed
        routeHills = p.hills
        routeLiving = p.living
        routeTrails = p.trails
        routeFerry = p.ferry
        routeAvoidTolls = p.avoidTolls
        routeHighways = p.highways
        routeShortest = p.shortest
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
