import Foundation

/// Kamus terjemahan dari `Resources/Translations.tsv`.
///
/// Format TSV: baris pertama = header `key<TAB>en<TAB>id<TAB>...` (kode bahasa per kolom). Tiap baris berikutnya
/// = satu teks: kolom 1 adalah kunci (teks Inggris, dipakai di kode lewat `tr("...")`), kolom berikutnya adalah
/// terjemahan per bahasa. Penampung `{0}`, `{1}`, ... diganti dengan argumen `tr`. Di dalam sel, `\n` = baris baru,
/// `\t` = tab, `\\` = garis miring terbalik. Baris yang berawalan `#` diabaikan. Baris berawalan `@` adalah
/// data bahasa, bukan teks (lihat `meta`): `@name`, `@locale`, `@voice`, `@routing`, `@decimal`, `@dashLang`.
///
/// Menambah bahasa: tambahkan kolom baru (mis. `ms`) di header dan isi `@name`, `@locale`, `@voice`, ... lalu
/// terjemahan tiap baris. Sel kosong memakai teks Inggris. Tidak perlu mengubah kode.
final class Loc {
    static let shared = Loc()

    struct Language { let code: String; let name: String }

    private let lock = NSLock()
    private var columns: [String] = []             // kode bahasa per kolom (setelah kolom kunci)
    private var table: [String: [String]] = [:]    // kunci -> nilai per kolom bahasa
    private var index = 0                          // kolom bahasa yang aktif
    private var code = "en"

    private(set) var languages: [Language] = []

    private init() {
        load()
        setLanguage(UserDefaults.standard.string(forKey: "language") ?? "en")
    }

    // MARK: - Pemuatan

    private static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "\\", let n = it.next() {
                switch n {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\\": out.append("\\")
                default: out.append(c); out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var header = true
        var t: [String: [String]] = [:]
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty || line.hasPrefix("#") { continue }
            let f = line.components(separatedBy: "\t")
            if header {
                columns = Array(f.dropFirst())
                header = false
                continue
            }
            let key = Loc.unescape(f[0])
            t[key] = f.dropFirst().map { Loc.unescape($0) }
        }
        table = t
        languages = columns.enumerated().map { i, c in
            let n = t["@name"].flatMap { i < $0.count ? $0[i] : nil } ?? ""
            return Language(code: c, name: n.isEmpty ? c : n)
        }
    }

    // MARK: - Bahasa aktif

    /// Pilih bahasa. Kode yang tidak dikenal kembali ke Inggris.
    func setLanguage(_ c: String) {
        lock.lock(); defer { lock.unlock() }
        if let i = columns.firstIndex(of: c) {
            index = i
            code = c
        } else {
            index = 0
            code = columns.first ?? "en"
        }
    }

    var currentCode: String { lock.lock(); defer { lock.unlock() }; return code }
    var currentName: String { languages.first { $0.code == currentCode }?.name ?? currentCode }

    // MARK: - Teks

    func text(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let row = table[key] else { return key }
        if index < row.count, !row[index].isEmpty { return row[index] }
        if let first = row.first, !first.isEmpty { return first }
        return key
    }

    /// Data bahasa (baris `@...`); nil bila kosong.
    func meta(_ name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let row = table["@" + name], index < row.count, !row[index].isEmpty else { return nil }
        return row[index]
    }

    var locale: Locale { Locale(identifier: meta("locale") ?? "en_US") }
    /// Bahasa suara petunjuk arah (AVSpeechSynthesisVoice), mis. "en-US", "id-ID".
    var voiceLanguage: String { meta("voice") ?? "en-US" }
    /// Bahasa untuk server routing (Valhalla).
    var routingLanguage: String { meta("routing") ?? "en-US" }
    var decimalSeparator: String { meta("decimal") ?? "." }
    /// Kode bahasa dash (cmd 12) untuk bahasa ini; -1 = tidak dikirim.
    var dashLangCode: Int { Int(meta("dashLang") ?? "") ?? -1 }
}

/// Terjemahkan `key` ke bahasa aplikasi. `{0}`, `{1}`, ... diganti dengan `args`.
func tr(_ key: String, _ args: Any...) -> String {
    var s = Loc.shared.text(key)
    for (i, a) in args.enumerated() {
        s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)")
    }
    return s
}

extension String {
    /// Ganti titik desimal dengan pemisah desimal bahasa aktif (koma untuk Indonesia).
    var localizedDecimal: String {
        let sep = Loc.shared.decimalSeparator
        return sep == "." ? self : replacingOccurrences(of: ".", with: sep)
    }
}
