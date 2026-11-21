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
    /// jarak waktu terlama antar dua tekan agar dihitung satu rangkaian klik cepat (detik)
    var doubleClickWindow: () -> Double = { 0.45 }
    /// Layar Musik: gesture musik aktif (2x = lagu berikutnya/sebelumnya, atas-bawah cepat = putar/jeda)
    var holdSkipEnabled: () -> Bool = { true }
    var onMusicSkip: (Bool) -> Void = { _ in }
    /// Layar Musik: atas lalu bawah cepat (atau sebaliknya) = putar/jeda
    var onTogglePlay: () -> Void = {}

    var contentProvider: () -> DashContent = { DashContent() }
    var screensProvider: () -> [DashScreen] = { [.mapData] }
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
    /// zoom dasar menurut kecepatan GPS (km/j); dari pengaturan Zoom peta
    var zoomProvider: (Double) -> Double = { _ in 16.8 }
    /// lama perpindahan zoom halus (detik), 0 = langsung
    var zoomSmoothProvider: () -> Double = { 0.8 }
    private let zoomSmoother = ZoomSmoother()
    private var smoothBase = 16.8
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
    // rangkaian klik cepat arah sama (jarak antar tekan <= jendela klik)
    private var chainUp = true
    private var chainLast = Date.distantPast
    private var chainCount = 0
    private var chainZoomBase = 0.0
    /// lagu berikutnya/sebelumnya dari klik 2x di layar Musik: ditunda selama jendela klik, karena klik ke-3 berarti ganti tampilan
    private var pendingSkip: DispatchWorkItem?
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
            onLog(tr("iAP session opened, waiting for ESN from the dash…"))
            onStatus(tr("Waiting for the dash…"))
            return true
        }
        onLog(tr("Failed to open iAP session (another app may be using the dash)"))
        onStatus(tr("Failed to open session"))
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
        // Saat navigasi hanya nama jalan dari rute. Bila segmen rute ini tidak punya nama jalan, bar dikosongkan;
        // jangan jatuh ke nama jalan hasil geocoding terakhir (itu nama jalan lain yang sudah terlewati).
        let road = navActive ? latestRoad : idleRoad
        guard road != lastRoad else { return }
        lastRoad = road
        // Nama kosong dikirim sebagai satu spasi: paket dengan isi kosong bisa dianggap "tidak ada pembaruan" oleh dash,
        // sehingga nama jalan lama tetap tampil.
        let text = Geo.ascii(road, maxLen: 64)
        let bytes = text.isEmpty ? [UInt8(0x20)] : Array(text.utf8)
        send(.pointer(NaviService.roadName, bytes))
    }

    // MARK: - Terima

    private func receive(_ data: Data) {
        let before = parser.droppedBytes
        let packets = parser.feed(data)
        let dropped = parser.droppedBytes - before
        if dropped > 0, Date().timeIntervalSince(lastDropLog) > 1 {
            lastDropLog = Date()
            let sample = parser.takeDropSample().map { String(format: "%02x", $0) }.joined(separator: " ")
            onLog(tr("← {0} B from the dash discarded (not a valid NaviLite packet): {1}", dropped, sample))
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
            guard d.count >= 12 else { onLog(tr("SEC_DATA too short")); return }
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
                onLog(tr("← AUTH_ACK: authenticated"))
                onStatus(tr("Connected, waiting for the dash to request the map"))
                sendInitialState()
                onAuthenticated(partNo)
            } else {
                onLog(tr("← AUTH_ACK: REJECTED"))
                onStatus(tr("Authentication rejected"))
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
                onLog(tr("START_CONTENT {0} not supported yet", t))
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
                    onLog(tr("← destination chosen from the dash: {0}", places[item].name))
                    onStartRoute(places[item])
                } else {
                    onLog(tr("← START_ROUTE item={0} list={1} unknown", item, lst))
                }
            }

        case NaviService.stopRoute:
            onLog(tr("← STOP_ROUTE from the dash"))
            onStopRoute()

        case NaviService.goHome:
            onLog(tr("← GO_HOME from the dash"))
            onGoHome()

        case NaviService.goOffice:
            onLog(tr("← GO_OFFICE from the dash"))
            onGoWork()

        case NaviService.vehicleSpeed:
            if p.payload.count >= 3 {
                let unit = p.payload[0]
                let v = Bytes.i16(p.payload, 1)
                let kmh = unit == 1 ? Int((Double(v) * 1.609).rounded()) : v
                onBikeSpeed(kmh)
            }

        case NaviService.sysInfo, NaviService.dialog:
            onLog(tr("← service {0} ({1} B)", p.service, p.payload.count))

        default:
            onLog(tr("← service {0} frameType={1} ({2} B)", p.service, p.frameType, p.payload.count))
        }
    }

    // MARK: - Tombol atas/bawah di dash

    /// Dash mengirim satu paket per tekan. Aturan (jarak antar tekan <= Durasi klik cepat di Pengaturan):
    ///   Layar biasa : 1x zoom (langsung), 2x zoom lagi, 3x ganti tampilan (zoom dikembalikan). Atas = berikutnya, bawah = sebelumnya.
    ///   Layar Musik : 1x volume (langsung), 2x lagu berikutnya (atas) / sebelumnya (bawah), 3x ganti tampilan.
    ///                 Atas lalu bawah cepat (atau sebaliknya) = putar/jeda.
    /// Tekan 1x dan zoom/volume tidak menunggu apa pun; efek klik awal dibatalkan bila rangkaian ternyata berlanjut.
    /// Hanya lagu berikutnya yang ditunda (selama jendela klik), karena pindah lagu tidak bisa dibatalkan.
    private func buttonPressed(up: Bool) {
        let before = labelSends
        handleButton(up: up)
        // docs/protocol/link-a-dash.md: tepat setelah tiap tekan 51/52, kirim cmd 14 (flag 1, `07 1A ...`); tanpa itu
        // hanya tekanan pertama dalam sesi yang sampai ke app. Label zoom sudah merupakan cmd 14, tetapi hanya
        // terkirim bila zoom berubah, jadi bila belum ada label yang terkirim, kirim sekarang (prioritas).
        if authenticated && labelSends == before {
            lastZoomLabel = ""
            sendZoomLabel(effectiveZoom(navigating: navActive))
        }
    }

    private func handleButton(up: Bool) {
        let music = isMusicScreen()
        let gestures = music && holdSkipEnabled()
        let window = max(0.2, doubleClickWindow())
        let now = Date()
        let gap = lastBtn.map { " (+\(Int(now.timeIntervalSince($0) * 1000)) ms)" } ?? ""
        lastBtn = now
        let dir = up ? tr("up") : tr("down")

        // Musik: arah BERLAWANAN tepat setelah tekan pertama = putar/jeda
        if gestures, chainCount == 1, chainUp != up, now.timeIntervalSince(chainLast) <= window {
            onVolume(!chainUp)                              // batalkan volume dari tekan pertama
            chainCount = 0
            onButtonEvent(tr("{0} after {1} quick{2} → play/pause", dir, chainUp ? tr("up") : tr("down"), gap))
            onTogglePlay()
            return
        }

        if chainCount > 0, chainUp == up, now.timeIntervalSince(chainLast) <= window {
            chainCount += 1
        } else {
            cancelPendingSkip()
            chainUp = up
            chainCount = 1
            chainZoomBase = zoomOffset
        }
        chainLast = now

        switch chainCount {
        case 1:
            onButtonEvent("\(dir) 1x\(gap)")
            if music { onVolume(up) } else { changeZoom(up ? 1 : -1) }
        case 2:
            onButtonEvent("\(dir) 2x\(gap)")
            if gestures {
                onVolume(!up)                               // batalkan volume dari klik pertama
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingSkip = nil
                    self?.onButtonEvent(tr("{0} 2x → track {1}", dir, up ? "berikutnya" : "sebelumnya"))
                    self?.onMusicSkip(up)
                }
                pendingSkip = work
                DispatchQueue.main.asyncAfter(deadline: .now() + window + 0.05, execute: work)
            } else if music {
                onVolume(up)
            } else {
                changeZoom(up ? 1 : -1)
            }
        case 3:
            cancelPendingSkip()
            onButtonEvent(tr("{0} 3x{1} → switch screen", dir, gap))
            if music {
                if !gestures { onVolume(!up); onVolume(!up) }   // batalkan dua langkah volume
            } else {
                setZoomOffset(chainZoomBase)                    // batalkan zoom dari dua klik pertama
            }
            onStepScreen(up)
        default:
            // tombol ditahan (dash mengulang paket) atau klik berlebih: abaikan sampai ada jeda
            onButtonEvent(tr("{0} press #{1} ignored{2}", dir, chainCount, gap))
        }
    }

    private func cancelPendingSkip() {
        pendingSkip?.cancel()
        pendingSkip = nil
    }

    private func changeZoom(_ d: Double) { setZoomOffset(zoomOffset + d) }

    private func setZoomOffset(_ v: Double) {
        zoomOffset = min(3, max(-3, v))
        lastZoomLabel = ""
        // kirim label zoom sekarang juga, jangan menunggu frame berikutnya selesai digambar
        if authenticated { sendZoomLabel(effectiveZoom(navigating: navActive)) }
    }

    // MARK: - Kirim

    private func send(_ p: NaviPacket, priority: Bool = false) { link.send(p.encode(), priority: priority) }

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
        send(.pointer(NaviService.zoomLevel, [0x07, 0x1A, UInt8(label.count), 0x00] + label), priority: true)
    }

    private func effectiveZoom(navigating: Bool) -> Double {
        return min(19.5, max(13, smoothBase + zoomOffset))
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
        onLog(tr("→ list {0}: {1} items", kind == 3 ? "favorit" : tr("Gas station"), list.count))
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
        onStatus(tr("Streaming map"))
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
        onStatus(tr("Streaming stopped"))
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
        smoothBase = zoomSmoother.step(to: zoomProvider(location.speedKmh), tau: zoomSmoothProvider())
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
                self.onLog(tr("Dash did not acknowledge the frame ({0} s), closing session", self.ackRetries * 3))
                self.stop()
                return
            }
            self.onLog(tr("Frame ACK not received, resending ({0}/{1})", self.ackRetries, maxRetries))
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
                self.onLog(tr("Render stuck > 4 s, restarted"))
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
        cancelPendingSkip()
        chainCount = 0
        onStatus(tr("Disconnected"))
        onLog(tr("Session closed"))
        onClosed()
    }
}
