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

    var contentProvider: () -> DashContent = { DashContent() }
    var screensProvider: () -> [DashScreen] = { [.mapData] }
    var buttonSchemeProvider: () -> Int = { 1 }
    var screenIndexProvider: () -> Int = { 0 }
    var onStepScreen: (Bool) -> Void = { _ in }
    /// true bila layar dash saat ini = Musik (tombol atas/bawah dipakai untuk volume)
    var isMusicScreen: () -> Bool = { false }
    var onVolume: (Bool) -> Void = { _ in }
    var wantsPreview: () -> Bool = { true }
    var maxFpsProvider: () -> Double = { 10 }
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
    private var lastRenderStart = Date.distantPast
    private var ackTimer: Timer?
    private var lastPayload: [UInt8] = []
    private var ackRetries = 0
    private var watchTimer: Timer?

    private var zoomOffset = 0.0
    private var lastBtn: Date?
    private var lastBtnUp = true
    private var pendingSingle: DispatchWorkItem?
    private var lastNight = false
    private var lastZoomLabel = ""
    private var navActive = false
    private var lastRoad = ""
    private var latestRoad = ""
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

    private func sendRoadIfNeeded() {
        guard authenticated, latestRoad != lastRoad else { return }
        lastRoad = latestRoad
        send(.pointer(NaviService.roadName, Array(Geo.ascii(latestRoad, maxLen: 64).utf8)))
    }

    // MARK: - Terima

    private func receive(_ data: Data) {
        for p in parser.feed(data) { handle(p) }
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

    /// Tanpa jeda: klik pertama langsung dieksekusi. Bila klik kedua (arah sama) datang < 0,5 dtk,
    /// aksi klik pertama dibatalkan lalu aksi "2x" dijalankan.
    /// Skema 0: 1x ganti tampilan, 2x zoom. Skema 1: 1x zoom, 2x ganti tampilan.
    /// Di layar Musik: 1x = volume, 2x = ganti tampilan.
    /// Tombol "+" (atas) = tampilan berikutnya/zoom in/volume naik, "-" (bawah) kebalikannya.
    private func buttonPressed(up: Bool) {
        let scheme = buttonSchemeProvider()
        let music = isMusicScreen()
        let now = Date()
        if let last = lastBtn { onLog("← tombol \(up ? "atas" : "bawah") (+\(Int(now.timeIntervalSince(last) * 1000)) ms)") }
        else { onLog("← tombol \(up ? "atas" : "bawah")") }
        if let last = lastBtn, lastBtnUp == up, now.timeIntervalSince(last) < 0.7 {
            lastBtn = nil
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
            if music { onVolume(up) }
            else if scheme == 0 { onStepScreen(up) }
            else { changeZoom(up ? 1 : -1) }
        }
    }

    private func changeZoom(_ d: Double) {
        zoomOffset = min(3, max(-3, zoomOffset + d))
        lastZoomLabel = ""
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
            transmit(jpeg)
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
                          center: location.coordinate, bearing: location.bearing, zoom: zoom,
                          route: navigating ? routeProvider() : [],
                          destination: navigating ? destinationProvider() : nil)
        DashRenderer.render(hud) { [weak self] image in
            guard let self = self, gen == self.generation else { return }
            self.renderBusy = false
            guard self.streaming else { return }
            self.sendZoomLabel(zoom)
            self.readyJPEG = self.encode(image)
            if self.wantsPreview(), Date().timeIntervalSince(self.lastPreview) > 0.15 {
                self.lastPreview = Date()
                self.onPreview(image)
            }
            self.pump()
        }
    }

    private func encode(_ image: UIImage) -> [UInt8] {
        var jpeg = image.jpegData(compressionQuality: 0.8) ?? Data()
        if jpeg.count <= 2048, let hq = image.jpegData(compressionQuality: 0.95) {
            jpeg = hq
            if jpeg.count < 2050 { jpeg.append(Data(count: 2050 - jpeg.count)) }
        }
        return [UInt8](jpeg)
    }

    private func transmit(_ jpeg: [UInt8]) {
        var payload = [UInt8]()
        payload.append(3)                      // 3 = layar penuh; semua elemen digambar app
        payload += [UInt8(seq & 0xFF), UInt8(seq >> 8)]
        payload += jpeg
        lastSentSeq = seq
        seq &+= 1
        ackPending = true
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
            if self.ackRetries > 3 {
                self.onLog("Dash tidak membalas ACK frame (\(self.ackRetries * 3) dtk), menutup sesi")
                self.stop()
                return
            }
            self.onLog("ACK frame belum datang, kirim ulang (\(self.ackRetries)/3)")
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
        onStatus("Terputus")
        onLog("Sesi ditutup")
        onClosed()
    }
}
