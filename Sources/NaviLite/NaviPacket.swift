import Foundation

// Format paket NaviLite (Garmin) sesuai docs/bike-protocol.md bagian 2. Semua multi-byte little-endian.

enum NaviService {
    static let imageFrame: UInt8 = 0
    static let eta: UInt8 = 1
    static let navStatus: UInt8 = 2
    static let roadName: UInt8 = 3
    static let nextTurn: UInt8 = 4
    static let favHeader: UInt8 = 7
    static let gasHeader: UInt8 = 8
    static let homeSetting: UInt8 = 10
    static let officeSetting: UInt8 = 11
    static let appSetting: UInt8 = 12
    static let gpsStatus: UInt8 = 13
    static let zoomLevel: UInt8 = 14
    static let imageStopped: UInt8 = 20
    static let dayNight: UInt8 = 31
    static let authRequest: UInt8 = 33
    static let startRoute: UInt8 = 48
    static let stopRoute: UInt8 = 49
    static let zoomIn: UInt8 = 51
    static let zoomOut: UInt8 = 52
    static let goHome: UInt8 = 53
    static let goOffice: UInt8 = 54
    static let startContent: UInt8 = 55
    static let stopContent: UInt8 = 56
    static let vehicleSpeed: UInt8 = 65
    static let esn: UInt8 = 66
    static let sysInfo: UInt8 = 69
    static let dialog: UInt8 = 70
    static let imageAck: UInt8 = 80
    static let esnAck: UInt8 = 81
    static let authAck: UInt8 = 82
    static let authSecData: UInt8 = 83
    static let authSecDataAck: UInt8 = 84
    static let favItem: UInt8 = 98
    static let gasItem: UInt8 = 99
}

enum Bytes {
    static func le16(_ v: Int16) -> [UInt8] {
        let u = UInt16(bitPattern: v)
        return [UInt8(u & 0xFF), UInt8(u >> 8)]
    }
    static func le32(_ v: UInt32) -> [UInt8] {
        return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    static func i16(_ b: [UInt8], _ o: Int) -> Int {
        let lo = UInt16(b[o])
        let hi = UInt16(b[o + 1]) << 8
        return Int(Int16(bitPattern: lo | hi))
    }
}

enum NaviCRC {
    // CRC-32/MPEG-2: poly 0x04C11DB7, init 0xFFFFFFFF, tanpa refleksi, tanpa XOR akhir.
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i) << 24
        for _ in 0..<8 {
            c = (c & 0x8000_0000) != 0 ? (c << 1) ^ 0x04C1_1DB7 : (c << 1)
        }
        return c
    }

    static func crc32(_ parts: [[UInt8]]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for part in parts {
            for b in part {
                crc = (crc << 8) ^ table[Int(((crc >> 24) ^ UInt32(b)) & 0xFF)]
            }
        }
        return crc
    }
}

extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func appendLE(_ v: UInt32) {
        for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xFF)) }
    }
}

struct NaviPacket {
    var frameType: UInt8 = 6          // 6 = phone -> TFT
    var service: UInt8
    var isPointer: Bool
    var payload: [UInt8]

    /// VALUE: tepat 2 byte int16 LE.
    static func value(_ service: UInt8, _ v: Int16) -> NaviPacket {
        let u = UInt16(bitPattern: v)
        return NaviPacket(service: service, isPointer: false, payload: [UInt8(u & 0xFF), UInt8(u >> 8)])
    }

    static func pointer(_ service: UInt8, _ payload: [UInt8]) -> NaviPacket {
        NaviPacket(service: service, isPointer: true, payload: payload)
    }

    var intValue: Int16? {
        guard payload.count >= 2 else { return nil }
        return Int16(bitPattern: UInt16(payload[0]) | (UInt16(payload[1]) << 8))
    }

    func encode() -> Data {
        var header: [UInt8] = [0x6E, 0x41, 0x6C, 0x40, 0x01, frameType, service]
        let n = UInt32(payload.count)
        header += [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)]
        header.append(isPointer ? 1 : 0)
        let crc = NaviCRC.crc32([header, payload])
        var out = Data(header)
        out.appendLE(crc)
        out.append(contentsOf: payload)
        return out
    }
}

struct NaviPacketParser {
    private var buf = [UInt8]()
    private static let magic: [UInt8] = [0x6E, 0x41, 0x6C, 0x40]
    /// jumlah byte dari dash yang dibuang karena bukan paket NaviLite yang sah (untuk diagnosis di Log)
    private(set) var droppedBytes = 0
    private var dropSample = [UInt8]()

    mutating func reset() { buf.removeAll() }

    /// Contoh byte yang dibuang (maks 32) sejak pemanggilan terakhir.
    mutating func takeDropSample() -> [UInt8] {
        let s = dropSample
        dropSample.removeAll()
        return s
    }

    private mutating func noteDrop(_ bytes: ArraySlice<UInt8>) {
        droppedBytes += bytes.count
        if dropSample.count < 32 { dropSample += bytes.prefix(32 - dropSample.count) }
    }

    mutating func feed(_ data: Data) -> [NaviPacket] {
        buf.append(contentsOf: data)
        var out = [NaviPacket]()
        while true {
            guard let i = indexOfMagic() else {
                if buf.count > 3 {
                    noteDrop(buf[0..<(buf.count - 3)])
                    buf.removeFirst(buf.count - 3)
                }
                break
            }
            if i > 0 {
                noteDrop(buf[0..<i])
                buf.removeFirst(i)
            }
            if buf.count < 16 { break }
            let size = Int(le32(at: 7))
            if size > 2_000_000 { buf.removeFirst(1); continue }
            if buf.count < 16 + size { break }
            let header = Array(buf[0..<12])
            let rxCRC = le32(at: 12)
            let payload = Array(buf[16..<(16 + size)])
            if NaviCRC.crc32([header, payload]) == rxCRC {
                out.append(NaviPacket(frameType: header[5], service: header[6],
                                      isPointer: header[11] == 1, payload: payload))
                buf.removeFirst(16 + size)
            } else {
                noteDrop(buf[0..<1])
                buf.removeFirst(1)   // CRC salah: buang dan sinkron ulang
            }
        }
        return out
    }

    private func indexOfMagic() -> Int? {
        guard buf.count >= 4 else { return nil }
        for i in 0...(buf.count - 4) where Array(buf[i..<(i + 4)]) == Self.magic { return i }
        return nil
    }

    private func le32(at o: Int) -> UInt32 {
        UInt32(buf[o]) | (UInt32(buf[o + 1]) << 8) | (UInt32(buf[o + 2]) << 16) | (UInt32(buf[o + 3]) << 24)
    }
}
