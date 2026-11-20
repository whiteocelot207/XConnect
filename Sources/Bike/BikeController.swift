import Foundation
import UIKit
import ExternalAccessory
import Combine
import CoreLocation
import AVFoundation
import CoreTelephony
import CallKit

final class BikeController: NSObject, ObservableObject {
    @Published var status = "Belum terhubung"
    @Published var isConnected = false {
        didSet {
            updateIdleTimer()
            location.setHighPower(isConnected)
            model?.music.dashConnected = isConnected
            model?.music.updateKeepAlive()
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

    weak var model: AppModel?

    private let location: LocationProvider
    private let settings: AppSettings
    private let places: PlaceStore
    private weak var nav: NavigationController?

    private var session: TftSession?
    private var manualStop = false
    private var attempts = 0
    private var reconnectWork: DispatchWorkItem?
    /// Beberapa detik setelah app ke latar belakang / kembali ke depan: thread utama sibuk (UI, sesi audio, rute), jadi ACK
    /// dash yang terlambat tidak boleh langsung membuat sesi ditutup.
    private var lifecycleGraceUntil = Date.distantPast
    /// pratinjau Home ditahan sebentar setelah app kembali ke depan, supaya thread utama tidak ikut sibuk menggambar ulang
    private var previewHoldoffUntil = Date.distantPast
    private var bgTask = UIBackgroundTaskIdentifier.invalid
    private var bag = Set<AnyCancellable>()
    private let ccuProbe = CcuProbe()
    /// membangunkan app tanpa dibuka (geofence titik parkir + BLE ke CCU), seperti WakeMonitor di NConnect
    private let wake = WakeMonitor()
    private var wakeCooldownUntil = Date.distantPast
    let vehicleLive = VehicleLive()
    private lazy var ccu: CcuLink = {
        let c = CcuLink(live: vehicleLive)
        c.languageProvider = { [weak self] in self?.settings.dashLang ?? -1 }
        return c
    }()
    private var ccuStarted = false
    private var previewVisible = false
    /// Halaman yang sedang memakai pratinjau ("home", "pengaturan"). Pratinjau mati hanya bila tidak ada pemakai lagi.
    private var previewOwners = Set<String>()
    private var localTimer: Timer?
    private var localBusy = false
    /// Waktu render pratinjau lokal dimulai dan nomor render terakhir; dipakai pengawas supaya satu render yang
    /// macet tidak membekukan pratinjau selamanya.
    private var localBusySince = Date.distantPast
    private var localRenderID = 0
    private let geocoder = CLGeocoder()
    private var lastGeocode = Date.distantPast
    private var lastGeocodeLoc: CLLocation?
    private let netInfo = CTTelephonyNetworkInfo()
    // Nilai yang butuh IPC ke mediaserverd/CommCenter (volume, rute audio, jaringan seluler) dibaca di antrean latar
    // tiap 1 dtk dan hanya disalin saat menggambar frame. Sebelumnya dibaca di thread utama sampai 10x/dtk, dan bila
    // layanan sistem sedang sibuk (musik diputar, volume berubah) thread utama tertahan: klik stang, data CCU dan frame ikut macet.
    private let sysLock = NSLock()
    private var cachedVolume: Float = 0
    private var lastPolledVolume: Float = -1
    private var cachedRoute = ""
    private var cachedNetwork = ""
    private var cachedSignal = 0
    private var cachedHeadset = false
    private let callObserver = CXCallObserver()
    private var statusTimer: Timer?
    private var sysTimer: DispatchSourceTimer?
    private var beatTimer: DispatchSourceTimer?
    private let sysQueue = DispatchQueue(label: "dash.sysinfo", qos: .utility)
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
            self?.log("Aksesori terputus: \(a?.name ?? "?") (app \(self?.appStateText ?? "?"))")
            self?.accessoryPresent = self?.findDash() != nil
            // Jangan langsung menutup sesi: saat app berpindah latar/depan, daftar aksesori kadang kosong sesaat padahal
            // dash masih tersambung. Bila dash benar-benar putus, stream iAP sendiri akan error/berakhir dan sesi ditutup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let self = self else { return }
                self.accessoryPresent = self.findDash() != nil
                if self.findDash() == nil {
                    self.log("Aksesori masih tidak ada setelah 2,5 dtk, sesi ditutup")
                    self.session?.stop()
                }
            }
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.lifecycleGraceUntil = Date().addingTimeInterval(10)
            self.previewHoldoffUntil = Date().addingTimeInterval(2.5)
            self.endBackgroundTask()
            self.accessoryPresent = self.findDash() != nil
            self.log("App aktif (sesi dash: \(self.session == nil ? "tidak ada" : "ada"), aksesori: \(self.accessoryPresent ? "ada" : "tidak ada"))")
            self.updateIdleTimer()
            // bila sesi sempat tertutup selama di latar belakang, sambung SEKARANG (tidak menunggu jadwal sambung ulang)
            if self.session == nil, self.reconnectWork != nil {
                self.reconnectWork?.cancel()
                self.reconnectWork = nil
            }
            self.autoConnectIfNeeded()
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.lifecycleGraceUntil = Date().addingTimeInterval(10)
            self.beginBackgroundTask()
            self.log("App ke latar belakang (sesi dash: \(self.session == nil ? "tidak ada" : "ada"))")
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.lifecycleGraceUntil = Date().addingTimeInterval(10)
            self.log("App kembali ke depan (sesi dash: \(self.session == nil ? "tidak ada" : "ada"))")
        }
        startSysInfoPolling()
        startMainThreadWatch()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.model?.music.pollVolumeView()
            self?.pushPhoneStatus()
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
                guard let self = self, let m = self.model, odo > 0 else { return }
                if abs(m.maint.odometerKm - odo) > 0.05 { m.maint.odometerKm = odo }
                // sisa bensin berkurang menurut konsumsi saat ini (CCU/riwayat/bawaan), bukan hanya jarak total sejak isi
                m.fuel.advance(odo: odo, tank: m.vehicle.tankL, def: self.settings.defaultKmPerL)
            }
            .store(in: &bag)

        wake.onLog = { [weak self] s in self?.log(s) }
        wake.onWake = { [weak self] reason in
            DispatchQueue.main.async { self?.handleWake(reason) }
        }
        wake.start()

        SelfTest.run().forEach { log($0) }
        accessoryPresent = findDash() != nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.autoConnectIfNeeded() }
    }

    private var appStateText: String {
        switch UIApplication.shared.applicationState {
        case .active: return "aktif"
        case .inactive: return "tidak aktif"
        default: return "latar belakang"
        }
    }

    /// Tambahan waktu eksekusi saat app berpindah ke latar belakang, supaya sesi dash tidak tertahan di tengah peralihan.
    private func beginBackgroundTask() {
        endBackgroundTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "dash-session") { [weak self] in self?.endBackgroundTask() }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    // MARK: - Cache info sistem & pemantau thread utama

    private func startSysInfoPolling() {
        guard sysTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: sysQueue)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.pollSysInfo() }
        t.resume()
        sysTimer = t
    }

    private func pollSysInfo() {
        let a = AVAudioSession.sharedInstance()
        let vol = a.outputVolume
        let route = a.currentRoute.outputs.first.map { Geo.ascii($0.portName, maxLen: 14) } ?? ""
        let net = networkText()
        let headset = a.currentRoute.outputs.contains {
            [AVAudioSession.Port.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones].contains($0.portType)
        }
        // iOS tidak punya API publik untuk jumlah bar sinyal: ada jaringan data = 4 bar, SIM ada tapi tanpa jaringan = tanpa sinyal
        let hasSim = !(netInfo.serviceSubscriberCellularProviders ?? [:]).isEmpty
        let signal = !net.isEmpty ? 5 : (hasSim ? 1 : 0)
        sysLock.lock()
        // outputVolume bisa basi (tidak ikut berubah saat volume diubah dari HP atau stang); jadi hanya dipakai bila nilainya
        // BARU berubah dari bacaan sebelumnya. Nilai dari KVO/notifikasi/stang tidak ditimpa oleh bacaan lama.
        if abs(vol - lastPolledVolume) > 0.001 {
            lastPolledVolume = vol
            cachedVolume = vol
        }
        cachedRoute = route
        cachedNetwork = net
        cachedSignal = signal
        cachedHeadset = headset
        sysLock.unlock()
    }

    /// Ikon bar atas dash (sinyal, baterai HP, headset): kirim status ponsel ke CCU, seperti Y-Connect/NConnect.
    private func pushPhoneStatus() {
        guard ccuStarted else { return }
        let dev = UIDevice.current
        let bl = dev.batteryLevel
        let charging = dev.batteryState == .charging || dev.batteryState == .full
        sysLock.lock()
        let vol = Int((cachedVolume * 100).rounded())
        let sig = cachedSignal
        let hs = cachedHeadset
        sysLock.unlock()
        let thermal: Int
        switch ProcessInfo.processInfo.thermalState {
        case .serious: thermal = 1
        case .critical: thermal = 2
        default: thermal = 0
        }
        let st = CcuLink.PhoneStatus(battery: bl >= 0 ? Int((bl * 100).rounded()) : 0, charging: charging,
                                     callVol: vol, mediaVol: vol,
                                     signal: sig, thermal: thermal, headset: hs)
        ccu.sendPhoneStatus(st)
        ccu.sendCallState(callObserver.calls.contains { !$0.hasEnded })
    }

    private func setCachedVolume(_ v: Float) {
        sysLock.lock(); cachedVolume = v; sysLock.unlock()
    }

    /// Volume sistem berubah (tombol HP, Control Center, atau stang): simpan dan langsung kirim ke dash,
    /// tidak menunggu siklus 1 dtk.
    func systemVolumeChanged(_ v: Float) {
        setCachedVolume(v)
        pushPhoneStatus()
    }

    /// Mencatat ke Log bila thread utama tertahan lebih dari 1 dtk (untuk menelusuri dash yang macet/tidak merespons klik).
    private func startMainThreadWatch() {
        guard beatTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: sysQueue)
        t.schedule(deadline: .now() + 2, repeating: 1.0)
        t.setEventHandler { [weak self] in
            let sent = Date()
            DispatchQueue.main.async {
                let d = Date().timeIntervalSince(sent)
                if d > 1.0 { self?.log(String(format: "Thread utama tertahan %.1f dtk", d)) }
            }
        }
        t.resume()
        beatTimer = t
    }

    // MARK: - Log & status

    func log(_ s: String) {
        DispatchQueue.main.async {
            self.logLines.append("\(self.fmt.string(from: Date())) \(s)")
            if self.logLines.count > 500 { self.logLines.removeFirst(100) }
        }
    }

    private func setStatus(_ s: String) { status = s }

    /// Catat peristiwa tombol ke Log.
    func buttonEvent(_ s: String) {
        log("Tombol: " + s)
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

    /// App dibangunkan iOS (keluar dari titik parkir, atau CCU motor terjangkau): sambungkan dash, dan coba lagi beberapa
    /// kali karena Bluetooth dash butuh beberapa detik setelah motor dinyalakan.
    private func handleWake(_ reason: String) {
        log("Wake: \(reason) (app \(appStateText))")
        wakeCooldownUntil = Date().addingTimeInterval(40)
        if UIApplication.shared.applicationState != .active { beginBackgroundTask() }
        accessoryPresent = findDash() != nil
        autoConnectIfNeeded()
        for d in [2.0, 5.0, 10.0, 20.0, 30.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self = self else { return }
                self.accessoryPresent = self.findDash() != nil
                self.autoConnectIfNeeded()
            }
        }
    }

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
        // percobaan pertama cepat (putus sesaat, mis. saat app berpindah latar/depan), lalu berangsur lebih jarang
        let delay: TimeInterval
        switch attempts {
        case 1: delay = 0.7
        case 2: delay = 1.5
        case 3: delay = 3
        default: delay = 8
        }
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
        log("Sesi dash tertutup (app \(appStateText)), menyambung ulang")
        scheduleReconnect()
        // motor mati/diparkir: pasang geofence di sini supaya app terbangun sendiri saat berangkat lagi
        if settings.autoConnect, let l = location.lastLocation { wake.arm(at: l) }
    }

    func syncHomeWork() {
        session?.updateHomeWork(home: places.home != nil, work: places.work != nil)
    }

    func locationUpdated(_ loc: CLLocation) {
        session?.gpsChanged()
        if !isConnected, session == nil, !wake.armed, settings.autoConnect, !location.simulating,
           Date() > wakeCooldownUntil, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 {
            wake.arm(at: loc)
        }
        if isConnected {
            if !location.simulating { model?.trips.update(loc) }     // simulasi tidak dicatat sebagai perjalanan
            model?.weather.refresh(loc.coordinate)
            updateStreet(loc)
        }
    }

    /// Nama jalan untuk bar bawah dash saat tidak navigasi. Dibatasi: minimal 6 detik dan 40 m antar permintaan.
    /// Bila lokasi sekarang tidak punya nama jalan (atau geocoding gagal), nama dikosongkan: tidak boleh
    /// menampilkan nama jalan terakhir yang sudah jauh terlewati.
    private func updateStreet(_ loc: CLLocation) {
        guard settings.showRoadName else {
            if !currentStreet.isEmpty { currentStreet = ""; session?.updateIdleRoad("") }
            return
        }
        if let last = lastGeocodeLoc, loc.distance(from: last) < 40, !currentStreet.isEmpty { return }
        // nama jalan lama yang sudah jauh (> 150 m) dari titik pencarian terakhir tidak lagi berlaku
        if let last = lastGeocodeLoc, loc.distance(from: last) > 150, !currentStreet.isEmpty {
            currentStreet = ""
            session?.updateIdleRoad("")
        }
        guard Date().timeIntervalSince(lastGeocode) > 6, !geocoder.isGeocoding else { return }
        lastGeocode = Date()
        lastGeocodeLoc = loc
        geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "id_ID")) { [weak self] marks, _ in
            // hanya `thoroughfare` (nama jalan). `name`/`subLocality` bisa berupa nomor rumah, tempat, atau kelurahan.
            let raw = marks?.first?.thoroughfare ?? ""
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self = self else { return }
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

    /// Pindah ke layar tertentu bila aktif (dipakai halaman pengaturan supaya pratinjau menampilkan layar yang relevan).
    func showScreen(_ screen: DashScreen) {
        guard let i = screens().firstIndex(of: screen), i != min(screenIndex, screens().count - 1) else { return }
        screenIndex = i
    }

    func stepScreen(forward: Bool) {
        let n = max(1, screens().count)
        screenIndex = (min(screenIndex, n - 1) + (forward ? 1 : n - 1)) % n
        log("Tampilan dash: \(currentScreen.title)")
        renderLocalPreview()
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
                            small: [settings.cardS1, settings.cardS2, settings.cardS3, settings.cardS4],
                            bigScale: CGFloat(settings.cardFontBig), smallScale: CGFloat(settings.cardFontSmall))
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
        sysLock.lock()
        let vol = cachedVolume
        c.audioOut = cachedRoute
        c.network = cachedNetwork
        sysLock.unlock()
        c.phoneVolume = Int((vol * 100).rounded())
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
            c.nav = NavHUD(icon: 35, text: "Jalan Lingkar Luar Jakarta", dist: "65 m", summary: "1,6 km · 0:37")
        }
        if let l = location.lastLocation {
            c.altitudeM = Int(l.altitude.rounded())
        }
        c.headingText = location.bearingKnown ? compass(location.bearing) : ""
        switch currentScreen {
        case .music:
            c.music = m.music.info
            c.musicToast = m.music.activeToast
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
        let map = netInfo.serviceCurrentRadioAccessTechnology
        var techs: [String] = map.map { Array($0.values) } ?? []
        // pakai jaringan yang dipakai untuk data seluler (kartu SIM data), bukan SIM lain
        if let id = netInfo.dataServiceIdentifier, let t = map?[id] { techs = [t] }
        if techs.isEmpty { return "" }
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

    // MARK: - Bar atas dan bawah dash (untuk pratinjau)

    /// Data yang sama dengan yang ditampilkan bar atas (jam, sinyal, headset, baterai HP, volume) dan bar bawah (nama jalan) di dash.
    struct BarStatus {
        var clock = ""
        var signal = 0
        var network = ""
        var battery = -1
        var charging = false
        var headset = false
        var gps = false
        var volume = 0
        var thermal = 0
        var road = ""
        var navigating = false
        var navSymbol = ""
        var connected = false
        var inCall = false
        var tempC: Int?
    }

    func barStatus() -> BarStatus {
        var b = BarStatus()
        b.clock = Fmt.clock(Date())
        let dev = UIDevice.current
        let bl = dev.batteryLevel
        b.battery = bl >= 0 ? Int((bl * 100).rounded()) : -1
        b.charging = dev.batteryState == .charging || dev.batteryState == .full
        switch ProcessInfo.processInfo.thermalState {
        case .serious: b.thermal = 1
        case .critical: b.thermal = 2
        default: b.thermal = 0
        }
        sysLock.lock()
        b.signal = cachedSignal
        b.network = cachedNetwork
        b.headset = cachedHeadset
        b.volume = Int((cachedVolume * 100).rounded())
        sysLock.unlock()
        b.gps = location.hasFix
        b.connected = isConnected
        b.inCall = callObserver.calls.contains { !$0.hasEnded }
        b.tempC = model?.weather.tempC
        if let n = nav, n.phase == .navigating {
            b.navigating = true
            b.navSymbol = n.nextSymbol
            b.road = n.currentRoad
        } else {
            b.road = currentStreet
        }
        return b
    }

    // MARK: - Preview di Home

    /// Dipanggil Home dan halaman Pengaturan saat tampil/hilang. Bila motor tidak tersambung, preview digambar lokal.
    /// Tiap halaman memakai `owner` sendiri: saat berpindah tab, halaman yang hilang tidak boleh mematikan pratinjau
    /// halaman yang baru tampil (urutan onDisappear/onAppear tidak dijamin), jadi pratinjau mati hanya bila semua pemakai sudah pergi.
    func setPreviewVisible(_ v: Bool, owner: String = "home") {
        if v { previewOwners.insert(owner) } else { previewOwners.remove(owner) }
        let want = !previewOwners.isEmpty
        if !v && want { return }              // masih ada halaman lain yang memakai pratinjau
        previewVisible = want
        localTimer?.invalidate()
        localTimer = nil
        if want {
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
        guard previewVisible, !isConnected,
              UIApplication.shared.applicationState == .active else { return }
        if localBusy {
            // render sebelumnya belum selesai: beri waktu 2 dtk, lalu anggap macet dan jalankan yang baru
            let stuck = Date().timeIntervalSince(localBusySince)
            guard stuck > 2.0 else { return }
            log("Pratinjau: render \(currentScreen.title) macet \(Int(stuck)) dtk, dicoba ulang")
            localBusy = false
        }
        localBusy = true
        localBusySince = Date()
        localRenderID += 1
        let id = localRenderID
        let started = Date()
        let screen = currentScreen
        let content = dashContent()
        let navigating = content.nav != nil
        let hud = DashHUD(size: CGSize(width: 480, height: 234), screen: screen, content: content,
                          center: location.coordinate, bearing: location.bearing,
                          zoom: navigating ? 17.2 : 16.8,
                          route: navigating ? (nav?.upcomingPoints() ?? []) : [],
                          destination: navigating ? nav?.destinationCoordinate : nil)
        DashRenderer.render(hud) { [weak self] img in
            guard let self = self else { return }
            let took = Date().timeIntervalSince(started)
            if took > 1.0 { self.log("Pratinjau: render \(screen.title) selesai \(String(format: "%.1f", took)) dtk") }
            // hasil render lama (yang sudah dianggap macet) tidak boleh menimpa render yang lebih baru,
            // tetapi gambarnya tetap dipakai bila belum ada yang lebih baru
            if id == self.localRenderID { self.localBusy = false }
            if !self.isConnected { self.preview = img }
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
                self.wake.disarm()
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
        s.onButtonEvent = { [weak self] in self?.buttonEvent($0) }
        s.doubleClickWindow = { [weak self] in Double(self?.settings.doubleClickMs ?? 450) / 1000 }
        s.holdSkipEnabled = { [weak self] in self?.settings.holdSkip ?? true }
        s.onMusicSkip = { [weak self] next in DispatchQueue.main.async { self?.model?.music.skip(next: next) } }
        s.onTogglePlay = { [weak self] in DispatchQueue.main.async { self?.model?.music.wheelTogglePlay() } }
        s.onVolume = { [weak self] up in
            DispatchQueue.main.async {
                let v = self?.model?.music.adjustVolume(up: up)
                if let v = v { self?.setCachedVolume(v) }
                self?.log(v.map { "Volume \(up ? "naik" : "turun") → \(Int(($0 * 100).rounded()))%" } ?? "Volume: slider sistem belum siap")
            }
        }
        s.contentProvider = { [weak self] in self?.dashContent() ?? DashContent() }
        s.screensProvider = { [weak self] in self?.screens() ?? [.mapData] }
        s.screenIndexProvider = { [weak self] in self?.screenIndex ?? 0 }
        s.maxFpsProvider = { [weak self] in self?.settings.maxFps ?? 10 }
        s.qualityProvider = { [weak self] in self?.settings.dashQuality ?? 0.7 }
        s.autoZoomProvider = { [weak self] in self?.settings.autoZoom ?? true }
        s.routeProvider = { [weak self] in self?.nav?.upcomingPoints() ?? [] }
        s.destinationProvider = { [weak self] in self?.nav?.destinationCoordinate }
        s.wantsPreview = { [weak self] in
            guard let self = self else { return false }
            return self.previewVisible && UIApplication.shared.applicationState == .active
                && Date() > self.previewHoldoffUntil
        }
        s.inLifecycleGrace = { [weak self] in
            guard let self = self else { return false }
            return Date() < self.lifecycleGraceUntil || UIApplication.shared.applicationState != .active
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
