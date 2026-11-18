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
    private var outQueue = [UInt8]()

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

    func send(_ data: Data) {
        guard session != nil else { return }
        outQueue.append(contentsOf: data)
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
        if notify { onClosed?() }
    }

    private func pump() {
        guard let os = session?.outputStream, !outQueue.isEmpty else { return }
        while os.hasSpaceAvailable && !outQueue.isEmpty {
            let n = outQueue.withUnsafeBufferPointer { os.write($0.baseAddress!, maxLength: $0.count) }
            if n <= 0 { break }
            outQueue.removeFirst(n)
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
            onLog?("Stream error: \(aStream.streamError?.localizedDescription ?? "?")")
            close()
        case .endEncountered:
            onLog?("Stream ditutup oleh dash")
            close()
        default: break
        }
    }
}
