import SwiftUI

/// Tema warna aplikasi (warna aksen). Mode terang/gelap tetap diatur terpisah di Pengaturan > Tampilan.
struct AppTheme: Identifiable {
    let id: Int
    /// kunci terjemahan nama tema
    let nameKey: String
    let color: Color

    var name: String { tr(nameKey) }

    static let all: [AppTheme] = [
        AppTheme(id: 0, nameKey: "Ocean", color: Color(red: 0.00, green: 0.48, blue: 1.00)),
        AppTheme(id: 1, nameKey: "Forest", color: Color(red: 0.16, green: 0.62, blue: 0.35)),
        AppTheme(id: 2, nameKey: "Sunset", color: Color(red: 0.97, green: 0.52, blue: 0.08)),
        AppTheme(id: 3, nameKey: "Rose", color: Color(red: 0.91, green: 0.26, blue: 0.51)),
        AppTheme(id: 4, nameKey: "Violet", color: Color(red: 0.55, green: 0.36, blue: 0.96)),
        AppTheme(id: 5, nameKey: "Crimson", color: Color(red: 0.84, green: 0.16, blue: 0.20)),
        AppTheme(id: 6, nameKey: "Teal", color: Color(red: 0.05, green: 0.60, blue: 0.64)),
        AppTheme(id: 7, nameKey: "Graphite", color: Color(red: 0.45, green: 0.48, blue: 0.54))
    ]

    static func theme(_ id: Int) -> AppTheme { all.first { $0.id == id } ?? all[0] }
}
