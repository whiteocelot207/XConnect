import SwiftUI

/// Ikon skuter/motor (garis) karena SF Symbols tidak punya ikon motor yang tersedia di iOS 15.
struct MotorcycleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 60
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        // roda belakang dan depan
        path.addEllipse(in: CGRect(origin: p(8, 36), size: CGSize(width: 22 * sx, height: 22 * sy)))
        path.addEllipse(in: CGRect(origin: p(70, 36), size: CGSize(width: 22 * sx, height: 22 * sy)))
        // bodi belakang dan jok
        path.move(to: p(19, 47))
        path.addLine(to: p(24, 30))
        path.addQuadCurve(to: p(44, 28), control: p(34, 21))
        path.addLine(to: p(52, 28))
        path.addLine(to: p(56, 44))
        // lantai dan dek depan
        path.move(to: p(30, 44))
        path.addLine(to: p(62, 44))
        path.addLine(to: p(70, 20))
        // garpu dan stang
        path.move(to: p(81, 47))
        path.addLine(to: p(72, 14))
        path.move(to: p(66, 11))
        path.addLine(to: p(80, 9))
        return path
    }
}

struct MotorcycleIcon: View {
    var body: some View {
        GeometryReader { g in
            MotorcycleShape()
                .stroke(style: StrokeStyle(lineWidth: max(1.5, g.size.height * 0.09), lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(100.0 / 60.0, contentMode: .fit)
    }
}

/// Ikon baris Pengaturan: SF Symbol, atau ikon motor khusus untuk "motorcycle.custom".
struct RowIcon: View {
    let name: String
    var body: some View {
        if name == "motorcycle.custom" {
            MotorcycleIcon().frame(width: 28, height: 17)
        } else {
            Image(systemName: name).frame(width: 28)
        }
    }
}
