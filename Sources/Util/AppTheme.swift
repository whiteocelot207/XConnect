import SwiftUI
import UIKit

/// Tema warna aplikasi: gradasi dua warna (awal -> akhir). Warna awal juga jadi warna aksen (tombol, tab, dll).
/// Gradasinya dipakai di kotak besar aplikasi dan kotak data besar di dash. Mode terang/gelap tetap diatur terpisah.
struct AppTheme: Identifiable {
    let id: Int
    /// kunci terjemahan nama tema
    let nameKey: String
    /// warna awal (aksen) dan warna akhir gradasi, masing-masing (r, g, b) 0...1
    let from: (r: Double, g: Double, b: Double)
    let to: (r: Double, g: Double, b: Double)

    var name: String { tr(nameKey) }

    var color: Color { Color(red: from.r, green: from.g, blue: from.b) }
    var color2: Color { Color(red: to.r, green: to.g, blue: to.b) }
    var uiColor: UIColor { UIColor(red: from.r, green: from.g, blue: from.b, alpha: 1) }
    var uiColor2: UIColor { UIColor(red: to.r, green: to.g, blue: to.b, alpha: 1) }

    /// Gradasi penuh (untuk contoh warna dan kotak besar).
    var gradient: LinearGradient {
        LinearGradient(colors: [color, color2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Gradasi lembut untuk latar kartu di aplikasi (tetap terbaca di mode terang maupun gelap).
    var softGradient: LinearGradient {
        LinearGradient(colors: [color.opacity(0.20), color2.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let all: [AppTheme] = [
        AppTheme(id: 0, nameKey: "Ocean", from: (0.00, 0.48, 1.00), to: (0.30, 0.80, 0.98)),
        AppTheme(id: 1, nameKey: "Forest", from: (0.16, 0.62, 0.35), to: (0.55, 0.78, 0.30)),
        AppTheme(id: 2, nameKey: "Sunset", from: (0.97, 0.52, 0.08), to: (0.95, 0.25, 0.30)),
        AppTheme(id: 3, nameKey: "Rose", from: (0.91, 0.26, 0.51), to: (0.99, 0.55, 0.35)),
        AppTheme(id: 4, nameKey: "Violet", from: (0.55, 0.36, 0.96), to: (0.90, 0.35, 0.70)),
        AppTheme(id: 5, nameKey: "Crimson", from: (0.84, 0.16, 0.20), to: (0.98, 0.45, 0.20)),
        AppTheme(id: 6, nameKey: "Teal", from: (0.05, 0.60, 0.64), to: (0.25, 0.78, 0.50)),
        AppTheme(id: 7, nameKey: "Graphite", from: (0.45, 0.48, 0.54), to: (0.22, 0.24, 0.30))
    ]

    static func theme(_ id: Int) -> AppTheme { all.first { $0.id == id } ?? all[0] }
}
