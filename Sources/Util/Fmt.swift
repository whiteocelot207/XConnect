import Foundation

enum Fmt {
    static func distance(_ m: Double) -> String {
        if m < 1000 {
            let r = Int((m / 10).rounded()) * 10
            return "\(r) m"
        }
        return String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func km(_ v: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func liters(_ v: Double) -> String {
        String(format: "%.1f L", v).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(_ s: Double) -> String {
        let mins = Int((s / 60).rounded())
        if mins < 60 { return "\(mins) mnt" }
        return "\(mins / 60) j \(mins % 60) mnt"
    }

    /// Format jam untuk teks yang digambar app (jam di kotak data, ETA). Diatur dari Pengaturan.
    static var clock24 = true

    private static let clock24Fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let clock12Fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    static func clock(_ d: Date) -> String {
        clock24 ? clock24Fmt.string(from: d) : clock12Fmt.string(from: d)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    static func shortDate(_ d: Date) -> String { dateFmt.string(from: d) }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "baru saja" }
        if s < 3600 { return "\(s / 60) menit yang lalu" }
        if s < 86400 { return "\(s / 3600) jam yang lalu" }
        return "\(s / 86400) hari yang lalu"
    }
}
