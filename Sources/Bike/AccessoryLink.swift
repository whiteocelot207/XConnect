import Foundation
import ExternalAccessory

/// Sesi ExternalAccessory (iAP) ke dash. Jalan di run loop utama.
final class AccessoryLink: NSObject, StreamDelegate {
    static let naviProtocol = "com.garmin.navilite.data"

    var onData: ((Data) -> Void)?
    var onClosed: (() -> Void)?
    var onLog: ((String) -> Void)?

    private let protocolName: String
    private var session: EASession?
    /// antrean paket keluar; `headOffset` = berapa byte paket paling depan yang sudah tertulis (paket tidak boleh dipotong)
    private var outQueue = [Data]()
    private var headOffset = 0

    init(protocolName: String = AccessoryLink.naviProtocol) {
        self.protocolName = protocolName
        super.init()
    }

    var isOpen: Bool { session != nil }

    func open(_ accessory: EAAccessory) -> Bool {
        close(notify: false)
        guard let s = EASession(accessory: accessory, forProtocol: protocolName) else { return false }
        session = s
        for stream in [s.inputStream, s.outputStream] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .common)
            stream?.open()
        }
        return true
    }

    /// `priority`: paket kecil yang harus cepat sampai (balasan tombol stang). Disisipkan di depan antrean, tepat
    /// setelah paket yang sedang setengah terkirim, jadi tidak menunggu frame peta berikutnya yang sudah antre.
    func send(_ data: Data, priority: Bool = false) {
        guard session != nil, !data.isEmpty else { return }
        if priority {
            let idx = (headOffset > 0 && !outQueue.isEmpty) ? 1 : 0
            outQueue.insert(data, at: idx)
        } else {
            outQueue.append(data)
        }
        pump()
    }

    func close(notify: Bool = true) {
        guard let s = session else { return }
        for stream in [s.inputStream, s.outputStream] {
            stream?.close()
            stream?.remove(from: .main, forMode: .common)
            stream?.delegate = nil
        }
        session = nil
        outQueue.removeAll()
        headOffset = 0
        if notify { onClosed?() }
    }

    private func pump() {
        guard let os = session?.outputStream else { return }
        while os.hasSpaceAvailable, let head = outQueue.first {
            let remaining = head.count - headOffset
            if remaining <= 0 { outQueue.removeFirst(); headOffset = 0; continue }
            let offset = headOffset
            let n = head.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return os.write(base + offset, maxLength: remaining)
            }
            if n <= 0 { break }
            headOffset += n
            if headOffset >= head.count {
                outQueue.removeFirst()
                headOffset = 0
            }
        }
    }

    private func readAvailable() {
        guard let input = session?.inputStream else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while input.hasBytesAvailable {
            let n = input.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            onData?(Data(buffer[0..<n]))
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable: readAvailable()
        case .hasSpaceAvailable: pump()
        case .errorOccurred:
            onLog?(tr("Stream error: {0}", aStream.streamError?.localizedDescription ?? "?"))
            close()
        case .endEncountered:
            onLog?(tr("Stream closed by the dash"))
            close()
        default: break
        }
    }
}
