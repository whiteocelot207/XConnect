import SwiftUI
import UIKit

/// Katalog ikon item perawatan bertema motor. Ikon disimpan sebagai teks: nama SF Symbol, atau "e:" + emoji.
enum MaintIcons {
    static let emojiPrefix = "e:"

    /// Simbol SF yang berkaitan dengan motor, mesin, servis, kelistrikan, dokumen. Simbol yang belum ada di versi iOS
    /// perangkat otomatis disaring (lihat `symbols`).
    private static let allSymbols: [String] = [
        // perkakas dan servis
        "wrench.fill", "wrench.and.screwdriver.fill", "screwdriver.fill", "hammer.fill", "gearshape.fill", "gearshape.2.fill",
        "slider.horizontal.3", "checklist", "list.clipboard.fill", "doc.on.clipboard.fill",
        // oli, bahan bakar, mesin
        "drop.fill", "drop.triangle.fill", "oilcan.fill", "fuelpump.fill", "fuelpump.circle.fill", "flame.fill",
        "engine.combustion.fill", "arrow.triangle.2.circlepath", "arrow.up.arrow.down", "arrow.left.arrow.right",
        "cylinder.fill", "cube.fill", "shippingbox.fill",
        // udara, suhu, pendingin
        "wind", "fan.fill", "thermometer", "thermometer.sun.fill", "snowflake", "humidity.fill",
        // kelistrikan
        "bolt.fill", "bolt.circle.fill", "bolt.car.fill", "bolt.batteryblock.fill", "battery.100", "battery.25",
        "powerplug.fill", "cable.connector", "lightbulb.fill", "light.max", "headlight.high.beam.fill",
        "headlight.low.beam.fill", "hazardsign.fill",
        // roda, rem, rantai
        "tire", "circle.circle.fill", "circle.dashed", "smallcircle.filled.circle", "record.circle.fill",
        "stop.circle.fill", "octagon.fill", "hand.raised.fill", "link", "figure.outdoor.cycle", "bicycle", "scooter",
        // instrumen dan jalan
        "speedometer", "gauge", "gauge.with.dots.needle.67percent", "timer", "stopwatch.fill", "road.lanes",
        "signpost.right.fill", "map.fill", "location.fill", "mappin.and.ellipse", "flag.checkered", "antenna.radiowaves.left.and.right",
        // keselamatan dan dokumen (STNK, SIM, asuransi, pajak)
        "shield.fill", "checkmark.shield.fill", "exclamationmark.triangle.fill", "exclamationmark.octagon.fill",
        "lock.fill", "key.fill", "creditcard.fill", "person.text.rectangle.fill", "doc.text.fill", "doc.plaintext.fill",
        "banknote.fill", "tag.fill", "calendar", "calendar.badge.clock", "clock.fill", "bell.fill",
        // kebersihan dan lainnya
        "sparkles", "paintbrush.fill", "paintpalette.fill", "sun.max.fill", "cloud.rain.fill", "umbrella.fill",
        "shower.fill", "bubbles.and.sparkles.fill", "car.fill", "cart.fill", "bag.fill", "star.fill", "heart.fill"
    ]

    /// Simbol yang tersedia di perangkat ini.
    static let symbols: [String] = allSymbols.filter { UIImage(systemName: $0) != nil }

    static let emojis: [String] = [
        "🏍️", "🛵", "🏁", "🛞", "⛽", "🛢️", "🔧", "🪛", "🔩", "⚙️", "🛠️", "🧰", "🔋", "🪫", "🔌", "💡", "🔦",
        "🌡️", "❄️", "🔥", "💧", "💨", "🔑", "🪪", "📄", "📋", "📝", "🛡️", "⚠️", "🚦", "🚥", "🛑", "🅿️", "🧯",
        "🔔", "⏱️", "📅", "🗓️", "💰", "🪙", "🧴", "🧽", "🧼", "🪣", "🚿", "⛓️", "🔗", "🪖", "🧤", "🥾", "🌧️", "☀️"
    ]

    static func isEmoji(_ icon: String) -> Bool { icon.hasPrefix(emojiPrefix) }
    static func emoji(_ icon: String) -> String { String(icon.dropFirst(emojiPrefix.count)) }
}

/// Menampilkan ikon item (SF Symbol atau emoji). Simbol yang tidak tersedia diganti kunci pas.
struct MaintIconView: View {
    let icon: String
    var color: Color = .accentColor
    var size: CGFloat = 17

    var body: some View {
        if MaintIcons.isEmoji(icon) {
            Text(MaintIcons.emoji(icon)).font(.system(size: size))
        } else {
            Image(systemName: UIImage(systemName: icon) != nil ? icon : "wrench.fill")
                .font(.system(size: size)).foregroundColor(color)
        }
    }
}

/// Halaman pilih ikon: kisi simbol dan kisi emoji.
struct MaintIconPicker: View {
    @Binding var selection: String
    @Environment(\.presentationMode) private var presentation
    @State private var kind = 0

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("", selection: $kind) {
                    Text(tr("Symbols")).tag(0)
                    Text(tr("Emoji")).tag(1)
                }
                .pickerStyle(.segmented)
                LazyVGrid(columns: columns, spacing: 10) {
                    if kind == 0 {
                        ForEach(MaintIcons.symbols, id: \.self) { s in cell(value: s) { MaintIconView(icon: s, size: 22) } }
                    } else {
                        ForEach(MaintIcons.emojis, id: \.self) { e in
                            cell(value: MaintIcons.emojiPrefix + e) { Text(e).font(.system(size: 26)) }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(tr("Icon"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { kind = MaintIcons.isEmoji(selection) ? 1 : 0 }
    }

    private func cell<Content: View>(value: String, @ViewBuilder _ content: () -> Content) -> some View {
        let on = selection == value
        return Button {
            selection = value
            presentation.wrappedValue.dismiss()
        } label: {
            content()
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(on ? 0.22 : 0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
