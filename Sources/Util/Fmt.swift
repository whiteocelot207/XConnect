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

    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "baru saja" }
        if s < 3600 { return "\(s / 60) menit yang lalu" }
        if s < 86400 { return "\(s / 3600) jam yang lalu" }
        return "\(s / 86400) hari yang lalu"
    }
}
