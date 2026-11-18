import Foundation
import UIKit
import ExternalAccessory
import Combine
import CoreLocation
import AVFoundation
import CoreTelephony

final class BikeController: NSObject, ObservableObject {
    @Published var status = "Belum terhubung"
    @Published var isConnected = false {
        didSet {
            updateIdleTimer()
            location.setHighPower(isConnected)
        }
    }
    @Published var logLines: [String] = []
    @Published var bikeSpeedKmh: Int?
    @Published var preview: UIImage?
    @Published var fps: Double = 0
    @Published var dashPart = ""
    @Published var accessoryPresent = false
    @Published var screenIndex = 0
    /// nama jalan saat ini (dari geocoding) bila tidak sedang navigasi
    @Published var currentStreet = ""
    /// true selama halaman pengaturan posisi terbuka: tampilkan contoh panel navigasi
    var demoNav = false
    /// peristiwa tombol terakhir (untuk layar Tes tombol di dash)
    private(set) var buttonLog: [String] = []

    weak var model: AppModel?

    private let location: LocationProvider
    private let settings: AppSettings
    private let places: PlaceStore
    private weak var nav: NavigationController?

    private var session: TftSession?
    private var manualStop = false
    private var attempts = 0
    private var reconnectWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()
    private let ccuProbe = CcuProbe()
    let vehicleLive = VehicleLive()
    private lazy var ccu = CcuLink(live: vehicleLive)
    private var ccuStarted = false
    private var previewVisible = false
    private var localTimer: Timer?
    private var localBusy = false
    private let geocoder = CLGeocoder()
    private var lastGeocode = Date.distantPast
    private var lastGeocodeLoc: CLLocation?
    private let netInfo = CTTelephonyNetworkInfo()
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(location: LocationProvider, settings: AppSettings, places: PlaceStore, nav: NavigationController) {
        self.location = location
        self.settings = settings
        self.places = places
        self.nav = nav
        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true
        EAAccessoryManager.shared().registerForLocalNotifications()
        let nc = NotificationCenter.default
        nc.addObserver(forName: .EAAccessoryDidConnect, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[EAAccessoryKey] as? EAAccessory
            self?.log("Aksesori tersambung: \(a?.name ?? "?")")
            self?.accessoryPresent = self?.findDash() != nil
            self?.manualStop = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.autoConnectIfNeeded() }
        }
        nc.addObserver(forName: .EAAccessoryDidDisconnect, object: nil, queue: .main) { [weak self] n in
            let a = n.userInfo?[EAAccessoryKey] as? EAAccessory
            self?.log("Aksesori terputus: \(a?.name ?? "?")")
            self?.accessoryPresent = self?.findDash() != nil
            if self?.findDash() == nil { self?.session?.stop() }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.accessoryPresent = self?.findDash() != nil
            self?.updateIdleTimer()
            self?.autoConnectIfNeeded()
        }

        nav.onDashState = { [weak self] s in
            self?.session?.updateNav(active: s != nil, road: s?.currentRoad ?? "")
        }
        places.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.syncHomeWork() } }
            .store(in: &bag)
        ccuProbe.onLog = { [weak self] s in self?.log("CCU: " + s) }
        ccuProbe.onInfo = { [weak self] id, pass in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ccu.extraIds = self.settings.ccuExtraIds
                    .split(whereSeparator: { $0 == "," || $0 == " " })
                    .compactMap { Int($0) }
                self.ccu.start(ccuId: id, passkey: pass)
            }
        }
        ccu.onLog = { [weak self] s in self?.log("CCU BLE: " + s) }
        ccu.prepare()   // memunculkan izin Bluetooth di Pengaturan iOS
        vehicleLive.$odoKm.compactMap { $0 }
            .sink { [weak self] odo in
                guard let m = self?.model, odo > 0, abs(m.maint.odometerKm - odo) > 0.05 else { return }
                m.maint.odometerKm = odo
            }
            .store(in: &bag)

        SelfTest.run().forEach { log($0) }
        accessoryPresent = findDash() != nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.autoConnectIfNeeded() }
    }

    // MARK: - Log & status

    func log(_ s: String) {
        DispatchQueue.main.async {
            self.logLines.append("\(self.fmt.string(from: Date())) \(s)")
            if self.logLines.count > 500 { self.logLines.removeFirst(100) }
        }
    }

    private func setStatus(_ s: String) { status = s }

    /// Catat peristiwa tombol: masuk log dan tampil di layar Tes tombol.
    func buttonEvent(_ s: String) {
        log("Tombol: " + s)
        DispatchQueue.main.async {
            self.buttonLog.append("\(self.fmt.string(from: Date())) \(s)")
            if self.buttonLog.count > 12 { self.buttonLog.removeFirst(self.buttonLog.count - 12) }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn && isConnected
    }

    // MARK: - Aksesori

    private func findDash() -> EAAccessory? {
        EAAccessoryManager.shared().connectedAccessories
            .first(where: { $0.protocolStrings.contains(AccessoryLink.naviProtocol) })
    }

    func showPairingPicker() {
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { [weak self] error in
            if let error = error { self?.log("Picker: \(error.localizedDescription)") }
        }
    }

    func listAccessories() {
        let list = EAAccessoryManager.shared().connectedAccessories
        if list.isEmpty { log("Tidak ada aksesori iAP tersambung ke iPhone") }
        for a in list {
            log("Aksesori: \(a.name) | \(a.manufacturer) | \(a.modelNumber) | protokol=\(a.protocolStrings)")
        }
    }

    // MARK: - Sambungan

    func autoConnectIfNeeded() {
        guard settings.autoConnect, !manualStop, session == nil, findDash() != nil else { return }
        connect(manual: false)
    }

    func connect(manual: Bool = true) {
        if manual {
            manualStop = false
            attempts = 0
        }
        reconnectWork?.cancel()
        reconnectWork = nil
        if session != nil { return }
        guard let acc = findDash() else {
            setStatus("Dash tidak ditemukan")
            if manual {
                listAccessories()
                log("Dash belum tersambung. Nyalakan motor, lalu pasangkan lewat tombol Pasangkan dash.")
            }
            return
        }
        let s = TftSession(location: location)
        wire(s)
        session = s
        setStatus("Menghubungkan…")
        if !s.start(accessory: acc) {
            session = nil
            scheduleReconnect()
        }
    }

    func disconnect() {
        manualStop = true
        reconnectWork?.cancel()
        reconnectWork = nil
        session?.stop()
        session = nil
        isConnected = false
        setStatus("Terputus (manual)")
    }

    private func scheduleReconnect() {
        guard settings.autoConnect, !manualStop else { return }
        attempts += 1
        let delay: TimeInterval = attempts <= 3 ? 3 : 8
        let work = DispatchWorkItem { [weak self] in self?.autoConnectIfNeeded() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func sessionClosed(_ closed: TftSession?) {
        if let c = closed, c === session {
            session = nil
        } else if closed != nil && session != nil {
            return
        }
        if isConnected {
            model?.trips.finish(at: location.lastLocation)
            model?.music.stop()
        }
        isConnected = false
        bikeSpeedKmh = nil
        fps = 0
        stopCcuProbe()
        setStatus("Terputus")
        scheduleReconnect()
    }

    func syncHomeWork() {
        session?.updateHomeWork(home: places.home != nil, work: places.work != nil)
    }

    func locationUpdated(_ loc: CLLocation) {
        session?.gpsChanged()
        if isConnected {
            model?.trips.update(loc)
            model?.weather.refresh(loc.coordinate)
            updateStreet(loc)
        }
    }

    /// Nama jalan untuk bar bawah dash saat tidak navigasi. Dibatasi: minimal 6 detik dan 40 m antar permintaan.
    private func updateStreet(_ loc: CLLocation) {
        guard settings.showRoadName else { return }
        if let last = lastGeocodeLoc, loc.distance(from: last) < 40, !currentStreet.isEmpty { return }
        guard Date().timeIntervalSince(lastGeocode) > 6, !geocoder.isGeocoding else { return }
        lastGeocode = Date()
        lastGeocodeLoc = loc
        geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "id_ID")) { [weak self] marks, _ in
            guard let self = self, let pm = marks?.first else { return }
            let name = pm.thoroughfare ?? pm.name ?? pm.subLocality ?? ""
            DispatchQueue.main.async {
                if name != self.currentStreet {
                    self.currentStreet = name
                    self.session?.updateIdleRoad(name)
                }
            }
        }
    }

    // MARK: - Tampilan dash

    func screens() -> [DashScreen] {
        var s = settings.enabledScreens
        if model?.slides.files.isEmpty ?? true { s.removeAll { $0 == .slideshow } }
        return s.isEmpty ? [.mapData] : s
    }

    var currentScreen: DashScreen {
        let s = screens()
        return s[min(max(0, screenIndex), s.count - 1)]
    }

    /// Pilih layar awal sesuai pengaturan (dipanggil saat dash baru tersambung).
    func applyStartScreen() {
        let list = screens()
        if settings.startScreen >= 0, let i = list.firstIndex(where: { $0.rawValue == settings.startScreen }) {
            screenIndex = i
        } else {
            screenIndex = 0
        }
        log("Layar awal: \(currentScreen.title)")
    }

    func stepScreen(forward: Bool) {
        let n = max(1, screens().count)
        screenIndex = (min(screenIndex, n - 1) + (forward ? 1 : n - 1)) % n
        log("Tampilan dash: \(currentScreen.title)")
    }

    func dashContent() -> DashContent {
        var c = DashContent()
        c.night = settings.isNight()
        c.showCards = settings.showCards
        c.routeColor = settings.routeUIColor
        c.greeting = settings.userName
        c.clock = Fmt.clock(Date())
        let live = vehicleLive
        let bikeSpd = bikeSpeedKmh ?? live.speedKmh
        c.speedFromBike = bikeSpd != nil
        c.speedKmh = bikeSpd ?? Int(location.speedKmh.rounded())
        c.batteryV = live.batteryV
        c.coolantC = live.coolantC
        c.airC = live.airC
        c.rpm = live.rpm
        c.ignitionOn = live.ignitionOn
        c.card = CardConfig(layout: settings.cardLayout, big: settings.cardBig,
                            small: [settings.cardS1, settings.cardS2, settings.cardS3, settings.cardS4])
        c.musicBlurBG = settings.musicBlurBG
        c.routeWidth = CGFloat(settings.routeWidth)
        c.routeBorder = CGFloat(settings.routeBorder)
        c.markerScale = CGFloat(settings.markerSize)
        c.markerRing = settings.markerRing
        c.markerY = CGFloat(settings.markerY)
        c.navScale = CGFloat(settings.navPanelScale)
        c.etaScale = CGFloat(settings.etaScale)
        c.infoDashL = settings.infoDashL
        c.infoDashR = settings.infoDashR
        c.infoMusicL = settings.infoMusicL
        c.infoMusicR = settings.infoMusicR
        c.infoPhotoL = settings.infoPhotoL
        c.infoPhotoR = settings.infoPhotoR
        c.photoShift = CGFloat(settings.photoShift)
        c.greetingWord = settings.greetingWord.isEmpty ? "Halo" : settings.greetingWord
        c.cardBgAlpha = CGFloat(settings.cardBgAlpha)
        c.markerX = CGFloat(settings.markerX)
        c.navDX = CGFloat(settings.navDX)
        c.navDY = CGFloat(settings.navDY)
        c.etaDX = CGFloat(settings.etaDX)
        c.etaDY = CGFloat(settings.etaDY)
        c.dtcCount = live.dtcCount
        c.ccuSpeedKmh = live.speedKmh
        c.ccuRaw = live.rawRecord
        c.dateText = Fmt.shortDate(Date())
        c.buttonLog = buttonLog
        let vol = AVAudioSession.sharedInstance().outputVolume
        c.phoneVolume = Int((vol * 100).rounded())
        c.audioOut = AVAudioSession.sharedInstance().currentRoute.outputs.first.map { Geo.ascii($0.portName, maxLen: 14) } ?? ""
        c.network = networkText()
        let bl = UIDevice.current.batteryLevel
        c.phoneBattery = bl >= 0 ? Int((bl * 100).rounded()) : -1
        guard let m = model else { return c }
        c.odoKm = live.odoKm ?? m.maint.odometerKm
        if m.fuel.levelL > 0 {
            c.fuelL = m.fuel.remainingL(odo: c.odoKm ?? m.maint.odometerKm, tank: m.vehicle.tankL, def: settings.defaultKmPerL)
            c.rangeKm = m.fuel.rangeKm(odo: c.odoKm ?? m.maint.odometerKm, tank: m.vehicle.tankL, def: settings.defaultKmPerL)
        }
        c.tempC = m.weather.tempC
        c.weatherText = m.weather.text
        c.nav = m.nav.hud
        if c.nav == nil, demoNav {
            c.nav = NavHUD(icon: 35, text: "Belok kanan", dist: "65 m", summary: "1,6 km · 0:37", street: "Jalan Contoh")
        }
        if let l = location.lastLocation {
            c.altitudeM = Int(l.altitude.rounded())
        }
        c.headingText = compass(location.bearing)
        switch currentScreen {
        case .music: c.music = m.music.info
        case .slideshow: c.slide = m.slides.current(interval: settings.slideSeconds)
        default: break
        }
        return c
    }

    private func compass(_ deg: Double) -> String {
        let names = ["U", "TL", "T", "TG", "S", "BD", "B", "BL"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return "\(names[i]) \(Int(deg.rounded()))°"
    }

    private func networkText() -> String {
        guard let techs = netInfo.serviceCurrentRadioAccessTechnology?.values else { return "" }
        var best = 0
        for t in techs {
            var g = 0
            if t.contains("NR") { g = 5 }
            else if t.contains("LTE") { g = 4 }
            else if t.contains("WCDMA") || t.contains("HSDPA") || t.contains("HSUPA") || t.contains("EVDO") || t.contains("eHRPD") { g = 3 }
            else if t.contains("GPRS") || t.contains("Edge") || t.contains("CDMA1x") { g = 2 }
            best = max(best, g)
        }
        return best == 0 ? "" : "\(best)G"
    }

    // MARK: - Preview di Home

    /// Dipanggil Home saat tampil/hilang. Bila motor tidak tersambung, preview digambar lokal.
    func setPreviewVisible(_ v: Bool) {
        previewVisible = v
        localTimer?.invalidate()
        localTimer = nil
        if v {
            model?.music.start()
            model?.weather.refresh(location.coordinate)
            localTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.renderLocalPreview()
            }
            renderLocalPreview()
        } else if !isConnected {
            model?.music.stop()
        }
    }

    private func renderLocalPreview() {
        guard previewVisible, !isConnected, !localBusy,
              UIApplication.shared.applicationState == .active else { return }
        localBusy = true
        let content = dashContent()
        let navigating = content.nav != nil
        let hud = DashHUD(size: CGSize(width: 480, height: 234), screen: currentScreen, content: content,
                          center: location.coordinate, bearing: location.bearing,
                          zoom: navigating ? 17.2 : 16.8,
                          route: navigating ? (nav?.upcomingPoints() ?? []) : [],
                          destination: navigating ? nav?.destinationCoordinate : nil)
        DashRenderer.render(hud) { [weak self] img in
            self?.localBusy = false
            if self?.isConnected == false { self?.preview = img }
        }
    }

    // MARK: - Sesi dash

    private func wire(_ s: TftSession) {
        s.onLog = { [weak self] in self?.log($0) }
        s.onStatus = { [weak self] st in DispatchQueue.main.async { self?.setStatus(st) } }
        s.onClosed = { [weak self, weak s] in DispatchQueue.main.async { self?.sessionClosed(s) } }
        s.onAuthenticated = { [weak self] part in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.attempts = 0
                if !self.isConnected {
                    self.applyStartScreen()
                    self.session?.updateIdleRoad(self.currentStreet)
                    self.model?.trips.begin()
                    self.model?.music.start()
                    self.model?.weather.refresh(self.location.coordinate)
                }
                self.isConnected = true
                self.dashPart = part
                self.syncHomeWork()
                self.nav?.republish()
                self.startCcuIfNeeded()
            }
        }
        s.onBikeSpeed = { [weak self] v in DispatchQueue.main.async { self?.bikeSpeedKmh = v } }
        s.onPreview = { [weak self] img in DispatchQueue.main.async { self?.preview = img } }
        s.onFps = { [weak self] f in DispatchQueue.main.async { self?.fps = f } }
        s.onRequestPOI = { [weak self] kind, done in self?.providePOI(kind: kind, done: done) }
        s.onStartRoute = { [weak self] p in DispatchQueue.main.async { self?.nav?.navigate(to: p, autoStart: true) } }
        s.onStopRoute = { [weak self] in DispatchQueue.main.async { self?.nav?.stop() } }
        s.onGoHome = { [weak self] in DispatchQueue.main.async { self?.nav?.goHome() } }
        s.onGoWork = { [weak self] in DispatchQueue.main.async { self?.nav?.goWork() } }
        s.onStepScreen = { [weak self] fwd in DispatchQueue.main.async { self?.stepScreen(forward: fwd) } }
        s.isMusicScreen = { [weak self] in self?.currentScreen == .music }
        s.isTestScreen = { [weak self] in self?.currentScreen == .buttonTest }
        s.onButtonEvent = { [weak self] in self?.buttonEvent($0) }
        s.doubleClickWindow = { [weak self] in Double(self?.settings.doubleClickMs ?? 800) / 1000 }
        s.onVolume = { [weak self] up in
            DispatchQueue.main.async {
                let v = self?.model?.music.adjustVolume(up: up)
                self?.log(v.map { "Volume \(up ? "naik" : "turun") → \(Int(($0 * 100).rounded()))%" } ?? "Volume: slider sistem belum siap")
            }
        }
        s.contentProvider = { [weak self] in self?.dashContent() ?? DashContent() }
        s.screensProvider = { [weak self] in self?.screens() ?? [.mapData] }
        s.screenIndexProvider = { [weak self] in self?.screenIndex ?? 0 }
        s.buttonSchemeProvider = { [weak self] in self?.settings.buttonScheme ?? 1 }
        s.maxFpsProvider = { [weak self] in self?.settings.maxFps ?? 10 }
        s.autoZoomProvider = { [weak self] in self?.settings.autoZoom ?? true }
        s.routeProvider = { [weak self] in self?.nav?.upcomingPoints() ?? [] }
        s.destinationProvider = { [weak self] in self?.nav?.destinationCoordinate }
        s.wantsPreview = { [weak self] in
            (self?.previewVisible ?? false) && UIApplication.shared.applicationState == .active
        }
    }

    private func providePOI(kind: Int, done: @escaping ([Place]) -> Void) {
        if kind == 3 {
            // hanya yang ditandai favorit (nama yang diubah di app ikut tampil)
            done(Array(places.favorites.prefix(30)))
        } else {
            let near = location.coordinate
            Task {
                let res = (try? await PlaceSearch.fuelStations(near: near, radius: 5000)) ?? []
                done(res)
            }
        }
    }

    // MARK: - Eksperimen CCU

    /// Jalan otomatis saat dash terhubung: ambil ID+passkey lewat iAP lalu sambung BLE.
    func startCcuIfNeeded() {
        guard settings.ccuEnabled, !ccuStarted else { return }
        ccuStarted = true
        runCcuProbe()
    }

    func runCcuProbe() {
        guard let acc = EAAccessoryManager.shared().connectedAccessories
            .first(where: { $0.protocolStrings.contains(CcuProbe.protocolName) }) else {
            log("CCU: aksesori dengan protokol \(CcuProbe.protocolName) tidak ditemukan")
            return
        }
        ccuProbe.stop()
        ccuProbe.start(accessory: acc)
    }

    func stopCcuProbe() { ccuProbe.stop(); ccu.stop(); ccuStarted = false }
}
