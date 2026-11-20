import Foundation
import UIKit
import ExternalAccessory
import CoreLocation

/// Sesi dengan dash TFT (docs/bike-protocol.md bagian 3-4): handshake, streaming layar dash
/// (digambar CPU, jadi jalan saat app di latar belakang), nama jalan, dan menu favorit/SPBU.
final class TftSession {
    var onLog: (String) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }
    var onClosed: () -> Void = {}
    var onAuthenticated: (String) -> Void = { _ in }
    var onBikeSpeed: (Int) -> Void = { _ in }
    var onPreview: (UIImage) -> Void = { _ in }
    var onFps: (Double) -> Void = { _ in }
    var onRequestPOI: (Int, @escaping ([Place]) -> Void) -> Void = { _, done in done([]) }
    var onStartRoute: (Place) -> Void = { _ in }
    var onStopRoute: () -> Void = {}
    var onGoHome: () -> Void = {}
    var onGoWork: () -> Void = {}
    /// catatan peristiwa tombol (masuk Log)
    var onButtonEvent: (String) -> Void = { _ in }
    var doubleClickWindow: () -> Double = { 0.8 }
    /// Layar Musik: tahan tombol atas/bawah = lagu berikutnya/sebelumnya (lama tahan dari Pengaturan)
    var holdSkipEnabled: () -> Bool = { true }
    var holdDuration: () -> Double = { 0.7 }
    var onMusicSkip: (Bool) -> Void = { _ in }

    var contentProvider: () -> DashContent = { DashContent() }
    var screensProvider: () -> [DashScreen] = { [.mapData] }
    var buttonSchemeProvider: () -> Int = { 1 }
    var screenIndexProvider: () -> Int = { 0 }
    var onStepScreen: (Bool) -> Void = { _ in }
    /// true bila layar dash saat ini = Musik (tombol atas/bawah dipakai untuk volume)
    var isMusicScreen: () -> Bool = { false }
    var onVolume: (Bool) -> Void = { _ in }
    var wantsPreview: () -> Bool = { true }
    /// true sesaat setelah app berpindah latar/depan: ACK dash yang terlambat tidak langsung menutup sesi
    var inLifecycleGrace: () -> Bool = { false }
    var maxFpsProvider: () -> Double = { 10 }
    var qualityProvider: () -> Double = { 0.7 }
    var autoZoomProvider: () -> Bool = { true }
    var routeProvider: () -> [CLLocationCoordinate2D] = { [] }
    var destinationProvider: () -> CLLocationCoordinate2D? = { nil }

    private let link = AccessoryLink()
    private var parser = NaviPacketParser()
    private let location: LocationProvider

    private var authenticated = false
    private var streaming = false
    private var generation = 0
    private var frameSize = CGSize(width: 480, height: 234)
    private var partNo = ""

    private var seq: UInt16 = 0
    private var lastSentSeq: UInt16 = 0
    private var ackPending = false
    private var renderBusy = false
    private var readyJPEG: [UInt8]?
    private var readyAt = Date.distantPast
    private var lastSentJPEG: [UInt8] = []
    private var lastTransmit = Date.distantPast
    private var lastDropLog = Date.distantPast
    /// frame yang sudah menunggu ACK lebih lama dari ini dibuang dan digambar ulang dengan data terbaru
    private let staleFrameLimit: TimeInterval = 0.15
    /// frame yang sama persis dengan sebelumnya tidak dikirim, kecuali sudah selama ini (supaya dash tidak menganggap putus)
    private let repeatInterval: TimeInterval = 1.0
    private var lastRenderStart = Date.distantPast
    private var ackTimer: Timer?
    private var lastPayload: [UInt8] = []
    private var ackRetries = 0
    private var watchTimer: Timer?

    private var zoomOffset = 0.0
    private var lastBtn: Date?
    private var labelSends = 0
    private var lastBtnUp = true
    private var pendingSingle: DispatchWorkItem?
    // rangkaian tekan di layar Musik (untuk mengenali tekan tahan)
    private var chainUp = true
    private var chainStart = Date.distantPast
    private var chainLast = Date.distantPast
    private var chainCount = 0
    private var holdFired = false
    private var pendingScreenStep: DispatchWorkItem?
    /// klik 2x di layar Musik: ganti tampilan ditunda sebentar untuk memastikan itu bukan awal tekan tahan
    private let holdProbe: TimeInterval = 0.4
    private var lastNight = false
    private var lastZoomLabel = ""
    private var navActive = false
    private var lastRoad = ""
    private var latestRoad = ""
    private var idleRoad = ""
    private var homeSet = false
    private var workSet = false
    private var lastGps = false
    private var lists: [Int: [Place]] = [:]
    private var listIdx = 0

    private var fpsStart = Date()
    private var fpsCount = 0
    private var lastPreview = Date.distantPast

    init(location: LocationProvider) {
        self.location = location
        link.onData = { [weak self] d in self?.receive(d) }
        link.onLog = { [weak self] s in self?.onLog(s) }
        link.onClosed = { [weak self] in self?.handleClosed() }
    }

    // MARK: - Siklus hidup

    func start(accessory: EAAccessory) -> Bool {
        parser.reset()
        authenticated = false
        streaming = false
        if link.open(accessory) {
            onLog("Sesi iAP dibuka, menunggu ESN dari dash…")
            onStatus("Menunggu dash…")
            return true
        }
        onLog("Gagal membuka sesi iAP (app lain mungkin sedang memakai dash)")
        onStatus("Gagal membuka sesi")
        return false
    }

    func stop() {
        streaming = false
        ackTimer?.invalidate()
        watchTimer?.invalidate()
        link.close()
    }

    // MARK: - Input dari app

    /// Dipanggil saat status navigasi berubah (nama jalan saat ini + apakah navigasi aktif).
    func updateNav(active: Bool, road: String) {
        let was = navActive
        navActive = active
        latestRoad = road
        guard authenticated else { return }
        if active != was { send(.value(NaviService.navStatus, active ? 1 : 0)) }
        sendRoadIfNeeded()
    }

    func updateHomeWork(home: Bool, work: Bool) {
        homeSet = home
        workSet = work
        guard authenticated else { return }
        send(.value(NaviService.homeSetting, home ? 1 : 0))
        send(.value(NaviService.officeSetting, work ? 1 : 0))
    }

    func gpsChanged() {
        let fix = location.hasFix
        guard fix != lastGps else { return }
        lastGps = fix
        if authenticated { send(.value(NaviService.gpsStatus, fix ? 1 : 0)) }
    }

    /// Nama jalan saat tidak navigasi (dari geocoding GPS), dipakai bila navigasi tidak punya nama jalan.
    func updateIdleRoad(_ road: String) {
        idleRoad = road
        sendRoadIfNeeded()
    }

    private func sendRoadIfNeeded() {
        guard authenticated else { return }
        let road = latestRoad.isEmpty ? idleRoad : latestRoad
        guard road != lastRoad else { return }
        lastRoad = road
        send(.pointer(NaviService.roadName, Array(Geo.ascii(road, maxLen: 64).utf8)))
    }

    // MARK: - Terima

    private func receive(_ data: Data) {
        let before = parser.droppedBytes
        let packets = parser.feed(data)
        let dropped = parser.droppedBytes - before
        if dropped > 0, Date().timeIntervalSince(lastDropLog) > 1 {
            lastDropLog = Date()
            let sample = parser.takeDropSample().map { String(format: "%02x", $0) }.joined(separator: " ")
            onLog("← \(dropped) B dari dash dibuang (bukan paket NaviLite sah): \(sample)")
        }
        for p in packets { handle(p) }
    }

    private func handle(_ p: NaviPacket) {
        switch p.service {
        case NaviService.esn:
            onLog("← ESN: \(String(bytes: p.payload, encoding: .ascii) ?? "?")")
            send(.value(NaviService.esnAck, 1))
            var auth = [UInt8]()
            auth += [UInt8(1870 & 0xFF), UInt8(1870 >> 8), 0x00, 0x01, 0, 0, 0, 0]
            send(.pointer(NaviService.authRequest, auth))

        case NaviService.authSecData:
            let d = p.payload.map { $0 ^ 0x0A }
            guard d.count >= 12 else { onLog("SEC_DATA terlalu pendek"); return }
            partNo = String(bytes: d[0..<12], encoding: .ascii) ?? ""
            let key = Array(d[12...])
            if partNo.contains("006-B4160") || partNo.contains("006-B4920") {
                frameSize = CGSize(width: 480, height: 240)
            } else {
                frameSize = CGSize(width: 480, height: 234)
            }
            onLog("← SEC_DATA partNo=\(partNo) frame=\(Int(frameSize.width))x\(Int(frameSize.height))")
            send(.pointer(NaviService.authSecDataAck, key))

        case NaviService.authAck:
            if p.intValue == 1 {
                authenticated = true
                onLog("← AUTH_ACK: terautentikasi")
                onStatus("Terhubung, menunggu dash minta peta")
                sendInitialState()
                onAuthenticated(partNo)
            } else {
                onLog("← AUTH_ACK: DITOLAK")
                onStatus("Autentikasi ditolak")
            }

        case NaviService.startContent:
            let t = Int(p.intValue ?? -1)
            onLog("← START_CONTENT \(t)")
            switch t {
            case 1:
                startStreaming()
            case 3, 4:
                onRequestPOI(t) { [weak self] places in
                    DispatchQueue.main.async { self?.sendPOIList(kind: t, places: places) }
                }
            default:
                onLog("START_CONTENT \(t) belum didukung")
            }

        case NaviService.stopContent:
            let t = Int(p.intValue ?? -1)
            onLog("← STOP_CONTENT \(t)")
            if t == 1 {
                stopStreaming()
                send(.value(NaviService.imageStopped, 0))
            }

        case NaviService.imageAck:
            guard let s = p.intValue, UInt16(bitPattern: s) == lastSentSeq else { return }
            ackTimer?.invalidate()
            ackPending = false
            pump()

        case NaviService.zoomIn:
            onLog("← zoom+ payload=\(p.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
            buttonPressed(up: true)
        case NaviService.zoomOut:
            onLog("← zoom- payload=\(p.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
            buttonPressed(up: false)

        case NaviService.startRoute:
            let b = p.payload
            if b.count >= 4 {
                let item = Bytes.i16(b, 0)
                let lst = Bytes.i16(b, 2)
                if let places = lists[lst], item >= 0, item < places.count {
                    onLog("← pilih tujuan dari dash: \(places[item].name)")
                    onStartRoute(places[item])
                } else {
                    onLog("← START_ROUTE item=\(item) list=\(lst) tidak dikenal")
                }
            }

        case NaviService.stopRoute:
            onLog("← STOP_ROUTE dari dash")
            onStopRoute()

        case NaviService.goHome:
            onLog("← GO_HOME dari dash")
            onGoHome()

        case NaviService.goOffice:
            onLog("← GO_OFFICE dari dash")
            onGoWork()

        case NaviService.vehicleSpeed:
            if p.payload.count >= 3 {
                let unit = p.payload[0]
                let v = Bytes.i16(p.payload, 1)
                let kmh = unit == 1 ? Int((Double(v) * 1.609).rounded()) : v
                onBikeSpeed(kmh)
            }

        case NaviService.sysInfo, NaviService.dialog:
            onLog("← layanan \(p.service) (\(p.payload.count) B)")

        default:
            onLog("← layanan \(p.service) frameType=\(p.frameType) (\(p.payload.count) B)")
        }
    }

    // MARK: - Tombol atas/bawah di dash

    /// Tanpa jeda: klik pertama langsung dieksekusi. Bila klik kedua (arah sama) datang dalam jendela waktu
    /// (Pengaturan > Kontrol pada motor), aksi klik pertama dibatalkan lalu aksi "2x" dijalankan.
    /// Skema 0: 1x ganti tampilan, 2x zoom. Skema 1: 1x zoom, 2x ganti tampilan.
    /// Di layar Musik: 1x = volume, 2x = ganti tampilan.
    /// Tombol "+" (atas) = tampilan berikutnya/zoom in/volume naik, "-" (bawah) kebalikannya.
    private func buttonPressed(up: Bool) {
        let before = labelSends
        handleButton(up: up)
        // docs/protocol/link-a-dash.md: tepat setelah tiap tekan 51/52, kirim cmd 14 (flag 1, `07 1A ...`); tanpa itu
        // hanya tekanan pertama dalam sesi yang sampai ke app. Label zoom sudah merupakan cmd 14, tetapi hanya
        // terkirim bila zoom berubah: klik volume di layar Musik atau ganti tampilan tidak mengirim
        // apa pun sehingga tombol stang berhenti merespons ("hang"). Kini label dikirim ulang bila belum ada.
        if authenticated && labelSends == before {
            lastZoomLabel = ""
            sendZoomLabel(effectiveZoom(navigating: navActive))
        }
    }

    private func handleButton(up: Bool) {
        let scheme = buttonSchemeProvider()
        let music = isMusicScreen()
        let window = doubleClickWindow()
        let now = Date()
        var gap = ""
        if let last = lastBtn { gap = " (+\(Int(now.timeIntervalSince(last) * 1000)) ms)" }
        let dir = up ? "atas" : "bawah"
        if music && holdSkipEnabled() {
            lastBtn = now
            lastBtnUp = up
            handleMusicButton(up: up, now: now, window: window, gap: gap)
            return
        }
        if let last = lastBtn, lastBtnUp == up, now.timeIntervalSince(last) < window {
            lastBtn = nil
            onButtonEvent("\(dir) 2x cepat\(gap)")
            if music {
                onVolume(!up)                    // batalkan volume dari klik pertama
                onStepScreen(up)
            } else if scheme == 0 {
                onStepScreen(!up)                // batalkan ganti tampilan
                changeZoom(up ? 1 : -1)
            } else {
                changeZoom(up ? -1 : 1)          // batalkan zoom
                onStepScreen(up)
            }
        } else {
            lastBtn = now
            lastBtnUp = up
            onButtonEvent("\(dir) 1x\(gap)")
            if music {
                onVolume(up)
            } else if scheme == 0 {
                onStepScreen(up)
            } else {
                changeZoom(up ? 1 : -1)
            }
        }
    }

    /// Layar Musik dengan tekan tahan aktif.
    /// Dash mengirim satu paket tiap tekan; saat tombol ditahan paket itu berulang. Rangkaian tekan arah sama (jeda
    /// antar tekan maksimal sama dengan jendela klik 2x) yang berlangsung >= durasi tahan dengan >= 3 tekan dianggap
    /// TAHAN: atas = lagu berikutnya, bawah = lagu sebelumnya (sekali per tahan).
    /// 1 tekan = volume (langsung), 2 tekan cepat = ganti tampilan (ditunda `holdProbe` supaya tidak salah dikira awal tahan).
    private func handleMusicButton(up: Bool, now: Date, window: Double, gap: String) {
        let dir = up ? "atas" : "bawah"
        if chainCount > 0, chainUp == up, now.timeIntervalSince(chainLast) <= window {
            chainCount += 1
        } else {
            pendingScreenStep?.cancel()
            pendingScreenStep = nil
            chainUp = up
            chainStart = now
            chainCount = 1
            holdFired = false
        }
        chainLast = now
        let span = now.timeIntervalSince(chainStart)
        let spanMs = Int(span * 1000)

        if holdFired {
            onButtonEvent("\(dir) tahan berlanjut (\(chainCount) tekan, \(spanMs) ms)\(gap)")
            return
        }
        if chainCount >= 3 && span >= holdDuration() {
            pendingScreenStep?.cancel()
            pendingScreenStep = nil
            holdFired = true
            onButtonEvent("\(dir) TAHAN (\(chainCount) tekan, \(spanMs) ms)\(gap) → lagu \(up ? "berikutnya" : "sebelumnya")")
            onMusicSkip(up)
            return
        }
        switch chainCount {
        case 1:
            onButtonEvent("\(dir) 1x\(gap)")
            onVolume(up)
        case 2:
            onButtonEvent("\(dir) 2x cepat\(gap)")
            onVolume(!up)                                   // batalkan volume dari klik pertama
            let work = DispatchWorkItem { [weak self] in
                self?.pendingScreenStep = nil
                self?.onStepScreen(up)
            }
            pendingScreenStep = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdProbe, execute: work)
        default:
            onButtonEvent("\(dir) tekan ke-\(chainCount), \(spanMs) ms dari awal (tahan butuh \(Int(holdDuration() * 1000)) ms)\(gap)")
        }
    }

    private func changeZoom(_ d: Double) {
        zoomOffset = min(3, max(-3, zoomOffset + d))
        lastZoomLabel = ""
        // kirim label zoom sekarang juga, jangan menunggu frame berikutnya selesai digambar
        if authenticated { sendZoomLabel(effectiveZoom(navigating: navActive)) }
    }

    // MARK: - Kirim

    private func send(_ p: NaviPacket) { link.send(p.encode()) }

    private func sendInitialState() {
        lastRoad = ""
        lastGps = location.hasFix
        send(.value(NaviService.navStatus, navActive ? 1 : 0))
        send(.value(NaviService.homeSetting, homeSet ? 1 : 0))
        send(.value(NaviService.officeSetting, workSet ? 1 : 0))
        send(.value(NaviService.gpsStatus, location.hasFix ? 1 : 0))
        send(.value(NaviService.appSetting, 1))
        lastNight = contentProvider().night
        send(.value(NaviService.dayNight, lastNight ? 2 : 1))
        lastZoomLabel = ""
        sendZoomLabel(effectiveZoom(navigating: navActive))
        sendRoadIfNeeded()
    }

    static func formatDistance(_ m: Double) -> (Double, String) {
        if m < 1000 {
            let r = m >= 100 ? (m / 10).rounded() * 10 : (m / 5).rounded() * 5
            return (r, "m")
        }
        return ((m / 100).rounded() / 10, "km")
    }

    private func zoomLabel(_ z: Double) -> String {
        switch Int(z.rounded()) {
        case ...13: return "5 km"
        case 14: return "2 km"
        case 15: return "1 km"
        case 16: return "500 m"
        case 17: return "300 m"
        case 18: return "200 m"
        default: return "100 m"
        }
    }

    private func sendZoomLabel(_ z: Double) {
        let text = zoomLabel(z)
        guard text != lastZoomLabel else { return }
        lastZoomLabel = text
        labelSends += 1
        let label = Array(text.utf8)
        send(.pointer(NaviService.zoomLevel, [0x07, 0x1A, UInt8(label.count), 0x00] + label))
    }

    private func effectiveZoom(navigating: Bool) -> Double {
        let v = location.speedKmh
        var base = 16.8
        if navigating && autoZoomProvider() {
            if v < 15 { base = 17.8 } else if v < 35 { base = 17.0 } else if v < 55 { base = 16.3 } else { base = 15.6 }
        }
        return min(19.5, max(13, base + zoomOffset))
    }

    // MARK: - Menu favorit / SPBU (docs 4.4)

    private func sendPOIList(kind: Int, places: [Place]) {
        guard authenticated else { return }
        let list = Array(places.prefix(30))
        listIdx = listIdx == 0 ? 1 : 0
        lists[listIdx] = list
        let headerSvc = kind == 3 ? NaviService.favHeader : NaviService.gasHeader
        let itemSvc = kind == 3 ? NaviService.favItem : NaviService.gasItem

        var h = Bytes.le16(Int16(list.count))
        h.append(0)
        send(.pointer(headerSvc, h))

        let here = location.coordinate
        let heading = location.bearing
        for (i, pl) in list.enumerated() {
            let d = Geo.distance(here, pl.coordinate)
            let (val, unit) = TftSession.formatDistance(d)
            let rel = Geo.bearing(from: here, to: pl.coordinate) - heading
            let a = (rel.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let dir = UInt8(Int((a + 22.5) / 45) % 8 + 1)
            let name = Array(Geo.ascii(pl.name, maxLen: 100).utf8)
            let unitB = Array(unit.utf8)
            var b = [UInt8]()
            b += Bytes.le16(Int16(i))
            b += Bytes.le16(Int16(listIdx))
            b.append(dir)
            b.append(UInt8(name.count))
            b.append(UInt8(unitB.count))
            b += Bytes.le32(Float(val).bitPattern)
            b += unitB
            b += name
            send(.pointer(itemSvc, b))
        }
        onLog("→ daftar \(kind == 3 ? "favorit" : "SPBU"): \(list.count) item")
    }

    // MARK: - Streaming layar (pipeline: gambar frame berikutnya selagi menunggu ACK)

    private func startStreaming() {
        guard authenticated else { return }
        streaming = true
        generation += 1
        ackPending = false
        renderBusy = false
        readyJPEG = nil
        lastSentJPEG = []
        seq = 0
        fpsStart = Date()
        fpsCount = 0
        onStatus("Streaming peta")
        startWatchdog()
        pump()
    }

    private func stopStreaming() {
        streaming = false
        generation += 1
        ackPending = false
        renderBusy = false
        readyJPEG = nil
        ackTimer?.invalidate()
        watchTimer?.invalidate()
        onStatus("Streaming berhenti")
    }

    private func pump() {
        guard streaming else { return }
        if !ackPending, let jpeg = readyJPEG {
            readyJPEG = nil
            let waited = Date().timeIntervalSince(readyAt)
            if waited > staleFrameLimit {
                // frame ini menunggu ACK terlalu lama (peta/angka sudah ketinggalan): gambar ulang yang baru
            } else if jpeg == lastSentJPEG, Date().timeIntervalSince(lastTransmit) < repeatInterval {
                // tidak ada yang berubah: tidak usah memenuhi Bluetooth dengan frame yang sama
            } else {
                transmit(jpeg)
            }
        }
        if !renderBusy && readyJPEG == nil {
            let minInterval = 1.0 / max(1.0, maxFpsProvider())
            let wait = minInterval - Date().timeIntervalSince(lastRenderStart)
            if wait > 0.005 {
                let gen = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    if let s = self, s.generation == gen { s.pump() }
                }
            } else {
                render()
            }
        }
    }

    private func render() {
        renderBusy = true
        lastRenderStart = Date()
        let gen = generation

        let content = contentProvider()
        if content.night != lastNight {
            lastNight = content.night
            send(.value(NaviService.dayNight, content.night ? 2 : 1))
        }
        let screens = screensProvider()
        let screen = screens[min(max(0, screenIndexProvider()), screens.count - 1)]
        let navigating = content.nav != nil
        let zoom = effectiveZoom(navigating: navigating)
        let hud = DashHUD(size: frameSize, screen: screen, content: content,
                          center: location.predictedCoordinate(extraLatency: 0.3), bearing: location.bearing, zoom: zoom,
                          route: navigating ? routeProvider() : [],
                          destination: navigating ? destinationProvider() : nil)
        let quality = CGFloat(qualityProvider())
        DashRenderer.renderJPEG(hud, quality: quality) { [weak self] image, jpeg in
            guard let self = self, gen == self.generation else { return }
            self.renderBusy = false
            guard self.streaming else { return }
            self.sendZoomLabel(zoom)
            self.readyJPEG = jpeg
            self.readyAt = Date()
            if self.wantsPreview(), Date().timeIntervalSince(self.lastPreview) > 0.15 {
                self.lastPreview = Date()
                self.onPreview(image)
            }
            self.pump()
        }
    }

    private func transmit(_ jpeg: [UInt8]) {
        var payload = [UInt8]()
        payload.append(3)                      // 3 = layar penuh; semua elemen digambar app
        payload += [UInt8(seq & 0xFF), UInt8(seq >> 8)]
        payload += jpeg
        lastSentSeq = seq
        seq &+= 1
        ackPending = true
        lastSentJPEG = jpeg
        lastTransmit = Date()
        lastPayload = payload
        ackRetries = 0
        send(.pointer(NaviService.imageFrame, payload))
        armAckTimer()
        fpsCount += 1
        let dt = Date().timeIntervalSince(fpsStart)
        if dt >= 2 {
            onFps(Double(fpsCount) / dt)
            fpsCount = 0
            fpsStart = Date()
        }
    }

    /// Dash kadang lambat membalas (iOS menunda proses saat layar terkunci). Kirim ulang frame yang sama
    /// beberapa kali sebelum menyerah, supaya sesi tidak putus-sambung terus.
    private func armAckTimer() {
        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, self.ackPending, self.streaming else { return }
            self.ackRetries += 1
            // saat app berpindah latar/depan thread utama bisa tertahan beberapa detik; beri kesempatan lebih lama
            let maxRetries = self.inLifecycleGrace() ? 8 : 3
            if self.ackRetries > maxRetries {
                self.onLog("Dash tidak membalas ACK frame (\(self.ackRetries * 3) dtk), menutup sesi")
                self.stop()
                return
            }
            self.onLog("ACK frame belum datang, kirim ulang (\(self.ackRetries)/\(maxRetries))")
            self.send(.pointer(NaviService.imageFrame, self.lastPayload))
            self.armAckTimer()
        }
    }

    /// Pengaman: bila render macet atau tidak ada frame berjalan, jalankan ulang pipeline.
    private func startWatchdog() {
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self, self.streaming else { return }
            if self.renderBusy, Date().timeIntervalSince(self.lastRenderStart) > 4 {
                self.onLog("Render macet > 4 dtk, diulang")
                self.generation += 1
                self.renderBusy = false
            }
            if !self.ackPending, self.readyJPEG == nil, !self.renderBusy { self.pump() }
        }
    }

    private func handleClosed() {
        watchTimer?.invalidate()
        authenticated = false
        streaming = false
        generation += 1
        ackPending = false
        renderBusy = false
        readyJPEG = nil
        ackTimer?.invalidate()
        pendingSingle?.cancel()
        pendingScreenStep?.cancel()
        pendingScreenStep = nil
        chainCount = 0
        onStatus("Terputus")
        onLog("Sesi ditutup")
        onClosed()
    }
}
