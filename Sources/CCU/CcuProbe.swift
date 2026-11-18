import Foundation
import ExternalAccessory

/// EKSPERIMEN: membuka sesi iAP `com.yconnect.data` dan mencatat semua byte yang masuk,
/// supaya format link CCU di iPhone bisa dipelajari dari log (docs/bike-protocol.md bagian 6).
final class CcuProbe {
    static let protocolName = "com.yconnect.data"

    var onLog: (String) -> Void = { _ in }
    /// dipanggil saat CCU memberi ID dan passkey (cmd 314)
    var onInfo: (String, String) -> Void = { _, _ in }

    private let link = AccessoryLink(protocolName: CcuProbe.protocolName)
    private var rx = [UInt8]()

    func start(accessory: EAAccessory) {
        rx.removeAll()
        link.onData = { [weak self] d in self?.receive(d) }
        link.onLog = { [weak self] s in self?.onLog(s) }
        link.onClosed = { [weak self] in self?.onLog("sesi ditutup") }
        if link.isOpen { link.close(notify: false) }
        guard link.open(accessory) else {
            onLog("gagal membuka sesi \(CcuProbe.protocolName)")
            return
        }
        onLog("sesi dibuka, mengirim cmd 313 (minta ID CCU)")
        // bingkai SPP: 01 | panjang u32 BE | [cmd u16 BE] | 04
        link.send(Data([0x01, 0x00, 0x00, 0x00, 0x02, 0x01, 0x39, 0x04]))
    }

    func stop() { link.close() }

    private func hex(_ b: [UInt8]) -> String {
        b.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func receive(_ d: Data) {
        let bytes = [UInt8](d)
        onLog("rx \(bytes.count) B: " + hex(Array(bytes.prefix(64))))
        rx += bytes
        if rx.count > 8192 { rx.removeAll() }

        while rx.count >= 6 {
            if rx[0] != 0x01 { rx.removeFirst(); continue }
            let len = (Int(rx[1]) << 24) | (Int(rx[2]) << 16) | (Int(rx[3]) << 8) | Int(rx[4])
            if len < 2 || len > 4096 { rx.removeFirst(); continue }
            if rx.count < 6 + len { break }
            let payload = Array(rx[5..<(5 + len)])
            let end = rx[5 + len]
            rx.removeFirst(6 + len)
            if end != 0x04 {
                onLog("bingkai tanpa 0x04 di akhir")
                continue
            }
            handle(payload)
        }
    }

    private func handle(_ payload: [UInt8]) {
        let cmd = (Int(payload[0]) << 8) | Int(payload[1])
        if cmd == 314 && payload.count >= 22 {
            let id = String(bytes: payload[2..<16], encoding: .ascii) ?? "?"
            let pass = String(bytes: payload[16..<22], encoding: .ascii) ?? ""
            onLog("cmd 314: ID CCU = \(id), passkey diterima (6 karakter, disembunyikan)")
            onInfo(id, pass)
        } else {
            onLog("cmd \(cmd), \(payload.count) B")
        }
    }
}
