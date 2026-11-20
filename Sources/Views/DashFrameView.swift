import SwiftUI

/// Pratinjau dash lengkap seperti di motor: bar atas (jam, GPS, sinyal, headset, volume, baterai HP),
/// layar yang digambar app, dan bar bawah (nama jalan atau petunjuk belok).
/// Ukuran semua elemen dihitung dari lebar 480 px dash lalu diskalakan, jadi proporsinya sama di layar HP mana pun.
struct DashFrameView: View {
    @EnvironmentObject var bike: BikeController

    private let topH: CGFloat = 38
    private let botH: CGFloat = 54

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / 480
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    topBar(bike.barStatus(), s)
                }
                .frame(height: topH * s)

                ZStack {
                    Rectangle().fill(Color.black)
                    if let img = bike.preview {
                        Image(uiImage: HomeView.visibleArea(img)).resizable().interpolation(.medium)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: DashComposer.visHeight * s)
                .clipped()

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    bottomBar(bike.barStatus(), s)
                }
                .frame(height: botH * s)
            }
        }
        .aspectRatio(480.0 / (topH + DashComposer.visHeight + botH), contentMode: .fit)
        .background(Color.black)
    }

    private let barColor = Color.black
    private let dim = Color.white.opacity(0.35)

    // MARK: - Bar atas (acuan: dash NMAX/XMAX asli)
    // Kiri: jam besar, ikon peta, telepon, pesan, sinyal, baterai HP, lencana "App". Kanan: suhu.

    private func topBar(_ st: BikeController.BarStatus, _ s: CGFloat) -> some View {
        HStack(spacing: 7 * s) {
            Text(st.clock)
                .font(.system(size: 22 * s, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
            // Ikon hanya muncul bila ada pemicunya dari HP (seperti dash asli)
            if st.connected {
                Image(systemName: "map")
                    .font(.system(size: 16 * s))
                    .foregroundColor(.white)
            }
            if st.inCall {
                Image(systemName: "phone.fill")
                    .font(.system(size: 15 * s))
                    .foregroundColor(.white)
            }
            if st.missedCall {
                Image(systemName: "phone.arrow.down.left")
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundColor(Color(red: 1, green: 0.25, blue: 0.2))
                    .contentShape(Rectangle())
                    .onTapGesture { bike.clearMissedCall() }
            }
            if st.headset {
                Image(systemName: "headphones")
                    .font(.system(size: 15 * s))
                    .foregroundColor(.white)
            }
            if st.connected && st.signal > 0 {
                SignalBars(level: st.signal)
                    .frame(width: 14 * s, height: 15 * s)
            }
            if st.connected && st.battery >= 0 {
                PhoneBattery(percent: st.battery, charging: st.charging)
                    .frame(width: 10 * s, height: 17 * s)
            }
            if st.connected {
                Text("App")
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 3 * s)
                    .frame(height: 15 * s)
                    .background(RoundedRectangle(cornerRadius: 2.5 * s).fill(Color.white))
            }
            Spacer(minLength: 4 * s)
            if let t = st.tempC {
                HStack(alignment: .firstTextBaseline, spacing: 1 * s) {
                    Text("\(t)").font(.system(size: 22 * s, weight: .medium)).monospacedDigit()
                    Text("\u{00B0}C").font(.system(size: 14 * s, weight: .medium))
                }
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(barColor)
    }

    // MARK: - Bar bawah: segitiga/ikon belok + nama jalan, rata tengah

    private func bottomBar(_ st: BikeController.BarStatus, _ s: CGFloat) -> some View {
        HStack(spacing: 6 * s) {
            if st.navigating && !st.navSymbol.isEmpty {
                Image(systemName: st.navSymbol)
                    .font(.system(size: 19 * s, weight: .bold))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1))
            } else if !st.road.isEmpty {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 11 * s))
                    .foregroundColor(.white)
            }
            Text(st.road)
                .font(.system(size: 20 * s, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 12 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(barColor)
    }
}

/// Bar sinyal (0 = tanpa sinyal, 1 = SIM tanpa jaringan, 5 = jaringan data; skala 0-5 dipetakan ke 4 batang).
private struct SignalBars: View {
    var level: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / 7
            let on = level <= 0 ? 0 : min(4, max(1, level - (level >= 5 ? 1 : 0)))
            HStack(alignment: .bottom, spacing: w * 0.8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.8)
                        .fill(i < on ? Color.white : Color.white.opacity(0.3))
                        .frame(width: w, height: g.size.height * CGFloat(i + 1) / 4)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottomLeading)
        }
    }
}

/// Ikon baterai HP vertikal seperti di dash: isi naik dari bawah, hijau saat mengisi, merah di bawah 20%.
private struct PhoneBattery: View {
    var percent: Int
    var charging: Bool

    var body: some View {
        GeometryReader { g in
            let capH = g.size.height * 0.1
            let bodyH = g.size.height - capH
            let frac = CGFloat(max(0, min(100, percent < 0 ? 100 : percent))) / 100
            let fill: Color = charging ? .green : (percent >= 0 && percent < 20 ? .red : .white)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: g.size.width * 0.45, height: capH)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: 1.6)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(fill)
                        .frame(width: g.size.width - 6, height: max(0, (bodyH - 6) * frac))
                        .padding(.bottom, 3)
                }
                .frame(height: bodyH)
            }
        }
    }
}
