import Foundation

/// Catatan versi dari CHANGELOG.md / CHANGELOG.id.md (ikut dibundel ke app). Format: tiap versi diawali `## x.y.z`.
/// Di app hanya bagian untuk versi yang terpasang yang ditampilkan.
enum Changelog {
    private static func load() -> String? {
        let lang = Loc.shared.currentCode
        if lang != "en", let u = Bundle.main.url(forResource: "CHANGELOG." + lang, withExtension: "md"),
           let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        if let u = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
           let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return nil
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
    }

    private static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Catatan untuk `version`; bila tidak ada bagian persis untuk versi itu, bagian versi terbaru yang tidak lebih baru darinya.
    static func notes(for version: String) -> (version: String, lines: [String])? {
        guard let text = load() else { return nil }
        var sections: [(String, [String])] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.hasPrefix("## ") {
                var v = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let sp = v.firstIndex(of: " ") { v = String(v[..<sp]) }
                if v.hasPrefix("v") { v.removeFirst() }
                sections.append((v, []))
            } else if !sections.isEmpty {
                sections[sections.count - 1].1.append(line)
            }
        }
        guard !sections.isEmpty else { return nil }
        let pick = sections.first { $0.0 == version }
            ?? sections.filter { !isNewer($0.0, than: version) }.max { isNewer($1.0, than: $0.0) }
            ?? sections[0]
        var lines = pick.1
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return (pick.0, lines)
    }
}
