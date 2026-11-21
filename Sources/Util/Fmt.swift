import Foundation

enum Fmt {
    static func distance(_ m: Double) -> String {
        if m < 1000 {
            let r = Int((m / 10).rounded()) * 10
            return "\(r) m"
        }
        return String(format: "%.1f km", m / 1000).localizedDecimal
    }

    static func km(_ v: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", v).localizedDecimal
    }

    static func liters(_ v: Double) -> String {
        String(format: "%.1f L", v).localizedDecimal
    }

    static func duration(_ s: Double) -> String {
        let mins = Int((s / 60).rounded())
        if mins < 60 { return tr("{0} min", mins) }
        return tr("{0} h {1} min", mins / 60, mins % 60)
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
        f.locale = Loc.shared.locale
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    static func shortDate(_ d: Date) -> String {
        dateFmt.locale = Loc.shared.locale
        return dateFmt.string(from: d)
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return tr("just now") }
        if s < 3600 { return tr("{0} minutes ago", s / 60) }
        if s < 86400 { return tr("{0} hours ago", s / 3600) }
        return tr("{0} days ago", s / 86400)
    }
}
