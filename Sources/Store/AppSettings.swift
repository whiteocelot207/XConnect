import Foundation
import UIKit

final class AppSettings: ObservableObject {
    @Published var autoConnect: Bool { didSet { put("autoConnect", autoConnect) } }
    /// 0 = otomatis (malam 18.00-06.00), 1 = siang, 2 = malam
    @Published var nightMode: Int { didSet { put("nightMode", nightMode) } }
    @Published var routingBase: String { didSet { put("routingBase", routingBase) } }
    @Published var keepScreenOn: Bool { didSet { put("keepScreenOn", keepScreenOn) } }
    /// 0 = ikuti ponsel, 1 = gelap, 2 = terang
    @Published var theme: Int { didSet { put("theme", theme) } }
    @Published var userName: String { didSet { put("userName", userName) } }
    /// bit 0 = Peta, 2 = Speedometer, 3 = Musik, 4 = Foto (bit 1 Peta saja dan bit 5 Tes tombol sudah dihapus)
    @Published var screenMask: Int { didSet { put("screenMask", screenMask) } }
    /// 0 = 1x tekan ganti tampilan, 2x zoom (seperti NConnect); 1 = 1x zoom, 2x ganti tampilan
    /// urutan layar dash (rawValue dipisah koma). Peta selalu pertama dan selalu aktif.
    @Published var screenOrder: String { didSet { put("screenOrder", screenOrder) } }
    @Published var buttonScheme: Int { didSet { put("buttonScheme", buttonScheme) } }
    @Published var slideSeconds: Int { didSet { put("slideSeconds", slideSeconds) } }
    @Published var saveBattery: Bool { didSet { put("saveBattery", saveBattery) } }
    @Published var showCards: Bool { didSet { put("showCards", showCards) } }
    @Published var routeColor: Int { didSet { put("routeColor", routeColor) } }
    @Published var autoZoom: Bool { didSet { put("autoZoom", autoZoom) } }
    /// zoom peta di dash bila zoom otomatis mati (skala tile; makin besar makin dekat)
    @Published var baseZoom: Double { didSet { put("baseZoom", baseZoom) } }
    /// aturan zoom otomatis menurut kecepatan GPS (berlaku saat navigasi maupun tidak)
    @Published var zoomRules: [ZoomRule] { didSet { put("zoomRules", ZoomRule.encode(zoomRules)) } }
    /// zoom untuk kecepatan di atas semua aturan
    @Published var zoomAbove: Double { didSet { put("zoomAbove", zoomAbove) } }
    /// lama perpindahan zoom halus (detik); 0 = langsung
    @Published var zoomSmooth: Double { didSet { put("zoomSmooth", zoomSmooth) } }

    /// Zoom peta dash untuk kecepatan GPS saat ini: aturan pertama (dari kecepatan terendah) yang batasnya di atas
    /// kecepatan; bila tidak ada, `zoomAbove`. Bila zoom otomatis mati, `baseZoom`. Zoom manual dari stang ditambahkan di TftSession.
    func dashZoom(speedKmh v: Double) -> Double {
        guard autoZoom else { return baseZoom }
        for r in zoomRules.sorted(by: { $0.below < $1.below }) where v < r.below { return r.zoom }
        return zoomAbove
    }
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
    /// 0 = transparan, 1 = hitam pekat (latar kolom Kartu Data di layar Peta)
    @Published var cardBgAlpha: Double { didSet { put("cardBgAlpha", cardBgAlpha) } }
    /// geser titik motor ke kiri (negatif) / kanan (positif), px
    @Published var markerX: Double { didSet { put("markerX", markerX) } }
    /// geser panel belokan (kotak hijau), px dari posisi bawaan
    @Published var navDX: Double { didSet { put("navDX", navDX) } }
    @Published var navDY: Double { didSet { put("navDY", navDY) } }
    /// geser pil jarak + ETA, px dari posisi bawaan
    @Published var etaDX: Double { didSet { put("etaDX", etaDX) } }
    @Published var etaDY: Double { didSet { put("etaDY", etaDY) } }
    /// layar yang tampil pertama saat motor dinyalakan (DashScreen.rawValue); bawaan Peta
    @Published var startScreen: Int { didSet { put("startScreen", startScreen) } }
    /// jendela klik cepat di tombol stang: jarak terlama antar tekan dalam satu rangkaian 2x/3x (milidetik)
    @Published var doubleClickMs: Int { didSet { put("doubleClickMs", doubleClickMs) } }
    /// layar Musik: gesture stang aktif (2x = ganti lagu, atas-bawah cepat = putar/jeda)
    @Published var holdSkip: Bool { didSet { put("holdSkip", holdSkip) } }
    /// lama tombol ditahan (milidetik) sebelum dianggap tekan tahan
    @Published var holdMs: Int { didSet { put("holdMs", holdMs) } }
    /// rata-rata konsumsi BBM dari CCU: dibaca dari byte paket data id 1 (mentah); -1 = mati
    @Published var ccuFuelByte: Int { didSet { put("ccuFuelByte", ccuFuelByte) } }
    /// true = nilai 2 byte (byte n dan n+1, big-endian), false = 1 byte
    @Published var ccuFuelWide: Bool { didSet { put("ccuFuelWide", ccuFuelWide) } }
    /// 0 = km/L, 1 = L/100 km, 2 = L/km
    @Published var ccuFuelUnit: Int { didSet { put("ccuFuelUnit", ccuFuelUnit) } }
    /// nilai mentah dibagi angka ini (mis. 10 bila 352 berarti 35,2)
    @Published var ccuFuelDiv: Double { didSet { put("ccuFuelDiv", ccuFuelDiv) } }
    /// true = jam 24 jam, false = 12 jam (untuk jam dan ETA yang digambar app)
    @Published var clock24: Bool { didSet { put("clock24", clock24); Fmt.clock24 = clock24 } }
    /// kode bahasa yang dikirim ke dash (cmd 12). -1 = tidak dikirim. 0 Inggris, 15 Vietnam. Dugaan: format jam dash mengikuti bahasa
    @Published var dashLang: Int { didSet { put("dashLang", dashLang) } }
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

    /// suara petunjuk arah ("Dalam 100 meter, belok kanan ke Jalan Lingkar Luar Jakarta")
    @Published var guideVoice: Bool { didSet { put("guideVoice", guideVoice) } }
    /// kecilkan volume musik/audio app lain selama suara berbunyi, lalu kembalikan
    @Published var guideDuck: Bool { didSet { put("guideDuck", guideDuck) } }
    /// volume musik saat pemberitahuan, sebagai bagian dari volume sekarang (0.5 = separuh)
    @Published var guideDuckLevel: Double { didSet { put("guideDuckLevel", guideDuckLevel) } }
    /// volume suara petunjuk arah (0.2 - 1.0, relatif terhadap volume ponsel)
    @Published var guideVolume: Double { didSet { put("guideVolume", guideVolume) } }
    /// penguat suara petunjuk di atas volume penuh (dB, 0 = mati, maks. 18). Dipakai bila suara masih terlalu pelan di jalan.
    @Published var guideBoostDb: Double { didSet { put("guideBoostDb", guideBoostDb) } }

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

    /// Semua pengaturan beserta nilai bawaannya. Satu-satunya sumber daftar kunci: cadangan (SettingsBackup)
    /// memakai kunci dari sini, jadi pengaturan baru otomatis ikut dicadangkan.
    static let defaultValues: [String: Any] = [
            "autoConnect": true, "nightMode": 0,
            "routingBase": "https://valhalla1.openstreetmap.de", "keepScreenOn": true,
            "theme": 0, "userName": "Tantan", "screenMask": 13, "buttonScheme": 1, "slideSeconds": 6, "saveBattery": false,
            "showCards": true, "routeColor": 0, "autoZoom": true, "baseZoom": 16.8, "zoomRules": "15.0:17.80,35.0:17.00,55.0:16.30", "zoomAbove": 15.6, "zoomSmooth": 0.8, "defaultKmPerL": 30.0,
            "updateRepo": "whiteocelot207/XConnect", "updater": 0, "autoCheckUpdate": true, "ccuEnabled": true,
            "routeWidth": 5.0, "routeBorder": 0.0, "markerSize": 0.6, "markerRing": true, "markerY": 0.78,
            "navPanelScale": 0.85, "musicBlurBG": true,
            "cardLayout": 1, "cardBig": 0, "cardS1": 1, "cardS2": 2, "cardS3": 3, "cardS4": 4,
            "etaScale": 0.9, "infoDashL": 4, "infoDashR": 2, "infoMusicL": 1, "infoMusicR": 16,
            "infoPhotoL": 12, "infoPhotoR": 12, "photoShift": 0.0,
            "greetingWord": "Halo", "cardBgAlpha": 0.78, "markerX": -6.0,
            "navDX": -4.0, "navDY": -4.0, "etaDX": -50.0, "etaDY": 4.0,
            "startScreen": 0, "doubleClickMs": 450, "holdSkip": true, "holdMs": 1000, "ccuFuelByte": -1, "ccuFuelWide": false, "ccuFuelUnit": 0, "ccuFuelDiv": 1.0, "dashLang": -1, "clock24": true, "ccuExtraIds": "",
            "showRoadName": true,
            "cardFontBig": 1.0, "cardFontSmall": 1.0, "dashQuality": 0.55, "keepAliveAudio": true, "etaShowDistance": true, "etaShowDuration": true, "etaShowArrival": true, "guideVoice": true, "guideDuck": true, "guideDuckLevel": 0.5, "guideVolume": 1.0, "guideBoostDb": 0.0,
            "routePrimary": 1.0, "routeTopSpeed": 80, "routeHills": 0.0, "routeLiving": 0.5,
            "routeTrails": 0.0, "routeFerry": 0.5, "routeAvoidTolls": true, "routeHighways": 1.0,
            "routeShortest": false,
            "screenOrder": "0,2,3,4"
    ]

    private func put(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: AppSettings.defaultValues)
        autoConnect = d.bool(forKey: "autoConnect")
        nightMode = d.integer(forKey: "nightMode")
        routingBase = d.string(forKey: "routingBase") ?? "https://valhalla1.openstreetmap.de"
        keepScreenOn = d.bool(forKey: "keepScreenOn")
        theme = d.integer(forKey: "theme")
        userName = d.string(forKey: "userName") ?? ""
        screenMask = Self.migratedMask(d.integer(forKey: "screenMask"))
        screenOrder = d.string(forKey: "screenOrder") ?? "0,2,3,4"
        buttonScheme = d.integer(forKey: "buttonScheme")
        slideSeconds = max(2, d.integer(forKey: "slideSeconds"))
        saveBattery = d.bool(forKey: "saveBattery")
        showCards = d.bool(forKey: "showCards")
        routeColor = d.integer(forKey: "routeColor")
        autoZoom = d.bool(forKey: "autoZoom")
        baseZoom = d.double(forKey: "baseZoom")
        zoomRules = ZoomRule.decode(d.string(forKey: "zoomRules") ?? "")
        zoomAbove = d.double(forKey: "zoomAbove")
        zoomSmooth = d.double(forKey: "zoomSmooth")
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
        startScreen = Self.migratedStart(d.integer(forKey: "startScreen"))
        doubleClickMs = min(max(250, d.integer(forKey: "doubleClickMs")), 1500)
        holdSkip = d.bool(forKey: "holdSkip")
        holdMs = min(max(300, d.integer(forKey: "holdMs")), 2000)
        ccuFuelByte = min(max(-1, d.integer(forKey: "ccuFuelByte")), 47)
        ccuFuelWide = d.bool(forKey: "ccuFuelWide")
        ccuFuelUnit = min(max(0, d.integer(forKey: "ccuFuelUnit")), 2)
        ccuFuelDiv = max(0.001, d.double(forKey: "ccuFuelDiv"))
        dashLang = d.integer(forKey: "dashLang")
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
        guideBoostDb = min(max(0, d.double(forKey: "guideBoostDb")), 18)
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
        routingBase = d.string(forKey: "routingBase") ?? "https://valhalla1.openstreetmap.de"
        keepScreenOn = d.bool(forKey: "keepScreenOn")
        theme = d.integer(forKey: "theme")
        userName = d.string(forKey: "userName") ?? ""
        screenMask = Self.migratedMask(d.integer(forKey: "screenMask"))
        screenOrder = d.string(forKey: "screenOrder") ?? "0,2,3,4"
        buttonScheme = d.integer(forKey: "buttonScheme")
        slideSeconds = max(2, d.integer(forKey: "slideSeconds"))
        saveBattery = d.bool(forKey: "saveBattery")
        showCards = d.bool(forKey: "showCards")
        routeColor = d.integer(forKey: "routeColor")
        autoZoom = d.bool(forKey: "autoZoom")
        baseZoom = d.double(forKey: "baseZoom")
        zoomRules = ZoomRule.decode(d.string(forKey: "zoomRules") ?? "")
        zoomAbove = d.double(forKey: "zoomAbove")
        zoomSmooth = d.double(forKey: "zoomSmooth")
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
        startScreen = Self.migratedStart(d.integer(forKey: "startScreen"))
        doubleClickMs = min(max(250, d.integer(forKey: "doubleClickMs")), 1500)
        holdSkip = d.bool(forKey: "holdSkip")
        holdMs = min(max(300, d.integer(forKey: "holdMs")), 2000)
        ccuFuelByte = min(max(-1, d.integer(forKey: "ccuFuelByte")), 47)
        ccuFuelWide = d.bool(forKey: "ccuFuelWide")
        ccuFuelUnit = min(max(0, d.integer(forKey: "ccuFuelUnit")), 2)
        ccuFuelDiv = max(0.001, d.double(forKey: "ccuFuelDiv"))
        dashLang = d.integer(forKey: "dashLang")
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
        guideBoostDb = min(max(0, d.double(forKey: "guideBoostDb")), 18)
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

    /// Jenis rute selalu skuter (NMAX/XMAX); pilihan kendaraan sudah dihapus dari Pengaturan.
    var costing: String { "motor_scooter" }

    /// Layar lama yang sudah dihapus: "Peta saja" (bit 1) digabung ke Peta, "Tes tombol" (bit 5) dibuang.
    /// Layar awal yang menunjuk ke layar itu dikembalikan ke bawaan.
    /// Peta (bit 0) selalu aktif; bit layar lama yang sudah dihapus (1 = Peta saja, 5 = Tes tombol) dibuang.
    private static func migratedMask(_ mask: Int) -> Int {
        (mask | 1) & 0b11101
    }

    /// Layar awal: nilai lama -1 ("layar pertama yang aktif") dan layar yang sudah dihapus menjadi Peta.
    private static func migratedStart(_ start: Int) -> Int {
        [0, 2, 3, 4].contains(start) ? start : 0
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
            return h >= 18 || h < 6
        }
    }

    /// Semua layar menurut urutan pilihan pengguna: Peta selalu pertama, sisanya sesuai `screenOrder`
    /// (layar yang belum tercatat di urutan ditaruh di akhir).
    var orderedScreens: [DashScreen] {
        var out: [DashScreen] = [.mapData]
        for t in screenOrder.split(separator: ",") {
            if let v = Int(t), let sc = DashScreen(rawValue: v), !out.contains(sc) { out.append(sc) }
        }
        for sc in DashScreen.allCases where !out.contains(sc) { out.append(sc) }
        return out
    }

    /// Layar yang aktif menurut urutan. Peta selalu ada.
    var enabledScreens: [DashScreen] {
        orderedScreens.filter { $0 == .mapData || screenMask & (1 << $0.rawValue) != 0 }
    }

    /// Simpan urutan layar selain Peta (Peta tetap di depan).
    func setScreenOrder(_ others: [DashScreen]) {
        screenOrder = ([DashScreen.mapData] + others.filter { $0 != .mapData }).map { String($0.rawValue) }.joined(separator: ",")
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
