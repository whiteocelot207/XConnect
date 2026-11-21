import Foundation
import CoreBluetooth

/// Kandidat byte rata-rata konsumsi di paket id 1 yang cocok dengan angka di dash.
struct FuelByteCandidate: Identifiable {
    let id = UUID()
    let byte: Int
    let wide: Bool
    let unit: Int          // 0 km/L, 1 L/100 km
    let div: Double
    let raw: Int
    let kmpl: Double

    var text: String {
        let width = wide ? tr("byte {0}-{1}", byte, byte + 1) : tr("byte {0}", byte)
        let u = unit == 1 ? "L/100 km" : "km/L"
        return tr("{0}: raw {1}, ÷{2}, {3} → {4} km/L", width, raw, Int(div), u, String(format: "%.1f", kmpl))
    }
}

extension VehicleLive {
    /// Mencari byte di paket id 1 yang nilainya cocok dengan rata-rata BBM yang tampil di dash (km/L).
    /// Byte yang sudah dikenal (RPM, kecepatan, aki, suhu, kode gangguan) dilewati. Hanya urutan byte besar-dulu (seperti pembacaan saat ini).
    func fuelByteCandidates(target: Double, skip: Set<Int> = [0, 1, 2, 6, 14, 15, 23]) -> [FuelByteCandidate] {
        guard target > 0, !rawRecord.isEmpty else { return [] }
        var out = [(Double, FuelByteCandidate)]()
        for i in 0..<rawRecord.count {
            for wide in [false, true] {
                if wide && i + 1 >= rawRecord.count { continue }
                if skip.contains(i) || (wide && skip.contains(i + 1)) { continue }
                let raw = wide ? Int(rawRecord[i]) << 8 | Int(rawRecord[i + 1]) : Int(rawRecord[i])
                if raw == 0 { continue }
                for unit in 0...1 {
                    for div in [1.0, 10.0, 100.0] {
                        let v = Double(raw) / div
                        let kmpl = unit == 1 ? 100 / v : v
                        guard (3...120).contains(kmpl) else { continue }
                        let tol = div == 1 ? max(1.0, target * 0.04) : max(0.06, target * 0.015)
                        let diff = abs(kmpl - target)
                        if diff <= tol {
                            out.append((diff, FuelByteCandidate(byte: i, wide: wide, unit: unit, div: div, raw: raw, kmpl: kmpl)))
                        }
                    }
                }
            }
        }
        return out.sorted { $0.0 < $1.0 }.prefix(12).map { $0.1 }
    }
}

/// Data motor yang dibaca dari CCU (docs/bike-protocol.md bagian 6.5).
final class VehicleLive: ObservableObject {
    @Published var state = tr("Not active yet")
    @Published var connected = false
    @Published var batteryV: Double?
    @Published var odoKm: Double?
    @Published var coolantC: Int?
    @Published var airC: Int?
    @Published var rpm: Int?
    @Published var speedKmh: Int?
    @Published var ignitionOn: Bool?
    @Published var dtcCount: Int?
    @Published var lastUpdate: Date?
    /// 24 byte paket data id 1 (mentah), untuk kotak "CCU byte n" dan tampilan data mentah
    @Published var rawRecord: [UInt8] = []
    /// paket mentah semua id data yang pernah masuk (id -> byte)
    @Published var rawById: [Int: [UInt8]] = [:]

    /// Rata-rata konsumsi BBM (km/L) dari CCU, dibaca dari byte paket id 1 sesuai Pengaturan.
    /// Nilai di luar 3...120 km/L dianggap tidak valid (belum ada data / byte salah) dan dikembalikan nil.
    func fuelKmPerL(byte: Int, wide: Bool, unit: Int, divisor: Double) -> Double? {
        let need = byte + (wide ? 2 : 1)
        guard byte >= 0, rawRecord.count >= need else { return nil }
        var v = wide ? Double(Int(rawRecord[byte]) << 8 | Int(rawRecord[byte + 1])) : Double(rawRecord[byte])
        v /= max(0.001, divisor)
        guard v > 0 else { return nil }
        let kmpl: Double
        switch unit {
        case 1: kmpl = 100 / v        // L/100 km
        case 2: kmpl = 1 / v          // L/km
        default: kmpl = v             // km/L
        }
        return (3...120).contains(kmpl) ? kmpl : nil
    }

    func reset() {
        connected = false
        batteryV = nil; odoKm = nil; coolantC = nil; airC = nil
        rpm = nil; speedKmh = nil; ignitionOn = nil; dtcCount = nil
        rawRecord = []; rawById = [:]
    }
}

/// Link BLE ke CCU Yamaha (service AFA2CDF4…), mengikuti urutan Y-Connect:
/// SPP/iAP (ID + passkey) → BLE connect → auth → langganan data kendaraan.
/// BELUM PERNAH diuji di motor: setiap langkah dicatat ke log supaya bisa diperbaiki dari log.
final class CcuLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "AFA2CDF4-ECCF-46A7-A5EA-9DA428C0157A")
    private enum U {
        static let ctrlWrite = CBUUID(string: "B606C7F9-E5A1-4E75-B313-2A920054A8EB")
        static let ctrlNotify = CBUUID(string: "9C810D26-B605-4306-8C1C-755A1BA3066C")
        static let ddtStatus = CBUUID(string: "75AB2788-87F6-4F61-BA9C-6F85A12600D1")
        static let ddtOutHeader = CBUUID(string: "56851826-A090-4F6A-A5DF-D1776520F74A")
        static let ddtOutData = CBUUID(string: "E998AEAB-EA8F-4063-83AA-2017C1A44484")
        static let ddtInHeader = CBUUID(string: "77808451-E42F-4F6B-83ED-3AB44AA3D16A")
        static let ddtInData = CBUUID(string: "347456EE-A588-4DD5-BD98-62BE3672E27A")
        static let ddtInAck = CBUUID(string: "1A1A7A79-3D72-42A1-B084-843058453068")
        static let ddtV2 = CBUUID(string: "E974B9A1-FA31-43C6-91AE-09931F3F6EF1")
        static let ddtV3In = CBUUID(string: "56DC2D58-CBE1-4BA9-A104-E9B8EB4DA95C")
        static let unknownInd = CBUUID(string: "AB8D233A-CC58-4932-B397-A3751911E021")
    }

    /// Status ponsel untuk ikon bar atas dash (sinyal, baterai HP, headset, volume). Format ctrl 316 dari docs/bike-protocol.md §6.6:
    /// [01 3C][baterai% | cas<<7][vol panggilan% | 0x80][vol media% | 0x80][1 | headset<<1 | termal<<2 | sinyal<<4]
    /// (bit 0 selalu 1, seperti capture app resmi; status panggilan dikirim terpisah lewat cmd 308)
    struct PhoneStatus: Equatable {
        var battery: Int       // 0...100
        var charging: Bool
        var callVol: Int       // 0...100
        var mediaVol: Int      // 0...100
        var signal: Int        // 0 tanpa layanan, 1 tanpa sinyal, 2...5 = 1...4 bar
        var thermal: Int       // 0 rendah, 1 sedang, 2 tinggi
        var headset: Bool
    }
    /// Kode bahasa dash untuk cmd 12 (-1 = tidak dikirim). Dikenal: 0 Inggris, 15 Vietnam (docs/protocol/link-b-ccu.md).
    var languageProvider: () -> Int = { -1 }
    private var lastCall: Bool?

    private func sendLanguage(_ why: String) {
        let lang = languageProvider()
        guard lang >= 0, lang <= 255 else { return }
        ctrl(0x000C, [nextReq(), UInt8(lang)])          // 12
        onLog(tr("CCU: dash language → code {0} ({1})", lang, why))
    }

    /// Bahasa aplikasi berubah: kirim bahasa baru ke dash (bila sesi CCU sudah terautentikasi).
    func resendLanguage() {
        guard authed, central != nil else { return }
        sendLanguage(tr("language changed"))
    }

    /// Ikon panggilan di dash: cmd 308 `[1]` saat ada panggilan, `[2]` saat selesai. Dikirim hanya saat berubah.
    func sendCallState(_ inCall: Bool) {
        guard authed, central != nil else { return }
        if lastCall == nil && !inCall { lastCall = false; return }
        guard inCall != lastCall else { return }
        lastCall = inCall
        ctrl(0x0134, [inCall ? 1 : 2])                  // 308
        onLog(tr("CCU: call state → {0}", inCall ? tr("call active") : tr("ended")))
    }

    private var lastStatus: PhoneStatus?
    private var lastStatusSent = Date.distantPast

    /// Dikirim saat berubah, dan diulang tiap 20 dtk supaya ikon tidak hilang bila CCU melewatkan satu paket. Panggil dari main.
    func sendPhoneStatus(_ st: PhoneStatus) {
        guard authed, central != nil else { return }
        if st == lastStatus, Date().timeIntervalSince(lastStatusSent) < 20 { return }
        func pct(_ v: Int) -> UInt8 { UInt8(min(100, max(0, v))) }
        let b0 = pct(st.battery) | (st.charging ? 0x80 : 0)
        let b1 = pct(st.callVol) | 0x80
        let b2 = pct(st.mediaVol) | 0x80
        var b3: UInt8 = 0x01
        b3 |= UInt8(min(15, max(0, st.signal))) << 4
        b3 |= UInt8(min(2, max(0, st.thermal))) << 2
        if st.headset { b3 |= 0x02 }
        ctrl(0x013C, [b0, b1, b2, b3])                  // 316
        if st != lastStatus {
            onLog(tr("CCU: phone status → 01 3c {0}", hex([b0, b1, b2, b3])))
        }
        lastStatus = st
        lastStatusSent = Date()
    }

    var onLog: (String) -> Void = { _ in }
    let live: VehicleLive
    /// ID data tambahan yang ikut dilanggan (eksperimen, diisi dari Pengaturan)
    var extraIds: [Int] = []
    private var lastRawLog = Date.distantPast
    private var lastRawHex = ""
    private var seenIds = Set<Int>()

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var chars: [CBUUID: CBCharacteristic] = [:]
    private var ccuId = ""
    private var passkey = ""
    private var wantRun = false
    private var scanning = false
    private var subscribeQueue: [CBUUID] = []
    private var authed = false
    private var reqCounter: UInt8 = 0
    private var servers: [Int] = []
    private var requested = Set<Int>()
    private var fallbackDone = false
    private var lastData = Date.distantPast
    private var watchdog: Timer?
    private var scanTimeout: Timer?

    // DDT keluar
    private enum OutState { case idle, awaitIdle, awaitHeader, writing, awaitStatus }
    private var outQueue: [[UInt8]] = []
    private var outState = OutState.idle
    private var outBody: [UInt8] = []
    private var outReq: UInt8 = 0
    private var outOffset = 0
    private var outTimer: Timer?

    // DDT masuk
    private var v2Parts: [UInt16: (total: Int, parts: [Int: [UInt8]], t: Date)] = [:]
    private var inId: UInt8 = 0
    private var inLen = 0
    private var inBuf: [UInt8] = []

    init(live: VehicleLive) {
        self.live = live
        super.init()
    }

    // MARK: - Siklus hidup

    /// Membuat CBCentralManager supaya iOS menampilkan izin Bluetooth untuk app ini.
    func prepare() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func start(ccuId: String, passkey: String) {
        // sesi iAP bisa dibuka ulang oleh dash; jangan putus BLE yang sudah jalan untuk CCU yang sama
        if wantRun, ccuId == self.ccuId, peripheral != nil {
            onLog(tr("BLE: already running, repeated request ignored"))
            return
        }
        self.ccuId = ccuId
        self.passkey = passkey
        wantRun = true
        authed = false
        prepare()
        setState(tr("Searching for CCU (BLE)…"))
        if central?.state == .poweredOn { beginScan() }
    }

    func stop() {
        wantRun = false
        scanTimeout?.invalidate()
        watchdog?.invalidate()
        outTimer?.invalidate()
        if scanning { central?.stopScan(); scanning = false }
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        chars.removeAll()
        outQueue.removeAll()
        outState = .idle
        authed = false
        servers.removeAll()
        requested.removeAll()
        fallbackDone = false
        DispatchQueue.main.async { self.live.reset(); self.live.state = tr("Stopped") }
    }

    private func setState(_ s: String) {
        onLog(s)
        DispatchQueue.main.async { self.live.state = s }
    }

    private func hex(_ b: [UInt8], _ n: Int = 40) -> String {
        b.prefix(n).map { String(format: "%02x", $0) }.joined(separator: " ") + (b.count > n ? " …" : "")
    }

    // MARK: - Scan & connect

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        onLog("Bluetooth state=\(c.state.rawValue)")
        if c.state == .poweredOn, wantRun { beginScan() }
    }

    private func beginScan() {
        guard let c = central, c.state == .poweredOn, peripheral == nil else { return }
        // coba perangkat yang sudah tersambung dulu
        for p in c.retrieveConnectedPeripherals(withServices: [CcuLink.service]) {
            onLog(tr("BLE: connected device found: {0}", p.name ?? "?"))
            connect(p)
            return
        }
        scanning = true
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onLog(tr("BLE: scanning for YCCU_{0}", ccuId))
        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self = self, self.scanning else { return }
            self.central?.stopScan()
            self.scanning = false
            self.setState(tr("CCU not found over BLE, retrying…"))
            self.retryLater()
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name.hasPrefix("YCCU_") || name.hasPrefix("YSCCU_") else { return }
        onLog("BLE: ditemukan \(name) rssi=\(rssi)")
        if !ccuId.isEmpty && !name.contains(ccuId) { return }
        c.stopScan()
        scanning = false
        scanTimeout?.invalidate()
        connect(p)
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        setState(tr("BLE: connecting…"))
        central?.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        // dicatat untuk WakeMonitor: sambungan BLE tertunda ke CCU ini yang membangunkan app saat motor dinyalakan
        UserDefaults.standard.set(p.identifier.uuidString, forKey: WakeMonitor.peripheralKey)
        onLog(tr("BLE: connected, looking for service"))
        p.discoverServices([CcuLink.service])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        onLog(tr("BLE: failed to connect: {0}", error?.localizedDescription ?? "?"))
        peripheral = nil
        retryLater()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        onLog(tr("BLE: disconnected {0}", error?.localizedDescription ?? ""))
        peripheral = nil
        chars.removeAll()
        authed = false
        outQueue.removeAll()
        outState = .idle
        watchdog?.invalidate()
        DispatchQueue.main.async { self.live.reset(); self.live.state = tr("Disconnected") }
        retryLater()
    }

    private func retryLater() {
        guard wantRun else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.wantRun, self.peripheral == nil else { return }
            self.beginScan()
        }
    }

    // MARK: - Service / karakteristik

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == CcuLink.service }) else {
            onLog(tr("BLE: CCU service missing ({0})", error?.localizedDescription ?? "-"))
            return
        }
        p.discoverCharacteristics(nil, for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] { chars[c.uuid] = c }
        onLog(tr("BLE: {0} characteristics", chars.count))
        subscribeQueue = [U.ctrlNotify, U.ddtStatus, U.ddtInHeader, U.ddtInData, U.ddtV2, U.ddtV3In, U.unknownInd]
        nextSubscribe()
    }

    private func nextSubscribe() {
        guard let p = peripheral else { return }
        while let u = subscribeQueue.first {
            subscribeQueue.removeFirst()
            if let c = chars[u] {
                p.setNotifyValue(true, for: c)
                return
            }
        }
        // semua langganan aktif
        setState(tr("BLE ready, authenticating…"))
        authenticate()
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let e = error { onLog(tr("BLE: notify {0} failed: {1}", c.uuid.uuidString.prefix(4), e.localizedDescription)) }
        nextSubscribe()
    }

    // MARK: - Tulis

    private func nextReq() -> UInt8 {
        reqCounter = reqCounter >= 255 ? 1 : reqCounter + 1
        return reqCounter
    }

    private func write(_ u: CBUUID, _ bytes: [UInt8]) {
        guard let p = peripheral, let c = chars[u] else { return }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        p.writeValue(Data(bytes), for: c, type: type)
    }

    private func ctrl(_ cmd: Int, _ body: [UInt8]) {
        write(U.ctrlWrite, [UInt8(cmd >> 8), UInt8(cmd & 0xFF)] + body)
    }

    private func u24(_ v: Int) -> [UInt8] { [UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    // MARK: - Autentikasi & startup

    private func authenticate() {
        // ConnectAppId lalu AuthenticationV2 (DDT 257)
        ctrl(2, [nextReq(), 0x00, 0x00, 0x12, 0x34])
        var body: [UInt8] = [0x01, 0x01]
        body += Array(ccuId.utf8.prefix(14))
        body += Array(passkey.utf8.prefix(6))
        sendDDT(body)
    }

    private func startupChain() {
        authed = true
        lastStatus = nil
        lastCall = nil
        sendLanguage(tr("after authentication"))
        requested.removeAll()
        fallbackDone = false
        setState(tr("Authenticated, requesting data server list"))
        ctrl(0x0103, [nextReq()])               // 259
        ctrl(0x0137, [nextReq()])               // 311: status kunci kontak
    }

    private func subscribe(server: Int, available: [Int]) {
        let wanted = server == 1248 ? [1, 72] : [1]
        var ids = wanted.filter { available.contains($0) }
        if ids.isEmpty { ids = wanted }
        if server == 1248 {
            for e in extraIds where !ids.contains(e) { ids.append(e) }
        }
        var pb = [UInt8]()
        pb += PB.varintField(3, server)
        pb += PB.bytesField(4, ids.flatMap { PB.varint($0) })
        pb += PB.varintField(5, 0)
        pb += PB.varintField(6, 100)
        sendDDT([0x01, 0x10] + u24(pb.count) + pb)  // 272
        onLog(tr("CCU: subscribing to server {0} id {1}", server, ids))
    }

    // MARK: - DDT keluar

    private func sendDDT(_ body: [UInt8]) {
        outQueue.append(body)
        pumpOut()
    }

    private func pumpOut() {
        guard outState == .idle, !outQueue.isEmpty, let p = peripheral, let st = chars[U.ddtStatus] else { return }
        outBody = outQueue.removeFirst()
        outReq = nextReq()
        outOffset = 0
        outState = .awaitIdle
        armOutTimer()
        p.readValue(for: st)
    }

    private func armOutTimer() {
        outTimer?.invalidate()
        outTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self = self, self.outState != .idle else { return }
            self.onLog(tr("DDT exit: timeout (state {0})", self.outState))
            self.outState = .idle
            self.pumpOut()
        }
    }

    private func ddtStatus(_ b: [UInt8]) {
        switch outState {
        case .awaitIdle:
            guard b.first == 0 else { onLog(tr("DDT: initial status {0}", hex(b))); return }
            outState = .awaitHeader
            armOutTimer()
            write(U.ddtOutHeader, [outReq] + u24(outBody.count))
        case .awaitHeader, .awaitStatus:
            if b.count >= 2, b[0] == 1, b[1] == outReq {
                sendChunk()
            } else if b == [0, 0], outOffset >= outBody.count {
                finishOut(ok: true)
            } else {
                onLog(tr("DDT: unexpected status {0}", hex(b)))
            }
        case .writing:
            if b == [0, 0], outOffset >= outBody.count { finishOut(ok: true) }
        case .idle:
            break
        }
    }

    private func sendChunk() {
        guard let p = peripheral else { return }
        let mtu = min(p.maximumWriteValueLength(for: .withResponse), 180)
        let size = max(1, mtu - 4)
        let end = min(outBody.count, outOffset + size)
        let chunk = Array(outBody[outOffset..<end])
        let head = [outReq] + u24(outOffset)
        outOffset = end
        outState = .writing
        armOutTimer()
        write(U.ddtOutData, head + chunk)
    }

    private func finishOut(ok: Bool) {
        outTimer?.invalidate()
        outState = .idle
        if !ok { onLog(tr("DDT exit failed")) }
        pumpOut()
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let e = error {
            onLog(tr("BLE: write {0} failed: {1}", c.uuid.uuidString.prefix(4), e.localizedDescription))
            if c.uuid == U.ddtOutHeader || c.uuid == U.ddtOutData { finishOut(ok: false) }
            return
        }
        if c.uuid == U.ddtOutData {
            if outOffset < outBody.count, let st = chars[U.ddtStatus] {
                outState = .awaitStatus
                armOutTimer()
                p.readValue(for: st)
            } else {
                outState = .writing   // tunggu notify [00 00]
                armOutTimer()
            }
        }
    }

    // MARK: - Terima

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, let d = c.value else { return }
        let b = [UInt8](d)
        switch c.uuid {
        case U.ddtStatus: ddtStatus(b)
        case U.ctrlNotify:
            guard b.count >= 2 else { return }
            handle(cmd: Int(b[0]) << 8 | Int(b[1]), body: Array(b[2...]))
        case U.ddtV2, U.ddtV3In: receiveV2(b)
        case U.ddtInHeader:
            guard b.count >= 4 else { return }
            inId = b[0]
            inLen = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            inBuf = [UInt8](repeating: 0, count: inLen)
            write(U.ddtInAck, [0x01, inId])
        case U.ddtInData:
            guard b.count >= 4 else { return }
            let off = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            let data = Array(b[4...])
            if off + data.count <= inBuf.count { inBuf.replaceSubrange(off..<(off + data.count), with: data) }
            write(U.ddtInData, [b[0]])
            if off + data.count >= inLen, inLen >= 2 {
                write(U.ddtInAck, [0x00, 0x00])
                let m = inBuf
                handle(cmd: Int(m[0]) << 8 | Int(m[1]), body: Array(m[2...]))
            }
        default:
            onLog("BLE rx \(c.uuid.uuidString.prefix(4)): \(hex(b))")
        }
    }

    private func receiveV2(_ b: [UInt8]) {
        guard b.count >= 4 else { return }
        let seq = UInt16(b[0]) << 8 | UInt16(b[1])
        let part = Int(b[2]), total = Int(b[3])
        var e = v2Parts[seq] ?? (total: total, parts: [:], t: Date())
        e.parts[part] = Array(b[4...])
        v2Parts[seq] = e
        if e.parts.count >= total {
            var m = [UInt8]()
            for i in 1...max(1, total) { m += e.parts[i] ?? [] }
            v2Parts[seq] = nil
            if m.count >= 2 { handle(cmd: Int(m[0]) << 8 | Int(m[1]), body: Array(m[2...])) }
        }
        for (k, v) in v2Parts where Date().timeIntervalSince(v.t) > 3 { v2Parts[k] = nil }
    }

    // MARK: - Pesan

    private func handle(cmd: Int, body: [UInt8]) {
        switch cmd {
        case 258:
            if body.last == 1 {
                onLog(tr("CCU: authentication OK"))
                startupChain()
            } else {
                setState(tr("CCU rejected authentication"))
                onLog("CCU: 258 body=\(hex(body))")
            }
        case 309:
            ctrl(0x0136, body)                  // echo keep-alive
        case 260:
            let list = PB.parse(body, expect: 3).flatMap { PB.ints($0, 3) } ?? []
            onLog("CCU: 260 server=\(list)")
            servers = Array(Set(list)).sorted()
            for s in servers where !requested.contains(s) {
                requested.insert(s)
                ctrl(0x0126, [nextReq(), UInt8(s >> 8), UInt8(s & 0xFF)])   // 294
            }
        case 295:
            if let f = PB.parse(body, expect: 3) {
                let server = PB.ints(f, 3).first ?? 0
                let ids = PB.ints(f, 4)
                onLog("CCU: 295 server=\(server) idList=\(ids.count)")
                subscribe(server: server, available: ids)
            } else { onLog(tr("CCU: 295 unreadable: {0}", hex(body))) }
        case 271:
            parseData(body)
        case 312:
            if let s = body.last {
                DispatchQueue.main.async { self.live.ignitionOn = s == 1 }
                onLog(tr("CCU: ignition {0}", s == 1 ? "ON" : "OFF"))
            }
        case 9:
            // CCU minta waktu: [reqId][epoch lokal u64]
            let t = UInt64(Date().timeIntervalSince1970) + UInt64(max(0, TimeZone.current.secondsFromGMT()))
            var e = [UInt8]()
            for i in (0..<8).reversed() { e.append(UInt8((t >> UInt64(i * 8)) & 0xFF)) }
            ctrl(0x000A, [nextReq()] + e)
        case 11:
            sendLanguage(tr("requested by CCU"))
        case 297:
            ctrl(0x012A, [0x01])
        case 0xFF01:
            onLog(tr("CCU: error {0}", hex(body)))
            // error "01 26 xx" = permintaan info server (cmd 294) ditolak CCU: langsung langganan data
            if body.count >= 2, Int(body[0]) << 8 | Int(body[1]) == 0x0126 { fallbackSubscribe() }
        default:
            onLog("CCU: cmd \(cmd) \(hex(body, 24))")
        }
    }

    /// Dipakai bila CCU menolak cmd 294: langganan langsung ke server yang diumumkan (id data 1 dan 72).
    private func fallbackSubscribe() {
        guard authed, !fallbackDone, !servers.isEmpty else { return }
        fallbackDone = true
        onLog(tr("CCU: cmd 294 rejected, subscribing directly to server {0}", servers))
        for s in servers { subscribe(server: s, available: []) }
    }

    private func parseData(_ body: [UInt8]) {
        guard let f = PB.parse(body, expect: 4) else { onLog(tr("CCU: 271 unreadable {0}", hex(body))); return }
        let server = PB.ints(f, 3).first ?? 0
        lastData = Date()
        var odo: Double?, volt: Double?, cool: Int?, air: Int?, rpm: Int?, spd: Int?, dtc: Int?
        var raw1: [UInt8]?
        var others: [Int: [UInt8]] = [:]
        for entry in f where entry.field == 4 && entry.wire == 2 {
            guard let e = PB.parseAll(entry.bytes) else { continue }
            let id = PB.ints(e, 1).first ?? -1
            let raw = e.first(where: { $0.field == 2 })?.bytes ?? []
            if id != 1, id != -1, !raw.isEmpty { others[id] = raw }
            if id == 1, raw.count >= 24 {
                raw1 = Array(raw.prefix(48))
                rpm = Int(raw[0]) << 8 | Int(raw[1])
                spd = Int(raw[2])
                volt = Double(raw[6]) * 18.75 / 256.0
                cool = Int(raw[14]) - 30
                air = Int(raw[15]) - 30
                dtc = Int(raw[23])
            } else if id == 72, !raw.isEmpty {
                var v: UInt64 = 0
                for x in raw.prefix(8) { v = v << 8 | UInt64(x) }
                odo = Double(v) / 10.0
            }
        }
        // catat paket mentah saat berubah (maks 1x per 2 detik) supaya byte yang belum diketahui bisa dipelajari dari log
        if let r = raw1 {
            let h = hex(r, 48)
            if h != lastRawHex, Date().timeIntervalSince(lastRawLog) > 2 {
                lastRawHex = h
                lastRawLog = Date()
                onLog("CCU: data id 1 = \(h)")
            }
        }
        for (id, r) in others where !seenIds.contains(id) {
            seenIds.insert(id)
            onLog(tr("CCU: data id {0} received for the first time ({1} B): {2}", id, r.count, hex(r, 32)))
        }
        DispatchQueue.main.async {
            if let r = raw1 { self.live.rawRecord = r }
            for (id, r) in others { self.live.rawById[id] = r }
            self.live.connected = true
            self.live.state = tr("CCU data received")
            self.live.lastUpdate = Date()
            if let v = volt { self.live.batteryV = v }
            if let v = odo { self.live.odoKm = v }
            if let v = cool { self.live.coolantC = v }
            if let v = air { self.live.airC = v }
            if let v = rpm { self.live.rpm = v }
            if let v = spd { self.live.speedKmh = v }
            if let v = dtc { self.live.dtcCount = v }
            if self.live.ignitionOn == nil { self.live.ignitionOn = true }
        }
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self = self, self.authed else { return }
                if Date().timeIntervalSince(self.lastData) > 5 && !self.servers.isEmpty {
                    self.lastData = Date()
                    self.onLog(tr("CCU: data stopped, resubscribing"))
                    for s in self.servers { self.ctrl(0x0126, [self.nextReq(), UInt8(s >> 8), UInt8(s & 0xFF)]) }
                }
            }
        }
        _ = server
    }
}

/// Pembaca protobuf minimal.
enum PB {
    struct Field { var field: Int; var wire: Int; var value: UInt64; var bytes: [UInt8] }

    static func varint(_ v: Int) -> [UInt8] {
        var x = UInt64(max(0, v)); var out = [UInt8]()
        repeat {
            var b = UInt8(x & 0x7F); x >>= 7
            if x != 0 { b |= 0x80 }
            out.append(b)
        } while x != 0
        return out
    }
    static func varintField(_ f: Int, _ v: Int) -> [UInt8] { varint(f << 3) + varint(v) }
    static func bytesField(_ f: Int, _ b: [UInt8]) -> [UInt8] { varint(f << 3 | 2) + varint(b.count) + b }

    /// Parse seluruh buffer; nil bila rusak.
    static func parseAll(_ d: [UInt8]) -> [Field]? {
        var i = 0; var out = [Field]()
        func rv() -> UInt64? {
            var v: UInt64 = 0; var shift: UInt64 = 0
            while i < d.count, shift < 64 {
                let b = d[i]; i += 1
                v |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return v }
                shift += 7
            }
            return nil
        }
        while i < d.count {
            guard let key = rv() else { return nil }
            let f = Int(key >> 3), w = Int(key & 7)
            if f == 0 { return nil }
            switch w {
            case 0: guard let v = rv() else { return nil }; out.append(Field(field: f, wire: 0, value: v, bytes: []))
            case 2:
                guard let l = rv(), i + Int(l) <= d.count else { return nil }
                out.append(Field(field: f, wire: 2, value: 0, bytes: Array(d[i..<(i + Int(l))]))); i += Int(l)
            case 1: guard i + 8 <= d.count else { return nil }; i += 8
            case 5: guard i + 4 <= d.count else { return nil }; i += 4
            default: return nil
            }
        }
        return out
    }

    /// Badan pesan bisa diawali panjang/reqId; coba beberapa offset sampai terbaca dan memuat field `expect`.
    static func parse(_ body: [UInt8], expect: Int) -> [Field]? {
        for off in [3, 0, 1, 2, 4, 5] where off <= body.count {
            if let f = parseAll(Array(body[off...])), f.contains(where: { $0.field == expect }) { return f }
        }
        return nil
    }

    /// Nilai integer field (varint berulang atau packed).
    static func ints(_ fields: [Field], _ n: Int) -> [Int] {
        var out = [Int]()
        for f in fields where f.field == n {
            if f.wire == 0 { out.append(Int(f.value)) }
            else if f.wire == 2 {
                var i = 0
                while i < f.bytes.count {
                    var v = 0; var shift = 0
                    while i < f.bytes.count {
                        let b = f.bytes[i]; i += 1
                        v |= Int(b & 0x7F) << shift
                        if b & 0x80 == 0 { break }
                        shift += 7
                    }
                    out.append(v)
                }
            }
        }
        return out
    }
}
