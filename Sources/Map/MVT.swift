import Foundation
import CoreGraphics

struct PBReader {
    let d: [UInt8]
    var p: Int
    let end: Int

    init(_ d: [UInt8], from: Int = 0, to: Int? = nil) {
        self.d = d
        self.p = from
        self.end = to ?? d.count
    }

    var atEnd: Bool { p >= end }

    mutating func varint() -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while p < end {
            let b = d[p]
            p += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { break }
        }
        return result
    }

    mutating func tag() -> (field: Int, wire: Int) {
        let v = varint()
        return (Int(truncatingIfNeeded: v >> 3), Int(truncatingIfNeeded: v & 7))
    }

    mutating func range() -> (Int, Int) {
        let n = Int(truncatingIfNeeded: varint())
        let s = p
        p = min(end, p + max(0, n))
        return (s, p)
    }

    mutating func skip(_ wire: Int) {
        switch wire {
        case 0: _ = varint()
        case 1: p = min(end, p + 8)
        case 2: _ = range()
        case 5: p = min(end, p + 4)
        default: p = end
        }
    }
}

struct MVTFeature {
    var type: Int                // 1 titik, 2 garis, 3 poligon
    var parts: [[CGPoint]]       // koordinat tile 0...4096
    var tags: [String: String]
}

struct MVTLayer {
    var name: String
    var features: [MVTFeature]
}

/// Dekoder Mapbox Vector Tile (protobuf) secukupnya untuk skema OpenMapTiles.
enum MVT {
    static let wantedLayers: Set<String> = ["water", "waterway", "landcover", "landuse", "park", "building",
                                            "transportation", "transportation_name", "place", "poi"]
    static let wantedKeys: Set<String> = ["class", "subclass", "name", "name:latin", "brunnel"]

    static func decode(_ data: [UInt8]) -> [MVTLayer] {
        var out = [MVTLayer]()
        var r = PBReader(data)
        while !r.atEnd {
            let t = r.tag()
            if t.field == 3 && t.wire == 2 {
                let (s, e) = r.range()
                if let l = decodeLayer(data, s, e) { out.append(l) }
            } else {
                r.skip(t.wire)
            }
        }
        return out
    }

    private static func str(_ d: [UInt8], _ a: Int, _ b: Int) -> String {
        String(decoding: d[a..<b], as: UTF8.self)
    }

    private static func decodeLayer(_ d: [UInt8], _ s: Int, _ e: Int) -> MVTLayer? {
        var r = PBReader(d, from: s, to: e)
        var name = ""
        while !r.atEnd {
            let t = r.tag()
            if t.field == 1 && t.wire == 2 {
                let (a, b) = r.range()
                name = str(d, a, b)
                break
            } else {
                r.skip(t.wire)
            }
        }
        guard wantedLayers.contains(name) else { return nil }

        var keys = [String]()
        var values = [String]()
        var featureRanges = [(Int, Int)]()
        var extent = 4096
        r = PBReader(d, from: s, to: e)
        while !r.atEnd {
            let t = r.tag()
            switch (t.field, t.wire) {
            case (2, 2):
                featureRanges.append(r.range())
            case (3, 2):
                let (a, b) = r.range()
                keys.append(str(d, a, b))
            case (4, 2):
                let (a, b) = r.range()
                values.append(decodeValue(d, a, b))
            case (5, 0):
                extent = Int(truncatingIfNeeded: r.varint())
            default:
                r.skip(t.wire)
            }
        }

        let scale = CGFloat(4096) / CGFloat(max(1, extent))
        var feats = [MVTFeature]()
        for (a, b) in featureRanges {
            var fr = PBReader(d, from: a, to: b)
            var type = 0
            var tagPairs = [Int]()
            var geom: (Int, Int)?
            while !fr.atEnd {
                let t = fr.tag()
                switch (t.field, t.wire) {
                case (2, 2):
                    let (x, y) = fr.range()
                    var pr = PBReader(d, from: x, to: y)
                    while !pr.atEnd { tagPairs.append(Int(truncatingIfNeeded: pr.varint())) }
                case (3, 0):
                    type = Int(truncatingIfNeeded: fr.varint())
                case (4, 2):
                    geom = fr.range()
                default:
                    fr.skip(t.wire)
                }
            }
            guard type >= 1, let g = geom else { continue }
            var tags = [String: String]()
            var i = 0
            while i + 1 < tagPairs.count {
                let k = tagPairs[i]
                let v = tagPairs[i + 1]
                if k < keys.count, v < values.count, wantedKeys.contains(keys[k]) {
                    tags[keys[k]] = values[v]
                }
                i += 2
            }
            let parts = decodeGeometry(d, g.0, g.1, type: type, scale: scale)
            if parts.isEmpty { continue }
            feats.append(MVTFeature(type: type, parts: parts, tags: tags))
        }
        return MVTLayer(name: name, features: feats)
    }

    private static func decodeValue(_ d: [UInt8], _ s: Int, _ e: Int) -> String {
        var r = PBReader(d, from: s, to: e)
        while !r.atEnd {
            let t = r.tag()
            switch (t.field, t.wire) {
            case (1, 2):
                let (a, b) = r.range()
                return str(d, a, b)
            case (4, 0), (5, 0):
                return String(r.varint())
            case (6, 0):
                return String(unzig(r.varint()))
            case (7, 0):
                return r.varint() != 0 ? "true" : "false"
            default:
                r.skip(t.wire)
            }
        }
        return ""
    }

    private static func unzig(_ v: UInt64) -> Int {
        Int(Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1))
    }

    private static func decodeGeometry(_ d: [UInt8], _ s: Int, _ e: Int, type: Int, scale: CGFloat) -> [[CGPoint]] {
        var r = PBReader(d, from: s, to: e)
        var parts = [[CGPoint]]()
        var cur = [CGPoint]()
        var x = 0
        var y = 0
        while !r.atEnd {
            let cmdInt = Int(truncatingIfNeeded: r.varint())
            let cmd = cmdInt & 7
            let count = min(cmdInt >> 3, 1_000_000)
            switch cmd {
            case 1, 2:
                var n = 0
                while n < count && !r.atEnd {
                    let dx = unzig(r.varint())
                    let dy = unzig(r.varint())
                    x += dx
                    y += dy
                    if cmd == 1 && !cur.isEmpty {
                        parts.append(cur)
                        cur = []
                    }
                    cur.append(CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale))
                    n += 1
                }
            case 7:
                if type == 3, let f = cur.first { cur.append(f) }
            default:
                return parts
            }
        }
        if !cur.isEmpty { parts.append(cur) }
        return parts
    }
}
