import Foundation

/// Mencocokkan encoder/parser dengan test vector di docs/bike-protocol.md bagian 2.3.
enum SelfTest {
    private static func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }

    static func run() -> [String] {
        var out = [String]()
        let ok = NaviCRC.crc32([Array("123456789".utf8)]) == 0x0376_E6E7
        out.append("CRC check value: \(ok ? "OK" : "GAGAL")")

        let enc: [(String, NaviPacket, String)] = [
            ("ESN_ACK", .value(81, 1), "6e 41 6c 40 01 06 51 02 00 00 00 00 1a 4d 1c ec 01 00"),
            ("NAV_STATUS", .value(2, 0), "6e 41 6c 40 01 06 02 02 00 00 00 00 11 ea df c1 00 00"),
            ("DAY_NIGHT", .value(31, 1), "6e 41 6c 40 01 06 1f 02 00 00 00 00 6d e3 75 5b 01 00"),
            ("AUTH_REQUEST", .pointer(33, [0x4E, 0x07, 0x00, 0x01, 0, 0, 0, 0]),
             "6e 41 6c 40 01 06 21 08 00 00 00 01 6f 6d 5a e2 4e 07 00 01 00 00 00 00")
        ]
        for (name, pkt, hex) in enc {
            out.append("Encode \(name): \([UInt8](pkt.encode()) == bytes(hex) ? "OK" : "GAGAL")")
        }

        var parser = NaviPacketParser()
        let rx = parser.feed(Data(bytes("6e 41 6c 40 01 03 50 02 00 00 00 00 5e 95 d8 c5 05 00")))
        let parsedOK = rx.count == 1 && rx[0].service == 80 && rx[0].intValue == 5
        out.append("Parse IMAGE_ACK: \(parsedOK ? "OK" : "GAGAL")")
        return out
    }
}
